//! Kitty clipboard protocol (OSC 5522) session password grants:
//! requests carrying a granted password skip the permission prompt, and
//! paste events mint one-time passwords.

const std = @import("std");
const Allocator = std.mem.Allocator;
const clipboard_command = @import("clipboard_command.zig");

const max_pw_len = clipboard_command.max_pw_len;

/// Session password grants, used to skip permission prompts for
/// requests carrying a known pw. Callers can choose to scope these
/// however they want, e.g. Kitty does it per window and the spec
/// doesn't demand anything.
pub const Grants = struct {
    entries: std.ArrayListUnmanaged(Entry) = .empty,

    const max_entries = 32;

    pub const Direction = enum { read, write };

    const Entry = struct {
        /// Owned by the allocator passed to grant.
        pw: []const u8,
        read: bool = false,
        write: bool = false,
        one_time: bool = false,
    };

    pub fn deinit(self: *Grants, alloc: Allocator) void {
        for (self.entries.items) |entry| alloc.free(entry.pw);
        self.entries.deinit(alloc);
    }

    /// Record a grant for pw. An existing grant for the same password
    /// gains the new direction.
    pub fn grant(
        self: *Grants,
        alloc: Allocator,
        pw: []const u8,
        dir: Direction,
        one_time: bool,
    ) Allocator.Error!void {
        if (pw.len == 0 or pw.len > max_pw_len) return;

        const entry: *Entry = entry: {
            if (self.findIndex(pw)) |idx| {
                const entry = &self.entries.items[idx];
                entry.one_time = entry.one_time and one_time;
                break :entry entry;
            }

            // Evict the oldest grant once full.
            if (self.entries.items.len >= max_entries) {
                const oldest = self.entries.orderedRemove(0);
                alloc.free(oldest.pw);
            }

            const owned = try alloc.dupe(u8, pw);
            errdefer alloc.free(owned);
            try self.entries.append(alloc, .{
                .pw = owned,
                .one_time = one_time,
            });
            break :entry &self.entries.items[self.entries.items.len - 1];
        };

        switch (dir) {
            .read => entry.read = true,
            .write => entry.write = true,
        }
    }

    /// Check whether pw grants the given direction. A one-time grant is
    /// consumed by this check even when the direction doesn't match,
    /// matching kitty's pop-on-check behavior.
    pub fn use(
        self: *Grants,
        alloc: Allocator,
        pw: []const u8,
        dir: Direction,
    ) bool {
        if (pw.len == 0) return false;
        const idx = self.findIndex(pw) orelse return false;
        const entry = &self.entries.items[idx];
        const allowed = switch (dir) {
            .read => entry.read,
            .write => entry.write,
        };
        if (entry.one_time) {
            const removed = self.entries.swapRemove(idx);
            alloc.free(removed.pw);
        }
        return allowed;
    }

    fn findIndex(self: *const Grants, pw: []const u8) ?usize {
        for (self.entries.items, 0..) |*entry, idx| {
            if (std.mem.eql(u8, entry.pw, pw)) return idx;
        }
        return null;
    }
};

/// The length of a one-time password generated for paste events.
pub const otp_len = 22;

/// Generate a one-time password for a paste event. The alphabet matches
/// kitty (alphanumeric without easily-confused characters), but the spec
/// doesn't demand this.
pub fn generateOtp(random: std.Random) [otp_len]u8 {
    const alphabet = "23456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";
    var result: [otp_len]u8 = undefined;
    for (&result) |*c| c.* = alphabet[random.uintLessThan(usize, alphabet.len)];
    return result;
}

test "grants: basic grant and use" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var grants: Grants = .{};
    defer grants.deinit(alloc);
    try testing.expect(!grants.use(alloc, "pw1", .read));

    try grants.grant(alloc, "pw1", .read, false);
    try testing.expect(grants.use(alloc, "pw1", .read));
    // Persistent grants survive use.
    try testing.expect(grants.use(alloc, "pw1", .read));
    try testing.expect(!grants.use(alloc, "pw1", .write));
}

test "grants: one-time consumed on check" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var grants: Grants = .{};
    defer grants.deinit(alloc);
    try grants.grant(alloc, "otp", .read, true);
    try testing.expect(grants.use(alloc, "otp", .read));
    try testing.expect(!grants.use(alloc, "otp", .read));
}

test "grants: one-time consumed even on direction mismatch" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var grants: Grants = .{};
    defer grants.deinit(alloc);
    try grants.grant(alloc, "otp", .read, true);
    try testing.expect(!grants.use(alloc, "otp", .write));
    try testing.expect(!grants.use(alloc, "otp", .read));
}

test "grants: directions are independent" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var grants: Grants = .{};
    defer grants.deinit(alloc);
    try grants.grant(alloc, "pw", .read, false);
    try grants.grant(alloc, "pw", .write, false);
    try testing.expect(grants.use(alloc, "pw", .read));
    try testing.expect(grants.use(alloc, "pw", .write));
}

test "grants: capacity evicts the oldest" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var grants: Grants = .{};
    defer grants.deinit(alloc);

    var buf: [8]u8 = undefined;
    for (0..Grants.max_entries + 1) |i| {
        const pw = try std.fmt.bufPrint(&buf, "pw{}", .{i});
        try grants.grant(alloc, pw, .read, false);
    }

    // The oldest grant was evicted; the newest survives.
    try testing.expect(!grants.use(alloc, "pw0", .read));
    const newest = try std.fmt.bufPrint(&buf, "pw{}", .{Grants.max_entries});
    try testing.expect(grants.use(alloc, newest, .read));
}
