const std = @import("std");

/// The clipboard destination for a write.
pub const Location = enum(c_int) {
    standard = 0,
    selection = 1,
    primary = 2,
    _,
};

/// MIME types that name plain text across the platforms terminals run
/// on. We accept the union everywhere since serving text under any of these
/// names is harmless.
pub fn isTextMime(mime: []const u8) bool {
    const names: []const []const u8 = &.{
        "text/plain",
        "text/plain;charset=utf-8",
        "UTF8_STRING",
        "TEXT",
        "STRING",
    };
    for (names) |n| if (std.mem.eql(u8, mime, n)) return true;
    return false;
}

/// A single representation of clipboard data.
///
/// The MIME type and data are borrowed and only valid for the duration of a
/// clipboard write callback. Data is binary-safe.
pub const Content = struct {
    mime: []const u8,
    data: []const u8,
};

/// One atomic clipboard write.
///
/// Contents are borrowed and only valid for the duration of a clipboard write
/// callback. An empty contents slice clears the destination.
pub const Write = struct {
    location: Location,
    contents: []const Content,
};

/// The result of a clipboard write.
pub const WriteResult = enum(c_int) {
    success = 0,
    denied = 1,
    unsupported = 2,
    busy = 3,
    invalid_data = 4,
    io_error = 5,
    _,
};

test isTextMime {
    const testing = std.testing;
    try testing.expect(isTextMime("text/plain"));
    try testing.expect(isTextMime("UTF8_STRING"));
    try testing.expect(!isTextMime("image/png"));
    try testing.expect(!isTextMime("."));
}
