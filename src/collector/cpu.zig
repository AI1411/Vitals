// /proc/stat パーサー (Linux) / sysctlbyname (macOS)

const std = @import("std");
const builtin = @import("builtin");

pub const MAX_CORES = 64;

/// /proc/stat の cpu 行から取得した生カウンタ
pub const CpuTimes = struct {
    user: u64 = 0,
    nice: u64 = 0,
    system: u64 = 0,
    idle: u64 = 0,
    iowait: u64 = 0,
    irq: u64 = 0,
    softirq: u64 = 0,
    steal: u64 = 0,
    guest: u64 = 0,
    guest_nice: u64 = 0,

    /// 全フィールドの合計
    /// guest は user に、guest_nice は nice にすでに含まれるため除外する
    pub fn total(self: CpuTimes) u64 {
        return self.user + self.nice + self.system + self.idle +
            self.iowait + self.irq + self.softirq + self.steal;
    }

    /// アイドル時間合計（idle + iowait）
    pub fn idleTotal(self: CpuTimes) u64 {
        return self.idle + self.iowait;
    }
};

/// /proc/stat のスナップショット（全体 + コア別）
pub const CpuSnapshot = struct {
    total: CpuTimes = .{},
    cores: [MAX_CORES]CpuTimes = [_]CpuTimes{.{}} ** MAX_CORES,
    core_count: usize = 0,
    /// MAX_CORES を超えるコアが存在したとき true
    truncated: bool = false,
};

/// /proc/stat の1行をパースして CpuTimes を返す。
/// フォーマット: "cpu[N]  <user> <nice> <system> <idle> <iowait> <irq> <softirq> <steal> <guest> <guest_nice>"
/// "cpu" で始まらない行や解析失敗時は null を返す。
pub fn parseCpuLine(line: []const u8) ?CpuTimes {
    if (!std.mem.startsWith(u8, line, "cpu")) return null;

    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next() orelse return null; // ラベル ("cpu" / "cpu0" 等) をスキップ

    var times: CpuTimes = .{};
    const fields = [_]*u64{
        &times.user,   &times.nice,       &times.system,  &times.idle,
        &times.iowait, &times.irq,        &times.softirq, &times.steal,
        &times.guest,  &times.guest_nice,
    };

    for (fields) |field| {
        const token = it.next() orelse return null;
        field.* = std.fmt.parseInt(u64, token, 10) catch return null;
    }

    return times;
}

/// /proc/stat の内容をパースして CpuSnapshot を返す。
/// 固定バッファを使用しヒープアロケーションなし。
pub fn parseSnapshot(content: []const u8) CpuSnapshot {
    var snapshot = CpuSnapshot{};
    var lines = std.mem.tokenizeScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "cpu")) break;

        const times = parseCpuLine(line) orelse continue;

        // line[3] が数字ならコア行 ("cpu0", "cpu1" …)、そうでなければ全体行 ("cpu  …")
        if (line.len > 3 and std.ascii.isDigit(line[3])) {
            if (snapshot.core_count < MAX_CORES) {
                snapshot.cores[snapshot.core_count] = times;
                snapshot.core_count += 1;
            } else {
                snapshot.truncated = true;
            }
        } else {
            snapshot.total = times;
        }
    }

    return snapshot;
}

/// macOS: sysctlbyname("kern.cp_time" / "kern.cp_times") から CpuSnapshot を収集する。
/// CP_USER=0, CP_NICE=1, CP_SYS=2, CP_INTR=3, CP_IDLE=4 (CPUSTATES=5, sizeof(long)=8)
pub fn collectMacos() CpuSnapshot {
    const sys = @import("../utils/macos_sys.zig");
    var snap = CpuSnapshot{};

    // ── 全体 CPU 時間 (kern.cp_time) ─────────────────────────────────
    var cp_time: [5]i64 = .{0} ** 5;
    var cp_time_len: usize = @sizeOf(@TypeOf(cp_time));
    _ = sys.sysctlbyname("kern.cp_time", &cp_time[0], &cp_time_len, null, 0);
    snap.total = cpTimesToCpuTimes(&cp_time);

    // ── コア別 CPU 時間 (kern.cp_times) ──────────────────────────────
    var cp_times: [MAX_CORES * 5]i64 = .{0} ** (MAX_CORES * 5);
    var cp_times_len: usize = @sizeOf(@TypeOf(cp_times));
    _ = sys.sysctlbyname("kern.cp_times", &cp_times[0], &cp_times_len, null, 0);

    const ncpus = cp_times_len / (5 * @sizeOf(i64));
    const actual_cores = @min(ncpus, MAX_CORES);
    snap.core_count = actual_cores;
    if (ncpus > MAX_CORES) snap.truncated = true;

    for (0..actual_cores) |i| {
        const base = i * 5;
        snap.cores[i] = cpTimesToCpuTimes(cp_times[base .. base + 5]);
    }

    return snap;
}

/// macOS の kern.cp_time[5] (i64 配列) を CpuTimes に変換する。
fn cpTimesToCpuTimes(cp: []const i64) CpuTimes {
    return CpuTimes{
        .user = @intCast(if (cp[0] > 0) cp[0] else 0),
        .nice = @intCast(if (cp[1] > 0) cp[1] else 0),
        .system = @intCast(if (cp[2] > 0) cp[2] else 0),
        .irq = @intCast(if (cp[3] > 0) cp[3] else 0),
        .idle = @intCast(if (cp[4] > 0) cp[4] else 0),
    };
}

/// 前回・今回の CpuTimes 差分から CPU 使用率 (0.0〜100.0) を計算する。
/// CPU% = (1 - idle_delta / total_delta) × 100
pub fn calcUsage(prev: CpuTimes, curr: CpuTimes) f64 {
    const total_delta = curr.total() -| prev.total();
    if (total_delta == 0) return 0.0;

    const idle_delta = curr.idleTotal() -| prev.idleTotal();
    return (1.0 - @as(f64, @floatFromInt(idle_delta)) / @as(f64, @floatFromInt(total_delta))) * 100.0;
}
