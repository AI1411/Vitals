// Top N プロセス収集 (Linux: /proc 走査, macOS: スタブ)

const std = @import("std");
const builtin = @import("builtin");
const proc_reader = @import("../utils/proc_reader.zig");

/// CPU 上位プロセスの最大取得数
pub const TOP_N = 10;
/// 走査する最大 PID 数
pub const MAX_PROCS = 512;
/// USER_HZ（Linux カーネルの clock tick 周波数）
const USER_HZ: f64 = 100.0;

/// プロセス情報（表示用）
pub const ProcInfo = struct {
    pid: u32 = 0,
    /// CPU 使用率 (0.0〜100.0)
    cpu_pct: f64 = 0.0,
    /// 物理メモリ使用量 (kB)
    mem_rss_kb: u64 = 0,
    /// DISK I/O スループット (bytes/sec, /proc/[pid]/io から取得)
    disk_io_bps: u64 = 0,
    /// プロセス名（/proc/[pid]/comm, 最大 15 文字）
    name: [16]u8 = [_]u8{0} ** 16,
    name_len: usize = 0,

    pub fn nameSlice(self: *const ProcInfo) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// 差分計算用の生データ（PID ごとの累積 CPU ticks）
pub const RawProcStat = struct {
    pid: u32 = 0,
    /// utime + stime の累積値
    cpu_ticks: u64 = 0,
};

/// プロセス収集スナップショット
pub const ProcessSnapshot = struct {
    /// CPU 上位 TOP_N プロセス（CPU 降順）
    top: [TOP_N]ProcInfo = [_]ProcInfo{.{}} ** TOP_N,
    top_count: usize = 0,
    /// 次回差分計算用の全プロセス生データ
    raw: [MAX_PROCS]RawProcStat = [_]RawProcStat{.{}} ** MAX_PROCS,
    raw_count: usize = 0,
    /// スナップショット取得時刻 (nanoseconds)
    timestamp_ns: i128 = 0,
};

/// /proc/[pid]/stat の内容から pid, utime, stime を解析する。
/// フォーマット: "pid (comm) state ppid ... utime stime ..."
/// comm はスペースを含む可能性があるため最後の ')' を基準に解析する。
/// 解析失敗時は null を返す。
pub fn parseProcStat(content: []const u8) ?struct { pid: u32, utime: u64, stime: u64 } {
    const lparen = std.mem.indexOf(u8, content, "(") orelse return null;
    const rparen = std.mem.lastIndexOf(u8, content, ")") orelse return null;
    if (lparen >= rparen) return null;

    const pid_str = std.mem.trim(u8, content[0..lparen], " \t");
    const pid = std.fmt.parseInt(u32, pid_str, 10) catch return null;

    // ')' 以降のフィールド:
    // state(1) ppid(2) pgroup(3) session(4) tty(5) tpgid(6) flags(7)
    // minflt(8) cminflt(9) majflt(10) cmajflt(11) utime(12) stime(13)
    var it = std.mem.tokenizeScalar(u8, content[rparen + 1 ..], ' ');
    var i: usize = 0;
    while (i < 11) : (i += 1) {
        _ = it.next() orelse return null;
    }
    const utime_str = it.next() orelse return null;
    const stime_str = it.next() orelse return null;
    const utime = std.fmt.parseInt(u64, utime_str, 10) catch return null;
    const stime = std.fmt.parseInt(u64, stime_str, 10) catch return null;

    return .{ .pid = pid, .utime = utime, .stime = stime };
}

/// /proc/[pid]/status の内容から VmRSS (kB) を取得する。
/// 見つからない場合は 0 を返す。
pub fn parseVmRss(content: []const u8) u64 {
    var lines = std.mem.tokenizeScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "VmRSS:")) continue;
        var it = std.mem.tokenizeAny(u8, line["VmRSS:".len..], " \t");
        const val_str = it.next() orelse continue;
        return std.fmt.parseInt(u64, val_str, 10) catch continue;
    }
    return 0;
}

/// /proc/[pid]/comm の内容からプロセス名を取得する（末尾の改行・空白を除去）。
pub fn parseComm(content: []const u8) []const u8 {
    return std.mem.trim(u8, content, " \n\r\t");
}

/// prev スナップショットから pid の前回 cpu_ticks を線形探索する。
fn prevTicksForPid(prev: *const ProcessSnapshot, pid: u32) ?u64 {
    for (0..prev.raw_count) |i| {
        if (prev.raw[i].pid == pid) return prev.raw[i].cpu_ticks;
    }
    return null;
}

/// /proc 以下を走査して CPU 上位 TOP_N プロセスのスナップショットを返す。
/// prev は前回のスナップショット（null の場合は CPU% = 0.0）。
/// buf は一時読み取りバッファ（proc_reader.PROC_BUF_SIZE 以上推奨）。
/// macOS では /proc が存在しないため空のスナップショットを返す。
pub fn collect(prev: ?*const ProcessSnapshot, buf: []u8) ProcessSnapshot {
    if (comptime builtin.os.tag == .macos) {
        var snap = ProcessSnapshot{};
        snap.timestamp_ns = std.time.nanoTimestamp();
        return snap;
    }

    var snap = ProcessSnapshot{};
    snap.timestamp_ns = std.time.nanoTimestamp();

    const elapsed_sec: f64 = if (prev) |p| blk: {
        const diff_ns = snap.timestamp_ns - p.timestamp_ns;
        const sec = @as(f64, @floatFromInt(if (diff_ns > 0) diff_ns else 1_000_000_000)) / 1e9;
        break :blk @max(sec, 0.001);
    } else 1.0;

    // ソート用一時バッファ
    const TmpEntry = struct {
        pid: u32,
        cpu_ticks: u64,
        cpu_pct: f64,
    };
    var tmp: [MAX_PROCS]TmpEntry = undefined;
    var tmp_count: usize = 0;

    // /proc を走査して PID ディレクトリを列挙
    var proc_dir = std.fs.openDirAbsolute("/proc", .{ .iterate = true }) catch return snap;
    defer proc_dir.close();

    var path_buf: [64]u8 = undefined;
    var iter = proc_dir.iterate();

    while (iter.next() catch null) |entry| {
        if (entry.kind != .directory) continue;
        const pid = std.fmt.parseInt(u32, entry.name, 10) catch continue;
        if (tmp_count >= MAX_PROCS) break;

        // /proc/[pid]/stat から CPU ticks を読み取る (#31)
        const stat_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/stat", .{pid}) catch continue;
        const stat_content = proc_reader.read(stat_path, buf) catch continue;
        const parsed = parseProcStat(stat_content) orelse continue;

        const cpu_ticks = parsed.utime + parsed.stime;
        const cpu_pct: f64 = if (prev) |p| blk: {
            const prev_ticks = prevTicksForPid(p, pid) orelse 0;
            const delta: f64 = @as(f64, @floatFromInt(cpu_ticks -| prev_ticks));
            break :blk delta / (elapsed_sec * USER_HZ) * 100.0;
        } else 0.0;

        // 差分計算用に raw に保存
        snap.raw[snap.raw_count] = .{ .pid = pid, .cpu_ticks = cpu_ticks };
        snap.raw_count += 1;

        tmp[tmp_count] = .{ .pid = pid, .cpu_ticks = cpu_ticks, .cpu_pct = cpu_pct };
        tmp_count += 1;
    }

    // CPU% 降順部分選択ソートで Top N を抽出 (#34)
    const n = @min(tmp_count, TOP_N);
    for (0..n) |i| {
        var max_idx = i;
        for (i + 1..tmp_count) |j| {
            if (tmp[j].cpu_pct > tmp[max_idx].cpu_pct) max_idx = j;
        }
        if (max_idx != i) {
            const t = tmp[i];
            tmp[i] = tmp[max_idx];
            tmp[max_idx] = t;
        }

        const pid = tmp[i].pid;
        var info = ProcInfo{
            .pid = pid,
            .cpu_pct = tmp[i].cpu_pct,
        };

        // /proc/[pid]/status から VmRSS を読み取る (#32)
        const status_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/status", .{pid}) catch {
            snap.top[snap.top_count] = info;
            snap.top_count += 1;
            continue;
        };
        if (proc_reader.read(status_path, buf)) |content| {
            info.mem_rss_kb = parseVmRss(content);
        } else |_| {}

        // /proc/[pid]/comm からプロセス名を読み取る (#33)
        const comm_path = std.fmt.bufPrint(&path_buf, "/proc/{d}/comm", .{pid}) catch {
            snap.top[snap.top_count] = info;
            snap.top_count += 1;
            continue;
        };
        if (proc_reader.read(comm_path, buf)) |content| {
            const name = parseComm(content);
            const copy_len = @min(name.len, info.name.len - 1);
            @memcpy(info.name[0..copy_len], name[0..copy_len]);
            info.name_len = copy_len;
        } else |_| {}

        snap.top[snap.top_count] = info;
        snap.top_count += 1;
    }

    return snap;
}

// --- テスト ---

const testing = std.testing;

test "parseProcStat: 基本的なフォーマット" {
    // "pid (comm) state ppid pgroup session tty tpgid flags minflt cminflt majflt cmajflt utime stime ..."
    const content = "1234 (bash) S 1 1234 1234 0 -1 4194304 100 200 0 0 500 300 0 0 20 0 1 0 0 0 0 0";
    const result = parseProcStat(content) orelse return error.ParseFailed;
    try testing.expectEqual(@as(u32, 1234), result.pid);
    try testing.expectEqual(@as(u64, 500), result.utime);
    try testing.expectEqual(@as(u64, 300), result.stime);
}

test "parseProcStat: comm にスペースを含む場合" {
    const content = "42 (my proc) S 1 42 42 0 -1 4194304 0 0 0 0 10 20 0 0 20 0 1 0 0 0 0 0";
    const result = parseProcStat(content) orelse return error.ParseFailed;
    try testing.expectEqual(@as(u32, 42), result.pid);
    try testing.expectEqual(@as(u64, 10), result.utime);
    try testing.expectEqual(@as(u64, 20), result.stime);
}

test "parseProcStat: 不正なフォーマット → null" {
    try testing.expectEqual(@as(?@TypeOf(parseProcStat("").?), null), parseProcStat("invalid"));
    try testing.expectEqual(@as(?@TypeOf(parseProcStat("").?), null), parseProcStat(""));
}

test "parseVmRss: 正常パース" {
    const content =
        \\Name:   bash
        \\Pid:    1234
        \\VmRSS:   4096 kB
        \\VmSize:  12345 kB
    ;
    try testing.expectEqual(@as(u64, 4096), parseVmRss(content));
}

test "parseVmRss: VmRSS なし → 0" {
    const content = "Name:   bash\nPid:    1234\n";
    try testing.expectEqual(@as(u64, 0), parseVmRss(content));
}

test "parseComm: 末尾改行を除去" {
    try testing.expectEqualStrings("bash", parseComm("bash\n"));
    try testing.expectEqualStrings("rust-analyzer", parseComm("rust-analyzer\n"));
}

test "parseComm: 改行なし" {
    try testing.expectEqualStrings("vim", parseComm("vim"));
}

test "ProcInfo.nameSlice: 正しいスライスを返す" {
    var info = ProcInfo{};
    const name = "bash";
    @memcpy(info.name[0..name.len], name);
    info.name_len = name.len;
    try testing.expectEqualStrings("bash", info.nameSlice());
}
