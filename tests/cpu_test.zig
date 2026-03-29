const std = @import("std");
const testing = std.testing;

const proc_stat_fixture = @embedFile("fixtures/proc_stat.txt");

test "proc_stat fixture: has cpu summary line" {
    try testing.expect(std.mem.startsWith(u8, proc_stat_fixture, "cpu "));
}

test "proc_stat fixture: has at least one core line" {
    try testing.expect(std.mem.indexOf(u8, proc_stat_fixture, "cpu0 ") != null);
}

test "proc_stat fixture: cpu line has 10 fields" {
    var lines = std.mem.tokenizeScalar(u8, proc_stat_fixture, '\n');
    const first_line = lines.next() orelse return error.EmptyFixture;
    var fields = std.mem.tokenizeScalar(u8, first_line, ' ');
    var count: usize = 0;
    while (fields.next()) |_| count += 1;
    // "cpu" + 10 numeric fields = 11 tokens
    try testing.expectEqual(@as(usize, 11), count);
}
