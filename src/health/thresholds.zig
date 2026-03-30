// 閾値定義 (正常/注意/危険)

/// ヘルス状態
pub const HealthStatus = enum {
    normal,
    warn,
    critical,
};

/// CPU 使用率 (%) のヘルス状態を返す
/// 正常: < 60%, 注意: 60-85%, 危険: > 85%
pub fn checkCpu(pct: f64) HealthStatus {
    if (pct > 85.0) return .critical;
    if (pct >= 60.0) return .warn;
    return .normal;
}

/// メモリ使用率 (%) のヘルス状態を返す
/// 正常: < 70%, 注意: 70-90%, 危険: > 90%
pub fn checkMemory(pct: f64) HealthStatus {
    if (pct > 90.0) return .critical;
    if (pct >= 70.0) return .warn;
    return .normal;
}

/// スワップ使用率 (%) のヘルス状態を返す
/// 正常: < 10%, 注意: 10-50%, 危険: > 50%
pub fn checkSwap(pct: f64) HealthStatus {
    if (pct > 50.0) return .critical;
    if (pct >= 10.0) return .warn;
    return .normal;
}

/// ディスク使用率 (%) のヘルス状態を返す
/// 正常: < 70%, 注意: 70-90%, 危険: > 90%
pub fn checkDisk(pct: f64) HealthStatus {
    if (pct > 90.0) return .critical;
    if (pct >= 70.0) return .warn;
    return .normal;
}

/// ロードアベレージのヘルス状態を返す
/// 正常: < cores×0.7, 注意: cores×0.7-1.0, 危険: > cores×1.0
pub fn checkLoadAvg(load: f64, cores: usize) HealthStatus {
    const c: f64 = @floatFromInt(cores);
    if (load > c * 1.0) return .critical;
    if (load >= c * 0.7) return .warn;
    return .normal;
}

/// ゾンビプロセス数のヘルス状態を返す
/// 正常: 0, 注意: 1-5, 危険: > 5
pub fn checkZombie(count: usize) HealthStatus {
    if (count > 5) return .critical;
    if (count >= 1) return .warn;
    return .normal;
}

// --- テスト ---

const testing = @import("std").testing;

test "checkCpu: 正常域 (59%)" {
    try testing.expectEqual(HealthStatus.normal, checkCpu(59.0));
}

test "checkCpu: 注意域 (60%)" {
    try testing.expectEqual(HealthStatus.warn, checkCpu(60.0));
}

test "checkCpu: 注意域 (85%)" {
    try testing.expectEqual(HealthStatus.warn, checkCpu(85.0));
}

test "checkCpu: 危険域 (85%超)" {
    try testing.expectEqual(HealthStatus.critical, checkCpu(85.1));
}

test "checkMemory: 正常域 (69%)" {
    try testing.expectEqual(HealthStatus.normal, checkMemory(69.0));
}

test "checkMemory: 注意域 (70%)" {
    try testing.expectEqual(HealthStatus.warn, checkMemory(70.0));
}

test "checkMemory: 危険域 (90%超)" {
    try testing.expectEqual(HealthStatus.critical, checkMemory(90.1));
}

test "checkSwap: 正常域 (9%)" {
    try testing.expectEqual(HealthStatus.normal, checkSwap(9.0));
}

test "checkSwap: 注意域 (10%)" {
    try testing.expectEqual(HealthStatus.warn, checkSwap(10.0));
}

test "checkSwap: 危険域 (50%超)" {
    try testing.expectEqual(HealthStatus.critical, checkSwap(50.1));
}

test "checkDisk: 正常域 (69%)" {
    try testing.expectEqual(HealthStatus.normal, checkDisk(69.0));
}

test "checkDisk: 注意域 (70%)" {
    try testing.expectEqual(HealthStatus.warn, checkDisk(70.0));
}

test "checkDisk: 危険域 (90%超)" {
    try testing.expectEqual(HealthStatus.critical, checkDisk(90.1));
}

test "checkLoadAvg: 正常域 (4コア, load=2.7)" {
    // 4×0.7=2.8 未満 → 正常
    try testing.expectEqual(HealthStatus.normal, checkLoadAvg(2.7, 4));
}

test "checkLoadAvg: 注意域 (4コア, load=2.8)" {
    // 4×0.7=2.8 以上 → 注意
    try testing.expectEqual(HealthStatus.warn, checkLoadAvg(2.8, 4));
}

test "checkLoadAvg: 危険域 (4コア, load=4.1)" {
    // 4×1.0=4.0 超 → 危険
    try testing.expectEqual(HealthStatus.critical, checkLoadAvg(4.1, 4));
}

test "checkZombie: 正常域 (0)" {
    try testing.expectEqual(HealthStatus.normal, checkZombie(0));
}

test "checkZombie: 注意域 (1)" {
    try testing.expectEqual(HealthStatus.warn, checkZombie(1));
}

test "checkZombie: 注意域 (5)" {
    try testing.expectEqual(HealthStatus.warn, checkZombie(5));
}

test "checkZombie: 危険域 (6)" {
    try testing.expectEqual(HealthStatus.critical, checkZombie(6));
}
