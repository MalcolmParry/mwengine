const std = @import("std");
const Build = std.Build;

const shader_path = "shaders/";
const shader_output = "res/shaders/";

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_tracy = b.option(bool, "tracy", "Build with tracy") orelse false;
    const mwengine = b.dependency("mwengine", .{}).module("mwengine");

    const tracy = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "mwengine_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "mwengine",
                    .module = mwengine,
                },
                .{
                    .name = "tracy",
                    .module = tracy.module("tracy"),
                },
            },
        }),
    });

    exe.root_module.addImport("tracy", tracy.module("tracy"));
    if (enable_tracy) {
        exe.root_module.addImport("tracy_impl", tracy.module("tracy_impl_enabled"));
    } else {
        exe.root_module.addImport("tracy_impl", tracy.module("tracy_impl_disabled"));
    }

    // build
    const build_step = &b.install_tls.step;
    const install = b.addInstallArtifact(exe, .{});
    build_step.dependOn(&install.step);
    try buildShaders(b, build_step);

    // run
    const run = b.addRunArtifact(exe);
    run.setCwd(.{ .cwd_relative = b.install_prefix });
    run.step.dependOn(build_step);

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run.step);

    // test
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

fn buildShaders(b: *Build, build_step: *Build.Step) !void {
    const dir = try b.build_root.handle.openDir(shader_path, .{ .iterate = true });
    var iter = try dir.walk(b.allocator);
    defer iter.deinit();

    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".glsl")) continue;

        try buildShader(b, build_step, entry, "vert", &.{"-D_VERTEX"});
        try buildShader(b, build_step, entry, "frag", &.{"-D_PIXEL"});
    }
}

fn buildShader(b: *Build, build_step: *Build.Step, entry: std.fs.Dir.Walker.Entry, t: []const u8, defines: []const []const u8) !void {
    const src = b.path(b.fmt("{s}/{s}", .{ shader_path, entry.path }));
    var name_iter = std.mem.splitScalar(u8, entry.basename, '.');
    const name = name_iter.next() orelse return error.Failed;
    const out_name = b.fmt("{s}.{s}.spv", .{ name, t });

    const command = b.addSystemCommand(&.{ "glslangValidator", "-S", t });
    command.addArgs(defines);
    command.addArg("-V");
    command.addFileInput(src);
    command.addFileArg(src);
    command.addArg("-o");

    const out = command.addOutputFileArg(out_name);
    const install = b.addInstallFile(out, b.fmt("{s}/{s}", .{ shader_output, out_name }));
    install.step.dependOn(&command.step);
    build_step.dependOn(&install.step);
}
