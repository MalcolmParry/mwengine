const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const include_gpu = b.option(bool, "gpu", "include gpu module") orelse true;
    const include_renderer = b.option(bool, "renderer", "include renderer module") orelse include_gpu;
    const include_windowing = b.option(bool, "windowing", "include windowing module") orelse true;

    const mwengine = b.addModule("mwengine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const options = b.addOptions();
    options.addOption(bool, "include_gpu", include_gpu);
    options.addOption(bool, "include_renderer", include_renderer);
    options.addOption(bool, "include_windowing", include_windowing);
    mwengine.addOptions("options", options);

    const vulkan = b.dependency("vulkan", .{
        .registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml"),
        .target = b.graph.host,
        .optimize = optimize,
    }).module("vulkan-zig");

    if (include_gpu)
        mwengine.addImport("vulkan", vulkan);

    if (include_renderer) {
        const freetype = b.dependency("freetype", .{});
        mwengine.linkLibrary(freetype.artifact("freetype"));
        mwengine.addIncludePath(freetype.path(""));
    }

    if (include_windowing) {
        const glfw = b.dependency("zglfw", .{
            .target = target,
            .optimize = optimize,
            .import_vulkan = include_gpu,
        });
        const glfw_mod = glfw.module("root");
        if (include_gpu)
            glfw_mod.addImport("vulkan", vulkan);

        mwengine.addImport("glfw", glfw_mod);
        mwengine.linkLibrary(glfw.artifact("glfw"));
    }

    // test
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
        }),
    });
    unit_tests.root_module.addOptions("options", options);

    const test_step = b.step("test", "Run unit tests");
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}
