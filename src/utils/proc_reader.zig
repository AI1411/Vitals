// /proc ファイル読み取りヘルパー

const std = @import("std");

/// /proc ファイル用推奨バッファサイズ (64 KB)
pub const PROC_BUF_SIZE = 65536;

/// path で指定したファイルを buf に読み取り、読み取ったスライスを返す。
/// ヒープアロケーションなし。読み取りに失敗した場合はエラーを返す。
pub fn read(path: []const u8, buf: []u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();
    const n = try file.readAll(buf);
    return buf[0..n];
}

/// dir と name を "/" で結合したパスのファイルを buf に読み取る。
/// path_buf は最低 dir.len + name.len + 2 バイト必要。
pub fn readAt(dir: []const u8, name: []const u8, buf: []u8, path_buf: []u8) ![]u8 {
    const path = try std.fmt.bufPrint(path_buf, "{s}/{s}", .{ dir, name });
    return read(path, buf);
}
