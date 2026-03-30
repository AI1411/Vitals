// /proc/mounts + statvfs パーサー

const std = @import("std");

pub const MAX_MOUNTS = 32;

/// 1マウントポイントのディスク使用量情報
pub const DiskStat = struct {
    /// マウントポイントパス（固定バッファ）
    mount_point: [256]u8 = [_]u8{0} ** 256,
    mount_point_len: usize = 0,
    /// 基本ブロックサイズ (bytes) — statvfs f_frsize
    block_size: u64 = 0,
    /// 総ブロック数 — statvfs f_blocks
    total_blocks: u64 = 0,
    /// 非特権ユーザー向け空きブロック数 — statvfs f_bavail
    avail_blocks: u64 = 0,

    pub fn mountPointSlice(self: *const DiskStat) []const u8 {
        return self.mount_point[0..self.mount_point_len];
    }

    pub fn totalBytes(self: DiskStat) u64 {
        return self.total_blocks * self.block_size;
    }

    pub fn availBytes(self: DiskStat) u64 {
        return self.avail_blocks * self.block_size;
    }

    /// Used = Total - Avail (アンダーフロー保護付き)
    pub fn usedBytes(self: DiskStat) u64 {
        return self.totalBytes() -| self.availBytes();
    }
};

/// /proc/mounts から収集したスナップショット
pub const DiskSnapshot = struct {
    stats: [MAX_MOUNTS]DiskStat = [_]DiskStat{.{}} ** MAX_MOUNTS,
    count: usize = 0,
    /// MAX_MOUNTS を超えるエントリが存在したとき true
    truncated: bool = false,
};

/// /proc/mounts の1行からマウントポイントを抽出する。
/// フォーマット: "device mountpoint fstype options dump pass"
/// 空行・コメント行・解析失敗時は null を返す。
pub fn parseMountsLine(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0 or trimmed[0] == '#') return null;

    var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
    _ = it.next() orelse return null; // device
    return it.next(); // mountpoint
}

/// statvfs() を呼び出して指定マウントポイントの DiskStat を返す。
pub fn statDisk(mount_point: []const u8) !DiskStat {
    if (mount_point.len == 0 or mount_point.len >= 256) return error.InvalidPath;

    var path_buf: [256]u8 = undefined;
    @memcpy(path_buf[0..mount_point.len], mount_point);
    path_buf[mount_point.len] = 0;
    const path_z: [:0]const u8 = path_buf[0..mount_point.len :0];

    const sv = try std.posix.statvfs(path_z);

    var stat = DiskStat{};
    const copy_len = @min(mount_point.len, stat.mount_point.len);
    @memcpy(stat.mount_point[0..copy_len], mount_point[0..copy_len]);
    stat.mount_point_len = copy_len;
    stat.block_size = sv.f_frsize;
    stat.total_blocks = sv.f_blocks;
    stat.avail_blocks = sv.f_bavail;
    return stat;
}

/// /proc/mounts の内容をパースし、各マウントポイントで statvfs() を実行して
/// DiskSnapshot を返す。固定バッファを使用しヒープアロケーションなし。
pub fn collect(mounts_content: []const u8) DiskSnapshot {
    var snapshot = DiskSnapshot{};
    var lines = std.mem.tokenizeScalar(u8, mounts_content, '\n');

    while (lines.next()) |line| {
        const mp = parseMountsLine(line) orelse continue;

        if (snapshot.count >= MAX_MOUNTS) {
            snapshot.truncated = true;
            break;
        }

        const stat = statDisk(mp) catch continue;
        snapshot.stats[snapshot.count] = stat;
        snapshot.count += 1;
    }

    return snapshot;
}
