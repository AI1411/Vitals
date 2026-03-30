const std = @import("std");
const testing = std.testing;
const memory = @import("memory");

const proc_meminfo_fixture = @embedFile("fixtures/proc_meminfo.txt");

test "proc_meminfo fixture: contains MemTotal" {
    try testing.expect(std.mem.indexOf(u8, proc_meminfo_fixture, "MemTotal:") != null);
}

test "proc_meminfo fixture: contains MemAvailable" {
    try testing.expect(std.mem.indexOf(u8, proc_meminfo_fixture, "MemAvailable:") != null);
}

test "proc_meminfo fixture: contains SwapFree" {
    try testing.expect(std.mem.indexOf(u8, proc_meminfo_fixture, "SwapFree:") != null);
}

test "proc_meminfo fixture: MemTotal value is positive" {
    var lines = std.mem.tokenizeScalar(u8, proc_meminfo_fixture, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "MemTotal:")) continue;
        // "MemTotal:       32768000 kB" → parse the numeric part
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        _ = it.next(); // "MemTotal:"
        const val_str = it.next() orelse return error.MissingValue;
        const val = try std.fmt.parseInt(u64, val_str, 10);
        try testing.expect(val > 0);
        return;
    }
    return error.MemTotalNotFound;
}

// --- parseMemLine ---

test "parseMemLine: MemTotal 行をパース" {
    const kv = memory.parseMemLine("MemTotal:       32768000 kB") orelse return error.ParseFailed;
    try testing.expectEqualStrings("MemTotal", kv.key);
    try testing.expectEqual(@as(u64, 32768000), kv.value);
}

test "parseMemLine: Buffers 行をパース" {
    const kv = memory.parseMemLine("Buffers:         1200000 kB") orelse return error.ParseFailed;
    try testing.expectEqualStrings("Buffers", kv.key);
    try testing.expectEqual(@as(u64, 1200000), kv.value);
}

test "parseMemLine: コロンのない行は null を返す" {
    try testing.expectEqual(@as(?@TypeOf(memory.parseMemLine("").?), null), memory.parseMemLine("invalid line"));
}

test "parseMemLine: 空行は null を返す" {
    try testing.expectEqual(@as(?@TypeOf(memory.parseMemLine("MemTotal: 1 kB").?), null), memory.parseMemLine(""));
}

// --- parseSnapshot ---

test "parseSnapshot: fixture を正しくパース" {
    const info = memory.parseSnapshot(proc_meminfo_fixture);
    try testing.expectEqual(@as(u64, 32768000), info.mem_total);
    try testing.expectEqual(@as(u64, 7200000), info.mem_free);
    try testing.expectEqual(@as(?u64, 12800000), info.mem_available);
    try testing.expectEqual(@as(u64, 1200000), info.buffers);
    try testing.expectEqual(@as(u64, 4300000), info.cached);
    try testing.expectEqual(@as(u64, 8192000), info.swap_total);
    try testing.expectEqual(@as(u64, 7800000), info.swap_free);
}

test "parseSnapshot: MemAvailable なし時は MemFree+Buffers+Cached でフォールバック" {
    const content = "MemTotal:       32768000 kB\nMemFree:         7200000 kB\nBuffers:         1200000 kB\nCached:          4300000 kB\n";
    const info = memory.parseSnapshot(content);
    // mem_available は null のまま
    try testing.expectEqual(@as(?u64, null), info.mem_available);
    // フォールバック: 7200000 + 1200000 + 4300000 = 12700000
    try testing.expectEqual(@as(u64, 32768000 - 12700000), info.memUsed());
}

// --- MemInfo ヘルパー ---

test "MemInfo.memUsed: Total - Available" {
    const info = memory.MemInfo{
        .mem_total = 32768000,
        .mem_available = @as(?u64, 12800000),
    };
    try testing.expectEqual(@as(u64, 32768000 - 12800000), info.memUsed());
}

test "MemInfo.memUsed: Available > Total のときアンダーフローしない" {
    const info = memory.MemInfo{
        .mem_total = 1000,
        .mem_available = @as(?u64, 2000),
    };
    try testing.expectEqual(@as(u64, 0), info.memUsed());
}

test "MemInfo.swapUsed: SwapTotal - SwapFree" {
    const info = memory.MemInfo{
        .swap_total = 8192000,
        .swap_free = 7800000,
    };
    try testing.expectEqual(@as(u64, 8192000 - 7800000), info.swapUsed());
}

test "MemInfo.swapUsed: fixture から計算" {
    const info = memory.parseSnapshot(proc_meminfo_fixture);
    try testing.expectEqual(@as(u64, 8192000 - 7800000), info.swapUsed());
}
