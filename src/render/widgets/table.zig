// プロセステーブル

const std = @import("std");
const process = @import("../../collector/process.zig");
const size = @import("../../utils/size.zig");

/// ANSI エスケープ: 太字
const BOLD = "\x1b[1m";
/// ANSI エスケープ: リセット
const RESET = "\x1b[0m";

/// テーブルヘッダー行を writer に書き込む。
pub fn renderHeader(writer: anytype) !void {
    try writer.writeAll(BOLD);
    try writer.writeAll("  PID    CPU%   MEM%      MEM  PROCESS\n");
    try writer.writeAll(RESET);
}

/// プロセス1行分を writer に書き込む。
/// mem_total_kb が 0 の場合は MEM% を 0.0 として表示する。
pub fn renderRow(writer: anytype, info: *const process.ProcInfo, mem_total_kb: u64) !void {
    const mem_pct: f64 = if (mem_total_kb > 0)
        @as(f64, @floatFromInt(info.mem_rss_kb)) / @as(f64, @floatFromInt(mem_total_kb)) * 100.0
    else
        0.0;

    var mem_buf: [16]u8 = undefined;
    const mem_str = size.formatKb(info.mem_rss_kb, &mem_buf);

    try std.fmt.format(writer, "{d:>6}  {d:>5.1}  {d:>5.1}  {s:>8}  {s}\n", .{
        info.pid,
        info.cpu_pct,
        mem_pct,
        mem_str,
        info.nameSlice(),
    });
}

/// ProcessSnapshot の Top N プロセステーブル全体を writer に書き込む。
/// mem_total_kb は MEM% 計算に使用する（0 の場合は MEM% = 0.0）。
pub fn render(writer: anytype, snap: *const process.ProcessSnapshot, mem_total_kb: u64) !void {
    try renderHeader(writer);
    for (0..snap.top_count) |i| {
        try renderRow(writer, &snap.top[i], mem_total_kb);
    }
}

// --- テスト ---

const testing = std.testing;

test "renderHeader: ヘッダー行に PID と CPU% を含む" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderHeader(fbs.writer());
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, "PID") != null);
    try testing.expect(std.mem.indexOf(u8, out, "CPU%") != null);
    try testing.expect(std.mem.indexOf(u8, out, "MEM%") != null);
    try testing.expect(std.mem.indexOf(u8, out, "PROCESS") != null);
}

test "renderRow: PID・CPU%・プロセス名を出力" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var info = process.ProcInfo{
        .pid = 1234,
        .cpu_pct = 45.2,
        .mem_rss_kb = 4096,
    };
    const name = "bash";
    @memcpy(info.name[0..name.len], name);
    info.name_len = name.len;

    try renderRow(fbs.writer(), &info, 8 * 1024 * 1024); // 8 GB total
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, "1234") != null);
    try testing.expect(std.mem.indexOf(u8, out, "45.2") != null);
    try testing.expect(std.mem.indexOf(u8, out, "bash") != null);
}

test "renderRow: mem_total_kb = 0 → MEM% = 0.0" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    var info = process.ProcInfo{ .pid = 1, .cpu_pct = 1.0, .mem_rss_kb = 1024 };
    info.name_len = 0;

    try renderRow(fbs.writer(), &info, 0);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, "0.0") != null);
}

test "render: 空スナップショット → ヘッダーのみ" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const snap = process.ProcessSnapshot{};
    try render(fbs.writer(), &snap, 0);
    const out = fbs.getWritten();
    // ヘッダー行のみ存在し、プロセス行がないこと
    try testing.expect(std.mem.indexOf(u8, out, "PID") != null);
    const newline_count = std.mem.count(u8, out, "\n");
    try testing.expectEqual(@as(usize, 1), newline_count);
}

test "render: 1プロセス → ヘッダー + 1行" {
    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var snap = process.ProcessSnapshot{};
    snap.top[0] = process.ProcInfo{ .pid = 99, .cpu_pct = 10.0, .mem_rss_kb = 2048 };
    const name = "vim";
    @memcpy(snap.top[0].name[0..name.len], name);
    snap.top[0].name_len = name.len;
    snap.top_count = 1;

    try render(fbs.writer(), &snap, 0);
    const out = fbs.getWritten();
    try testing.expect(std.mem.indexOf(u8, out, "99") != null);
    try testing.expect(std.mem.indexOf(u8, out, "vim") != null);
    const newline_count = std.mem.count(u8, out, "\n");
    try testing.expectEqual(@as(usize, 2), newline_count);
}
