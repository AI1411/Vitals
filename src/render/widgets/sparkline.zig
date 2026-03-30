// ミニグラフ (▁▂▃▄▅▆▇█)

const std = @import("std");

pub const spark_chars = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };

/// 値 v を [0, max] の範囲で正規化して対応するスパークライン文字を返す。
/// max <= 0 の場合は最小文字 ▁ を返す。
pub fn charForValue(v: f64, max: f64) []const u8 {
    if (max <= 0.0) return spark_chars[0];
    const clamped = @max(v, 0.0);
    const ratio = @min(clamped / max, 1.0);
    const idx = @min(@as(usize, @intFromFloat(ratio * 8.0)), 7);
    return spark_chars[idx];
}

/// values を sparkline として writer に書き込む。
pub fn render(writer: anytype, values: []const f64, max: f64) !void {
    for (values) |v| {
        try writer.writeAll(charForValue(v, max));
    }
}

// --- テスト ---

const testing = @import("std").testing;

test "charForValue: max<=0 → ▁" {
    try testing.expectEqualStrings("▁", charForValue(50.0, 0.0));
    try testing.expectEqualStrings("▁", charForValue(50.0, -1.0));
}

test "charForValue: 0 → ▁" {
    try testing.expectEqualStrings("▁", charForValue(0.0, 100.0));
}

test "charForValue: max → █" {
    try testing.expectEqualStrings("█", charForValue(100.0, 100.0));
}

test "charForValue: 負の値 → ▁ (0にクランプ)" {
    try testing.expectEqualStrings("▁", charForValue(-10.0, 100.0));
}

test "charForValue: max超過 → █ (1.0にクランプ)" {
    try testing.expectEqualStrings("█", charForValue(200.0, 100.0));
}

test "charForValue: 8レベルの対応 (▁▂▃▄▅▆▇█)" {
    // index = floor(v/max * 8) をクランプ [0,7]
    try testing.expectEqualStrings("▁", charForValue(0.0, 100.0));    // 0/8
    try testing.expectEqualStrings("▂", charForValue(12.5, 100.0));   // 1/8
    try testing.expectEqualStrings("▃", charForValue(25.0, 100.0));   // 2/8
    try testing.expectEqualStrings("▄", charForValue(37.5, 100.0));   // 3/8
    try testing.expectEqualStrings("▅", charForValue(50.0, 100.0));   // 4/8
    try testing.expectEqualStrings("▆", charForValue(62.5, 100.0));   // 5/8
    try testing.expectEqualStrings("▇", charForValue(75.0, 100.0));   // 6/8
    try testing.expectEqualStrings("█", charForValue(87.5, 100.0));   // 7/8
}

test "render: empty values → 出力なし" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), &[_]f64{}, 100.0);
    try testing.expectEqualStrings("", fbs.getWritten());
}

test "render: 単一値0 → ▁" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), &[_]f64{0.0}, 100.0);
    try testing.expectEqualStrings("▁", fbs.getWritten());
}

test "render: 単一値max → █" {
    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), &[_]f64{100.0}, 100.0);
    try testing.expectEqualStrings("█", fbs.getWritten());
}

test "render: 昇順8値 → ▁▂▃▄▅▆▇█" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const values = [_]f64{ 0, 12.5, 25.0, 37.5, 50.0, 62.5, 75.0, 87.5 };
    try render(fbs.writer(), &values, 100.0);
    try testing.expectEqualStrings("▁▂▃▄▅▆▇█", fbs.getWritten());
}

test "render: 降順8値 → █▇▆▅▄▃▂▁" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const values = [_]f64{ 87.5, 75.0, 62.5, 50.0, 37.5, 25.0, 12.5, 0.0 };
    try render(fbs.writer(), &values, 100.0);
    try testing.expectEqualStrings("█▇▆▅▄▃▂▁", fbs.getWritten());
}
