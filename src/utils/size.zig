// バイト数→人間可読変換

const std = @import("std");

const KB: u64 = 1024;
const MB: u64 = 1024 * KB;
const GB: u64 = 1024 * MB;
const TB: u64 = 1024 * GB;

/// バイト数を適切な単位 (B/KB/MB/GB/TB) に変換し "12.4 MB" 形式で buf に書き込む。
/// 返値: 書き込んだスライス。buf が短すぎる場合は空スライスを返す。
pub fn format(bytes: u64, buf: []u8) []const u8 {
    if (bytes >= TB) {
        const v = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(TB));
        return std.fmt.bufPrint(buf, "{d:.1} TB", .{v}) catch "";
    } else if (bytes >= GB) {
        const v = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(GB));
        return std.fmt.bufPrint(buf, "{d:.1} GB", .{v}) catch "";
    } else if (bytes >= MB) {
        const v = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(MB));
        return std.fmt.bufPrint(buf, "{d:.1} MB", .{v}) catch "";
    } else if (bytes >= KB) {
        const v = @as(f64, @floatFromInt(bytes)) / @as(f64, @floatFromInt(KB));
        return std.fmt.bufPrint(buf, "{d:.1} KB", .{v}) catch "";
    } else {
        return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch "";
    }
}

/// /proc/meminfo 等の kB 単位の値をバイトに変換して format() に渡す。
pub fn formatKb(kb: u64, buf: []u8) []const u8 {
    return format(kb * KB, buf);
}

/// bytes/sec を "12.4 MB/s" 形式で buf に書き込む。
pub fn formatRate(bytes_per_sec: f64, buf: []u8) []const u8 {
    const b: u64 = @intFromFloat(@max(bytes_per_sec, 0.0));
    var tmp: [32]u8 = undefined;
    const base = format(b, &tmp);
    return std.fmt.bufPrint(buf, "{s}/s", .{base}) catch "";
}

/// bytes/sec をミニ表示用 "12M" / "3K" / "500" 形式で buf に書き込む。
/// 小数点なし・単位のみ (M/K/なし)。
pub fn formatRateMini(bytes_per_sec: f64, buf: []u8) []const u8 {
    const b = @as(u64, @intFromFloat(@max(bytes_per_sec, 0.0)));
    if (b >= MB) {
        const v = b / MB;
        return std.fmt.bufPrint(buf, "{d}M", .{v}) catch "";
    } else if (b >= KB) {
        const v = b / KB;
        return std.fmt.bufPrint(buf, "{d}K", .{v}) catch "";
    } else {
        return std.fmt.bufPrint(buf, "{d}", .{b}) catch "";
    }
}
