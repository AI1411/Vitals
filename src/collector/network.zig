// /proc/net/dev パーサー

const std = @import("std");

pub const MAX_IFACES = 32;
/// インターフェース名の最大長
const IFNAME_MAX = 16;

/// 1インターフェースの送受信バイト数スナップショット
pub const NetIfStat = struct {
    /// インターフェース名（固定バッファ）
    name: [IFNAME_MAX]u8 = [_]u8{0} ** IFNAME_MAX,
    name_len: usize = 0,
    /// 受信バイト数 — rx_bytes
    rx_bytes: u64 = 0,
    /// 送信バイト数 — tx_bytes
    tx_bytes: u64 = 0,

    pub fn nameSlice(self: *const NetIfStat) []const u8 {
        return self.name[0..self.name_len];
    }
};

/// /proc/net/dev から収集したスナップショット
pub const NetSnapshot = struct {
    ifaces: [MAX_IFACES]NetIfStat = [_]NetIfStat{.{}} ** MAX_IFACES,
    count: usize = 0,
    /// MAX_IFACES を超えるエントリが存在したとき true
    truncated: bool = false,
};

/// スループット計算結果 (bytes/sec)
pub const Throughput = struct {
    rx_bytes_per_sec: f64 = 0.0,
    tx_bytes_per_sec: f64 = 0.0,
};

/// /proc/net/dev の1行をパースして NetIfStat を返す。
/// フォーマット: "  iface: rx_bytes rx_packets ... tx_bytes ..."
/// ヘッダー行や解析失敗時は null を返す。
pub fn parseNetLine(line: []const u8) ?NetIfStat {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return null;

    // コロンでインターフェース名と統計を分割
    const colon = std.mem.indexOf(u8, trimmed, ":") orelse return null;
    const raw_name = std.mem.trim(u8, trimmed[0..colon], " \t");
    if (raw_name.len == 0 or raw_name.len >= IFNAME_MAX) return null;

    var it = std.mem.tokenizeScalar(u8, trimmed[colon + 1 ..], ' ');

    // rx_bytes (フィールド1)
    const rx_str = it.next() orelse return null;
    const rx_bytes = std.fmt.parseInt(u64, rx_str, 10) catch return null;

    // rx_packets, rx_errs, rx_drop, rx_fifo, rx_frame, rx_compressed, rx_multicast をスキップ (7フィールド)
    for (0..7) |_| {
        _ = it.next() orelse return null;
    }

    // tx_bytes (フィールド9)
    const tx_str = it.next() orelse return null;
    const tx_bytes = std.fmt.parseInt(u64, tx_str, 10) catch return null;

    var stat = NetIfStat{
        .rx_bytes = rx_bytes,
        .tx_bytes = tx_bytes,
    };
    @memcpy(stat.name[0..raw_name.len], raw_name);
    stat.name_len = raw_name.len;

    return stat;
}

/// /proc/net/dev の内容をパースして NetSnapshot を返す。
/// 固定バッファを使用しヒープアロケーションなし。
pub fn parseSnapshot(content: []const u8) NetSnapshot {
    var snapshot = NetSnapshot{};
    var lines = std.mem.tokenizeScalar(u8, content, '\n');
    var header_count: usize = 0;

    while (lines.next()) |line| {
        // 最初の2行はヘッダー行をスキップ
        if (header_count < 2) {
            header_count += 1;
            continue;
        }

        const stat = parseNetLine(line) orelse continue;

        if (snapshot.count >= MAX_IFACES) {
            snapshot.truncated = true;
            break;
        }

        snapshot.ifaces[snapshot.count] = stat;
        snapshot.count += 1;
    }

    return snapshot;
}

/// 前回・今回の NetIfStat 差分と経過時間からスループット (bytes/sec) を計算する。
/// interval_sec が 0 以下の場合は 0.0 を返す。
pub fn calcThroughput(prev: NetIfStat, curr: NetIfStat, interval_sec: f64) Throughput {
    if (interval_sec <= 0.0) return .{};

    const rx_delta = curr.rx_bytes -| prev.rx_bytes;
    const tx_delta = curr.tx_bytes -| prev.tx_bytes;

    return .{
        .rx_bytes_per_sec = @as(f64, @floatFromInt(rx_delta)) / interval_sec,
        .tx_bytes_per_sec = @as(f64, @floatFromInt(tx_delta)) / interval_sec,
    };
}
