// ヘルス→ANSIカラーマッピング

const thresholds = @import("thresholds.zig");
pub const HealthStatus = thresholds.HealthStatus;

pub const GREEN = "\x1b[32m";
pub const YELLOW = "\x1b[33m";
pub const RED = "\x1b[31m";
pub const RESET = "\x1b[0m";

/// HealthStatus に対応する ANSI カラーコードを返す
pub fn colorForHealth(status: HealthStatus) []const u8 {
    return switch (status) {
        .normal => GREEN,
        .warn => YELLOW,
        .critical => RED,
    };
}

// --- テスト ---

const testing = @import("std").testing;

test "colorForHealth: normal → 緑" {
    try testing.expectEqualStrings(GREEN, colorForHealth(.normal));
}

test "colorForHealth: warn → 黄" {
    try testing.expectEqualStrings(YELLOW, colorForHealth(.warn));
}

test "colorForHealth: critical → 赤" {
    try testing.expectEqualStrings(RED, colorForHealth(.critical));
}
