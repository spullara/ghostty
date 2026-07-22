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
    });
    deps.help_strings.addImport(exe);

    // Iterating @typeInfo(KeybindAction) forces analysis of the full
    // Binding.zig file which references the uucode module.
    deps.addUucode(b, exe.root_module, target, optimize);

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
    const schema = run.captureStdOut();
    const schema_check = b.addCheckFile(schema, .{
        .expected_exact = @embedFile("settingsgen/test-schema-golden.json"),
    });
    schema_check.setName("settingsgen schema matches golden file");
    try steps.append(b.allocator, &b.addInstallFile(
        schema,
        "share/ghostty/settings-schema.json",
    ).step);

    return .{
        .steps = steps.items,
        .check_step = &schema_check.step,
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
