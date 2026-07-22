//! Generates the settings-schema.json bundled with the macOS app
//! that drives the native Settings window. The schema enumerates
//! every Config field with a type descriptor and, for known named
//! types, kind-specific extras (enum values, packed struct field
//! names, etc.). Unknown types degrade to `"custom"`, so the UI
//! can always render a validated free-text row.

const std = @import("std");
const Config = @import("../../config/Config.zig");
const RepeatableStringMap = @import("../../config/RepeatableStringMap.zig");
const RepeatableReadableIO = @import("../../config/io.zig").RepeatableReadableIO;
const KeybindAction = @import("../../input/Binding.zig").Action;
const KeyRemapSet = @import("../../input/key_mods.zig").RemapSet;
const formatter = @import("../../config/formatter.zig");
const help_strings = @import("help_strings");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    // Real default config so formatEntry produces canonical text for
    // every field.
    var cfg = try Config.default(alloc);
    defer cfg.deinit();

    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buffer);
    const stdout = &stdout_writer.interface;

    var ws: std.json.Stringify = .{ .writer = stdout, .options = .{} };

    try ws.beginObject();
    try ws.objectField("version");
    try ws.write(1);

    try ws.objectField("options");
    try ws.beginArray();
    @setEvalBranchQuota(200_000);
    inline for (@typeInfo(Config).@"struct".fields) |field| {
        if (field.name[0] != '_') try emitOption(alloc, &ws, &cfg, field);
    }
    try ws.endArray();

    try ws.objectField("keybind_actions");
    try ws.beginArray();
    inline for (@typeInfo(KeybindAction).@"union".fields) |field| {
        if (field.name[0] != '_') try emitKeybindAction(&ws, field);
    }
    try ws.endArray();

    try ws.endObject();
    try stdout.flush();
}

fn emitTypeDescriptor(
    ws: *std.json.Stringify,
    comptime T: type,
) !void {
    // Peel off ?T once and emit "optional": true. Repeatable list types
    // wrap themselves so we don't need to recurse.
    switch (@typeInfo(T)) {
        .optional => |info| {
            try ws.objectField("optional");
            try ws.write(true);
            return emitInnerTypeDescriptor(ws, info.child);
        },
        else => return emitInnerTypeDescriptor(ws, T),
    }
}

fn emitInnerTypeDescriptor(
    ws: *std.json.Stringify,
    comptime T: type,
) !void {
    // Named Config types first — checked by identity so we get the
    // exact known kinds even when their internal structure looks
    // like a generic struct.
    if (T == Config.Color) return writeKind(ws, "color");
    if (T == Config.TerminalColor) {
        try writeKind(ws, "color");
        try ws.objectField("special_values");
        try ws.beginArray();
        try ws.write("cell-foreground");
        try ws.write("cell-background");
        try ws.endArray();
        return;
    }
    if (T == Config.ColorList) return writeKind(ws, "color-list");
    if (T == Config.Palette) return writeKind(ws, "palette");
    if (T == Config.Duration) return writeKind(ws, "duration");
    if (T == Config.Path) return writeKind(ws, "path");
    if (T == Config.RepeatablePath) return writeKind(ws, "repeatable-path");
    if (T == Config.RepeatableString) return writeKind(ws, "repeatable-string");
    if (T == RepeatableStringMap) return writeKind(ws, "string-map");
    if (T == Config.Keybinds) return writeKind(ws, "keybinds");
    if (T == Config.RepeatableCodepointMap) return writeKind(ws, "codepoint-map");
    if (T == Config.RepeatableCommand) return writeKind(ws, "command-palette-entry");
    if (T == Config.Command) return writeKind(ws, "command");
    if (T == Config.FontStyle) return writeKind(ws, "font-style");
    if (T == Config.Theme) return writeKind(ws, "theme");

    // These named Config structs intentionally render as free-text rows.
    // Future unregistered structs fall through to the compile log below.
    if (T == Config.SelectionWordChars) return writeKind(ws, "custom");
    if (T == Config.RepeatableFontVariation) return writeKind(ws, "custom");
    if (T == Config.RepeatableClipboardCodepointMap) return writeKind(ws, "custom");
    if (T == Config.RepeatableLink) return writeKind(ws, "custom");
    if (T == Config.MouseScrollMultiplier) return writeKind(ws, "custom");
    if (T == Config.QuickTerminalSize) return writeKind(ws, "custom");
    if (T == Config.WindowPadding) return writeKind(ws, "custom");
    if (T == RepeatableReadableIO) return writeKind(ws, "custom");
    if (T == KeyRemapSet) return writeKind(ws, "custom");

    // Generic fallbacks by @typeInfo.
    switch (@typeInfo(T)) {
        .bool => return writeKind(ws, "bool"),
        .int => |info| {
            try writeKind(ws, "int");
            try ws.objectField("signed");
            try ws.write(info.signedness == .signed);
            try ws.objectField("bits");
            try ws.write(info.bits);
        },
        .float => return writeKind(ws, "float"),
        .@"enum" => |info| {
            try writeKind(ws, "enum");
            try ws.objectField("values");
            try ws.beginArray();
            inline for (info.fields) |f| try ws.write(f.name);
            try ws.endArray();
        },
        .pointer => switch (T) {
            []const u8, [:0]const u8 => try writeKind(ws, "string"),
            else => try writeKind(ws, "custom"),
        },
        .@"struct" => |info| switch (info.layout) {
            .@"packed" => {
                try writeKind(ws, "packed-bools");
                try ws.objectField("fields");
                try ws.beginArray();
                inline for (info.fields) |f| {
                    if (f.type == bool) try ws.write(f.name);
                }
                try ws.endArray();
            },
            else => {
                logCustomStructFallback(T);
                try writeKind(ws, "custom");
            },
        },
        else => try writeKind(ws, "custom"),
    }
}

fn logCustomStructFallback(comptime T: type) void {
    @compileLog("settingsgen: falling back to 'custom' for type " ++ settingsgenTypeName(T));
}

fn settingsgenTypeName(comptime T: type) []const u8 {
    const name = @typeName(T);
    const config_marker = ".Config.";
    if (std.mem.indexOf(u8, name, config_marker)) |i| {
        return "Config." ++ name[i + config_marker.len ..];
    }
    return name;
}

fn writeKind(ws: *std.json.Stringify, comptime k: []const u8) !void {
    try ws.objectField("kind");
    try ws.write(k);
}

fn emitOption(
    alloc: std.mem.Allocator,
    ws: *std.json.Stringify,
    cfg: *const Config,
    comptime field: std.builtin.Type.StructField,
) !void {
    try ws.beginObject();
    try ws.objectField("name");
    try ws.write(field.name);

    // Canonical default text (multi-line for repeatables; empty for null).
    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();
    try formatter.formatEntry(
        field.type,
        field.name,
        @field(cfg, field.name),
        &buf.writer,
    );
    try ws.objectField("default");
    try ws.write(buf.written());

    if (@hasDecl(help_strings.Config, field.name)) {
        try ws.objectField("docs");
        try ws.write(@field(help_strings.Config, field.name));
    }

    try emitTypeDescriptor(ws, field.type);
    try ws.endObject();
}

fn emitKeybindAction(
    ws: *std.json.Stringify,
    comptime field: std.builtin.Type.UnionField,
) !void {
    try ws.beginObject();
    try ws.objectField("name");
    try ws.write(field.name);

    if (@hasDecl(help_strings.KeybindAction, field.name)) {
        try ws.objectField("docs");
        try ws.write(@field(help_strings.KeybindAction, field.name));
    }

    try ws.objectField("argument");
    try emitKeybindArgument(ws, field.type);

    try ws.endObject();
}

fn emitKeybindArgument(
    ws: *std.json.Stringify,
    comptime T: type,
) !void {
    if (T == void) {
        try ws.beginObject();
        try ws.objectField("kind");
        try ws.write("none");
        try ws.endObject();
        return;
    }

    switch (@typeInfo(T)) {
        .@"enum" => |info| {
            try ws.beginObject();
            try ws.objectField("kind");
            try ws.write("enum");
            try ws.objectField("values");
            try ws.beginArray();
            inline for (info.fields) |f| try ws.write(f.name);
            try ws.endArray();
            try ws.endObject();
        },
        .int => {
            try ws.beginObject();
            try ws.objectField("kind");
            try ws.write("int");
            try ws.endObject();
        },
        .pointer => switch (T) {
            []const u8, [:0]const u8 => {
                try ws.beginObject();
                try ws.objectField("kind");
                try ws.write("string");
                try ws.endObject();
            },
            else => try emitCustomArgument(ws),
        },
        else => try emitCustomArgument(ws),
    }
}

fn emitCustomArgument(ws: *std.json.Stringify) !void {
    try ws.beginObject();
    try ws.objectField("kind");
    try ws.write("custom");
    try ws.endObject();
}
