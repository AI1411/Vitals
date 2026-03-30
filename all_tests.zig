// 全モジュールをコンパイル対象に含める集約テストルート
// 実装が追加されるたびに自動的にビルド検証の対象となる

// collector
const cpu = @import("src/collector/cpu.zig");
const disk = @import("src/collector/disk.zig");
const history = @import("src/collector/history.zig");
const loadavg = @import("src/collector/loadavg.zig");
const memory = @import("src/collector/memory.zig");
const network = @import("src/collector/network.zig");
const process = @import("src/collector/process.zig");
const snapshot = @import("src/collector/snapshot.zig");

// health
const color = @import("src/health/color.zig");
const thresholds = @import("src/health/thresholds.zig");

// render
const dashboard = @import("src/render/dashboard.zig");
const mini = @import("src/render/mini.zig");
const once = @import("src/render/once.zig");
const watch = @import("src/render/watch.zig");
const bar = @import("src/render/widgets/bar.zig");
const gauge = @import("src/render/widgets/gauge.zig");
const graph = @import("src/render/widgets/graph.zig");
const sparkline = @import("src/render/widgets/sparkline.zig");
const table = @import("src/render/widgets/table.zig");

// utils
const ansi = @import("src/utils/ansi.zig");
const parser = @import("src/utils/parser.zig");
const proc_reader = @import("src/utils/proc_reader.zig");
const ring_buffer = @import("src/utils/ring_buffer.zig");
const size = @import("src/utils/size.zig");
const terminal = @import("src/utils/terminal.zig");

// suppress unused import warnings
comptime {
    _ = cpu;
    _ = disk;
    _ = history;
    _ = loadavg;
    _ = memory;
    _ = network;
    _ = process;
    _ = snapshot;
    _ = color;
    _ = thresholds;
    _ = dashboard;
    _ = mini;
    _ = once;
    _ = watch;
    _ = bar;
    _ = gauge;
    _ = graph;
    _ = sparkline;
    _ = table;
    _ = ansi;
    _ = parser;
    _ = proc_reader;
    _ = ring_buffer;
    _ = size;
    _ = terminal;
}
