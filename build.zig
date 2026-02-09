const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nanomodbus_dep = b.dependency("nanomodbus", .{ .target = target, .optimize = optimize });

    const nanomodbus_lib = b.addLibrary(.{
        .name = "nanomodbus",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
        .linkage = .static,
    });
    nanomodbus_lib.root_module.addCSourceFile(.{
        .file = nanomodbus_dep.path("nanomodbus.c"),
    });
    nanomodbus_lib.installHeader(nanomodbus_dep.path("nanomodbus.h"), "nanomodbus.h");

    const zig_nanomodbus = b.addModule("zig_nanomodbus", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zig_nanomodbus.linkLibrary(nanomodbus_lib);

    const check = b.step("check", "Check if foo compiles");

    const example_main = b.addExecutable(.{
        .name = "example_main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig_nanomodbus", .module = zig_nanomodbus },
            },
        }),
    });

    const example_main_check = b.addExecutable(.{
        .name = "example_main_check",
        .root_module = example_main.root_module,
    });
    check.dependOn(&example_main_check.step);

    const run_example_main_cmd = b.addRunArtifact(example_main);
    run_example_main_cmd.step.dependOn(&example_main.step);
    if (b.args) |args| {
        run_example_main_cmd.addArgs(args);
    }
    b.step("example-main", "Run the app").dependOn(&run_example_main_cmd.step);

    const example_raw = b.addExecutable(.{
        .name = "example_raw",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/raw.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    example_raw.root_module.linkLibrary(nanomodbus_lib);

    const example_raw_check = b.addExecutable(.{
        .name = "example_raw_check",
        .root_module = example_raw.root_module,
    });
    check.dependOn(&example_raw_check.step);

    const run_example_raw_cmd = b.addRunArtifact(example_raw);
    run_example_raw_cmd.step.dependOn(&example_raw.step);
    if (b.args) |args| {
        run_example_raw_cmd.addArgs(args);
    }
    b.step("example-raw", "Run the app").dependOn(&run_example_raw_cmd.step);
}
