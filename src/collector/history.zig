// リングバッファで過去N分保持

const std = @import("std");
const snapshot_mod = @import("snapshot.zig");

/// デフォルト容量: 5分 × 1秒間隔
pub const DEFAULT_CAPACITY: usize = 300;
/// 最大容量: 60分 × 1秒間隔
pub const MAX_CAPACITY: usize = 3600;

/// 1サンプルの主要メトリクス (グラフ描画に必要な値のみ保持)
pub const Sample = struct {
    cpu_pct: f64 = 0.0,
    mem_pct: f64 = 0.0,
    /// 最初の非ループバックインターフェースの受信スループット (bytes/sec)
    net_rx_bps: f64 = 0.0,
    /// 最初の非ループバックインターフェースの送信スループット (bytes/sec)
    net_tx_bps: f64 = 0.0,
};

/// UsageSnapshot から Sample に変換する。
/// net_* は net_count > 0 の最初のインターフェースを使用する。
pub fn sampleFromUsage(usage: snapshot_mod.UsageSnapshot) Sample {
    var rx: f64 = 0.0;
    var tx: f64 = 0.0;
    if (usage.net_count > 0) {
        rx = usage.net_throughput[0].rx_bytes_per_sec;
        tx = usage.net_throughput[0].tx_bytes_per_sec;
    }
    return .{
        .cpu_pct = usage.cpu_pct,
        .mem_pct = usage.mem_pct,
        .net_rx_bps = rx,
        .net_tx_bps = tx,
    };
}

/// 最大 MAX_CAPACITY サンプルを保持するリングバッファ履歴。
/// ゼロアロケーション: スタック上に確保可能 (≈115 KB)。
pub const History = struct {
    samples: [MAX_CAPACITY]Sample = [_]Sample{.{}} ** MAX_CAPACITY,
    /// 次の書き込み位置 (== 最古エントリの位置, len == MAX_CAPACITY 時)
    head: usize = 0,
    /// 格納済みのサンプル数 (最大 MAX_CAPACITY)
    len: usize = 0,

    /// 新しいサンプルを追加する。バッファが満杯の場合は最古を上書き。
    pub fn push(self: *History, sample: Sample) void {
        self.samples[self.head] = sample;
        self.head = (self.head + 1) % MAX_CAPACITY;
        if (self.len < MAX_CAPACITY) self.len += 1;
    }

    /// 最新の n 件の cpu_pct を buf に古い順でコピーし、スライスを返す。
    pub fn getCpuPct(self: *const History, n: usize, buf: []f64) []f64 {
        return self.getFieldImpl(n, buf, 0);
    }

    /// 最新の n 件の mem_pct を buf に古い順でコピーし、スライスを返す。
    pub fn getMemPct(self: *const History, n: usize, buf: []f64) []f64 {
        return self.getFieldImpl(n, buf, 1);
    }

    /// 最新の n 件の net_rx_bps を buf に古い順でコピーし、スライスを返す。
    pub fn getNetRxBps(self: *const History, n: usize, buf: []f64) []f64 {
        return self.getFieldImpl(n, buf, 2);
    }

    /// 最新の n 件の net_tx_bps を buf に古い順でコピーし、スライスを返す。
    pub fn getNetTxBps(self: *const History, n: usize, buf: []f64) []f64 {
        return self.getFieldImpl(n, buf, 3);
    }

    /// field: 0=cpu_pct, 1=mem_pct, 2=net_rx_bps, 3=net_tx_bps
    fn getFieldImpl(self: *const History, n: usize, buf: []f64, field: u2) []f64 {
        const count = @min(n, @min(self.len, buf.len));
        if (count == 0) return buf[0..0];

        const oldest = if (self.len < MAX_CAPACITY) 0 else self.head;
        const skip = self.len - count;
        for (0..count) |i| {
            const s = self.samples[(oldest + skip + i) % MAX_CAPACITY];
            buf[i] = switch (field) {
                0 => s.cpu_pct,
                1 => s.mem_pct,
                2 => s.net_rx_bps,
                3 => s.net_tx_bps,
            };
        }
        return buf[0..count];
    }
};

// --- テスト ---

const testing = std.testing;

test "History: 初期状態は len=0" {
    const h = History{};
    try testing.expectEqual(@as(usize, 0), h.len);
    try testing.expectEqual(@as(usize, 0), h.head);
}

test "History: push で len が増える" {
    var h = History{};
    h.push(.{ .cpu_pct = 10.0 });
    try testing.expectEqual(@as(usize, 1), h.len);
    h.push(.{ .cpu_pct = 20.0 });
    try testing.expectEqual(@as(usize, 2), h.len);
}

test "History: MAX_CAPACITY を超えても len は最大 MAX_CAPACITY" {
    var h = History{};
    for (0..MAX_CAPACITY + 5) |_| {
        h.push(.{});
    }
    try testing.expectEqual(MAX_CAPACITY, h.len);
}

test "History: getCpuPct は古い順に返す" {
    var h = History{};
    h.push(.{ .cpu_pct = 10.0 });
    h.push(.{ .cpu_pct = 20.0 });
    h.push(.{ .cpu_pct = 30.0 });
    var buf: [10]f64 = undefined;
    const s = h.getCpuPct(10, &buf);
    try testing.expectEqual(@as(usize, 3), s.len);
    try testing.expectApproxEqAbs(10.0, s[0], 1e-9);
    try testing.expectApproxEqAbs(20.0, s[1], 1e-9);
    try testing.expectApproxEqAbs(30.0, s[2], 1e-9);
}

test "History: getCpuPct n < len → 最新 n 件" {
    var h = History{};
    h.push(.{ .cpu_pct = 1.0 });
    h.push(.{ .cpu_pct = 2.0 });
    h.push(.{ .cpu_pct = 3.0 });
    var buf: [2]f64 = undefined;
    const s = h.getCpuPct(2, &buf);
    try testing.expectEqual(@as(usize, 2), s.len);
    try testing.expectApproxEqAbs(2.0, s[0], 1e-9);
    try testing.expectApproxEqAbs(3.0, s[1], 1e-9);
}

test "History: getMemPct は mem_pct を返す" {
    var h = History{};
    h.push(.{ .mem_pct = 55.0 });
    var buf: [5]f64 = undefined;
    const s = h.getMemPct(5, &buf);
    try testing.expectEqual(@as(usize, 1), s.len);
    try testing.expectApproxEqAbs(55.0, s[0], 1e-9);
}

test "History: getNetRxBps / getNetTxBps" {
    var h = History{};
    h.push(.{ .net_rx_bps = 1000.0, .net_tx_bps = 500.0 });
    var buf: [5]f64 = undefined;
    const rx = h.getNetRxBps(5, &buf);
    try testing.expectApproxEqAbs(1000.0, rx[0], 1e-9);
    const tx = h.getNetTxBps(5, &buf);
    try testing.expectApproxEqAbs(500.0, tx[0], 1e-9);
}

test "sampleFromUsage: net_count=0 の場合 rx/tx は 0" {
    const usage = snapshot_mod.UsageSnapshot{ .cpu_pct = 42.0, .mem_pct = 70.0 };
    const s = sampleFromUsage(usage);
    try testing.expectApproxEqAbs(42.0, s.cpu_pct, 1e-9);
    try testing.expectApproxEqAbs(70.0, s.mem_pct, 1e-9);
    try testing.expectApproxEqAbs(0.0, s.net_rx_bps, 1e-9);
    try testing.expectApproxEqAbs(0.0, s.net_tx_bps, 1e-9);
}

test "History: 空の場合 getCpuPct は空スライスを返す" {
    const h = History{};
    var buf: [10]f64 = undefined;
    const s = h.getCpuPct(10, &buf);
    try testing.expectEqual(@as(usize, 0), s.len);
}
