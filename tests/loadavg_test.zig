const std = @import("std");
const testing = std.testing;
const loadavg = @import("loadavg");

const proc_loadavg_fixture = @embedFile("fixtures/proc_loadavg.txt");

// --- fixture 構造チェック ---

test "proc_loadavg fixture: 正しくパースできる" {
    const result = loadavg.parseSnapshot(proc_loadavg_fixture) orelse return error.ParseFailed;
    try testing.expectApproxEqAbs(@as(f64, 3.42), result.load1, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2.81), result.load5, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2.15), result.load15, 0.001);
    try testing.expectEqual(@as(u32, 4), result.running);
    try testing.expectEqual(@as(u32, 312), result.total);
    try testing.expectEqual(@as(u32, 12345), result.last_pid);
}

// --- parseSnapshot ---

test "parseSnapshot: 標準的な入力をパース" {
    const input = "3.42 2.81 2.15 4/312 12345\n";
    const result = loadavg.parseSnapshot(input) orelse return error.ParseFailed;
    try testing.expectApproxEqAbs(@as(f64, 3.42), result.load1, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2.81), result.load5, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2.15), result.load15, 0.001);
    try testing.expectEqual(@as(u32, 4), result.running);
    try testing.expectEqual(@as(u32, 312), result.total);
    try testing.expectEqual(@as(u32, 12345), result.last_pid);
}

test "parseSnapshot: ロードアベレージが 0.00 の場合" {
    const input = "0.00 0.00 0.00 1/100 1\n";
    const result = loadavg.parseSnapshot(input) orelse return error.ParseFailed;
    try testing.expectApproxEqAbs(@as(f64, 0.0), result.load1, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), result.load5, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), result.load15, 0.001);
    try testing.expectEqual(@as(u32, 1), result.running);
    try testing.expectEqual(@as(u32, 100), result.total);
    try testing.expectEqual(@as(u32, 1), result.last_pid);
}

test "parseSnapshot: 高負荷時の値" {
    const input = "12.50 8.32 5.01 16/512 99999\n";
    const result = loadavg.parseSnapshot(input) orelse return error.ParseFailed;
    try testing.expectApproxEqAbs(@as(f64, 12.50), result.load1, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 8.32), result.load5, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 5.01), result.load15, 0.001);
    try testing.expectEqual(@as(u32, 16), result.running);
    try testing.expectEqual(@as(u32, 512), result.total);
    try testing.expectEqual(@as(u32, 99999), result.last_pid);
}

test "parseSnapshot: 空文字列は null を返す" {
    try testing.expectEqual(@as(?loadavg.LoadAvg, null), loadavg.parseSnapshot(""));
}

test "parseSnapshot: フィールド不足は null を返す" {
    try testing.expectEqual(@as(?loadavg.LoadAvg, null), loadavg.parseSnapshot("3.42 2.81"));
}

test "parseSnapshot: running/total のスラッシュなしは null を返す" {
    try testing.expectEqual(@as(?loadavg.LoadAvg, null), loadavg.parseSnapshot("3.42 2.81 2.15 4 12345\n"));
}

test "parseSnapshot: 改行のみは null を返す" {
    try testing.expectEqual(@as(?loadavg.LoadAvg, null), loadavg.parseSnapshot("\n"));
}
