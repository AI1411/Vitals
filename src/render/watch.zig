// 時系列グラフ TUI

const std = @import("std");
const snapshot_mod = @import("../collector/snapshot.zig");
const history_mod = @import("../collector/history.zig");
const graph = @import("widgets/graph.zig");
const gauge = @import("widgets/gauge.zig");
const size_mod = @import("../utils/size.zig");
const terminal = @import("../utils/terminal.zig");
const ansi = @import("../utils/ansi.zig");
const proc_reader = @import("../utils/proc_reader.zig");

// --- 定数 ---

/// 表示時間範囲のデフォルト (秒)
pub const DEFAULT_TIME_RANGE: usize = 300; // 5分
/// 表示時間範囲の最小値 (秒)
pub const MIN_TIME_RANGE: usize = 60; // 1分
/// 表示時間範囲の最大値 (秒)
pub const MAX_TIME_RANGE: usize = 3600; // 60分
/// 時間範囲の変化ステップ (秒)
pub const TIME_RANGE_STEP: usize = 60;

/// グラフ高さ (行数)
const GRAPH_HEIGHT: usize = 6;

// --- 状態 ---

/// watch モードの操作アクション
pub const Action = enum {
    none,
    quit,
    pause_toggle,
    reset,
    zoom_in, // + キー: 時間範囲縮小
    zoom_out, // - キー: 時間範囲拡大
};

/// watch モードの状態
pub const WatchState = struct {
    /// 表示する時間範囲 (秒)
    time_range_secs: usize = DEFAULT_TIME_RANGE,
    /// 一時停止中か
    paused: bool = false,
};

/// キー入力を処理して WatchState を更新し、アクションを返す。
/// q     → quit
/// space → pause_toggle
/// r     → reset
/// +     → zoom_in  (時間範囲を縮小: より短い期間を表示)
/// -     → zoom_out (時間範囲を拡大: より長い期間を表示)
pub fn handleKey(state: *WatchState, key: u8) Action {
    switch (key) {
        'q', 3 => return .quit, // q or Ctrl-C
        ' ' => {
            state.paused = !state.paused;
            return .pause_toggle;
        },
        'r' => return .reset,
        '+' => {
            // 時間範囲を縮小 (より短い期間にズームイン)
            if (state.time_range_secs > MIN_TIME_RANGE) {
                state.time_range_secs -|= TIME_RANGE_STEP;
                if (state.time_range_secs < MIN_TIME_RANGE)
                    state.time_range_secs = MIN_TIME_RANGE;
            }
            return .zoom_in;
        },
        '-' => {
            // 時間範囲を拡大 (より長い期間にズームアウト)
            if (state.time_range_secs < MAX_TIME_RANGE) {
                state.time_range_secs +|= TIME_RANGE_STEP;
                if (state.time_range_secs > MAX_TIME_RANGE)
                    state.time_range_secs = MAX_TIME_RANGE;
            }
            return .zoom_out;
        },
        else => return .none,
    }
}

// --- レンダリング ---

/// 1フレーム分の watch TUI を writer に書き込む。
/// history から最新のデータを取得してグラフを描画する。
pub fn renderFrame(
    writer: anytype,
    state: *const WatchState,
    history: *const history_mod.History,
    latest_sample: history_mod.Sample,
    term_cols: u16,
    term_rows: u16,
) !void {
    _ = term_rows; // 将来の高さ対応用

    const graph_width = if (term_cols > graph.Y_LABEL_WIDTH + 4)
        @as(usize, term_cols) - graph.Y_LABEL_WIDTH - 2
    else
        40;

    const n_samples = @min(state.time_range_secs, history.len);

    // 現在値ゲージ表示バッファ
    var fmt_buf: [64]u8 = undefined;

    // ── タイトルバー ─────────────────────────────────────────────────
    const mins = state.time_range_secs / 60;
    const pause_str = if (state.paused) " [PAUSED]" else "";
    try writer.print("{s}{s}  vitals watch  ({d}m range){s}{s}\n", .{ ansi.bold, ansi.fg_cyan, mins, pause_str, ansi.reset });

    // ── CPU グラフ ───────────────────────────────────────────────────
    {
        var cpu_buf: [history_mod.MAX_CAPACITY]f64 = undefined;
        const cpu_vals = history.getCpuPct(n_samples, cpu_buf[0..n_samples]);
        const cpu_label = std.fmt.bufPrint(&fmt_buf, "CPU Usage ({d}m)  now: {d:.1}%", .{ mins, latest_sample.cpu_pct }) catch "CPU Usage";
        try graph.render(writer, cpu_vals, 100.0, GRAPH_HEIGHT, graph_width, cpu_label, state.time_range_secs);
        try writer.writeByte('\n');
    }

    // ── Memory グラフ ────────────────────────────────────────────────
    {
        var mem_buf: [history_mod.MAX_CAPACITY]f64 = undefined;
        const mem_vals = history.getMemPct(n_samples, mem_buf[0..n_samples]);
        const mem_label = std.fmt.bufPrint(&fmt_buf, "Memory Usage ({d}m)  now: {d:.1}%", .{ mins, latest_sample.mem_pct }) catch "Memory Usage";
        try graph.render(writer, mem_vals, 100.0, GRAPH_HEIGHT, graph_width, mem_label, state.time_range_secs);
        try writer.writeByte('\n');
    }

    // ── Network I/O グラフ ───────────────────────────────────────────
    {
        var rx_buf: [history_mod.MAX_CAPACITY]f64 = undefined;
        var tx_buf: [history_mod.MAX_CAPACITY]f64 = undefined;
        const rx_vals = history.getNetRxBps(n_samples, rx_buf[0..n_samples]);
        const tx_vals = history.getNetTxBps(n_samples, tx_buf[0..n_samples]);

        // 最大値を動的に決定
        var net_max: f64 = 1024.0 * 1024.0; // 1 MB/s をデフォルト最小
        for (rx_vals) |v| if (v > net_max) {
            net_max = v;
        };
        for (tx_vals) |v| if (v > net_max) {
            net_max = v;
        };
        // 見やすいように最大値を切り上げ
        net_max *= 1.2;

        var rx_str: [32]u8 = undefined;
        var tx_str: [32]u8 = undefined;
        const rx_now = size_mod.formatRate(latest_sample.net_rx_bps, &rx_str);
        const tx_now = size_mod.formatRate(latest_sample.net_tx_bps, &tx_str);
        const net_label = std.fmt.bufPrint(&fmt_buf, "Network ({d}m)  ↓{s}  ↑{s}", .{ mins, rx_now, tx_now }) catch "Network";

        // Download (rx) グラフ
        try graph.render(writer, rx_vals, net_max, GRAPH_HEIGHT, graph_width, net_label, state.time_range_secs);

        // Upload (tx) を簡易表示
        try writer.writeAll("       "); // Y軸ラベル分インデント
        for (0..@min(tx_vals.len, graph_width)) |i| {
            const ratio = @min(tx_vals[i] / net_max, 1.0);
            _ = ratio;
            // 簡易表示: 送信グラフは ▲ ▼ でミニ表示
            try writer.writeAll("▲");
        }
        try writer.writeAll("  ↑ Upload\n\n");
    }

    // ── フッター ─────────────────────────────────────────────────────
    try writer.print("{s}[q] 終了  [+/-] 時間範囲  [space] 一時停止  [r] リセット{s}\n", .{ ansi.dim, ansi.reset });
}

// --- メインループ ---

/// watch モードの TUI を起動する。
/// Ctrl-C または 'q' キーで終了する。
pub fn run(interval_sec: u64) !void {
    const stdout = std.io.getStdOut();
    const stdin = std.io.getStdIn();

    // ターミナル設定
    try terminal.enterRaw();
    defer terminal.leaveRaw();

    const w = stdout.writer();
    try w.writeAll(ansi.alt_screen_enter);
    try w.writeAll(ansi.cursor_hide);
    defer {
        w.writeAll(ansi.cursor_show) catch {};
        w.writeAll(ansi.alt_screen_leave) catch {};
    }

    // SIGWINCH ハンドラを登録: リサイズ時に再描画トリガー
    terminal.installSigwinch();

    var state = WatchState{};
    var history = history_mod.History{};
    var proc_buf: [proc_reader.PROC_BUF_SIZE]u8 = undefined;
    var render_buf: [1024 * 64]u8 = undefined; // 64KB レンダリングバッファ
    var last_update_ns: i128 = 0;
    var prev_snap = snapshot_mod.collect(&proc_buf);
    var latest_sample = history_mod.Sample{};

    // stdin を non-blocking に設定
    const stdin_fd = stdin.handle;
    const flags = std.posix.fcntl(stdin_fd, std.posix.F.GETFL, 0) catch 0;
    _ = std.posix.fcntl(stdin_fd, std.posix.F.SETFL, flags | 0o4000) catch {}; // O_NONBLOCK

    while (true) {
        // キー入力をノンブロッキングで読む
        var key_buf: [4]u8 = undefined;
        const n_read = stdin.read(&key_buf) catch 0;
        if (n_read > 0) {
            const action = handleKey(&state, key_buf[0]);
            switch (action) {
                .quit => break,
                .reset => {
                    history = history_mod.History{};
                    prev_snap = snapshot_mod.collect(&proc_buf);
                },
                else => {},
            }
        }

        // リサイズ検知: フラグが立っていれば即座に再描画 (フレーム描画処理へ続行)
        const did_resize = terminal.checkAndClearResized();
        _ = did_resize;

        // 更新間隔チェック
        const now_ns = std.time.nanoTimestamp();
        const elapsed_ns = now_ns - last_update_ns;
        const interval_ns = @as(i128, @intCast(interval_sec)) * std.time.ns_per_s;
        if (elapsed_ns >= interval_ns and !state.paused) {
            const curr_snap = snapshot_mod.collect(&proc_buf);
            const interval_f: f64 = @floatFromInt(interval_sec);
            const usage = snapshot_mod.calcUsage(prev_snap, curr_snap, interval_f);
            latest_sample = history_mod.sampleFromUsage(usage);
            history.push(latest_sample);
            prev_snap = curr_snap;
            last_update_ns = now_ns;
        }

        // フレームレンダリング
        var fbs = std.io.fixedBufferStream(&render_buf);
        const fb_writer = fbs.writer();

        const term_size = terminal.getSize() catch .{ .rows = 24, .cols = 80 };

        try fb_writer.writeAll(ansi.cursor_home);
        try fb_writer.writeAll(ansi.clear_screen);
        try renderFrame(fb_writer, &state, &history, latest_sample, term_size.cols, term_size.rows);

        // バッファをまとめて出力 (フリッカー防止)
        try w.writeAll(fbs.getWritten());

        // 短いスリープ (CPU使用率を抑制)
        std.Thread.sleep(50 * std.time.ns_per_ms);
    }
}

// --- テスト ---

const testing = std.testing;

test "WatchState: デフォルト値" {
    const state = WatchState{};
    try testing.expectEqual(DEFAULT_TIME_RANGE, state.time_range_secs);
    try testing.expect(!state.paused);
}

test "handleKey: 'q' → quit" {
    var state = WatchState{};
    try testing.expectEqual(Action.quit, handleKey(&state, 'q'));
}

test "handleKey: Ctrl-C → quit" {
    var state = WatchState{};
    try testing.expectEqual(Action.quit, handleKey(&state, 3));
}

test "handleKey: space → pause_toggle, paused=true" {
    var state = WatchState{};
    try testing.expectEqual(Action.pause_toggle, handleKey(&state, ' '));
    try testing.expect(state.paused);
}

test "handleKey: space 2回 → paused=false" {
    var state = WatchState{};
    _ = handleKey(&state, ' ');
    _ = handleKey(&state, ' ');
    try testing.expect(!state.paused);
}

test "handleKey: 'r' → reset" {
    var state = WatchState{};
    try testing.expectEqual(Action.reset, handleKey(&state, 'r'));
}

test "handleKey: '+' → zoom_in, 時間範囲縮小" {
    var state = WatchState{ .time_range_secs = 300 };
    const action = handleKey(&state, '+');
    try testing.expectEqual(Action.zoom_in, action);
    try testing.expectEqual(@as(usize, 240), state.time_range_secs);
}

test "handleKey: '+' で MIN_TIME_RANGE 以下にはならない" {
    var state = WatchState{ .time_range_secs = MIN_TIME_RANGE };
    _ = handleKey(&state, '+');
    try testing.expectEqual(MIN_TIME_RANGE, state.time_range_secs);
}

test "handleKey: '-' → zoom_out, 時間範囲拡大" {
    var state = WatchState{ .time_range_secs = 300 };
    const action = handleKey(&state, '-');
    try testing.expectEqual(Action.zoom_out, action);
    try testing.expectEqual(@as(usize, 360), state.time_range_secs);
}

test "handleKey: '-' で MAX_TIME_RANGE を超えない" {
    var state = WatchState{ .time_range_secs = MAX_TIME_RANGE };
    _ = handleKey(&state, '-');
    try testing.expectEqual(MAX_TIME_RANGE, state.time_range_secs);
}

test "handleKey: '+' を繰り返して MIN_TIME_RANGE でクランプ" {
    var state = WatchState{ .time_range_secs = MIN_TIME_RANGE + TIME_RANGE_STEP };
    _ = handleKey(&state, '+');
    try testing.expectEqual(MIN_TIME_RANGE, state.time_range_secs);
    _ = handleKey(&state, '+'); // これ以上縮小しない
    try testing.expectEqual(MIN_TIME_RANGE, state.time_range_secs);
}

test "handleKey: '-' を繰り返して MAX_TIME_RANGE でクランプ" {
    var state = WatchState{ .time_range_secs = MAX_TIME_RANGE - TIME_RANGE_STEP };
    _ = handleKey(&state, '-');
    try testing.expectEqual(MAX_TIME_RANGE, state.time_range_secs);
    _ = handleKey(&state, '-'); // これ以上拡大しない
    try testing.expectEqual(MAX_TIME_RANGE, state.time_range_secs);
}

test "handleKey: 未知のキー → none, 状態変更なし" {
    var state = WatchState{};
    const action = handleKey(&state, 'z');
    try testing.expectEqual(Action.none, action);
    try testing.expectEqual(DEFAULT_TIME_RANGE, state.time_range_secs);
    try testing.expect(!state.paused);
}

test "renderFrame: クラッシュしない (空の履歴)" {
    var buf: [1024 * 64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const state = WatchState{};
    const history = history_mod.History{};
    const sample = history_mod.Sample{};
    try renderFrame(fbs.writer(), &state, &history, sample, 80, 24);
    try testing.expect(fbs.getWritten().len > 0);
}

test "renderFrame: データあり" {
    var buf: [1024 * 64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const state = WatchState{};
    var history = history_mod.History{};
    for (0..30) |i| {
        history.push(.{
            .cpu_pct = @as(f64, @floatFromInt(i)) * 2.0,
            .mem_pct = 50.0,
            .net_rx_bps = 1024.0 * @as(f64, @floatFromInt(i)),
        });
    }
    const sample = history_mod.Sample{ .cpu_pct = 60.0, .mem_pct = 50.0 };
    try renderFrame(fbs.writer(), &state, &history, sample, 80, 24);
    try testing.expect(fbs.getWritten().len > 0);
}
