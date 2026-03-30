// 全メトリクスの1時点構造体

const std = @import("std");
const builtin = @import("builtin");
const cpu_mod = @import("cpu.zig");
const memory_mod = @import("memory.zig");
const disk_mod = @import("disk.zig");
const network_mod = @import("network.zig");
const loadavg_mod = @import("loadavg.zig");
const proc_reader = @import("../utils/proc_reader.zig");

/// 1時点のシステム状態を集約した構造体。
/// 各コレクターの生データを保持し、Renderer に渡す統一データ型として機能する。
pub const Snapshot = struct {
    /// CPU 生カウンタ (全体行 + コア別)
    cpu: cpu_mod.CpuSnapshot = .{},
    /// メモリ情報 (kB 単位)
    mem: memory_mod.MemInfo = .{},
    /// ディスク使用量
    disk: disk_mod.DiskSnapshot = .{},
    /// ネットワーク I/O バイト数
    net: network_mod.NetSnapshot = .{},
    /// ロードアベレージ
    load: loadavg_mod.LoadAvg = .{},
    /// スナップショット取得時刻 (nanoseconds since epoch)
    timestamp_ns: i128 = 0,
};

/// 2つの Snapshot 間の差分から計算した使用率をまとめた構造体。
pub const UsageSnapshot = struct {
    /// CPU 全体使用率 (0.0〜100.0)
    cpu_pct: f64 = 0.0,
    /// コア別使用率 (0.0〜100.0)
    core_pct: [cpu_mod.MAX_CORES]f64 = [_]f64{0.0} ** cpu_mod.MAX_CORES,
    core_count: usize = 0,
    /// メモリ使用率 (0.0〜100.0)
    mem_pct: f64 = 0.0,
    /// スワップ使用率 (0.0〜100.0)
    swap_pct: f64 = 0.0,
    /// インターフェース別スループット (bytes/sec)
    net_throughput: [network_mod.MAX_IFACES]network_mod.Throughput =
        [_]network_mod.Throughput{.{}} ** network_mod.MAX_IFACES,
    /// net_throughput の有効エントリ数 (curr.net.count に対応)
    net_count: usize = 0,
};

/// 現在の Snapshot を返す。
/// macOS では sysctl / mach API を使用する。
/// Linux では /proc 以下の各ファイルを読み取る。
/// buf は Linux 専用 (proc_reader.PROC_BUF_SIZE = 64 KB 以上推奨)。
pub fn collect(buf: []u8) Snapshot {
    var snap = Snapshot{};
    snap.timestamp_ns = std.time.nanoTimestamp();

    if (comptime builtin.os.tag == .macos) {
        snap.cpu = cpu_mod.collectMacos();
        snap.mem = memory_mod.collectMacos();
        snap.disk = disk_mod.collectMacos();
        snap.net = network_mod.collectMacos();
        snap.load = loadavg_mod.collectMacos();
    } else {
        // Linux: /proc 以下を読み取る
        if (proc_reader.read("/proc/stat", buf)) |content| {
            snap.cpu = cpu_mod.parseSnapshot(content);
        } else |_| {}

        if (proc_reader.read("/proc/meminfo", buf)) |content| {
            snap.mem = memory_mod.parseSnapshot(content);
        } else |_| {}

        if (proc_reader.read("/proc/mounts", buf)) |content| {
            snap.disk = disk_mod.collect(content);
        } else |_| {}

        if (proc_reader.read("/proc/net/dev", buf)) |content| {
            snap.net = network_mod.parseSnapshot(content);
        } else |_| {}

        if (proc_reader.read("/proc/loadavg", buf)) |content| {
            snap.load = loadavg_mod.parseSnapshot(content) orelse .{};
        } else |_| {}
    }

    return snap;
}

/// 2つの Snapshot と経過時間 (秒) から UsageSnapshot を計算する。
/// interval_sec が 0 以下の場合、CPU/NET 計算は 0.0 になる。
pub fn calcUsage(prev: Snapshot, curr: Snapshot, interval_sec: f64) UsageSnapshot {
    var usage = UsageSnapshot{};

    // CPU 全体
    usage.cpu_pct = cpu_mod.calcUsage(prev.cpu.total, curr.cpu.total);

    // コア別
    usage.core_count = curr.cpu.core_count;
    for (0..curr.cpu.core_count) |i| {
        usage.core_pct[i] = cpu_mod.calcUsage(prev.cpu.cores[i], curr.cpu.cores[i]);
    }

    // メモリ
    if (curr.mem.mem_total > 0) {
        usage.mem_pct = @as(f64, @floatFromInt(curr.mem.memUsed())) /
            @as(f64, @floatFromInt(curr.mem.mem_total)) * 100.0;
    }
    if (curr.mem.swap_total > 0) {
        usage.swap_pct = @as(f64, @floatFromInt(curr.mem.swapUsed())) /
            @as(f64, @floatFromInt(curr.mem.swap_total)) * 100.0;
    }

    // ネットワーク
    usage.net_count = curr.net.count;
    for (0..@min(curr.net.count, prev.net.count)) |i| {
        usage.net_throughput[i] = network_mod.calcThroughput(
            prev.net.ifaces[i],
            curr.net.ifaces[i],
            interval_sec,
        );
    }

    return usage;
}
