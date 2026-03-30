// メインダッシュボード TUI

const std = @import("std");

/// レイアウトモード (ターミナル幅に応じた表示形式)
pub const LayoutMode = enum {
    wide,   // 幅 120+
    normal, // 幅 80-119
    narrow, // 幅 60-79
    mini,   // 幅 <60
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

/// CPU コア展開/折りたたみ状態
pub const DashboardState = struct {
    cpu_expanded: bool = false,
    sort_by: SortKey = .cpu,
    show_history: bool = false,
    show_help: bool = false,
};

/// CPU コア展開状態を切り替える
pub fn toggleCpuExpanded(state: *DashboardState) void {
    state.cpu_expanded = !state.cpu_expanded;
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
    try testing.expectApproxEqAbs(1.0, s[0], 1e-9);   // 最古
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
