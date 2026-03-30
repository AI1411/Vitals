const std = @import("std");

const Mode = enum { dashboard, once, mini, watch };

const usage =
    \\Usage: vitals [options]
    \\
    \\Options:
    \\  --once         One-shot output and exit
    \\  --mini         Single-line output for tmux/prompt
    \\  --watch        Time-series graph mode
    \\  --interval N   Update interval in seconds (default: 1)
    \\
;

pub fn main() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    const stderr = std.fs.File.stderr().deprecatedWriter();

    var mode: Mode = .dashboard;
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
        } else if (std.mem.eql(u8, arg, "--interval")) {
            _ = args.next(); // consume value
        } else {
            try stderr.print("unknown option: {s}\n\n", .{arg});
            try stderr.writeAll(usage);
            std.process.exit(1);
        }
    }

    // TODO: dispatch to mode implementation
    switch (mode) {
        .dashboard, .once, .mini, .watch => try stdout.print("vitals\n", .{}),
    }
}
