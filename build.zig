const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const pixelz_mod = b.createModule(.{
        .root_source_file = b.path("pixelz.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pixelz_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "pixelz",
        .root_module = pixelz_mod,
    });
    b.installArtifact(pixelz_lib);

    if (b.option(bool, "sdl3_primitives", "Compile sdl3_primitives example")) |_| {
        compile_example(b, target, optimize, pixelz_mod, "examples/sdl3_primitives.zig");
    }
    if (b.option(bool, "sdl3_radiance_cascades", "Compile sdl3_radiance_cascades example")) |_| {
        compile_example(b, target, optimize, pixelz_mod, "examples/sdl3_radiance_cascades.zig");
    }
}

fn compile_example(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    pixelz_mod: *std.Build.Module,
    path: []const u8,
) void {
    const example_mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("pixelz_lib", pixelz_mod);
    const example_exe = b.addExecutable(.{
        .name = "pixelz",
        .root_module = example_mod,
    });

    // Add SDL3 headers and link libc and SDL3 libs
    example_exe.linkLibC();
    var env_map = std.process.getEnvMap(b.allocator) catch unreachable;
    defer env_map.deinit();
    example_exe.addIncludePath(.{ .cwd_relative = env_map.get("SDL3_INCLUDE_PATH").? });
    example_exe.linkSystemLibrary("SDL3");

    b.installArtifact(example_exe);

    const run_cmd = b.addRunArtifact(example_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
