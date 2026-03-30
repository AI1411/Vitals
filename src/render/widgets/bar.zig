// プログレスバー (色分け付き)

const std = @import("std");

/// バーの幅 (文字数)
pub const BAR_WIDTH = 32;

/// ▓ (U+2593) は UTF-8 で 3 バイト
const CHAR_BYTES = 3;

/// 色の閾値
const WARN_PCT: f64 = 70.0;
const CRIT_PCT: f64 = 90.0;

/// ANSI エスケープコード
pub const COLOR_GREEN = "\x1b[32m";
pub const COLOR_YELLOW = "\x1b[33m";
pub const COLOR_RED = "\x1b[31m";
pub const COLOR_RESET = "\x1b[0m";

/// 使用率 pct に応じた ANSI 色コードを返す。
pub fn colorForPct(pct: f64) []const u8 {
    if (pct >= CRIT_PCT) return COLOR_RED;
    if (pct >= WARN_PCT) return COLOR_YELLOW;
    return COLOR_GREEN;
}

/// バー1行分のバイト列型 (▓/░ × BAR_WIDTH × 3 バイト)
const BarBytes = [BAR_WIDTH * CHAR_BYTES]u8;

/// comptime でバー文字列を事前構築 (0〜100% の 101 パターン)。
/// BAR_TABLE[i] は i% に対応したバー文字列 (filled + empty)。
const BAR_TABLE: [101]BarBytes = blk: {
    // ▓ = 0xE2 0x96 0x93,  ░ = 0xE2 0x96 0x91
    const filled_bytes = [CHAR_BYTES]u8{ 0xE2, 0x96, 0x93 };
    const empty_bytes = [CHAR_BYTES]u8{ 0xE2, 0x96, 0x91 };
    @setEvalBranchQuota(200_000);
    var table: [101]BarBytes = undefined;
    var pct: usize = 0;
    while (pct <= 100) : (pct += 1) {
        const n_filled = pct * BAR_WIDTH / 100;
        var buf: BarBytes = undefined;
        var i: usize = 0;
        while (i < n_filled) : (i += 1) {
            buf[i * CHAR_BYTES + 0] = filled_bytes[0];
            buf[i * CHAR_BYTES + 1] = filled_bytes[1];
            buf[i * CHAR_BYTES + 2] = filled_bytes[2];
        }
        while (i < BAR_WIDTH) : (i += 1) {
            buf[i * CHAR_BYTES + 0] = empty_bytes[0];
            buf[i * CHAR_BYTES + 1] = empty_bytes[1];
            buf[i * CHAR_BYTES + 2] = empty_bytes[2];
        }
        table[pct] = buf;
    }
    break :blk table;
};

/// 使用率 pct (0.0〜100.0) のプログレスバーを writer に書き込む。
/// 幅は BAR_WIDTH 文字固定。filled 部分に ANSI カラーを付与する。
pub fn render(writer: anytype, pct: f64) !void {
    const clamped = @min(@max(pct, 0.0), 100.0);
    const idx: usize = @min(@as(usize, @intFromFloat(clamped)), @as(usize, 100));
    const n_filled = idx * BAR_WIDTH / 100;
    const bar = &BAR_TABLE[idx];

    if (n_filled > 0) {
        try writer.writeAll(colorForPct(clamped));
        try writer.writeAll(bar[0 .. n_filled * CHAR_BYTES]);
        try writer.writeAll(COLOR_RESET);
    }
    if (n_filled < BAR_WIDTH) {
        try writer.writeAll(bar[n_filled * CHAR_BYTES ..]);
    }
}

/// カラーなしでプログレスバーを writer に書き込む (リダイレクト先など ANSI 非対応環境向け)。
pub fn renderPlain(writer: anytype, pct: f64) !void {
    const clamped = @min(@max(pct, 0.0), 100.0);
    const idx: usize = @min(@as(usize, @intFromFloat(clamped)), @as(usize, 100));
    try writer.writeAll(&BAR_TABLE[idx]);
}

/// HealthStatus に基づく色でプログレスバーを writer に書き込む。
pub fn renderWithHealth(writer: anytype, pct: f64, status: health_color.HealthStatus) !void {
    const clamped = @min(@max(pct, 0.0), 100.0);
    const idx: usize = @min(@as(usize, @intFromFloat(clamped)), @as(usize, 100));
    const n_filled = idx * @as(usize, BAR_WIDTH) / 100;
    const bar = &BAR_TABLE[idx];

    if (n_filled > 0) {
        try writer.writeAll(health_color.colorForHealth(status));
        try writer.writeAll(bar[0 .. n_filled * CHAR_BYTES]);
        try writer.writeAll(health_color.RESET);
    }
    if (n_filled < BAR_WIDTH) {
        try writer.writeAll(bar[n_filled * CHAR_BYTES ..]);
    }
}

const health_color = @import("../../health/color.zig");

// --- テスト ---

const testing = @import("std").testing;

test "renderWithHealth: normal → 緑コードを含む" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderWithHealth(fbs.writer(), 50.0, .normal);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, health_color.GREEN) != null);
}

test "renderWithHealth: warn → 黄コードを含む" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderWithHealth(fbs.writer(), 50.0, .warn);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, health_color.YELLOW) != null);
}

test "renderWithHealth: critical → 赤コードを含む" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderWithHealth(fbs.writer(), 50.0, .critical);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, health_color.RED) != null);
}

test "renderWithHealth: 0% → 色コードなし (filled なし)" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderWithHealth(fbs.writer(), 0.0, .critical);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, health_color.RED) == null);
}

test "renderWithHealth: RESETコードを含む (50%)" {
    var buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderWithHealth(fbs.writer(), 50.0, .normal);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, health_color.RESET) != null);
}
