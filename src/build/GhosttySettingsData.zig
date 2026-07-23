//! GhosttySettingsData generates settings-schema.json bundled with the
//! macOS app that drives the native Settings window.
const GhosttySettingsData = @This();

const std = @import("std");
const SharedDeps = @import("SharedDeps.zig");

steps: []*std.Build.Step,
check_step: *std.Build.Step,

pub fn init(
    b: *std.Build,
    deps: *const SharedDeps,
) !GhosttySettingsData {
    var steps: std.ArrayList(*std.Build.Step) = .empty;
    errdefer steps.deinit(b.allocator);

    const target = b.graph.host;
    const optimize: std.builtin.OptimizeMode = .Debug;
    const exe = b.addExecutable(.{
        .name = "settingsgen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = false,
            .omit_frame_pointer = false,
            .unwind_tables = .sync,
        }),
        // The self-hosted x86_64 backend currently crashes when compiling
        // this comptime-heavy generator on the 0.16.0 toolchain.
        .use_llvm = true,
    });
    deps.help_strings.addImport(exe);

    // The uucode module is now automatically added by deps.add() below,
    // but we need to ensure deps.add() is called for this exe.
    exe.root_module.addImport("uucode", deps.uucode_mod);

    {
        const buildconfig = config: {
            var copy = deps.config.*;
            copy.exe_entrypoint = .settingsgen;
            break :config copy;
        };

        const options = b.addOptions();
        try buildconfig.addOptions(options);
        exe.root_module.addOptions("build_options", options);
    }

    const run = b.addRunArtifact(exe);
    const schema = run.captureStdOut(.{});
    // Ghostty's Config defaults are OS-conditional (keybinds, font size,
    // etc.), so the generated schema differs per host and each supported
    // build host gets its own golden snapshot. Unsupported hosts must
    // capture their own snapshot rather than silently reusing another
    // platform's file.
    const schema_check: *std.Build.Step = switch (target.result.os.tag) {
        .macos => macos: {
            const check = b.addCheckFile(schema, .{
                .expected_exact = @embedFile("settingsgen/test-schema-golden.macos.json"),
            });
            check.setName("settingsgen schema matches golden file");
            break :macos &check.step;
        },
        .linux => linux: {
            const check = b.addCheckFile(schema, .{
                .expected_exact = @embedFile("settingsgen/test-schema-golden.linux.json"),
            });
            check.setName("settingsgen schema matches golden file");
            break :linux &check.step;
        },
        else => &b.addFail(b.fmt(
            "settingsgen: no golden schema snapshot for host OS '{s}'. " ++
                "Capture one at src/build/settingsgen/test-schema-golden.<os>.json " ++
                "and add a branch to GhosttySettingsData.zig.",
            .{@tagName(target.result.os.tag)},
        )).step,
    };
    try steps.append(b.allocator, &b.addInstallFile(
        schema,
        "share/ghostty/settings-schema.json",
    ).step);

    return .{
        .steps = steps.items,
        .check_step = schema_check,
    };
}

pub fn install(self: *const GhosttySettingsData) void {
    const b = self.steps[0].owner;
    for (self.steps) |step| b.getInstallStep().dependOn(step);
}

pub fn addStepDependencies(
    self: *const GhosttySettingsData,
    other_step: *std.Build.Step,
) void {
    for (self.steps) |step| other_step.dependOn(step);
}

pub fn addTestStepDependencies(
    self: *const GhosttySettingsData,
    other_step: *std.Build.Step,
) void {
    other_step.dependOn(self.check_step);
}
