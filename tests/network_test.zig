const std = @import("std");
const testing = std.testing;
const network = @import("network");

const proc_net_dev_fixture = @embedFile("fixtures/proc_net_dev.txt");

// --- fixture 構造チェック ---

test "proc_net_dev fixture: eth0 エントリが存在する" {
    const snapshot = network.parseSnapshot(proc_net_dev_fixture);
    var found = false;
    for (snapshot.ifaces[0..snapshot.count]) |iface| {
        if (std.mem.eql(u8, iface.nameSlice(), "eth0")) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

// --- parseNetLine ---

test "parseNetLine: eth0 行をパース" {
    const line = "  eth0: 123456789  98765    0    0    0     0          0         0 987654321  87654    0    0    0     0       0          0";
    const stat = network.parseNetLine(line) orelse return error.ParseFailed;
    try testing.expectEqualStrings("eth0", stat.nameSlice());
    try testing.expectEqual(@as(u64, 123456789), stat.rx_bytes);
    try testing.expectEqual(@as(u64, 987654321), stat.tx_bytes);
}

test "parseNetLine: lo 行をパース" {
    const line = "    lo:  45678901  12345    0    0    0     0          0         0  45678901  12345    0    0    0     0       0          0";
    const stat = network.parseNetLine(line) orelse return error.ParseFailed;
    try testing.expectEqualStrings("lo", stat.nameSlice());
    try testing.expectEqual(@as(u64, 45678901), stat.rx_bytes);
    try testing.expectEqual(@as(u64, 45678901), stat.tx_bytes);
}

test "parseNetLine: ヘッダー行は null を返す" {
    try testing.expectEqual(@as(?network.NetIfStat, null), network.parseNetLine("Inter-|   Receive"));
    try testing.expectEqual(@as(?network.NetIfStat, null), network.parseNetLine(" face |bytes    packets"));
}

test "parseNetLine: 空行は null を返す" {
    try testing.expectEqual(@as(?network.NetIfStat, null), network.parseNetLine(""));
}

// --- parseSnapshot ---

test "parseSnapshot: fixture を正しくパース" {
    const snapshot = network.parseSnapshot(proc_net_dev_fixture);
    try testing.expectEqual(@as(usize, 2), snapshot.count);
    try testing.expect(!snapshot.truncated);

    // eth0
    try testing.expectEqualStrings("eth0", snapshot.ifaces[0].nameSlice());
    try testing.expectEqual(@as(u64, 123456789), snapshot.ifaces[0].rx_bytes);
    try testing.expectEqual(@as(u64, 987654321), snapshot.ifaces[0].tx_bytes);

    // lo
    try testing.expectEqualStrings("lo", snapshot.ifaces[1].nameSlice());
    try testing.expectEqual(@as(u64, 45678901), snapshot.ifaces[1].rx_bytes);
    try testing.expectEqual(@as(u64, 45678901), snapshot.ifaces[1].tx_bytes);
}

test "parseSnapshot: MAX_IFACES 超えで truncated = true" {
    var buf: [network.MAX_IFACES * 120 + 200]u8 = undefined;
    var pos: usize = 0;
    const header1 = "Inter-|   Receive                                                |  Transmit\n";
    const header2 = " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n";
    @memcpy(buf[pos .. pos + header1.len], header1);
    pos += header1.len;
    @memcpy(buf[pos .. pos + header2.len], header2);
    pos += header2.len;

    for (0..network.MAX_IFACES + 1) |i| {
        const line = std.fmt.bufPrint(buf[pos..], "  eth{d}: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n", .{i}) catch break;
        pos += line.len;
    }

    const snapshot = network.parseSnapshot(buf[0..pos]);
    try testing.expectEqual(network.MAX_IFACES, snapshot.count);
    try testing.expect(snapshot.truncated);
}

// --- NetIfStat ヘルパー ---

test "NetIfStat.nameSlice: インターフェース名を返す" {
    var stat = network.NetIfStat{};
    const name = "eth0";
    @memcpy(stat.name[0..name.len], name);
    stat.name_len = name.len;
    try testing.expectEqualStrings(name, stat.nameSlice());
}

// --- calcThroughput ---

test "calcThroughput: 正常なスループット計算" {
    const prev = network.NetIfStat{ .rx_bytes = 1000, .tx_bytes = 2000 };
    const curr = network.NetIfStat{ .rx_bytes = 2000, .tx_bytes = 4000 };
    const tp = network.calcThroughput(prev, curr, 1.0);
    try testing.expectApproxEqAbs(@as(f64, 1000.0), tp.rx_bytes_per_sec, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2000.0), tp.tx_bytes_per_sec, 0.001);
}

test "calcThroughput: interval=0.5 秒でスループット2倍" {
    const prev = network.NetIfStat{ .rx_bytes = 0, .tx_bytes = 0 };
    const curr = network.NetIfStat{ .rx_bytes = 500, .tx_bytes = 1000 };
    const tp = network.calcThroughput(prev, curr, 0.5);
    try testing.expectApproxEqAbs(@as(f64, 1000.0), tp.rx_bytes_per_sec, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 2000.0), tp.tx_bytes_per_sec, 0.001);
}

test "calcThroughput: interval <= 0 のとき 0 を返す" {
    const prev = network.NetIfStat{ .rx_bytes = 0, .tx_bytes = 0 };
    const curr = network.NetIfStat{ .rx_bytes = 1000, .tx_bytes = 2000 };
    const tp = network.calcThroughput(prev, curr, 0.0);
    try testing.expectApproxEqAbs(@as(f64, 0.0), tp.rx_bytes_per_sec, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), tp.tx_bytes_per_sec, 0.001);
}

test "calcThroughput: カウンターラップアラウンドでアンダーフロー保護" {
    // curr < prev の場合は 0 になること
    const prev = network.NetIfStat{ .rx_bytes = 1000, .tx_bytes = 1000 };
    const curr = network.NetIfStat{ .rx_bytes = 500, .tx_bytes = 500 };
    const tp = network.calcThroughput(prev, curr, 1.0);
    try testing.expectApproxEqAbs(@as(f64, 0.0), tp.rx_bytes_per_sec, 0.001);
    try testing.expectApproxEqAbs(@as(f64, 0.0), tp.tx_bytes_per_sec, 0.001);
}
