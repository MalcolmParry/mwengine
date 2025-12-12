const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

const shader_path = "examples/shaders/";
const shader_output = "res/shaders/";

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable_tracy = b.option(bool, "tracy", "Build with tracy") orelse false;
    const use_glfw = b.option(bool, "glfw", "Use glfw for window") orelse true;

    const module = b.addModule("mwengine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const options = b.addOptions();
    options.addOption(bool, "use_glfw", use_glfw);
    module.addOptions("build_options", options);

    const tracy = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
    });
    module.addImport("tracy", tracy.module("tracy"));

    const vulkan = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
        .target = target,
        .optimize = optimize,
    }).module("vulkan-zig");
    module.addImport("vulkan", vulkan);

    if (use_glfw) {
        const glfw = b.dependency("zglfw", .{
            .target = target,
            .optimize = optimize,
            .import_vulkan = true,
        });
        const glfw_mod = glfw.module("root");
        glfw_mod.addImport("vulkan", vulkan);

        module.addImport("glfw", glfw_mod);
        module.linkLibrary(glfw.artifact("glfw"));
    } else {
        module.link_libc = true;
        module.linkSystemLibrary("X11", .{});
    }

    // example
    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/triangle.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{
                .name = "mwengine",
                .module = module,
            }},
        }),
    });

    example.root_module.addImport("tracy", tracy.module("tracy"));
    if (enable_tracy) {
        example.root_module.addImport("tracy_impl", tracy.module("tracy_impl_enabled"));
    } else {
        example.root_module.addImport("tracy_impl", tracy.module("tracy_impl_disabled"));
    }

    // build the example
    const example_build_artifact = b.addInstallArtifact(example, .{});
    const example_build_step = b.step("example", "Build the example executable");
    example_build_step.dependOn(&example_build_artifact.step);
    try buildShaders(b, example_build_step);

    // run the example
    const run_command = b.addRunArtifact(example);
    run_command.setCwd(.{ .cwd_relative = b.install_prefix });
    run_command.step.dependOn(example_build_step);

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&run_command.step);

    // testing
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
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
