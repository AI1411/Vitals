// /proc/meminfo パーサー (Linux) / sysctl + host_statistics64 (macOS)

const std = @import("std");
const builtin = @import("builtin");

/// /proc/meminfo から取得したメモリ情報 (単位: kB)
pub const MemInfo = struct {
    mem_total: u64 = 0,
    mem_free: u64 = 0,
    /// MemAvailable は古いカーネルで欠落しうるため optional
    mem_available: ?u64 = null,
    buffers: u64 = 0,
    cached: u64 = 0,
    swap_total: u64 = 0,
    swap_free: u64 = 0,

    /// Used = Total - Available
    /// MemAvailable が欠落している場合は MemFree + Buffers + Cached でフォールバック
    pub fn memUsed(self: MemInfo) u64 {
        const available = self.mem_available orelse (self.mem_free + self.buffers + self.cached);
        return self.mem_total -| available;
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

/// macOS: sysctlbyname + host_statistics64 からメモリ情報を収集する。
/// - hw.memsize → 物理メモリ合計 (bytes)
/// - host_statistics64(HOST_VM_INFO64) → free / inactive / speculative ページ数
/// - vm.swapusage → スワップ使用量
/// available = (free + inactive + speculative) * page_size
pub fn collectMacos() MemInfo {
    const sys = @import("../utils/macos_sys.zig");
    var info = MemInfo{};

    // ── 物理メモリ合計 ─────────────────────────────────────────────
    var mem_size: u64 = 0;
    var mem_size_len: usize = @sizeOf(u64);
    _ = sys.sysctlbyname("hw.memsize", &mem_size, &mem_size_len, null, 0);
    info.mem_total = mem_size / 1024;

    // ── ページサイズ取得 ──────────────────────────────────────────
    var page_size: u32 = 16384;
    var page_size_len: usize = @sizeOf(u32);
    _ = sys.sysctlbyname("hw.pagesize", &page_size, &page_size_len, null, 0);

    // ── VM 統計 (vm_statistics64) ──────────────────────────────────
    var vm_info: [sys.HOST_VM_INFO64_COUNT]u32 = .{0} ** sys.HOST_VM_INFO64_COUNT;
    var vm_count: sys.mach_msg_type_number_t = sys.HOST_VM_INFO64_COUNT;
    const kr = sys.host_statistics64(
        sys.mach_host_self(),
        sys.HOST_VM_INFO64,
        @as([*]u32, &vm_info),
        &vm_count,
    );
    if (kr == 0) {
        const free_pages: u64 = vm_info[sys.VM_STAT64_FREE_IDX];
        const inactive_pages: u64 = vm_info[sys.VM_STAT64_INACTIVE_IDX];
        const speculative_pages: u64 = vm_info[sys.VM_STAT64_SPECULATIVE_IDX];
        const available_bytes = (free_pages + inactive_pages + speculative_pages) *
            @as(u64, page_size);
        info.mem_available = available_bytes / 1024;
        info.mem_free = (free_pages * @as(u64, page_size)) / 1024;
    }

    // ── スワップ使用量 ─────────────────────────────────────────────
    var swap: sys.XswUsage = std.mem.zeroes(sys.XswUsage);
    var swap_len: usize = @sizeOf(sys.XswUsage);
    _ = sys.sysctlbyname("vm.swapusage", &swap, &swap_len, null, 0);
    info.swap_total = swap.xsu_total / 1024;
    info.swap_free = swap.xsu_avail / 1024;

    return info;
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
