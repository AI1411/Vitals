// 汎用行パーサー

const std = @import("std");

/// スペース / タブ区切りで先頭トークンを1つ取り出す。
/// 返値: { token, rest } — rest は残りの未処理文字列。
/// 入力が空またはトークンがない場合は null を返す。
pub fn nextToken(s: []const u8) ?struct { token: []const u8, rest: []const u8 } {
    const trimmed = std.mem.trimLeft(u8, s, " \t");
    if (trimmed.len == 0) return null;
    const end = std.mem.indexOfAny(u8, trimmed, " \t") orelse trimmed.len;
    return .{ .token = trimmed[0..end], .rest = trimmed[end..] };
}

/// "Key: value" または "Key value" 形式の行をパースして key/value ペアを返す。
/// コロンが含まれる場合は "key: value" 形式として解析する。
/// コロンがない場合は最初のトークンがキー、次のトークンがバリューとなる。
/// 解析失敗時は null を返す。
pub fn parseKeyValue(line: []const u8) ?struct { key: []const u8, value: []const u8 } {
    if (line.len == 0) return null;

    if (std.mem.indexOf(u8, line, ":")) |colon| {
        const key = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (key.len == 0) return null;
        return .{ .key = key, .value = value };
    }

    // スペース区切り key value
    const kv = nextToken(line) orelse return null;
    const vv = nextToken(kv.rest) orelse return null;
    return .{ .key = kv.token, .value = vv.token };
}

/// 行をスペース / タブ区切りでフィールドに分割し、buf に格納する。
/// 返値: 実際に格納したフィールド数 (buf.len を超えた分は切り捨て)。
pub fn splitFields(line: []const u8, buf: [][]const u8) usize {
    var count: usize = 0;
    var rest = line;
    while (count < buf.len) {
        const r = nextToken(rest) orelse break;
        buf[count] = r.token;
        count += 1;
        rest = r.rest;
    }
    return count;
}
