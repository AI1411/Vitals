// パーセンテージゲージ

const std = @import("std");

/// ゲージのデフォルト幅 (文字数)
pub const DEFAULT_WIDTH: usize = 20;

/// ANSI カラー閾値
const WARN_PCT: f64 = 70.0;
const CRIT_PCT: f64 = 90.0;

const COLOR_GREEN = "\x1b[32m";
const COLOR_YELLOW = "\x1b[33m";
const COLOR_RED = "\x1b[31m";
const COLOR_RESET = "\x1b[0m";

/// 使用率 pct に応じた ANSI 色コードを返す。
pub fn colorForPct(pct: f64) []const u8 {
    if (pct >= CRIT_PCT) return COLOR_RED;
    if (pct >= WARN_PCT) return COLOR_YELLOW;
    return COLOR_GREEN;
}

/// 使用率 pct (0.0〜100.0) のゲージを writer に書き込む。
/// 出力例: "[████████░░░░░░░░░░░░]  80%"
/// gauge_width: ゲージ内の文字数 (0 の場合 DEFAULT_WIDTH を使用)
pub fn render(writer: anytype, pct: f64, gauge_width: usize) !void {
    const w = if (gauge_width == 0) DEFAULT_WIDTH else gauge_width;
    const clamped = @min(@max(pct, 0.0), 100.0);
    const filled = @as(usize, @intFromFloat(clamped / 100.0 * @as(f64, @floatFromInt(w))));

    try writer.writeAll("[");
    try writer.writeAll(colorForPct(clamped));
    for (0..filled) |_| try writer.writeAll("█");
    try writer.writeAll(COLOR_RESET);
    for (filled..w) |_| try writer.writeAll("░");
    try writer.print("] {d:3.0}%", .{clamped});
}

/// ラベル付きゲージを writer に書き込む。
/// 出力例: "CPU  [████████░░░░░░░░░░░░]  80%"
pub fn renderLabeled(writer: anytype, label: []const u8, pct: f64, gauge_width: usize) !void {
    try writer.print("{s}  ", .{label});
    try render(writer, pct, gauge_width);
}

// --- テスト ---

const testing = std.testing;

test "colorForPct: 0% → green" {
    try testing.expectEqualStrings(COLOR_GREEN, colorForPct(0.0));
}

test "colorForPct: 69% → green" {
    try testing.expectEqualStrings(COLOR_GREEN, colorForPct(69.9));
}

test "colorForPct: 70% → yellow" {
    try testing.expectEqualStrings(COLOR_YELLOW, colorForPct(70.0));
}

test "colorForPct: 89% → yellow" {
    try testing.expectEqualStrings(COLOR_YELLOW, colorForPct(89.9));
}

test "colorForPct: 90% → red" {
    try testing.expectEqualStrings(COLOR_RED, colorForPct(90.0));
}

test "colorForPct: 100% → red" {
    try testing.expectEqualStrings(COLOR_RED, colorForPct(100.0));
}

test "render: 0% → 全て空" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), 0.0, 10);
    const out = fbs.getWritten();
    // "[" + color + "" + reset + "░░░░░░░░░░" + "]   0%"
    try testing.expect(std.mem.indexOf(u8, out, "░░░░░░░░░░") != null);
    try testing.expect(std.mem.indexOf(u8, out, "  0%") != null);
}

test "render: 100% → 全て埋まる" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), 100.0, 10);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, "░") == null);
    try testing.expect(std.mem.indexOf(u8, out, "100%") != null);
}

test "render: 50% → 半分埋まる (width=10)" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), 50.0, 10);
    const out = fbs.getWritten();
    // 5個の█と5個の░
    var block_count: usize = 0;
    var shade_count: usize = 0;
    var i: usize = 0;
    while (i < out.len) {
        // █ is U+2588 (3 bytes: E2 96 88)
        if (i + 2 < out.len and out[i] == 0xE2 and out[i + 1] == 0x96 and out[i + 2] == 0x88) {
            block_count += 1;
            i += 3;
            // ░ is U+2591 (3 bytes: E2 96 91)
        } else if (i + 2 < out.len and out[i] == 0xE2 and out[i + 1] == 0x96 and out[i + 2] == 0x91) {
            shade_count += 1;
            i += 3;
        } else {
            i += 1;
        }
    }
    try testing.expectEqual(@as(usize, 5), block_count);
    try testing.expectEqual(@as(usize, 5), shade_count);
}

test "render: gauge_width=0 → DEFAULT_WIDTH を使用" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), 50.0, 0);
    // エラーにならなければ OK
    try testing.expect(fbs.getWritten().len > 0);
}

test "render: 負の値は 0 にクランプ" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), -10.0, 10);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, "  0%") != null);
}

test "render: 100超の値は 100 にクランプ" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try render(fbs.writer(), 150.0, 10);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, "100%") != null);
}
