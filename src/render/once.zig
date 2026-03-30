// ワンショット stdout 出力

const std = @import("std");
const snapshot = @import("../collector/snapshot.zig");
const bar = @import("widgets/bar.zig");
const size = @import("../utils/size.zig");

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
