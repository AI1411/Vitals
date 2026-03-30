// /proc/mounts + statvfs パーサー

const std = @import("std");

pub const MAX_MOUNTS = 32;
/// Linux PATH_MAX
const PATH_MAX = 4096;

/// 1マウントポイントのディスク使用量情報
pub const DiskStat = struct {
    /// マウントポイントパス（固定バッファ、表示用）
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

/// /proc/mounts の1行からマウントポイントを抽出する（生エスケープあり）。
/// フォーマット: "device mountpoint fstype options dump pass"
/// 空行・コメント行・解析失敗時は null を返す。
/// 返値はオクタルエスケープを含む可能性があるため、使用前に decodeMountPath を適用すること。
pub fn parseMountsLine(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0 or trimmed[0] == '#') return null;

    var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
    _ = it.next() orelse return null; // device
    return it.next(); // mountpoint (raw, may contain \040 etc.)
}

/// /proc/mounts のオクタルエスケープをデコードして buf に書き込み、書き込んだスライスを返す。
/// `\040` → ' ', `\011` → '\t', `\012` → '\n', `\134` → '\\' など3桁オクタルに対応。
/// buf が短い場合は途中で切り捨てる。
pub fn decodeMountPath(raw: []const u8, buf: []u8) []u8 {
    var out: usize = 0;
    var i: usize = 0;
    while (i < raw.len and out < buf.len) {
        if (raw[i] == '\\' and i + 3 < raw.len) {
            if (std.fmt.parseInt(u8, raw[i + 1 .. i + 4], 8)) |byte| {
                buf[out] = byte;
                out += 1;
                i += 4;
            } else |_| {
                buf[out] = raw[i];
                out += 1;
                i += 1;
            }
        } else {
            buf[out] = raw[i];
            out += 1;
            i += 1;
        }
    }
    return buf[0..out];
}

/// statvfs() を呼び出して指定マウントポイントの DiskStat を返す。
/// mount_point はデコード済みのパス（PATH_MAX 未満）を渡す。
pub fn statDisk(mount_point: []const u8) !DiskStat {
    if (mount_point.len == 0 or mount_point.len >= PATH_MAX) return error.InvalidPath;

    var path_buf: [PATH_MAX]u8 = undefined;
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
        const raw_mp = parseMountsLine(line) orelse continue;

        if (snapshot.count >= MAX_MOUNTS) {
            snapshot.truncated = true;
            break;
        }

        var decoded_buf: [PATH_MAX]u8 = undefined;
        const mp = decodeMountPath(raw_mp, &decoded_buf);
        const stat = statDisk(mp) catch continue;
        snapshot.stats[snapshot.count] = stat;
        snapshot.count += 1;
    }

    return snapshot;
}
