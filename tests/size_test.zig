const std = @import("std");
const testing = std.testing;
const size = @import("size");

// --- format ---

test "format: バイト未満の値" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("512 B", size.format(512, &buf));
}

test "format: KB 単位" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("1.0 KB", size.format(1024, &buf));
}

test "format: MB 単位" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("1.0 MB", size.format(1024 * 1024, &buf));
}

test "format: GB 単位" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("1.0 GB", size.format(1024 * 1024 * 1024, &buf));
}

test "format: TB 単位" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("1.0 TB", size.format(1024 * 1024 * 1024 * 1024, &buf));
}

test "format: 小数点1桁" {
    var buf: [32]u8 = undefined;
    // 12.4 MB = 12 * 1024 * 1024 + 0.4 * 1024 * 1024 = 13,004,800 bytes
    const bytes: u64 = @intFromFloat(12.4 * 1024.0 * 1024.0);
    const s = size.format(bytes, &buf);
    // "12.4 MB" または "12.3 MB" (浮動小数点誤差許容)
    try testing.expect(std.mem.startsWith(u8, s, "12.") and std.mem.endsWith(u8, s, " MB"));
}

test "format: 0 バイト" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("0 B", size.format(0, &buf));
}

// --- formatKb ---

test "formatKb: kB → バイト変換してから format" {
    var buf: [32]u8 = undefined;
    // 1024 kB = 1 MB
    try testing.expectEqualStrings("1.0 MB", size.formatKb(1024, &buf));
}

// --- formatRateMini ---

test "formatRateMini: MB/s レート" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("12M", size.formatRateMini(12.4 * 1024.0 * 1024.0, &buf));
}

test "formatRateMini: KB/s レート" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("3K", size.formatRateMini(3.0 * 1024.0, &buf));
}

test "formatRateMini: バイト/s レート" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("500", size.formatRateMini(500.0, &buf));
}

test "formatRateMini: 0 バイト/s" {
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("0", size.formatRateMini(0.0, &buf));
}
