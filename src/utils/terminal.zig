// ターミナルサイズ取得、raw mode

const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

/// ターミナルサイズ
pub const Size = struct {
    rows: u16,
    cols: u16,
};

/// raw mode 移行前の termios を保存する（復元用）
var orig_termios: ?posix.termios = null;

/// raw mode に切り替える。
/// 成功したら orig_termios に元の設定を保存し、leaveRaw() で復元できるようにする。
pub fn enterRaw() !void {
    const fd = posix.STDIN_FILENO;
    const original = try posix.tcgetattr(fd);
    orig_termios = original;

    var raw = original;
    // 行バッファ・エコー・シグナル生成を無効化
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;
    // フロー制御・改行変換を無効化
    raw.iflag.IXON = false;
    raw.iflag.ICRNL = false;
    raw.iflag.BRKINT = false;
    raw.iflag.INPCK = false;
    raw.iflag.ISTRIP = false;
    // 8-bit クリーンモード
    raw.cflag.CSIZE = .CS8;
    // read は最低 1 バイト、タイムアウトなし
    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;

    try posix.tcsetattr(fd, .FLUSH, raw);
}

/// raw mode から通常モードに復元する。
/// enterRaw() を呼んでいない場合は何もしない。
pub fn leaveRaw() void {
    if (orig_termios) |orig| {
        posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, orig) catch {};
        orig_termios = null;
    }
}

/// 代替スクリーンバッファに切り替える。
pub fn enterAltScreen(writer: anytype) !void {
    try writer.writeAll("\x1b[?1049h");
}

/// 代替スクリーンバッファから通常バッファに戻る。
pub fn leaveAltScreen(writer: anytype) !void {
    try writer.writeAll("\x1b[?1049l");
}

/// ターミナルサイズを ioctl(TIOCGWINSZ) で取得する。
pub fn getSize() !Size {
    var ws: posix.winsize = undefined;
    const rc = posix.system.ioctl(posix.STDOUT_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (posix.errno(rc) != .SUCCESS) return error.IoctlFailed;
    return .{ .rows = ws.row, .cols = ws.col };
}

// --- SIGWINCH リサイズ検知 ---

/// SIGWINCH を受信したときにセットされるフラグ。
var resized: bool = false;

/// リサイズフラグを立てる (SIGWINCH ハンドラ内および テスト用)。
pub fn markResized() void {
    resized = true;
}

/// リサイズフラグを確認してクリアする。
/// リサイズがあった場合は true を返す。
pub fn checkAndClearResized() bool {
    const was = resized;
    resized = false;
    return was;
}

/// SIGWINCH シグナルハンドラ (C calling convention)。
fn sigwinchHandler(_: c_int) callconv(.c) void {
    resized = true;
}

/// SIGWINCH ハンドラを登録する。
pub fn installSigwinch() void {
    const sa = posix.Sigaction{
        .handler = .{ .handler = sigwinchHandler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.WINCH, &sa, null);
}

// --- テスト ---

const testing = @import("std").testing;

test "checkAndClearResized: 初期状態は false" {
    resized = false; // テスト前にリセット
    try testing.expect(!checkAndClearResized());
}

test "markResized: フラグを true にする" {
    resized = false;
    markResized();
    try testing.expect(resized);
    resized = false; // cleanup
}

test "checkAndClearResized: true → true を返してフラグをクリア" {
    resized = false;
    markResized();
    try testing.expect(checkAndClearResized());
    try testing.expect(!resized);
}

test "checkAndClearResized: 2回目は false" {
    resized = false;
    markResized();
    _ = checkAndClearResized();
    try testing.expect(!checkAndClearResized());
}
