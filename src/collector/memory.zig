// /proc/meminfo パーサー

const std = @import("std");

/// /proc/meminfo から取得したメモリ情報 (単位: kB)
pub const MemInfo = struct {
    mem_total: u64 = 0,
    mem_free: u64 = 0,
    mem_available: u64 = 0,
    buffers: u64 = 0,
    cached: u64 = 0,
    swap_total: u64 = 0,
    swap_free: u64 = 0,

    /// Used = Total - Available
    pub fn memUsed(self: MemInfo) u64 {
        return self.mem_total -| self.mem_available;
    }

    /// Swap Used = SwapTotal - SwapFree
    pub fn swapUsed(self: MemInfo) u64 {
        return self.swap_total -| self.swap_free;
    }
};

/// /proc/meminfo の1行をパースして (key, value_kb) を返す。
/// フォーマット: "Key:   <value> kB"
/// 解析失敗時は null を返す。
pub fn parseMemLine(line: []const u8) ?struct { key: []const u8, value: u64 } {
    const colon = std.mem.indexOf(u8, line, ":") orelse return null;
    const key = std.mem.trim(u8, line[0..colon], " ");

    var it = std.mem.tokenizeScalar(u8, line[colon + 1 ..], ' ');
    const val_str = it.next() orelse return null;
    const value = std.fmt.parseInt(u64, val_str, 10) catch return null;

    return .{ .key = key, .value = value };
}

/// /proc/meminfo の内容をパースして MemInfo を返す。
/// 固定バッファを使用しヒープアロケーションなし。
pub fn parseSnapshot(content: []const u8) MemInfo {
    var info = MemInfo{};
    var lines = std.mem.tokenizeScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const kv = parseMemLine(line) orelse continue;

        if (std.mem.eql(u8, kv.key, "MemTotal")) {
            info.mem_total = kv.value;
        } else if (std.mem.eql(u8, kv.key, "MemFree")) {
            info.mem_free = kv.value;
        } else if (std.mem.eql(u8, kv.key, "MemAvailable")) {
            info.mem_available = kv.value;
        } else if (std.mem.eql(u8, kv.key, "Buffers")) {
            info.buffers = kv.value;
        } else if (std.mem.eql(u8, kv.key, "Cached")) {
            info.cached = kv.value;
        } else if (std.mem.eql(u8, kv.key, "SwapTotal")) {
            info.swap_total = kv.value;
        } else if (std.mem.eql(u8, kv.key, "SwapFree")) {
            info.swap_free = kv.value;
        }
    }

    return info;
}
