const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const pixelz_mod = b.createModule(.{
        .root_source_file = b.path("pixelz.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example_mod = b.createModule(.{
        .root_source_file = b.path("sdl3_example.zig"),
        .target = target,
        .optimize = optimize,
    });

    example_mod.addImport("pixelz_lib", pixelz_mod);

    const pixelz_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "pixelz",
        .root_module = pixelz_mod,
    });
    b.installArtifact(pixelz_lib);

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
