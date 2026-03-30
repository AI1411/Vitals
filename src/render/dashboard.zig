// メインダッシュボード TUI

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

/// CPU コア展開/折りたたみ状態
pub const DashboardState = struct {
    cpu_expanded: bool = false,
};

/// CPU コア展開状態を切り替える
pub fn toggleCpuExpanded(state: *DashboardState) void {
    state.cpu_expanded = !state.cpu_expanded;
}

/// キー入力を処理してダッシュボード状態を更新する
/// '1' → CPU コア展開/折りたたみ切り替え
pub fn handleKey(state: *DashboardState, key: u8) void {
    switch (key) {
        '1' => toggleCpuExpanded(state),
        else => {},
    }
}

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
    handleKey(&state, '1');
    try testing.expect(state.cpu_expanded);
    handleKey(&state, '1');
    try testing.expect(!state.cpu_expanded);
}

test "handleKey: '1'以外のキーは状態変更なし" {
    var state = DashboardState{};
    handleKey(&state, '2');
    handleKey(&state, 'q');
    try testing.expect(!state.cpu_expanded);
}
