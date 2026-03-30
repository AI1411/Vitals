// ASCII 時系列グラフ

const std = @import("std");

/// グラフのデフォルト高さ (行数, Y軸の解像度)
pub const DEFAULT_HEIGHT: usize = 6;

/// Y軸ラベル幅 (例: " 100%┤" = 7文字)
pub const Y_LABEL_WIDTH: usize = 7;

/// 時間軸ラベル幅 (例: "  -5m" = 5文字)
const TIME_LABEL_WIDTH: usize = 6;

/// 値 v (0.0〜max_val) をディスプレイ行インデックスに変換する。
/// display_row: 0 = 最上行 (最大値), height-1 = 最下行 (0)
pub fn valueToDisplayRow(v: f64, max_val: f64, height: usize) usize {
    if (height == 0) return 0;
    if (max_val <= 0.0) return height - 1;
    const ratio = @min(@max(v / max_val, 0.0), 1.0);
    const value_row = @as(usize, @intFromFloat(ratio * @as(f64, @floatFromInt(height - 1))));
    return (height - 1) - value_row;
}

/// ライン描画文字を選択する。
/// prev_dr: 前の列のディスプレイ行 (なければ curr_dr)
/// curr_dr: 現在の列のディスプレイ行
/// next_dr: 次の列のディスプレイ行 (なければ curr_dr)
pub fn lineChar(prev_dr: usize, curr_dr: usize, next_dr: usize) []const u8 {
    const from_above = prev_dr < curr_dr; // 前列が上にある (値が高かった)
    const from_below = prev_dr > curr_dr; // 前列が下にある (値が低かった)
    const to_above = next_dr < curr_dr; // 次列が上にある (値が高くなる)
    const to_below = next_dr > curr_dr; // 次列が下にある (値が低くなる)

    if (!from_above and !from_below and !to_above and !to_below) return "─"; // 水平
    if (from_above and !to_above and !to_below) return "╰"; // 上から来て右へ水平
    if (from_below and !to_above and !to_below) return "╭"; // 下から来て右へ水平
    if (!from_above and !from_below and to_above) return "╯"; // 左水平→右上
    if (!from_above and !from_below and to_below) return "╮"; // 左水平→右下
    if (from_below and to_above) return "╭"; // 下から上へ (急上昇の頂点)
    if (from_above and to_below) return "╰"; // 上から下へ (急下降の底点)
    if (from_above and to_above) return "╰"; // 両隣が上 (谷)
    if (from_below and to_below) return "╭"; // 両隣が下 (峰)
    return "─";
}

/// 指定行 row が a と b の間 (exclusive) にあるか判定する。
pub fn isBetween(row: usize, a: usize, b: usize) bool {
    const lo = @min(a, b);
    const hi = @max(a, b);
    return row > lo and row < hi;
}

/// 時間範囲 time_range_secs から時間軸ラベルを生成する。
/// num_ticks: 目盛り数 (通常 6)
/// tick_interval: 各目盛りの列間隔
pub fn formatTimeLabel(secs: i64, buf: []u8) []const u8 {
    if (secs == 0) return std.fmt.bufPrint(buf, "  now", .{}) catch "";
    const abs_secs = if (secs < 0) -secs else secs;
    if (abs_secs >= 60) {
        const mins = @divTrunc(abs_secs, 60);
        return std.fmt.bufPrint(buf, "-{d}m", .{mins}) catch "";
    }
    return std.fmt.bufPrint(buf, "-{d}s", .{abs_secs}) catch "";
}

/// values (古い順) を ASCII 時系列グラフとして writer に書き込む。
///
/// - values: 表示する値のスライス (古い順)
/// - max_val: Y軸最大値 (0.0 の場合は 100.0 を使用)
/// - height: グラフ行数 (0 の場合は DEFAULT_HEIGHT)
/// - graph_width: グラフ列数 (Y軸ラベルを除く幅)
/// - label: グラフタイトル
/// - time_range_secs: 表示時間範囲 (秒)。X軸ラベルに使用。
/// - y_label_fmt: Y軸ラベルフォーマット ("{d:.0}%" など)
pub fn render(
    writer: anytype,
    values: []const f64,
    max_val: f64,
    height: usize,
    graph_width: usize,
    label: []const u8,
    time_range_secs: usize,
) !void {
    const eff_max = if (max_val <= 0.0) 100.0 else max_val;
    const h = if (height == 0) DEFAULT_HEIGHT else height;
    const w = if (graph_width == 0) 60 else graph_width;

    // タイトル行
    try writer.print("  {s}\n", .{label});

    // values の最新 w 件を使用 (データが少ない場合は左側を空白でパディング)
    const n_vals = @min(values.len, w);
    const offset = values.len - n_vals; // values 内の開始インデックス

    // 各列のディスプレイ行インデックスを計算 (左パディング分は最下行=空白)
    var display_rows: [4096]usize = undefined; // w <= 4096 を仮定
    const w_clamped = @min(w, 4096);
    for (0..w_clamped) |col| {
        if (col < w - n_vals) {
            // 左パディング: データなし
            display_rows[col] = h; // 番兵値 (範囲外 = データなし)
        } else {
            const val_idx = offset + (col - (w - n_vals));
            display_rows[col] = valueToDisplayRow(values[val_idx], eff_max, h);
        }
    }

    // h 行のグラフをレンダリング (0=最上行, h-1=最下行)
    for (0..h) |dr| {
        // Y軸ラベル: 各行の代表値
        const row_val = eff_max * @as(f64, @floatFromInt(h - 1 - dr)) / @as(f64, @floatFromInt(h - 1));

        if (dr == h - 1) {
            // 最下行: ┼ (X軸との交点)
            var label_buf: [16]u8 = undefined;
            const lbl = std.fmt.bufPrint(&label_buf, "{d:.0}", .{row_val}) catch "0";
            try writer.print(" {s:>4}%┼", .{lbl});
        } else {
            var label_buf: [16]u8 = undefined;
            const lbl = std.fmt.bufPrint(&label_buf, "{d:.0}", .{row_val}) catch "0";
            try writer.print(" {s:>4}%┤", .{lbl});
        }

        // グラフ部分
        for (0..w_clamped) |col| {
            const curr_dr = display_rows[col];
            if (curr_dr >= h) {
                // データなし (左パディング)
                try writer.writeAll(if (dr == h - 1) "─" else " ");
                continue;
            }

            const prev_dr = if (col > 0 and display_rows[col - 1] < h)
                display_rows[col - 1]
            else
                curr_dr;

            if (curr_dr == dr) {
                // この行にラインが通る: 適切な文字を選択
                const next_dr = if (col + 1 < w_clamped and display_rows[col + 1] < h)
                    display_rows[col + 1]
                else
                    curr_dr;
                try writer.writeAll(lineChar(prev_dr, curr_dr, next_dr));
            } else if (display_rows[col] < h and isBetween(dr, prev_dr, curr_dr)) {
                // 前列との垂直接続 (複数行ジャンプ時の補間)
                try writer.writeAll("│");
            } else if (dr == h - 1) {
                // 最下行の軸線
                try writer.writeAll("─");
            } else {
                try writer.writeAll(" ");
            }
        }
        try writer.writeByte('\n');
    }

    // X軸時間ラベル行
    try renderTimeAxis(writer, w_clamped, time_range_secs);
}

/// X軸の時間ラベルを writer に書き込む。
/// 出力例: "       -5m   -4m   -3m   -2m   -1m   now"
fn renderTimeAxis(writer: anytype, graph_width: usize, time_range_secs: usize) !void {
    // Y軸ラベル分のインデント
    try writer.writeAll("       ");

    // 6目盛りを均等配置
    const n_ticks: usize = 6;
    if (graph_width < n_ticks) {
        try writer.writeByte('\n');
        return;
    }

    const tick_interval = graph_width / n_ticks;
    var labels_buf: [n_ticks][8]u8 = undefined;
    var labels: [n_ticks][]const u8 = undefined;
    var col_positions: [n_ticks]usize = undefined;

    for (0..n_ticks) |i| {
        col_positions[i] = i * tick_interval;
        // i=0: 最古 (-time_range_secs), i=n_ticks-1: now (0)
        const elapsed_secs = @divTrunc(
            @as(i64, @intCast(time_range_secs)) * @as(i64, @intCast(n_ticks - 1 - i)),
            @as(i64, @intCast(n_ticks - 1)),
        );
        const neg_elapsed: i64 = -elapsed_secs;
        labels[i] = formatTimeLabel(neg_elapsed, &labels_buf[i]);
    }

    // 各目盛りラベルを正しい位置に配置
    var current_col: usize = 0;
    for (0..n_ticks) |i| {
        const target = col_positions[i];
        // ラベルを目盛り中央に配置
        const lbl = labels[i];
        const center_offset = lbl.len / 2;
        const lbl_start = if (target >= center_offset) target - center_offset else target;

        // 現在位置からラベル開始位置までスペースを挿入
        while (current_col < lbl_start) : (current_col += 1) {
            try writer.writeByte(' ');
        }

        try writer.writeAll(lbl);
        current_col += lbl.len;
    }
    try writer.writeByte('\n');
}

// --- テスト ---

const testing = std.testing;

test "valueToDisplayRow: max=100, height=6" {
    // 100% → row 0 (最上行)
    try testing.expectEqual(@as(usize, 0), valueToDisplayRow(100.0, 100.0, 6));
    // 0% → row 5 (最下行)
    try testing.expectEqual(@as(usize, 5), valueToDisplayRow(0.0, 100.0, 6));
    // 50% → row 2 (中間, height-1=5, 5-floor(0.5*5)=5-2=3... wait
    // ratio=0.5, value_row=floor(0.5*5)=2, display_row=5-2=3
    try testing.expectEqual(@as(usize, 3), valueToDisplayRow(50.0, 100.0, 6));
}

test "valueToDisplayRow: max<=0 → 最下行" {
    try testing.expectEqual(@as(usize, 5), valueToDisplayRow(50.0, 0.0, 6));
    try testing.expectEqual(@as(usize, 5), valueToDisplayRow(50.0, -1.0, 6));
}

test "valueToDisplayRow: height=1 → 常に 0" {
    try testing.expectEqual(@as(usize, 0), valueToDisplayRow(0.0, 100.0, 1));
    try testing.expectEqual(@as(usize, 0), valueToDisplayRow(100.0, 100.0, 1));
}

test "valueToDisplayRow: 負の値は 0 にクランプ" {
    try testing.expectEqual(@as(usize, 5), valueToDisplayRow(-10.0, 100.0, 6));
}

test "valueToDisplayRow: max超の値は最上行にクランプ" {
    try testing.expectEqual(@as(usize, 0), valueToDisplayRow(200.0, 100.0, 6));
}

test "lineChar: 水平 → ─" {
    try testing.expectEqualStrings("─", lineChar(2, 2, 2));
}

test "lineChar: 下から来て右水平 → ╭" {
    try testing.expectEqualStrings("╭", lineChar(3, 2, 2)); // prev > curr (来た方が下)
}

test "lineChar: 上から来て右水平 → ╰" {
    try testing.expectEqualStrings("╰", lineChar(1, 2, 2)); // prev < curr (来た方が上)
}

test "lineChar: 左水平→右上 → ╯" {
    try testing.expectEqualStrings("╯", lineChar(2, 2, 1)); // next < curr (上に行く)
}

test "lineChar: 左水平→右下 → ╮" {
    try testing.expectEqualStrings("╮", lineChar(2, 2, 3)); // next > curr (下に行く)
}

test "isBetween: 中間値は true" {
    try testing.expect(isBetween(3, 1, 5));
    try testing.expect(isBetween(3, 5, 1));
}

test "isBetween: 境界値は false" {
    try testing.expect(!isBetween(1, 1, 5));
    try testing.expect(!isBetween(5, 1, 5));
}

test "isBetween: 等しい場合は false" {
    try testing.expect(!isBetween(3, 3, 3));
}

test "render: 空値でもクラッシュしない" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), &[_]f64{}, 100.0, 6, 20, "Test", 300);
    try testing.expect(fbs.getWritten().len > 0);
}

test "render: 単一値でもクラッシュしない" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), &[_]f64{50.0}, 100.0, 6, 20, "CPU", 300);
    try testing.expect(fbs.getWritten().len > 0);
}

test "formatTimeLabel: now (0秒)" {
    var buf: [8]u8 = undefined;
    const lbl = formatTimeLabel(0, &buf);
    try testing.expectEqualStrings("  now", lbl);
}

test "formatTimeLabel: -5分" {
    var buf: [8]u8 = undefined;
    const lbl = formatTimeLabel(-300, &buf);
    try testing.expectEqualStrings("-5m", lbl);
}

test "formatTimeLabel: -30秒" {
    var buf: [8]u8 = undefined;
    const lbl = formatTimeLabel(-30, &buf);
    try testing.expectEqualStrings("-30s", lbl);
}
