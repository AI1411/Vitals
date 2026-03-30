const std = @import("std");
const testing = std.testing;
const cpu = @import("cpu");

const proc_stat_fixture = @embedFile("fixtures/proc_stat.txt");

// --- fixture 構造チェック ---

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
    // "cpu" + 10 数値フィールド = 11 トークン
    try testing.expectEqual(@as(usize, 11), count);
}

// --- parseCpuLine ---

test "parseCpuLine: 全体行をパース" {
    const line = "cpu  12345 678 9012 345678 901 234 56 0 0 0";
    const times = cpu.parseCpuLine(line) orelse return error.ParseFailed;
    try testing.expectEqual(@as(u64, 12345), times.user);
    try testing.expectEqual(@as(u64, 678), times.nice);
    try testing.expectEqual(@as(u64, 9012), times.system);
    try testing.expectEqual(@as(u64, 345678), times.idle);
    try testing.expectEqual(@as(u64, 901), times.iowait);
    try testing.expectEqual(@as(u64, 234), times.irq);
    try testing.expectEqual(@as(u64, 56), times.softirq);
    try testing.expectEqual(@as(u64, 0), times.steal);
}

test "parseCpuLine: コア行をパース" {
    const line = "cpu0 3000 170 2200 86000 200 60 14 0 0 0";
    const times = cpu.parseCpuLine(line) orelse return error.ParseFailed;
    try testing.expectEqual(@as(u64, 3000), times.user);
    try testing.expectEqual(@as(u64, 86000), times.idle);
    try testing.expectEqual(@as(u64, 14), times.softirq);
}

test "parseCpuLine: cpu 行以外は null を返す" {
    try testing.expectEqual(@as(?cpu.CpuTimes, null), cpu.parseCpuLine("intr 12345 0 0"));
    try testing.expectEqual(@as(?cpu.CpuTimes, null), cpu.parseCpuLine(""));
    try testing.expectEqual(@as(?cpu.CpuTimes, null), cpu.parseCpuLine("mem 1000"));
}

// --- parseSnapshot ---

test "parseSnapshot: fixture を正しくパース" {
    const snapshot = cpu.parseSnapshot(proc_stat_fixture);
    // 全体行
    try testing.expectEqual(@as(u64, 12345), snapshot.total.user);
    try testing.expectEqual(@as(u64, 345678), snapshot.total.idle);
    try testing.expectEqual(@as(u64, 901), snapshot.total.iowait);
    // コア数
    try testing.expectEqual(@as(usize, 4), snapshot.core_count);
    // 各コアの user 値
    try testing.expectEqual(@as(u64, 3000), snapshot.cores[0].user);
    try testing.expectEqual(@as(u64, 3100), snapshot.cores[1].user);
    try testing.expectEqual(@as(u64, 3200), snapshot.cores[2].user);
    try testing.expectEqual(@as(u64, 3045), snapshot.cores[3].user);
}

// --- CpuTimes ヘルパー ---

test "CpuTimes.total: 全フィールドを合計" {
    const times = cpu.CpuTimes{
        .user = 12345,
        .nice = 678,
        .system = 9012,
        .idle = 345678,
        .iowait = 901,
        .irq = 234,
        .softirq = 56,
    };
    const expected: u64 = 12345 + 678 + 9012 + 345678 + 901 + 234 + 56;
    try testing.expectEqual(expected, times.total());
}

test "CpuTimes.idleTotal: idle + iowait" {
    const times = cpu.CpuTimes{ .idle = 345678, .iowait = 901 };
    try testing.expectEqual(@as(u64, 345678 + 901), times.idleTotal());
}

// --- calcUsage ---

test "calcUsage: 100% 使用率" {
    const prev = cpu.CpuTimes{ .user = 0, .idle = 1000 };
    const curr = cpu.CpuTimes{ .user = 100, .idle = 1000 };
    // total_delta=100, idle_delta=0 → 100%
    try testing.expectApproxEqAbs(@as(f64, 100.0), cpu.calcUsage(prev, curr), 0.001);
}

test "calcUsage: 0% 使用率（アイドル）" {
    const prev = cpu.CpuTimes{ .user = 100, .idle = 900 };
    const curr = cpu.CpuTimes{ .user = 100, .idle = 1000 };
    // total_delta=100, idle_delta=100 → 0%
    try testing.expectApproxEqAbs(@as(f64, 0.0), cpu.calcUsage(prev, curr), 0.001);
}

test "calcUsage: 50% 使用率" {
    const prev = cpu.CpuTimes{ .user = 0, .idle = 0 };
    const curr = cpu.CpuTimes{ .user = 50, .idle = 50 };
    // total_delta=100, idle_delta=50 → 50%
    try testing.expectApproxEqAbs(@as(f64, 50.0), cpu.calcUsage(prev, curr), 0.001);
}

test "calcUsage: total_delta=0 のとき 0% を返す" {
    const prev = cpu.CpuTimes{ .user = 100 };
    const curr = cpu.CpuTimes{ .user = 100 };
    try testing.expectApproxEqAbs(@as(f64, 0.0), cpu.calcUsage(prev, curr), 0.001);
}

test "calcUsage: iowait もアイドルに含まれる" {
    const prev = cpu.CpuTimes{ .user = 0, .idle = 0, .iowait = 0 };
    const curr = cpu.CpuTimes{ .user = 30, .idle = 50, .iowait = 20 };
    // total_delta=100, idle_delta=70 → 30%
    try testing.expectApproxEqAbs(@as(f64, 30.0), cpu.calcUsage(prev, curr), 0.001);
}
