const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
        .target = b.graph.host,
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

    // test
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
