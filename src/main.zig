const std = @import("std");
const snapshot = @import("collector/snapshot.zig");
const once_render = @import("render/once.zig");
const mini_render = @import("render/mini.zig");
const proc_reader = @import("utils/proc_reader.zig");

const Mode = enum { dashboard, once, mini, watch };

const usage =
    \\Usage: vitals [options]
    \\
    \\Options:
    \\  --once         One-shot output and exit
    \\  --mini         Single-line output for tmux/prompt
    \\  --watch        Time-series graph mode
    \\  --interval N   Update interval in seconds (default: 1)
    \\  --json         Output as JSON (with --once)
    \\
;

pub fn main() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();

    var mode: Mode = .dashboard;
    var interval_sec: u64 = 1;
    var json_output = false;

    var args = try std.process.argsWithAllocator(std.heap.page_allocator);
    defer args.deinit();
    _ = args.next(); // skip binary name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--once")) {
            mode = .once;
        } else if (std.mem.eql(u8, arg, "--mini")) {
            mode = .mini;
        } else if (std.mem.eql(u8, arg, "--watch")) {
            mode = .watch;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json_output = true;
        } else if (std.mem.eql(u8, arg, "--interval")) {
            const val_str = args.next() orelse {
                try stderr.writeAll("--interval requires a value\n");
                std.process.exit(1);
            };
            interval_sec = std.fmt.parseInt(u64, val_str, 10) catch {
                try stderr.print("invalid interval: {s}\n", .{val_str});
                std.process.exit(1);
            };
        } else {
            try stderr.print("unknown option: {s}\n\n", .{arg});
            try stderr.writeAll(usage);
            std.process.exit(1);
        }
    }

    switch (mode) {
        .once, .mini => {
            var buf: [proc_reader.PROC_BUF_SIZE]u8 = undefined;

            // 2スナップショット方式で CPU 使用率を計算
            const snap1 = snapshot.collect(&buf);
            std.Thread.sleep(interval_sec * std.time.ns_per_s);
            const snap2 = snapshot.collect(&buf);

            const usage_snap = snapshot.calcUsage(snap1, snap2, @floatFromInt(interval_sec));

            if (json_output) {
                // TODO: JSON 出力は P4-9 で実装
                try stdout.print("{{\"mode\":\"{s}\"}}\n", .{@tagName(mode)});
            } else {
                switch (mode) {
                    .once => try once_render.render(stdout, snap2, usage_snap),
                    .mini => try mini_render.render(stdout, snap2, usage_snap),
                    else => unreachable,
                }
            }
        },
        .dashboard => {
            // TODO: P2 ダッシュボード TUI を実装
            try stdout.print("vitals dashboard (not yet implemented)\n", .{});
        },
        .watch => {
            // TODO: P4 ウォッチモード TUI を実装
            try stdout.print("vitals watch (not yet implemented)\n", .{});
        },
    }
}
