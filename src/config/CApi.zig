const builtin = @import("builtin");
const std = @import("std");
const cli = @import("../cli.zig");
const inputpkg = @import("../input.zig");
const global = @import("../global.zig");
const String = @import("../main_c.zig").String;
const terminal_color = @import("../terminal/color.zig");

const Config = @import("Config.zig");
const c_get = @import("c_get.zig");
const edit = @import("edit.zig");
const formatter = @import("formatter.zig");
const Key = @import("key.zig").Key;

const log = std.log.scoped(.config);

/// Create a new configuration filled with the initial default values.
export fn ghostty_config_new() ?*Config {
    const result = global.alloc().create(Config) catch |err| {
        log.err("error allocating config err={}", .{err});
        return null;
    };

    result.* = Config.default(global.alloc()) catch |err| {
        log.err("error creating config err={}", .{err});
        global.alloc().destroy(result);
        return null;
    };

    return result;
}

export fn ghostty_config_free(ptr: ?*Config) void {
    if (ptr) |v| {
        v.deinit();
        global.alloc().destroy(v);
    }
}

/// Deep clone the configuration.
export fn ghostty_config_clone(self: *Config) ?*Config {
    const result = global.alloc().create(Config) catch |err| {
        log.err("error allocating config err={}", .{err});
        return null;
    };

    result.* = self.clone(global.alloc()) catch |err| {
        log.err("error cloning config err={}", .{err});
        global.alloc().destroy(result);
        return null;
    };

    return result;
}

/// Load the configuration from the CLI args.
export fn ghostty_config_load_cli_args(self: *Config) void {
    self.loadCliArgs(global.alloc()) catch |err| {
        log.err("error loading config err={}", .{err});
    };
}

/// Load the configuration from the default file locations. This
/// is usually done first. The default file locations are locations
/// such as the home directory.
export fn ghostty_config_load_default_files(self: *Config) void {
    self.loadDefaultFiles(global.alloc()) catch |err| {
        log.err("error loading config err={}", .{err});
    };
}

/// Load the configuration from a specific file path.
/// The path must be null-terminated.
export fn ghostty_config_load_file(self: *Config, path: [*:0]const u8) void {
    const path_slice = std.mem.span(path);
    self.loadFile(global.alloc(), path_slice) catch |err| {
        log.err("error loading config from file path={s} err={}", .{ path_slice, err });
    };
}

/// Load the configuration from the user-specified configuration
/// file locations in the previously loaded configuration. This will
/// recursively continue to load up to a built-in limit.
export fn ghostty_config_load_recursive_files(self: *Config) void {
    self.loadRecursiveFiles(global.alloc()) catch |err| {
        log.err("error loading config err={}", .{err});
    };
}

export fn ghostty_config_finalize(self: *Config) void {
    self.finalize() catch |err| {
        log.err("error finalizing config err={}", .{err});
    };
}

export fn ghostty_config_get(
    self: *Config,
    ptr: *anyopaque,
    key_str: [*]const u8,
    len: usize,
) bool {
    @setEvalBranchQuota(10_000);
    const key = std.meta.stringToEnum(Key, key_str[0..len]) orelse return false;
    return c_get.get(self, key, ptr);
}

export fn ghostty_config_trigger(
    self: *Config,
    str: [*]const u8,
    len: usize,
) inputpkg.Binding.Trigger.C {
    return config_trigger_(self, str[0..len]) catch |err| err: {
        log.err("error finding trigger err={}", .{err});
        break :err .{};
    };
}

fn config_trigger_(
    self: *Config,
    str: []const u8,
) !inputpkg.Binding.Trigger.C {
    const action = try inputpkg.Binding.Action.parse(str);
    const trigger: inputpkg.Binding.Trigger = self.keybind.set.getTrigger(action) orelse .{};
    return trigger.cval();
}

export fn ghostty_config_diagnostics_count(self: *Config) u32 {
    return @intCast(self._diagnostics.items().len);
}

export fn ghostty_config_get_diagnostic(self: *Config, idx: u32) Diagnostic {
    const items = self._diagnostics.items();
    if (idx >= items.len) return .{};
    const message = self._diagnostics.precompute.messages.items[idx];
    return .{ .message = message.ptr };
}

export fn ghostty_config_open_path() String {
    const path = edit.openPath(global.alloc()) catch |err| {
        log.err("error opening config in editor err={}", .{err});
        return .empty;
    };

    return .fromSlice(path);
}

/// Format the current value of a single config key as config-file
/// text ("key = value\n", possibly multiple lines for repeatable
/// values). Returns an empty String if the key is unknown or the
/// value could not be formatted. Caller must free with
/// ghostty_string_free.
export fn ghostty_config_get_value_text(
    self: *Config,
    key_str: [*]const u8,
    len: usize,
) String {
    const bytes = getValueText(global.alloc(), self, key_str[0..len]) orelse return .empty;
    return .fromSlice(bytes);
}

fn getValueText(alloc: std.mem.Allocator, self: *Config, name: []const u8) ?[]u8 {
    // Formatting by key switches over every Config field at comptime. The
    // quota was picked by trial and error to cover today's roughly 200-field
    // Config with headroom. If Zig reports "evaluation exceeded backwards
    // branches" here after adding config fields, raise it.
    @setEvalBranchQuota(100_000);
    const key = std.meta.stringToEnum(Key, name) orelse return null;
    var buf: std.Io.Writer.Allocating = .init(alloc);
    defer buf.deinit();
    switch (key) {
        inline else => |k| formatter.formatEntry(
            @TypeOf(@field(self, @tagName(k))),
            @tagName(k),
            @field(self, @tagName(k)),
            &buf.writer,
        ) catch return null,
    }
    return alloc.dupe(u8, buf.written()) catch null;
}

/// Load configuration from a string in config-file format. Parse
/// problems are reported via the config's diagnostics
/// (ghostty_config_diagnostics_count). Returns false on internal
/// error.
export fn ghostty_config_load_string(
    self: *Config,
    str: [*]const u8,
    len: usize,
) bool {
    return loadString(global.alloc(), self, str[0..len]);
}

/// Parse a single palette entry ("N=COLOR") using Ghostty's config parser.
export fn ghostty_config_palette_parse_entry(
    str: [*]const u8,
    len: usize,
    out: *PaletteEntry,
) bool {
    const entry = terminal_color.parsePaletteEntry(str[0..len]) catch return false;
    out.* = .{
        .index = entry.index,
        .color = .{ .r = entry.color.r, .g = entry.color.g, .b = entry.color.b },
    };
    return true;
}

/// Format a single palette entry in canonical config syntax ("N=#rrggbb").
/// Caller must free the returned string with ghostty_string_free.
export fn ghostty_config_palette_format_entry(index: u8, color: Config.Color.C) String {
    const bytes = formatPaletteEntry(global.alloc(), index, color) catch |err| {
        log.err("error formatting palette entry err={}", .{err});
        return .empty;
    };
    return .fromSlice(bytes);
}

fn formatPaletteEntry(alloc: std.mem.Allocator, index: u8, color: Config.Color.C) ![]u8 {
    return std.fmt.allocPrint(
        alloc,
        "{d}=#{x:0>2}{x:0>2}{x:0>2}",
        .{ index, color.r, color.g, color.b },
    );
}

fn loadString(alloc: std.mem.Allocator, self: *Config, bytes: []const u8) bool {
    var reader: std.Io.Reader = .fixed(bytes);
    var iter: cli.args.LineIterator = .{ .r = &reader, .filepath = "" };
    self.loadIter(alloc, &iter) catch |err| {
        log.err("error loading config from string err={}", .{err});
        return false;
    };
    return true;
}

/// Sync with ghostty_diagnostic_s
const Diagnostic = extern struct {
    message: [*:0]const u8 = "",
};

/// Sync with ghostty_config_palette_entry_s.
const PaletteEntry = extern struct {
    index: u8,
    color: Config.Color.C,
};

test "ghostty_config_get: bool" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.maximize = true;

    var out = false;
    const key = "maximize";
    try testing.expect(ghostty_config_get(&cfg, &out, key, key.len));
    try testing.expect(out);
}

test "ghostty_config_get: enum" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"window-theme" = .dark;

    var out: [*:0]const u8 = undefined;
    const key = "window-theme";
    try testing.expect(ghostty_config_get(&cfg, @ptrCast(&out), key, key.len));
    const str = std.mem.sliceTo(out, 0);
    try testing.expectEqualStrings("dark", str);
}

test "ghostty_config_get: optional null returns false" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"unfocused-split-fill" = null;

    var out: Config.Color.C = undefined;
    const key = "unfocused-split-fill";
    try testing.expect(!ghostty_config_get(&cfg, @ptrCast(&out), key, key.len));
}

test "ghostty_config_get: unknown key returns false" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();

    var out = false;
    const key = "not-a-real-key";
    try testing.expect(!ghostty_config_get(&cfg, &out, key, key.len));
}

test "ghostty_config_get: optional string null returns true" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.title = null;

    var out: ?[*:0]const u8 = undefined;
    const key = "title";
    try testing.expect(ghostty_config_get(&cfg, @ptrCast(&out), key, key.len));
    try testing.expect(out == null);
}

test "ghostty_config_get: float" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"background-opacity" = 0.42;

    var out: f64 = 0;
    const key = "background-opacity";
    try testing.expect(ghostty_config_get(&cfg, &out, key, key.len));
    try testing.expectApproxEqAbs(@as(f64, 0.42), out, 0.000001);
}

test "ghostty_config_get: struct cval conversion" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.background = .{ .r = 12, .g = 34, .b = 56 };

    var out: Config.Color.C = undefined;
    const key = "background";
    try testing.expect(ghostty_config_get(&cfg, @ptrCast(&out), key, key.len));
    try testing.expectEqual(@as(u8, 12), out.r);
    try testing.expectEqual(@as(u8, 34), out.g);
    try testing.expectEqual(@as(u8, 56), out.b);
}

test "getValueText: bool" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.maximize = true;

    const s = getValueText(alloc, &cfg, "maximize").?;
    defer alloc.free(s);
    try testing.expectEqualStrings("maximize = true\n", s);
}

test "getValueText: enum" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"window-theme" = .dark;

    const s = getValueText(alloc, &cfg, "window-theme").?;
    defer alloc.free(s);
    try testing.expectEqualStrings("window-theme = dark\n", s);
}

test "getValueText: float" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"background-opacity" = 0.42;

    const s = getValueText(alloc, &cfg, "background-opacity").?;
    defer alloc.free(s);
    try testing.expectEqualStrings("background-opacity = 0.42\n", s);
}

test "getValueText: unknown key" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();

    try testing.expect(getValueText(alloc, &cfg, "not-a-real-key") == null);
}

test "loadString: valid" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();

    try testing.expect(loadString(alloc, &cfg, "font-size = 14\n"));
    try testing.expectEqual(@as(u32, 0), ghostty_config_diagnostics_count(&cfg));
    try testing.expectEqual(@as(f32, 14), cfg.@"font-size");
}

test "loadString: invalid produces diagnostic" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();

    try testing.expect(loadString(alloc, &cfg, "font-size = bogus\n"));
    try testing.expect(ghostty_config_diagnostics_count(&cfg) >= 1);
}

test "loadString: round-trip via getValueText" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var cfg = try Config.default(alloc);
    defer cfg.deinit();
    cfg.@"font-size" = 17;

    // Serialize current value.
    const text = getValueText(alloc, &cfg, "font-size").?;
    defer alloc.free(text);

    // Reset and re-load from the serialized text.
    cfg.@"font-size" = 13;
    try testing.expect(loadString(alloc, &cfg, text));
    try testing.expectEqual(@as(u32, 0), ghostty_config_diagnostics_count(&cfg));
    try testing.expectEqual(@as(f32, 17), cfg.@"font-size");
}

test "palette entry parse and format C API" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var entry: PaletteEntry = undefined;
    const named = "5=red";
    try testing.expect(ghostty_config_palette_parse_entry(named, named.len, &entry));
    try testing.expectEqual(@as(u8, 5), entry.index);
    try testing.expectEqual(@as(u8, 255), entry.color.r);
    try testing.expectEqual(@as(u8, 0), entry.color.g);
    try testing.expectEqual(@as(u8, 0), entry.color.b);

    const rgb = "6=rgb:0/f/0";
    try testing.expect(ghostty_config_palette_parse_entry(rgb, rgb.len, &entry));
    try testing.expectEqual(@as(u8, 6), entry.index);
    try testing.expectEqual(@as(u8, 0), entry.color.r);
    try testing.expectEqual(@as(u8, 255), entry.color.g);
    try testing.expectEqual(@as(u8, 0), entry.color.b);

    const formatted = try formatPaletteEntry(alloc, 6, entry.color);
    defer alloc.free(formatted);
    try testing.expectEqualStrings("6=#00ff00", formatted);
}

test "ghostty_config_trigger: default keybind" {
    const testing = std.testing;

    var cfg = try Config.default(testing.allocator);
    defer cfg.deinit();

    // Default commands should be fetchable through config_trigger_
    {
        const trigger = try config_trigger_(&cfg, "open_config");
        try testing.expectEqual(.unicode, trigger.tag);
        try testing.expectEqual(@as(u32, ','), trigger.key.unicode);
    }
    {
        const trigger = try config_trigger_(&cfg, "reload_config");
        try testing.expectEqual(.unicode, trigger.tag);
        try testing.expectEqual(@as(u32, ','), trigger.key.unicode);
    }
    // Performable bindings are not tracked in the reverse map,
    // so config_trigger_ should return a default (empty) trigger.
    if (comptime builtin.target.os.tag.isDarwin()) {
        const next = try config_trigger_(&cfg, "navigate_search:next");
        try testing.expectEqual(.physical, next.tag);
        try testing.expectEqual(.unidentified, next.key.physical);

        const prev = try config_trigger_(&cfg, "navigate_search:previous");
        try testing.expectEqual(.physical, prev.tag);
        try testing.expectEqual(.unidentified, prev.key.physical);
    }
    {
        const trigger = try config_trigger_(&cfg, "adjust_selection:left");
        try testing.expectEqual(.physical, trigger.tag);
        try testing.expectEqual(.unidentified, trigger.key.physical);
    }
}
