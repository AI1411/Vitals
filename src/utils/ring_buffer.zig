// 固定サイズリングバッファ

const std = @import("std");
const snapshot_mod = @import("../collector/snapshot.zig");

/// リングバッファの容量 (5分 × 1秒間隔)
pub const CAPACITY: usize = 300;

/// 固定サイズ・ゼロアロケーションのスナップショット履歴バッファ。
pub const HistoryBuffer = struct {
    snapshots: [CAPACITY]snapshot_mod.Snapshot = [_]snapshot_mod.Snapshot{.{}} ** CAPACITY,
    /// 次の書き込み位置。バッファが満杯の場合は最古エントリの位置でもある。
    head: usize = 0,
    /// バッファに格納済みのエントリ数 (最大 CAPACITY)
    len: usize = 0,

    /// 新しいスナップショットを追加する。バッファが満杯の場合は最古を上書き。
    pub fn push(self: *HistoryBuffer, snap: snapshot_mod.Snapshot) void {
        self.snapshots[self.head] = snap;
        self.head = (self.head + 1) % CAPACITY;
        if (self.len < CAPACITY) self.len += 1;
    }

    /// 最新の n 件を古い順で返す。n > len の場合は全件を返す。
    /// バッファがラップしていない場合は直接スライスを返す。
    /// ラップしている場合は連続した部分のみを返す可能性があるため、
    /// 完全な順序保証が必要な場合は getOrdered を使用すること。
    pub fn latest(self: *const HistoryBuffer, n: usize) []const snapshot_mod.Snapshot {
        const count = @min(n, self.len);
        if (count == 0) return &[_]snapshot_mod.Snapshot{};

        // head は次の書き込み位置 (= 最新エントリの次)
        // 最新 count 件の開始位置
        const start = (self.head + CAPACITY - count) % CAPACITY;

        if (start < self.head) {
            // ラップなし: 連続したスライスを直接返す
            return self.snapshots[start..self.head];
        } else if (self.head == 0) {
            // head がちょうど 0 のとき: 末尾から count 件
            return self.snapshots[CAPACITY - count .. CAPACITY];
        } else {
            // ラップあり: start から配列末尾までの連続部分を返す
            return self.snapshots[start..CAPACITY];
        }
    }

    /// 最新の n 件を buf に古い順でコピーし、コピーしたスライスを返す。
    /// ラップが発生している場合でも正しい順序を保証する。
    pub fn getOrdered(self: *const HistoryBuffer, n: usize, buf: []snapshot_mod.Snapshot) []snapshot_mod.Snapshot {
        const count = @min(n, @min(self.len, buf.len));
        if (count == 0) return buf[0..0];

        const oldest = if (self.len < CAPACITY) 0 else self.head;
        const skip = self.len - count;
        for (0..count) |i| {
            buf[i] = self.snapshots[(oldest + skip + i) % CAPACITY];
        }
        return buf[0..count];
    }
};

// --- テスト ---

const testing = std.testing;

test "HistoryBuffer: 初期状態は len=0" {
    const buf = HistoryBuffer{};
    try testing.expectEqual(@as(usize, 0), buf.len);
    try testing.expectEqual(@as(usize, 0), buf.head);
}

test "HistoryBuffer: push で len が増える" {
    var buf = HistoryBuffer{};
    var s = snapshot_mod.Snapshot{};
    s.timestamp_ns = 1;
    buf.push(s);
    try testing.expectEqual(@as(usize, 1), buf.len);
    try testing.expectEqual(@as(usize, 1), buf.head);
}

test "HistoryBuffer: CAPACITY を超えても len は最大 CAPACITY" {
    var buf = HistoryBuffer{};
    var s = snapshot_mod.Snapshot{};
    for (0..CAPACITY + 5) |i| {
        s.timestamp_ns = @intCast(i);
        buf.push(s);
    }
    try testing.expectEqual(CAPACITY, buf.len);
}

test "HistoryBuffer: latest(0) → 空スライス" {
    var buf = HistoryBuffer{};
    var s = snapshot_mod.Snapshot{};
    s.timestamp_ns = 1;
    buf.push(s);
    try testing.expectEqual(@as(usize, 0), buf.latest(0).len);
}

test "HistoryBuffer: latest(n) で n > len → 全件返す" {
    var buf = HistoryBuffer{};
    var s1 = snapshot_mod.Snapshot{};
    s1.timestamp_ns = 10;
    var s2 = snapshot_mod.Snapshot{};
    s2.timestamp_ns = 20;
    buf.push(s1);
    buf.push(s2);
    const items = buf.latest(10);
    try testing.expectEqual(@as(usize, 2), items.len);
}

test "HistoryBuffer: latest(n) で n < len → 最新 n 件" {
    var buf = HistoryBuffer{};
    for (0..5) |i| {
        var s = snapshot_mod.Snapshot{};
        s.timestamp_ns = @intCast(i + 1);
        buf.push(s);
    }
    const items = buf.latest(3);
    try testing.expectEqual(@as(usize, 3), items.len);
    // 最新3件: timestamp 3,4,5
    try testing.expectEqual(@as(i128, 3), items[0].timestamp_ns);
    try testing.expectEqual(@as(i128, 4), items[1].timestamp_ns);
    try testing.expectEqual(@as(i128, 5), items[2].timestamp_ns);
}

test "HistoryBuffer: getOrdered は正しい順序で返す (満杯後)" {
    var buf = HistoryBuffer{};
    // CAPACITY + 2 件プッシュして最古 2 件を上書き
    for (0..CAPACITY + 2) |i| {
        var s = snapshot_mod.Snapshot{};
        s.timestamp_ns = @intCast(i);
        buf.push(s);
    }
    var out: [5]snapshot_mod.Snapshot = undefined;
    const items = buf.getOrdered(3, &out);
    try testing.expectEqual(@as(usize, 3), items.len);
    // 最新3件: CAPACITY-1, CAPACITY, CAPACITY+1
    try testing.expectEqual(@as(i128, CAPACITY - 1), items[0].timestamp_ns);
    try testing.expectEqual(@as(i128, CAPACITY), items[1].timestamp_ns);
    try testing.expectEqual(@as(i128, CAPACITY + 1), items[2].timestamp_ns);
}

test "HistoryBuffer: getOrdered は空バッファで空スライス" {
    const buf = HistoryBuffer{};
    var out: [10]snapshot_mod.Snapshot = undefined;
    const items = buf.getOrdered(5, &out);
    try testing.expectEqual(@as(usize, 0), items.len);
}
