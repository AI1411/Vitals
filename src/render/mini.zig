// 1行ミニ出力

const std = @import("std");
const snapshot = @import("../collector/snapshot.zig");
const size = @import("../utils/size.zig");
const disk_mod = @import("../collector/disk.zig");
const network_mod = @import("../collector/network.zig");

/// ディスクの最大使用率 (%) を計算する。
/// 実マウント (totalBytes > 0、/proc /sys /dev /run 除外) の中で最も高い値を返す。
fn maxDiskPct(disk: disk_mod.DiskSnapshot) f64 {
    var max: f64 = 0.0;
    const skip_prefixes = [_][]const u8{ "/proc", "/sys", "/dev", "/run" };
    for (0..disk.count) |i| {
        const stat = disk.stats[i];
        const total = stat.totalBytes();
        if (total == 0) continue;
        const mp = stat.mountPointSlice();
        var skip = false;
        for (skip_prefixes) |pfx| {
            if (std.mem.startsWith(u8, mp, pfx)) {
                skip = true;
                break;
            }
        }
        if (skip) continue;
        const pct = @as(f64, @floatFromInt(total - stat.availBytes())) /
            @as(f64, @floatFromInt(total)) * 100.0;
        if (pct > max) max = pct;
    }
    return max;
}

/// vitals --mini の1行出力を writer に書き込む。
///
/// 出力フォーマット:
///   CPU 42% │ MEM 65% │ DISK 72% │ NET ↓12M ↑3M │ LOAD 3.42
pub fn render(
    writer: anytype,
    snap: snapshot.Snapshot,
    usage: snapshot.UsageSnapshot,
) !void {
    var buf: [32]u8 = undefined;

    // CPU
    try writer.print("CPU {d:.0}%", .{usage.cpu_pct});

    // MEM
    try writer.print(" \u{2502} MEM {d:.0}%", .{usage.mem_pct});

    // DISK (全実マウント中の最大使用率)
    const disk_pct = maxDiskPct(snap.disk);
    try writer.print(" \u{2502} DISK {d:.0}%", .{disk_pct});

    // NET (最初の非ループバックインターフェース)
    for (0..snap.net.count) |i| {
        const iface = snap.net.ifaces[i];
        if (std.mem.eql(u8, iface.nameSlice(), "lo")) continue;
        const tp = if (i < usage.net_count) usage.net_throughput[i] else network_mod.Throughput{};
        const rx_str = size.formatRateMini(tp.rx_bytes_per_sec, &buf);
        var buf2: [32]u8 = undefined;
        const tx_str = size.formatRateMini(tp.tx_bytes_per_sec, &buf2);
        try writer.print(" \u{2502} NET \u{2193}{s} \u{2191}{s}", .{ rx_str, tx_str });
        break;
    }

    // LOAD
    try writer.print(" \u{2502} LOAD {d:.2}\n", .{snap.load.load1});
}
