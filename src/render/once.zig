// ワンショット stdout 出力

const std = @import("std");
const snapshot = @import("../collector/snapshot.zig");
const bar = @import("widgets/bar.zig");
const size = @import("../utils/size.zig");

/// vitals --json の JSON 出力を writer に書き込む。
///
/// 出力形式:
/// ```json
/// {
///   "timestamp_ms": 1234567890123,
///   "cpu": {"usage_pct": 42.0, "cores": [...]},
///   "memory": {"usage_pct": 65.0, "total_kb": ..., "used_kb": ...},
///   "swap": {"usage_pct": 5.0, "total_kb": ..., "used_kb": ...},
///   "load": {"load1": 3.42, "load5": 2.81, "load15": 2.15},
///   "disk": [...],
///   "network": [...]
/// }
/// ```
pub fn renderJson(
    writer: anytype,
    snap: snapshot.Snapshot,
    usage: snapshot.UsageSnapshot,
) !void {
    const ts_ms = @divTrunc(snap.timestamp_ns, std.time.ns_per_ms);

    try writer.writeAll("{\n");
    try writer.print("  \"timestamp_ms\": {d},\n", .{ts_ms});

    // CPU
    try writer.print("  \"cpu\": {{\"usage_pct\": {d:.2}, \"cores\": [", .{usage.cpu_pct});
    for (0..usage.core_count) |i| {
        if (i > 0) try writer.writeAll(", ");
        try writer.print("{d:.2}", .{usage.core_pct[i]});
    }
    try writer.writeAll("]},\n");

    // Memory
    const mem_available = snap.mem.mem_available orelse
        (snap.mem.mem_free + snap.mem.buffers + snap.mem.cached);
    try writer.print(
        "  \"memory\": {{\"usage_pct\": {d:.2}, \"total_kb\": {d}, \"used_kb\": {d}, \"available_kb\": {d}}},\n",
        .{ usage.mem_pct, snap.mem.mem_total, snap.mem.memUsed(), mem_available },
    );

    // Swap
    try writer.print(
        "  \"swap\": {{\"usage_pct\": {d:.2}, \"total_kb\": {d}, \"used_kb\": {d}}},\n",
        .{ usage.swap_pct, snap.mem.swap_total, snap.mem.swapUsed() },
    );

    // Load average
    try writer.print(
        "  \"load\": {{\"load1\": {d:.2}, \"load5\": {d:.2}, \"load15\": {d:.2}}},\n",
        .{ snap.load.load1, snap.load.load5, snap.load.load15 },
    );

    // Disk
    try writer.writeAll("  \"disk\": [");
    var first_disk = true;
    for (0..snap.disk.count) |i| {
        const stat = snap.disk.stats[i];
        if (!isRealMount(stat)) continue;
        if (!first_disk) try writer.writeAll(", ");
        first_disk = false;
        const total = stat.totalBytes();
        const avail = stat.availBytes();
        const used_pct: f64 = if (total > 0)
            @as(f64, @floatFromInt(total - avail)) / @as(f64, @floatFromInt(total)) * 100.0
        else
            0.0;
        try writer.print(
            "{{\"mount\": \"{s}\", \"usage_pct\": {d:.2}, \"total_bytes\": {d}, \"avail_bytes\": {d}}}",
            .{ stat.mountPointSlice(), used_pct, total, avail },
        );
    }
    try writer.writeAll("],\n");

    // Network
    try writer.writeAll("  \"network\": [");
    var first_net = true;
    for (0..snap.net.count) |i| {
        if (isLoopback(snap.net.ifaces[i])) continue;
        if (!first_net) try writer.writeAll(", ");
        first_net = false;
        const tp = if (i < usage.net_count) usage.net_throughput[i] else @import("../collector/network.zig").Throughput{};
        try writer.print(
            "{{\"interface\": \"{s}\", \"rx_bytes_per_sec\": {d:.2}, \"tx_bytes_per_sec\": {d:.2}}}",
            .{ snap.net.ifaces[i].nameSlice(), tp.rx_bytes_per_sec, tp.tx_bytes_per_sec },
        );
    }
    try writer.writeAll("]\n");

    try writer.writeAll("}\n");
}

/// ディスクマウントが表示対象かどうかを判定する。
/// totalBytes() == 0 の仮想FSや /proc /sys /dev /run 以下は除外する。
fn isRealMount(stat: @import("../collector/disk.zig").DiskStat) bool {
    if (stat.totalBytes() == 0) return false;
    const mp = stat.mountPointSlice();
    const skip_prefixes = [_][]const u8{ "/proc", "/sys", "/dev", "/run" };
    for (skip_prefixes) |pfx| {
        if (std.mem.startsWith(u8, mp, pfx)) return false;
    }
    return true;
}

/// ネットワークインターフェース名がループバックかどうかを判定する。
fn isLoopback(iface: @import("../collector/network.zig").NetIfStat) bool {
    return std.mem.eql(u8, iface.nameSlice(), "lo");
}

/// vitals --once の出力を writer に書き込む。
///
/// レイアウト (docs/requirements.md 参照):
/// ```
///   CPU  ████████████████████░░░░░░░░░░░░  42%    MEM  ████████████████████░░░░░░░░░░  65%
///   SWP  ▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   5%    LOAD 3.42 / 2.81 / 2.15
///
///   /      ████████████████░░░░░░░░  72%  187.0 GB free    eth0  ↓ 12.4 MB/s  ↑ 3.2 MB/s
///   /home  ████████░░░░░░░░░░░░░░░  45%  530.0 GB free
/// ```
pub fn render(
    writer: anytype,
    snap: snapshot.Snapshot,
    usage: snapshot.UsageSnapshot,
) !void {
    var buf: [64]u8 = undefined;

    // ── 1行目: CPU | MEM ────────────────────────────────────────────
    try writer.writeAll("  CPU  ");
    try bar.render(writer, usage.cpu_pct);
    try writer.print("  {d:3.0}%    MEM  ", .{usage.cpu_pct});
    try bar.render(writer, usage.mem_pct);
    try writer.print("  {d:3.0}%\n", .{usage.mem_pct});

    // ── 2行目: SWP | LOAD ───────────────────────────────────────────
    try writer.writeAll("  SWP  ");
    try bar.render(writer, usage.swap_pct);
    try writer.print("  {d:3.0}%    LOAD {d:.2} / {d:.2} / {d:.2}\n", .{
        usage.swap_pct,
        snap.load.load1,
        snap.load.load5,
        snap.load.load15,
    });

    try writer.writeByte('\n');

    // ── DISK 行 (実マウントのみ) ─────────────────────────────────────
    // ネットワーク: 最初の非ループバックインターフェース
    var net_printed = false;
    var disk_idx: usize = 0;

    for (0..snap.disk.count) |i| {
        const stat = snap.disk.stats[i];
        if (!isRealMount(stat)) continue;

        const total = stat.totalBytes();
        const avail = stat.availBytes();
        const used_pct: f64 = if (total > 0)
            @as(f64, @floatFromInt(total - avail)) / @as(f64, @floatFromInt(total)) * 100.0
        else
            0.0;

        const mp = stat.mountPointSlice();
        try writer.print("  {s:<8} ", .{mp});
        try bar.render(writer, used_pct);
        const avail_str = size.format(avail, &buf);
        try writer.print("  {d:3.0}%  {s} free", .{ used_pct, avail_str });

        // 危険ゾーン警告
        if (used_pct >= 90.0) try writer.writeAll(" \x1b[31m⚠\x1b[0m");

        // 最初のディスク行に NET を追記
        if (disk_idx == 0) {
            for (0..snap.net.count) |j| {
                if (isLoopback(snap.net.ifaces[j])) continue;
                const tp = if (j < usage.net_count) usage.net_throughput[j] else .{};
                const rx_str = size.formatRate(tp.rx_bytes_per_sec, &buf);
                var buf2: [32]u8 = undefined;
                const tx_str = size.formatRate(tp.tx_bytes_per_sec, &buf2);
                try writer.print("    {s}  \u{2193} {s}  \u{2191} {s}", .{
                    snap.net.ifaces[j].nameSlice(),
                    rx_str,
                    tx_str,
                });
                net_printed = true;
                break;
            }
        }

        try writer.writeByte('\n');
        disk_idx += 1;
    }

    // ディスクがない場合でも NET を表示
    if (!net_printed) {
        for (0..snap.net.count) |j| {
            if (isLoopback(snap.net.ifaces[j])) continue;
            const tp = if (j < usage.net_count) usage.net_throughput[j] else .{};
            const rx_str = size.formatRate(tp.rx_bytes_per_sec, &buf);
            var buf2: [32]u8 = undefined;
            const tx_str = size.formatRate(tp.tx_bytes_per_sec, &buf2);
            try writer.print("  {s}  \u{2193} {s}  \u{2191} {s}\n", .{
                snap.net.ifaces[j].nameSlice(),
                rx_str,
                tx_str,
            });
            break;
        }
    }
}

// --- テスト ---

const testing = std.testing;

test "renderJson: クラッシュしない (空のスナップショット)" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const snap = snapshot.Snapshot{};
    const usage = snapshot.UsageSnapshot{};
    try renderJson(fbs.writer(), snap, usage);
    const written = fbs.getWritten();
    try testing.expect(written.len > 0);
    try testing.expect(std.mem.indexOf(u8, written, "\"timestamp_ms\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\"cpu\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\"memory\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\"swap\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\"load\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\"disk\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\"network\"") != null);
}

test "renderJson: CPU 使用率が正しく出力される" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const snap = snapshot.Snapshot{};
    var usage = snapshot.UsageSnapshot{};
    usage.cpu_pct = 42.5;
    try renderJson(fbs.writer(), snap, usage);
    const written = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, written, "42.50") != null);
}

test "renderJson: メモリ情報が出力される" {
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var snap = snapshot.Snapshot{};
    snap.mem.mem_total = 16384;
    snap.mem.mem_free = 8192;
    snap.mem.mem_available = 8192;
    var usage = snapshot.UsageSnapshot{};
    usage.mem_pct = 50.0;
    try renderJson(fbs.writer(), snap, usage);
    const written = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, written, "16384") != null);
}
