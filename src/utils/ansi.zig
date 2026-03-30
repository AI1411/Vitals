// ANSI エスケープヘルパー

const std = @import("std");

// ── 文字色 ──────────────────────────────────────────────────────────
pub const fg_black = "\x1b[30m";
pub const fg_red = "\x1b[31m";
pub const fg_green = "\x1b[32m";
pub const fg_yellow = "\x1b[33m";
pub const fg_blue = "\x1b[34m";
pub const fg_magenta = "\x1b[35m";
pub const fg_cyan = "\x1b[36m";
pub const fg_white = "\x1b[37m";
pub const fg_default = "\x1b[39m";

// ── 背景色 ──────────────────────────────────────────────────────────
pub const bg_black = "\x1b[40m";
pub const bg_red = "\x1b[41m";
pub const bg_green = "\x1b[42m";
pub const bg_yellow = "\x1b[43m";
pub const bg_blue = "\x1b[44m";
pub const bg_magenta = "\x1b[45m";
pub const bg_cyan = "\x1b[46m";
pub const bg_white = "\x1b[47m";
pub const bg_default = "\x1b[49m";

// ── 属性 ────────────────────────────────────────────────────────────
pub const reset = "\x1b[0m";
pub const bold = "\x1b[1m";
pub const dim = "\x1b[2m";
pub const underline = "\x1b[4m";
pub const blink = "\x1b[5m";
pub const reverse = "\x1b[7m";

// ── カーソル制御 ────────────────────────────────────────────────────
pub const cursor_home = "\x1b[H";
pub const cursor_hide = "\x1b[?25l";
pub const cursor_show = "\x1b[?25h";
pub const cursor_save = "\x1b[s";
pub const cursor_restore = "\x1b[u";

// ── 画面クリア ──────────────────────────────────────────────────────
pub const clear_screen = "\x1b[2J";
pub const clear_screen_home = "\x1b[2J\x1b[H";
pub const clear_line = "\x1b[2K";
pub const clear_line_to_end = "\x1b[K";

// ── 代替スクリーンバッファ ──────────────────────────────────────────
pub const alt_screen_enter = "\x1b[?1049h";
pub const alt_screen_leave = "\x1b[?1049l";

// ── 動的カーソル移動 (関数) ─────────────────────────────────────────

/// カーソルを指定行・列に移動する (1-based)。
pub fn moveTo(writer: anytype, row: u16, col: u16) !void {
    try writer.print("\x1b[{d};{d}H", .{ row, col });
}

/// カーソルを n 行上に移動する。
pub fn cursorUp(writer: anytype, n: u16) !void {
    try writer.print("\x1b[{d}A", .{n});
}

/// カーソルを n 行下に移動する。
pub fn cursorDown(writer: anytype, n: u16) !void {
    try writer.print("\x1b[{d}B", .{n});
}

/// カーソルを n 列右に移動する。
pub fn cursorRight(writer: anytype, n: u16) !void {
    try writer.print("\x1b[{d}C", .{n});
}

/// カーソルを n 列左に移動する。
pub fn cursorLeft(writer: anytype, n: u16) !void {
    try writer.print("\x1b[{d}D", .{n});
}
