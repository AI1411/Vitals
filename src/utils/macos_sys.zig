// macOS システムコール・データ構造 extern 宣言
// 本ファイルはコンパイル時 builtin.os.tag == .macos のときのみ使用する。

const std = @import("std");

// ── sysctl ─────────────────────────────────────────────────────────────
pub extern "c" fn sysctlbyname(
    name: [*:0]const u8,
    oldp: ?*anyopaque,
    oldlenp: ?*usize,
    newp: ?*anyopaque,
    newlen: usize,
) c_int;

// ── getloadavg ─────────────────────────────────────────────────────────
pub extern "c" fn getloadavg(loadavg: [*]f64, nelem: c_int) c_int;

// ── getfsstat ──────────────────────────────────────────────────────────
pub const MNT_NOWAIT: c_int = 2;
pub const MNT_LOCAL: u32 = 0x1000;

/// macOS struct statfs (Apple Silicon 実測: sizeof=2168)
/// オフセット:
///   f_bsize(u32)@0, f_iosize(i32)@4, f_blocks(u64)@8, f_bfree(u64)@16,
///   f_bavail(u64)@24, f_fsid([2]i32)@48, f_flags(u32)@64,
///   f_mntonname([1024]u8)@88, f_mntfromname([1024]u8)@1112
pub const MacStatfs = extern struct {
    f_bsize: u32,
    f_iosize: i32,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_owner: u32,
    f_type: u32,
    f_flags: u32,
    f_fssubtype: u32,
    f_fstypename: [16]u8,
    f_mntonname: [1024]u8,
    f_mntfromname: [1024]u8,
    f_reserved: [8]u32,
};

comptime {
    // レイアウト検証
    std.debug.assert(@sizeOf(MacStatfs) == 2168);
    std.debug.assert(@offsetOf(MacStatfs, "f_blocks") == 8);
    std.debug.assert(@offsetOf(MacStatfs, "f_bavail") == 24);
    std.debug.assert(@offsetOf(MacStatfs, "f_flags") == 64);
    std.debug.assert(@offsetOf(MacStatfs, "f_mntonname") == 88);
    std.debug.assert(@offsetOf(MacStatfs, "f_mntfromname") == 1112);
}

pub extern "c" fn getfsstat(buf: ?[*]MacStatfs, bufsize: i32, flags: c_int) c_int;

// ── getifaddrs ─────────────────────────────────────────────────────────
pub const AF_LINK: u8 = 18;

/// macOS struct if_data (Apple Silicon 実測: sizeof=96, ifi_ibytes@40, ifi_obytes@44)
pub const IfData = extern struct {
    ifi_type: u8,
    ifi_typelen: u8,
    ifi_physical: u8,
    ifi_addrlen: u8,
    ifi_hdrlen: u8,
    ifi_recvquota: u8,
    ifi_xmitquota: u8,
    ifi_unused1: u8,
    ifi_mtu: u32,
    ifi_metric: u32,
    ifi_baudrate: u32,
    ifi_ipackets: u32,
    ifi_ierrors: u32,
    ifi_opackets: u32,
    ifi_oerrors: u32,
    ifi_collisions: u32,
    ifi_ibytes: u32, // @40
    ifi_obytes: u32, // @44
    _pad: [48]u8,
};

comptime {
    std.debug.assert(@sizeOf(IfData) == 96);
    std.debug.assert(@offsetOf(IfData, "ifi_ibytes") == 40);
    std.debug.assert(@offsetOf(IfData, "ifi_obytes") == 44);
}

/// macOS struct ifaddrs
pub const Ifaddrs = extern struct {
    ifa_next: ?*Ifaddrs,
    ifa_name: ?[*:0]const u8,
    ifa_flags: u32,
    _pad: u32, // ポインタ整列のためのパディング
    ifa_addr: ?*anyopaque,
    ifa_netmask: ?*anyopaque,
    ifa_dstaddr: ?*anyopaque,
    ifa_data: ?*anyopaque,
};

pub extern "c" fn getifaddrs(ifap: **Ifaddrs) c_int;
pub extern "c" fn freeifaddrs(ifp: *Ifaddrs) void;

// ── Mach host statistics ───────────────────────────────────────────────
pub const mach_port_t = u32;
pub const kern_return_t = c_int;
pub const host_flavor_t = c_int;
pub const mach_msg_type_number_t = u32;

pub const HOST_VM_INFO64: host_flavor_t = 4;
/// vm_statistics64_data_t は u32 を 40 個並べた 160 バイト
pub const HOST_VM_INFO64_COUNT: mach_msg_type_number_t = 40;

/// vm_statistics64 フィールドの u32 配列インデックス (Apple Silicon 実測)
pub const VM_STAT64_FREE_IDX: usize = 0; // free_count @0
pub const VM_STAT64_INACTIVE_IDX: usize = 2; // inactive_count @8
pub const VM_STAT64_WIRE_IDX: usize = 3; // wire_count @12
pub const VM_STAT64_SPECULATIVE_IDX: usize = 23; // speculative_count @92

pub extern "c" fn mach_host_self() mach_port_t;
pub extern "c" fn host_statistics64(
    host_priv: mach_port_t,
    flavor: host_flavor_t,
    host_info_out: [*]u32,
    host_info_outCnt: *mach_msg_type_number_t,
) kern_return_t;

// ── xsw_usage (vm.swapusage) ───────────────────────────────────────────
/// struct xsw_usage (sizeof=32)
pub const XswUsage = extern struct {
    xsu_total: u64, // @0
    xsu_avail: u64, // @8
    xsu_used: u64, // @16
    xsu_pagesize: u32, // @24
    xsu_encrypted: u32, // @28
};

comptime {
    std.debug.assert(@sizeOf(XswUsage) == 32);
}
