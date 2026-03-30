const std = @import("std");
const testing = std.testing;
const parser = @import("parser");

// --- nextToken ---

test "nextToken: 通常のトークンを取り出す" {
    const r = parser.nextToken("hello world") orelse return error.Unexpected;
    try testing.expectEqualStrings("hello", r.token);
    try testing.expectEqualStrings(" world", r.rest);
}

test "nextToken: 先頭スペースをスキップする" {
    const r = parser.nextToken("   foo bar") orelse return error.Unexpected;
    try testing.expectEqualStrings("foo", r.token);
}

test "nextToken: タブ区切りも処理する" {
    const r = parser.nextToken("\thello\tworld") orelse return error.Unexpected;
    try testing.expectEqualStrings("hello", r.token);
}

test "nextToken: 1トークンのみの入力" {
    const r = parser.nextToken("single") orelse return error.Unexpected;
    try testing.expectEqualStrings("single", r.token);
    try testing.expectEqualStrings("", r.rest);
}

test "nextToken: 空文字列は null を返す" {
    try testing.expectEqual(@as(?@TypeOf(parser.nextToken("x").?), null), parser.nextToken(""));
}

test "nextToken: スペースのみは null を返す" {
    try testing.expectEqual(@as(?@TypeOf(parser.nextToken("x").?), null), parser.nextToken("   "));
}

// --- parseKeyValue ---

test "parseKeyValue: コロン区切り形式" {
    const kv = parser.parseKeyValue("MemTotal:   16384000 kB") orelse return error.Unexpected;
    try testing.expectEqualStrings("MemTotal", kv.key);
    try testing.expectEqualStrings("16384000 kB", kv.value);
}

test "parseKeyValue: コロン後のスペースをトリム" {
    const kv = parser.parseKeyValue("Key:   value") orelse return error.Unexpected;
    try testing.expectEqualStrings("Key", kv.key);
    try testing.expectEqualStrings("value", kv.value);
}

test "parseKeyValue: スペース区切り形式" {
    const kv = parser.parseKeyValue("cpu 12345") orelse return error.Unexpected;
    try testing.expectEqualStrings("cpu", kv.key);
    try testing.expectEqualStrings("12345", kv.value);
}

test "parseKeyValue: 空文字列は null を返す" {
    try testing.expect(parser.parseKeyValue("") == null);
}

test "parseKeyValue: コロンのみは null を返す" {
    try testing.expect(parser.parseKeyValue(":") == null);
}

// --- splitFields ---

test "splitFields: スペース区切りで分割" {
    var buf: [8][]const u8 = undefined;
    const n = parser.splitFields("a b c d", &buf);
    try testing.expectEqual(@as(usize, 4), n);
    try testing.expectEqualStrings("a", buf[0]);
    try testing.expectEqualStrings("b", buf[1]);
    try testing.expectEqualStrings("c", buf[2]);
    try testing.expectEqualStrings("d", buf[3]);
}

test "splitFields: buf が小さい場合は切り捨て" {
    var buf: [2][]const u8 = undefined;
    const n = parser.splitFields("a b c d e", &buf);
    try testing.expectEqual(@as(usize, 2), n);
    try testing.expectEqualStrings("a", buf[0]);
    try testing.expectEqualStrings("b", buf[1]);
}

test "splitFields: 空文字列は 0 を返す" {
    var buf: [4][]const u8 = undefined;
    const n = parser.splitFields("", &buf);
    try testing.expectEqual(@as(usize, 0), n);
}

test "splitFields: 複数スペース間隔も正しく分割" {
    var buf: [4][]const u8 = undefined;
    const n = parser.splitFields("x   y   z", &buf);
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqualStrings("x", buf[0]);
    try testing.expectEqualStrings("y", buf[1]);
    try testing.expectEqualStrings("z", buf[2]);
}
