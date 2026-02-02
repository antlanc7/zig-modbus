const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nanomodbus_dep = b.dependency("nanomodbus", .{ .target = target, .optimize = optimize });

    const nanomodbus = b.addModule("nanomodbus", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    nanomodbus.addCSourceFile(.{
        .file = nanomodbus_dep.path("nanomodbus.c"),
    });
    nanomodbus.addIncludePath(nanomodbus_dep.path(""));
    nanomodbus.addCMacro("NMBS_SERVER_DISABLED", "1");
    nanomodbus.addCMacro("NMBS_STRERROR_DISABLED", "1");

    const nanomodbus_static_lib = b.addLibrary(.{
        .name = "nanomodbus",
        .root_module = nanomodbus,
        .linkage = .static,
    });
    const nanomodbus_static_lib_step = b.addInstallArtifact(nanomodbus_static_lib, .{});

    const build_lib_step = b.step("lib", "Build as static lib");
    build_lib_step.dependOn(&nanomodbus_static_lib_step.step);

    const exe = b.addExecutable(.{
        .name = "zig_modbus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "nanomodbus", .module = nanomodbus },
            },
        }),
    });
    const build_exe = b.addInstallArtifact(exe, .{});

    const exe_check = b.addExecutable(.{
        .name = "zig_modbus_check",
        .root_module = exe.root_module,
    });
    b.step("check", "Check if foo compiles").dependOn(&exe_check.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&build_exe.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    b.step("run", "Run the app").dependOn(&run_cmd.step);
}
