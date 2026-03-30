// メインダッシュボード TUI

const std = @import("std");
const process_mod = @import("../collector/process.zig");

/// レイアウトモード (ターミナル幅に応じた表示形式)
pub const LayoutMode = enum {
    wide, // 幅 120+
    normal, // 幅 80-119
    narrow, // 幅 60-79
    mini, // 幅 <60
};

/// ターミナル幅からレイアウトモードを決定する
pub fn layoutFromCols(cols: u16) LayoutMode {
    if (cols >= 120) return .wide;
    if (cols >= 80) return .normal;
    if (cols >= 60) return .narrow;
    return .mini;
}

/// レイアウトモードに応じたバー幅を返す
pub fn barWidthForLayout(mode: LayoutMode) usize {
    return switch (mode) {
        .wide => 40,
        .normal => 30,
        .narrow => 20,
        .mini => 0,
    };
}

/// プロセスソートキー (c/m/d キーで切り替え)
pub const SortKey = enum {
    cpu,
    mem,
    disk,
};

/// handleKey の戻り値: 呼び出し元が処理すべきアクション
pub const Action = enum {
    none,
    quit,
    kill,
    process_detail,
    search,
};

/// プロセス kill 確認段階
pub const KillStage = enum {
    none, // kill 未開始
    confirm, // 確認ダイアログ表示中
};

/// CPU コア展開/折りたたみ状態
pub const DashboardState = struct {
    cpu_expanded: bool = false,
    sort_by: SortKey = .cpu,
    show_history: bool = false,
    show_help: bool = false,
    /// プロセス検索状態
    search_active: bool = false,
    search_query: [64]u8 = [_]u8{0} ** 64,
    search_query_len: usize = 0,
    /// kill 確認状態
    kill_stage: KillStage = .none,
    kill_target_pid: u32 = 0,
};

/// CPU コア展開状態を切り替える
pub fn toggleCpuExpanded(state: *DashboardState) void {
    state.cpu_expanded = !state.cpu_expanded;
}

// --- Issue #36: ソート切り替え ---

/// プロセスリストを key に従って降順ソートする (in-place)。
pub fn sortProcesses(entries: []process_mod.ProcInfo, key: SortKey) void {
    const Context = struct {
        sort_key: SortKey,
        pub fn lessThan(ctx: @This(), a: process_mod.ProcInfo, b: process_mod.ProcInfo) bool {
            return switch (ctx.sort_key) {
                .cpu => a.cpu_pct > b.cpu_pct,
                .mem => a.mem_rss_kb > b.mem_rss_kb,
                .disk => a.disk_io_bps > b.disk_io_bps,
            };
        }
    };
    std.mem.sort(process_mod.ProcInfo, entries, Context{ .sort_key = key }, Context.lessThan);
}

// --- Issue #37: プロセス検索 ---

/// name が query を含むか大文字小文字を区別せずに判定する。
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

/// entries からクエリにマッチするプロセスを out に書き込み、件数を返す。
/// クエリが空の場合は全件をコピーする。
pub fn filterProcesses(
    entries: []const process_mod.ProcInfo,
    query: []const u8,
    out: []process_mod.ProcInfo,
) usize {
    if (query.len == 0) {
        const n = @min(entries.len, out.len);
        @memcpy(out[0..n], entries[0..n]);
        return n;
    }
    var count: usize = 0;
    for (entries) |e| {
        if (count >= out.len) break;
        if (containsIgnoreCase(e.nameSlice(), query)) {
            out[count] = e;
            count += 1;
        }
    }
    return count;
}

// --- Issue #38: プロセス kill ---

/// pid に signal を送る。
pub fn sendSignal(pid: u32, sig: u32) !void {
    try std.posix.kill(@intCast(pid), @intCast(sig));
}

// --- Issue #39: プロセス詳細表示 ---

/// プロセス詳細情報
pub const ProcessDetail = struct {
    pid: u32 = 0,
    /// /proc/[pid]/fd のエントリ数
    fd_count: usize = 0,
    /// /proc/[pid]/status の Threads フィールド
    thread_count: u32 = 0,
    /// /proc/[pid]/stat の starttime (clock ticks since boot)
    start_time_ticks: u64 = 0,
};

/// /proc/[pid]/status の内容から Threads フィールドを取得する。
pub fn parseThreadCount(content: []const u8) u32 {
    var lines = std.mem.tokenizeScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "Threads:")) continue;
        var it = std.mem.tokenizeAny(u8, line["Threads:".len..], " \t");
        const val_str = it.next() orelse continue;
        return std.fmt.parseInt(u32, val_str, 10) catch continue;
    }
    return 0;
}

/// /proc/[pid]/stat の内容から starttime (フィールド22) を取得する。
pub fn parseStartTime(content: []const u8) u64 {
    const rparen = std.mem.lastIndexOf(u8, content, ")") orelse return 0;
    // ')' 以降: state ppid pgroup session tty tpgid flags
    //           minflt cminflt majflt cmajflt utime stime cutime cstime
    //           priority nice num_threads itrealvalue starttime(20番目)
    var it = std.mem.tokenizeScalar(u8, content[rparen + 1 ..], ' ');
    var i: usize = 0;
    while (i < 19) : (i += 1) {
        _ = it.next() orelse return 0;
    }
    const starttime_str = it.next() orelse return 0;
    return std.fmt.parseInt(u64, starttime_str, 10) catch 0;
}

/// /proc/[pid]/fd のエントリ数を数える。
pub fn collectFdCount(pid: u32, path_buf: []u8) usize {
    const path = std.fmt.bufPrint(path_buf, "/proc/{d}/fd", .{pid}) catch return 0;
    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch return 0;
    defer dir.close();
    var count: usize = 0;
    var iter = dir.iterate();
    while (iter.next() catch null) |_| {
        count += 1;
    }
    return count;
}

/// キー入力を処理してダッシュボード状態を更新する。
/// 呼び出し元が処理すべきアクションを返す。
/// '1' → CPU コア展開/折りたたみ切り替え
/// 'c'/'m'/'d' → ソートキー切り替え
/// 'h' → ヒストリ表示トグル
/// '?' → ヘルプ表示トグル
/// 'q' → Action.quit
/// 'k' → Action.kill
/// 'p' → Action.process_detail
/// '/' → Action.search
pub fn handleKey(state: *DashboardState, key: u8) Action {
    switch (key) {
        '1' => {
            toggleCpuExpanded(state);
            return .none;
        },
        'c' => {
            state.sort_by = .cpu;
            return .none;
        },
        'm' => {
            state.sort_by = .mem;
            return .none;
        },
        'd' => {
            state.sort_by = .disk;
            return .none;
        },
        'h' => {
            state.show_history = !state.show_history;
            return .none;
        },
        '?' => {
            state.show_help = !state.show_help;
            return .none;
        },
        'q' => return .quit,
        'k' => return .kill,
        'p' => return .process_detail,
        '/' => return .search,
        else => return .none,
    }
}

// --- 定期更新ループ ---

/// 更新間隔: 1 秒 (ナノ秒)
pub const UPDATE_INTERVAL_NS: i64 = 1_000_000_000;

/// last_update_ns から now_ns までの経過時間が UPDATE_INTERVAL_NS 以上か判定する。
pub fn isTimeToUpdate(last_update_ns: i64, now_ns: i64) bool {
    return (now_ns - last_update_ns) >= UPDATE_INTERVAL_NS;
}

// --- MetricHistory (直近60秒のリングバッファ) ---

/// 履歴に保持するサンプル数 (= 60 秒)
pub const HISTORY_LEN: usize = 60;

/// 単一メトリクスの直近 HISTORY_LEN サンプルを保持するリングバッファ。
pub const MetricHistory = struct {
    values: [HISTORY_LEN]f64 = [_]f64{0.0} ** HISTORY_LEN,
    /// バッファに格納済みのサンプル数 (最大 HISTORY_LEN)
    count: usize = 0,
    /// 次に書き込む位置 (最古サンプルの位置でもある, count == HISTORY_LEN 時)
    head: usize = 0,

    /// 新しい値を追加する。バッファが満杯の場合は最古を上書き。
    pub fn push(self: *MetricHistory, val: f64) void {
        self.values[self.head] = val;
        self.head = (self.head + 1) % HISTORY_LEN;
        if (self.count < HISTORY_LEN) self.count += 1;
    }

    /// 古い順 → 新しい順で buf に書き込み、書き込んだスライスを返す。
    /// buf の長さが count より小さい場合は末尾 (最新) を優先して切り詰める。
    pub fn getOrdered(self: *const MetricHistory, buf: []f64) []f64 {
        const n = @min(self.count, buf.len);
        if (n == 0) return buf[0..0];
        // count < HISTORY_LEN なら values[0..count] が古い順に並んでいる
        // count == HISTORY_LEN なら head が最古
        const oldest = if (self.count < HISTORY_LEN) 0 else self.head;
        const skip = self.count - n; // 先頭から何個飛ばすか
        for (0..n) |i| {
            buf[i] = self.values[(oldest + skip + i) % HISTORY_LEN];
        }
        return buf[0..n];
    }
};

// --- テスト ---

const testing = @import("std").testing;

test "layoutFromCols: 120以上 → wide" {
    try testing.expectEqual(LayoutMode.wide, layoutFromCols(120));
    try testing.expectEqual(LayoutMode.wide, layoutFromCols(200));
}

test "layoutFromCols: 80-119 → normal" {
    try testing.expectEqual(LayoutMode.normal, layoutFromCols(80));
    try testing.expectEqual(LayoutMode.normal, layoutFromCols(119));
}

test "layoutFromCols: 60-79 → narrow" {
    try testing.expectEqual(LayoutMode.narrow, layoutFromCols(60));
    try testing.expectEqual(LayoutMode.narrow, layoutFromCols(79));
}

test "layoutFromCols: 59以下 → mini" {
    try testing.expectEqual(LayoutMode.mini, layoutFromCols(59));
    try testing.expectEqual(LayoutMode.mini, layoutFromCols(0));
}

test "barWidthForLayout: wide → 40" {
    try testing.expectEqual(@as(usize, 40), barWidthForLayout(.wide));
}

test "barWidthForLayout: normal → 30" {
    try testing.expectEqual(@as(usize, 30), barWidthForLayout(.normal));
}

test "barWidthForLayout: narrow → 20" {
    try testing.expectEqual(@as(usize, 20), barWidthForLayout(.narrow));
}

test "barWidthForLayout: mini → 0 (バーなし)" {
    try testing.expectEqual(@as(usize, 0), barWidthForLayout(.mini));
}

test "toggleCpuExpanded: false → true" {
    var state = DashboardState{};
    try testing.expect(!state.cpu_expanded);
    toggleCpuExpanded(&state);
    try testing.expect(state.cpu_expanded);
}

test "toggleCpuExpanded: true → false" {
    var state = DashboardState{ .cpu_expanded = true };
    toggleCpuExpanded(&state);
    try testing.expect(!state.cpu_expanded);
}

test "handleKey: '1' でCPU展開を切り替え" {
    var state = DashboardState{};
    _ = handleKey(&state, '1');
    try testing.expect(state.cpu_expanded);
    _ = handleKey(&state, '1');
    try testing.expect(!state.cpu_expanded);
}

test "handleKey: '1' → Action.none" {
    var state = DashboardState{};
    const action = handleKey(&state, '1');
    try testing.expectEqual(Action.none, action);
}

test "handleKey: '1'以外のキーは cpu_expanded 変更なし" {
    var state = DashboardState{};
    _ = handleKey(&state, '2');
    try testing.expect(!state.cpu_expanded);
}

test "handleKey: 'q' → Action.quit" {
    var state = DashboardState{};
    try testing.expectEqual(Action.quit, handleKey(&state, 'q'));
}

test "handleKey: 'k' → Action.kill" {
    var state = DashboardState{};
    try testing.expectEqual(Action.kill, handleKey(&state, 'k'));
}

test "handleKey: 'p' → Action.process_detail" {
    var state = DashboardState{};
    try testing.expectEqual(Action.process_detail, handleKey(&state, 'p'));
}

test "handleKey: '/' → Action.search" {
    var state = DashboardState{};
    try testing.expectEqual(Action.search, handleKey(&state, '/'));
}

test "handleKey: 'c' → sort_by = cpu" {
    var state = DashboardState{ .sort_by = .mem };
    _ = handleKey(&state, 'c');
    try testing.expectEqual(SortKey.cpu, state.sort_by);
}

test "handleKey: 'm' → sort_by = mem" {
    var state = DashboardState{};
    _ = handleKey(&state, 'm');
    try testing.expectEqual(SortKey.mem, state.sort_by);
}

test "handleKey: 'd' → sort_by = disk" {
    var state = DashboardState{};
    _ = handleKey(&state, 'd');
    try testing.expectEqual(SortKey.disk, state.sort_by);
}

test "handleKey: 'h' → show_history トグル" {
    var state = DashboardState{};
    _ = handleKey(&state, 'h');
    try testing.expect(state.show_history);
    _ = handleKey(&state, 'h');
    try testing.expect(!state.show_history);
}

test "handleKey: '?' → show_help トグル" {
    var state = DashboardState{};
    _ = handleKey(&state, '?');
    try testing.expect(state.show_help);
    _ = handleKey(&state, '?');
    try testing.expect(!state.show_help);
}

test "handleKey: 未知のキー → Action.none, 状態変更なし" {
    var state = DashboardState{};
    const action = handleKey(&state, 'z');
    try testing.expectEqual(Action.none, action);
    try testing.expect(!state.cpu_expanded);
    try testing.expectEqual(SortKey.cpu, state.sort_by);
}

// --- MetricHistory テスト ---

test "MetricHistory: 初期状態は count=0" {
    const h = MetricHistory{};
    try testing.expectEqual(@as(usize, 0), h.count);
}

test "MetricHistory: push で count が増える" {
    var h = MetricHistory{};
    h.push(10.0);
    try testing.expectEqual(@as(usize, 1), h.count);
    h.push(20.0);
    try testing.expectEqual(@as(usize, 2), h.count);
}

test "MetricHistory: HISTORY_LEN を超えても count は最大 HISTORY_LEN" {
    var h = MetricHistory{};
    for (0..HISTORY_LEN + 5) |i| {
        h.push(@floatFromInt(i));
    }
    try testing.expectEqual(HISTORY_LEN, h.count);
}

test "MetricHistory: getOrdered は古い順に返す (満杯前)" {
    var h = MetricHistory{};
    h.push(1.0);
    h.push(2.0);
    h.push(3.0);
    var buf: [HISTORY_LEN]f64 = undefined;
    const s = h.getOrdered(&buf);
    try testing.expectEqual(@as(usize, 3), s.len);
    try testing.expectApproxEqAbs(1.0, s[0], 1e-9);
    try testing.expectApproxEqAbs(2.0, s[1], 1e-9);
    try testing.expectApproxEqAbs(3.0, s[2], 1e-9);
}

test "MetricHistory: getOrdered は古い順に返す (満杯後)" {
    var h = MetricHistory{};
    // 60 サンプル push してから +1 する → 最古 (0) が上書きされ 1 が最古になる
    for (0..HISTORY_LEN) |i| {
        h.push(@floatFromInt(i)); // 0,1,...,59
    }
    h.push(100.0); // 60 → 0 を上書き、最古は 1
    var buf: [HISTORY_LEN]f64 = undefined;
    const s = h.getOrdered(&buf);
    try testing.expectEqual(HISTORY_LEN, s.len);
    try testing.expectApproxEqAbs(1.0, s[0], 1e-9); // 最古
    try testing.expectApproxEqAbs(100.0, s[HISTORY_LEN - 1], 1e-9); // 最新
}

test "MetricHistory: getOrdered で buf が小さい場合は最新を返す" {
    var h = MetricHistory{};
    h.push(1.0);
    h.push(2.0);
    h.push(3.0);
    var buf: [2]f64 = undefined;
    const s = h.getOrdered(&buf);
    try testing.expectEqual(@as(usize, 2), s.len);
    try testing.expectApproxEqAbs(2.0, s[0], 1e-9);
    try testing.expectApproxEqAbs(3.0, s[1], 1e-9);
}

test "MetricHistory: empty の getOrdered は空スライスを返す" {
    const h = MetricHistory{};
    var buf: [HISTORY_LEN]f64 = undefined;
    const s = h.getOrdered(&buf);
    try testing.expectEqual(@as(usize, 0), s.len);
}

// --- isTimeToUpdate テスト ---

test "isTimeToUpdate: 経過時間 < 1s → false" {
    try testing.expect(!isTimeToUpdate(0, UPDATE_INTERVAL_NS - 1));
}

test "isTimeToUpdate: 経過時間 = 1s → true" {
    try testing.expect(isTimeToUpdate(0, UPDATE_INTERVAL_NS));
}

test "isTimeToUpdate: 経過時間 > 1s → true" {
    try testing.expect(isTimeToUpdate(0, UPDATE_INTERVAL_NS + 1));
}

test "isTimeToUpdate: 経過時間 0 → false" {
    try testing.expect(!isTimeToUpdate(1000, 1000));
}

test "isTimeToUpdate: 任意の基準時刻で動作する" {
    const base: i64 = 5_000_000_000;
    try testing.expect(!isTimeToUpdate(base, base + UPDATE_INTERVAL_NS - 1));
    try testing.expect(isTimeToUpdate(base, base + UPDATE_INTERVAL_NS));
}

// --- sortProcesses テスト (#36) ---

test "sortProcesses: cpu降順" {
    var procs = [_]process_mod.ProcInfo{
        .{ .cpu_pct = 10.0 },
        .{ .cpu_pct = 50.0 },
        .{ .cpu_pct = 30.0 },
    };
    sortProcesses(&procs, .cpu);
    try testing.expectApproxEqAbs(50.0, procs[0].cpu_pct, 1e-9);
    try testing.expectApproxEqAbs(30.0, procs[1].cpu_pct, 1e-9);
    try testing.expectApproxEqAbs(10.0, procs[2].cpu_pct, 1e-9);
}

test "sortProcesses: mem降順" {
    var procs = [_]process_mod.ProcInfo{
        .{ .mem_rss_kb = 100 },
        .{ .mem_rss_kb = 500 },
        .{ .mem_rss_kb = 300 },
    };
    sortProcesses(&procs, .mem);
    try testing.expectEqual(@as(u64, 500), procs[0].mem_rss_kb);
    try testing.expectEqual(@as(u64, 300), procs[1].mem_rss_kb);
    try testing.expectEqual(@as(u64, 100), procs[2].mem_rss_kb);
}

test "sortProcesses: disk降順" {
    var procs = [_]process_mod.ProcInfo{
        .{ .disk_io_bps = 1000 },
        .{ .disk_io_bps = 5000 },
        .{ .disk_io_bps = 3000 },
    };
    sortProcesses(&procs, .disk);
    try testing.expectEqual(@as(u64, 5000), procs[0].disk_io_bps);
    try testing.expectEqual(@as(u64, 3000), procs[1].disk_io_bps);
    try testing.expectEqual(@as(u64, 1000), procs[2].disk_io_bps);
}

test "sortProcesses: 空スライスはクラッシュしない" {
    var procs = [_]process_mod.ProcInfo{};
    sortProcesses(&procs, .cpu);
}

// --- filterProcesses テスト (#37) ---

fn makeProc(name: []const u8, cpu: f64) process_mod.ProcInfo {
    var p = process_mod.ProcInfo{ .cpu_pct = cpu };
    const n = @min(name.len, p.name.len - 1);
    @memcpy(p.name[0..n], name[0..n]);
    p.name_len = n;
    return p;
}

test "filterProcesses: 空クエリは全件通す" {
    const entries = [_]process_mod.ProcInfo{
        makeProc("bash", 1.0),
        makeProc("nginx", 2.0),
    };
    var out: [10]process_mod.ProcInfo = undefined;
    const n = filterProcesses(&entries, "", &out);
    try testing.expectEqual(@as(usize, 2), n);
}

test "filterProcesses: クエリにマッチするものを返す" {
    const entries = [_]process_mod.ProcInfo{
        makeProc("bash", 1.0),
        makeProc("nginx", 2.0),
        makeProc("sshd", 3.0),
    };
    var out: [10]process_mod.ProcInfo = undefined;
    const n = filterProcesses(&entries, "sh", &out);
    try testing.expectEqual(@as(usize, 2), n); // bash, sshd
}

test "filterProcesses: 大文字小文字を区別しない" {
    const entries = [_]process_mod.ProcInfo{
        makeProc("Nginx", 1.0),
        makeProc("bash", 2.0),
    };
    var out: [10]process_mod.ProcInfo = undefined;
    const n = filterProcesses(&entries, "NGINX", &out);
    try testing.expectEqual(@as(usize, 1), n);
    try testing.expectEqualStrings("Nginx", out[0].nameSlice());
}

test "filterProcesses: マッチなし → 0件" {
    const entries = [_]process_mod.ProcInfo{
        makeProc("bash", 1.0),
    };
    var out: [10]process_mod.ProcInfo = undefined;
    const n = filterProcesses(&entries, "zzz", &out);
    try testing.expectEqual(@as(usize, 0), n);
}

// --- DashboardState 検索・kill状態テスト (#37 #38) ---

test "DashboardState: 初期検索状態" {
    const state = DashboardState{};
    try testing.expect(!state.search_active);
    try testing.expectEqual(@as(usize, 0), state.search_query_len);
}

test "DashboardState: 初期kill状態" {
    const state = DashboardState{};
    try testing.expectEqual(KillStage.none, state.kill_stage);
    try testing.expectEqual(@as(u32, 0), state.kill_target_pid);
}

// --- parseThreadCount テスト (#39) ---

test "parseThreadCount: 正常パース" {
    const content = "Name:\tbash\nPid:\t1234\nThreads:\t4\n";
    try testing.expectEqual(@as(u32, 4), parseThreadCount(content));
}

test "parseThreadCount: タブ・スペース混在" {
    const content = "Threads:  12\n";
    try testing.expectEqual(@as(u32, 12), parseThreadCount(content));
}

test "parseThreadCount: フィールドなし → 0" {
    const content = "Name:\tbash\n";
    try testing.expectEqual(@as(u32, 0), parseThreadCount(content));
}

// --- parseStartTime テスト (#39) ---

test "parseStartTime: 正常パース" {
    // "pid (comm) state ppid ... (20フィールド目がstarttime)"
    // state ppid pgroup session tty tpgid flags minflt cminflt majflt cmajflt
    // utime stime cutime cstime priority nice num_threads itrealvalue starttime
    const content = "1 (bash) S 0 1 1 0 -1 0 0 0 0 0 100 50 0 0 20 0 1 0 99999";
    try testing.expectEqual(@as(u64, 99999), parseStartTime(content));
}

test "parseStartTime: 不正フォーマット → 0" {
    try testing.expectEqual(@as(u64, 0), parseStartTime("invalid"));
    try testing.expectEqual(@as(u64, 0), parseStartTime(""));
}
