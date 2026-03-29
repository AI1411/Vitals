const std = @import("std");
const testing = std.testing;

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
