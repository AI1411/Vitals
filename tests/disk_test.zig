const std = @import("std");
const testing = std.testing;
const disk = @import("disk");

const proc_mounts_fixture = @embedFile("fixtures/proc_mounts.txt");

// --- fixture 構造チェック ---

test "proc_mounts fixture: / エントリが存在する" {
    var lines = std.mem.tokenizeScalar(u8, proc_mounts_fixture, '\n');
    var found = false;
    while (lines.next()) |line| {
        if (disk.parseMountsLine(line)) |mp| {
            if (std.mem.eql(u8, mp, "/")) {
                found = true;
                break;
            }
        }
    }
    try testing.expect(found);
}

// --- parseMountsLine ---

test "parseMountsLine: 通常エントリからマウントポイントを抽出" {
    const mp = disk.parseMountsLine("/dev/sda1 / ext4 rw,relatime 0 0") orelse return error.ParseFailed;
    try testing.expectEqualStrings("/", mp);
}

test "parseMountsLine: /boot エントリをパース" {
    const mp = disk.parseMountsLine("/dev/sda2 /boot ext4 rw,relatime 0 0") orelse return error.ParseFailed;
    try testing.expectEqualStrings("/boot", mp);
}

test "parseMountsLine: /proc エントリをパース" {
    const mp = disk.parseMountsLine("proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0") orelse return error.ParseFailed;
    try testing.expectEqualStrings("/proc", mp);
}

test "parseMountsLine: 空行は null を返す" {
    try testing.expectEqual(@as(?[]const u8, null), disk.parseMountsLine(""));
}

test "parseMountsLine: コメント行は null を返す" {
    try testing.expectEqual(@as(?[]const u8, null), disk.parseMountsLine("# this is a comment"));
}

test "parseMountsLine: デバイスのみの行は null を返す" {
    try testing.expectEqual(@as(?[]const u8, null), disk.parseMountsLine("singletoken"));
}

// --- DiskStat ヘルパー ---

test "DiskStat.totalBytes: block_size * total_blocks" {
    const s = disk.DiskStat{
        .block_size = 4096,
        .total_blocks = 1000,
        .avail_blocks = 400,
    };
    try testing.expectEqual(@as(u64, 4096 * 1000), s.totalBytes());
}

test "DiskStat.availBytes: block_size * avail_blocks" {
    const s = disk.DiskStat{
        .block_size = 4096,
        .total_blocks = 1000,
        .avail_blocks = 400,
    };
    try testing.expectEqual(@as(u64, 4096 * 400), s.availBytes());
}

test "DiskStat.usedBytes: Total - Avail" {
    const s = disk.DiskStat{
        .block_size = 4096,
        .total_blocks = 1000,
        .avail_blocks = 400,
    };
    try testing.expectEqual(@as(u64, 4096 * 600), s.usedBytes());
}

test "DiskStat.usedBytes: Avail > Total のときアンダーフローしない" {
    const s = disk.DiskStat{
        .block_size = 512,
        .total_blocks = 100,
        .avail_blocks = 200,
    };
    try testing.expectEqual(@as(u64, 0), s.usedBytes());
}

test "DiskStat.mountPointSlice: マウントポイント文字列を返す" {
    var s = disk.DiskStat{};
    const path = "/boot";
    @memcpy(s.mount_point[0..path.len], path);
    s.mount_point_len = path.len;
    try testing.expectEqualStrings(path, s.mountPointSlice());
}
