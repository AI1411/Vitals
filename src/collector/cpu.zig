// /proc/stat パーサー

const std = @import("std");

pub const MAX_CORES = 64;

/// /proc/stat の cpu 行から取得した生カウンタ
pub const CpuTimes = struct {
    user: u64 = 0,
    nice: u64 = 0,
    system: u64 = 0,
    idle: u64 = 0,
    iowait: u64 = 0,
    irq: u64 = 0,
    softirq: u64 = 0,
    steal: u64 = 0,
    guest: u64 = 0,
    guest_nice: u64 = 0,

    /// 全フィールドの合計
    /// guest は user に、guest_nice は nice にすでに含まれるため除外する
    pub fn total(self: CpuTimes) u64 {
        return self.user + self.nice + self.system + self.idle +
            self.iowait + self.irq + self.softirq + self.steal;
    }

    /// アイドル時間合計（idle + iowait）
    pub fn idleTotal(self: CpuTimes) u64 {
        return self.idle + self.iowait;
    }
};

/// /proc/stat のスナップショット（全体 + コア別）
pub const CpuSnapshot = struct {
    total: CpuTimes = .{},
    cores: [MAX_CORES]CpuTimes = [_]CpuTimes{.{}} ** MAX_CORES,
    core_count: usize = 0,
    /// MAX_CORES を超えるコアが存在したとき true
    truncated: bool = false,
};

/// /proc/stat の1行をパースして CpuTimes を返す。
/// フォーマット: "cpu[N]  <user> <nice> <system> <idle> <iowait> <irq> <softirq> <steal> <guest> <guest_nice>"
/// "cpu" で始まらない行や解析失敗時は null を返す。
pub fn parseCpuLine(line: []const u8) ?CpuTimes {
    if (!std.mem.startsWith(u8, line, "cpu")) return null;

    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next() orelse return null; // ラベル ("cpu" / "cpu0" 等) をスキップ

    var times: CpuTimes = .{};
    const fields = [_]*u64{
        &times.user,   &times.nice,       &times.system,  &times.idle,
        &times.iowait, &times.irq,        &times.softirq, &times.steal,
        &times.guest,  &times.guest_nice,
    };

    for (fields) |field| {
        const token = it.next() orelse return null;
        field.* = std.fmt.parseInt(u64, token, 10) catch return null;
    }

    return times;
}

/// /proc/stat の内容をパースして CpuSnapshot を返す。
/// 固定バッファを使用しヒープアロケーションなし。
pub fn parseSnapshot(content: []const u8) CpuSnapshot {
    var snapshot = CpuSnapshot{};
    var lines = std.mem.tokenizeScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "cpu")) break;

        const times = parseCpuLine(line) orelse continue;

        // line[3] が数字ならコア行 ("cpu0", "cpu1" …)、そうでなければ全体行 ("cpu  …")
        if (line.len > 3 and std.ascii.isDigit(line[3])) {
            if (snapshot.core_count < MAX_CORES) {
                snapshot.cores[snapshot.core_count] = times;
                snapshot.core_count += 1;
            } else {
                snapshot.truncated = true;
            }
        } else {
            snapshot.total = times;
        }
    }

    return snapshot;
}

/// 前回・今回の CpuTimes 差分から CPU 使用率 (0.0〜100.0) を計算する。
/// CPU% = (1 - idle_delta / total_delta) × 100
pub fn calcUsage(prev: CpuTimes, curr: CpuTimes) f64 {
    const total_delta = curr.total() -| prev.total();
    if (total_delta == 0) return 0.0;

    const idle_delta = curr.idleTotal() -| prev.idleTotal();
    return (1.0 - @as(f64, @floatFromInt(idle_delta)) / @as(f64, @floatFromInt(total_delta))) * 100.0;
}
