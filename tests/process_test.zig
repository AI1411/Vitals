const std = @import("std");
const testing = std.testing;
const process = @import("process");

const proc_pid_stat_fixture = @embedFile("fixtures/proc_pid_stat.txt");
const proc_pid_status_fixture = @embedFile("fixtures/proc_pid_status.txt");

// --- fixture 構造チェック ---

test "proc_pid_stat fixture: pid で始まる" {
    try testing.expect(std.mem.startsWith(u8, proc_pid_stat_fixture, "1234"));
}

test "proc_pid_status fixture: VmRSS 行を含む" {
    try testing.expect(std.mem.indexOf(u8, proc_pid_status_fixture, "VmRSS:") != null);
}

// --- parseProcStat ---

test "parseProcStat: fixture から pid/utime/stime を正しく取得" {
    const result = process.parseProcStat(proc_pid_stat_fixture) orelse return error.ParseFailed;
    try testing.expectEqual(@as(u32, 1234), result.pid);
    try testing.expectEqual(@as(u64, 500), result.utime);
    try testing.expectEqual(@as(u64, 300), result.stime);
}

test "parseProcStat: comm にスペースを含む" {
    const content = "42 (my proc name) S 1 42 42 0 -1 0 0 0 0 0 10 20 0 0 20 0 1 0 0 0 0 0";
    const result = process.parseProcStat(content) orelse return error.ParseFailed;
    try testing.expectEqual(@as(u32, 42), result.pid);
    try testing.expectEqual(@as(u64, 10), result.utime);
    try testing.expectEqual(@as(u64, 20), result.stime);
}

test "parseProcStat: utime=0, stime=0 の場合" {
    const content = "1 (init) S 0 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 0 0 0 0";
    const result = process.parseProcStat(content) orelse return error.ParseFailed;
    try testing.expectEqual(@as(u64, 0), result.utime);
    try testing.expectEqual(@as(u64, 0), result.stime);
}

test "parseProcStat: 空文字列 → null" {
    const result = process.parseProcStat("");
    try testing.expectEqual(@as(?@TypeOf(process.parseProcStat("").?), null), result);
}

test "parseProcStat: 不正フォーマット → null" {
    try testing.expect(process.parseProcStat("not a stat line") == null);
    try testing.expect(process.parseProcStat("1 (bash) S") == null);
}

// --- parseVmRss ---

test "parseVmRss: fixture から VmRSS を正しく取得" {
    const rss = process.parseVmRss(proc_pid_status_fixture);
    try testing.expectEqual(@as(u64, 4096), rss);
}

test "parseVmRss: VmRSS なし → 0" {
    const content = "Name:\tbash\nPid:\t1234\n";
    try testing.expectEqual(@as(u64, 0), process.parseVmRss(content));
}

test "parseVmRss: 複数行から VmRSS のみ抽出" {
    const content =
        \\VmPeak:   12345 kB
        \\VmSize:   11234 kB
        \\VmRSS:     8192 kB
        \\VmData:    2048 kB
    ;
    try testing.expectEqual(@as(u64, 8192), process.parseVmRss(content));
}

// --- parseComm ---

test "parseComm: 末尾改行を除去" {
    try testing.expectEqualStrings("bash", process.parseComm("bash\n"));
}

test "parseComm: 改行なし" {
    try testing.expectEqualStrings("nginx", process.parseComm("nginx"));
}

test "parseComm: 複数行は最初のトリムのみ" {
    try testing.expectEqualStrings("rust-analyzer", process.parseComm("rust-analyzer\n"));
}

// --- ProcInfo ---

test "ProcInfo.nameSlice: name_len=0 → 空スライス" {
    const info = process.ProcInfo{};
    try testing.expectEqualStrings("", info.nameSlice());
}

test "ProcInfo.nameSlice: セットした名前を返す" {
    var info = process.ProcInfo{};
    const name = "systemd";
    @memcpy(info.name[0..name.len], name);
    info.name_len = name.len;
    try testing.expectEqualStrings("systemd", info.nameSlice());
}

// --- ProcessSnapshot ---

test "ProcessSnapshot: デフォルト値は全ゼロ" {
    const snap = process.ProcessSnapshot{};
    try testing.expectEqual(@as(usize, 0), snap.top_count);
    try testing.expectEqual(@as(usize, 0), snap.raw_count);
}
