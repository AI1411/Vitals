// /proc/loadavg パーサー (Linux) / getloadavg (macOS)

const std = @import("std");
const builtin = @import("builtin");

/// /proc/loadavg から取得したロードアベレージ情報
pub const LoadAvg = struct {
    /// 1分間のロードアベレージ
    load1: f64 = 0.0,
    /// 5分間のロードアベレージ
    load5: f64 = 0.0,
    /// 15分間のロードアベレージ
    load15: f64 = 0.0,
    /// 実行中プロセス数
    running: u32 = 0,
    /// 総プロセス数
    total: u32 = 0,
    /// 最後に作成されたプロセスのPID
    last_pid: u32 = 0,
};

/// macOS: getloadavg(3) からロードアベレージを取得する。
/// running / total / last_pid は macOS では取得不可のため 0 のまま。
pub fn collectMacos() LoadAvg {
    const sys = @import("../utils/macos_sys.zig");
    var avgs: [3]f64 = .{ 0.0, 0.0, 0.0 };
    const ret = sys.getloadavg(@as([*]f64, &avgs), 3);
    if (ret < 0) return LoadAvg{};
    return LoadAvg{
        .load1 = avgs[0],
        .load5 = avgs[1],
        .load15 = avgs[2],
    };
}

/// /proc/loadavg の内容をパースして LoadAvg を返す。
/// フォーマット: "1m 5m 15m running/total last_pid\n"
/// 解析失敗時は null を返す。
pub fn parseSnapshot(content: []const u8) ?LoadAvg {
    const line = std.mem.trim(u8, content, " \t\n\r");
    if (line.len == 0) return null;

    var it = std.mem.tokenizeScalar(u8, line, ' ');

    // 1分ロードアベレージ
    const load1_str = it.next() orelse return null;
    const load1 = std.fmt.parseFloat(f64, load1_str) catch return null;

    // 5分ロードアベレージ
    const load5_str = it.next() orelse return null;
    const load5 = std.fmt.parseFloat(f64, load5_str) catch return null;

    // 15分ロードアベレージ
    const load15_str = it.next() orelse return null;
    const load15 = std.fmt.parseFloat(f64, load15_str) catch return null;

    // running/total
    const procs_str = it.next() orelse return null;
    const slash = std.mem.indexOf(u8, procs_str, "/") orelse return null;
    const running = std.fmt.parseInt(u32, procs_str[0..slash], 10) catch return null;
    const total = std.fmt.parseInt(u32, procs_str[slash + 1 ..], 10) catch return null;

    // last_pid
    const pid_str = it.next() orelse return null;
    const last_pid = std.fmt.parseInt(u32, pid_str, 10) catch return null;

    return LoadAvg{
        .load1 = load1,
        .load5 = load5,
        .load15 = load15,
        .running = running,
        .total = total,
        .last_pid = last_pid,
    };
}
