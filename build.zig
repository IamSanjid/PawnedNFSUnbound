const std = @import("std");

pub fn build(b: *std.Build) !void {
    const hook_cmd = b.step("hook", "Generates hook template source in `src/hooks` directory");
    const hook_name_option = b.option([]const u8, "hook-name", "Name for the generated hook");
    const hook_offset_option = blk: {
        if (b.option([]const u8, "hook-offset", "The offset")) |v| {
            break :blk std.fmt.parseInt(usize, v, 0) catch break :blk null;
        }
        break :blk null;
    };
    const hook_base_module = b.option([]const u8, "hook-base-module", "The base module eg. `something.exe`") orelse "NeedForSpeedUnbound.exe";
    var generate_hook = @import("build/GenerateHook.zig").create(b, .{
        .name = hook_name_option,
        .offset = hook_offset_option,
        .base_module = hook_base_module,
    });
    hook_cmd.dependOn(&generate_hook.step);

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .os_tag = .windows,
            .cpu_arch = .x86_64,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const windows_extra = b.createModule(.{
        .root_source_file = b.path("src/windows_extra.zig"),
        .target = target,
        .optimize = optimize,
    });

    const capstone_bindings_zig = b.dependency("capstone_bindings_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const capstone_z = capstone_bindings_zig.module("capstone-bindings-zig");

    const asm_patch_buffer_dep = b.dependency("asm_patch_buffer", .{
        .target = target,
        .optimize = optimize,
    });
    const asm_patch_buffer = asm_patch_buffer_dep.module("asm_patch_buffer");

    const disasm = b.createModule(.{
        .root_source_file = b.path("src/disasm/disasm.zig"),
        .target = target,
        .optimize = optimize,
    });
    disasm.addImport("capstone_z", capstone_z);

    const binary_analysis = b.createModule(.{
        .root_source_file = b.path("src/binary_analysis/binary_analysis.zig"),
        .target = target,
        .optimize = optimize,
    });
    binary_analysis.addImport("disasm", disasm);
    binary_analysis.addImport("windows_extra", windows_extra);
    binary_analysis.addImport("asm_patch_buffer", asm_patch_buffer);

    const pawned = b.addSharedLibrary(.{
        .name = "PawnedNFSUnbound",
        .root_source_file = b.path("src/dllmain.zig"),
        .target = target,
        .optimize = optimize,
    });
    pawned.root_module.addImport("windows_extra", windows_extra);
    pawned.root_module.addImport("binary_analysis", binary_analysis);
    pawned.subsystem = .Console;
    pawned.linkLibC();
    // pawned.addWin32ResourceFile(.{ .file = b.path("res/resource.rc") });

    b.installArtifact(pawned);

    // loader dll...
    const load_cmd = b.step("loader", "Only builds and installs the loader dll.");
    const loader = b.addSharedLibrary(.{
        .name = "PawnedNFSUnboundLoader",
        .root_source_file = b.path("src/loader_dllmain.zig"),
        .target = target,
        .optimize = optimize,
    });
    loader.root_module.addImport("windows_extra", windows_extra);
    loader.subsystem = .Console;
    loader.linkLibC();
    // loader.addWin32ResourceFile(.{ .file = b.path("res/resource.rc") });
    load_cmd.dependOn(&b.addInstallArtifact(loader, .{}).step);

    // build all
    const all = b.step("all", "Builds and installs the loader and the main dll.");
    all.dependOn(&b.addInstallArtifact(pawned, .{}).step);
    all.dependOn(&b.addInstallArtifact(loader, .{}).step);

    // tests...
    const test_cmd = b.step("test", "Runs the available unit tests.");
    test_cmd.dependOn(&b.addRunArtifact(b.addTest(.{
        .root_module = binary_analysis,
        .target = target,
        .optimize = optimize,
    })).step);
    test_cmd.dependOn(&b.addRunArtifact(b.addTest(.{
        .root_module = disasm,
        .target = target,
        .optimize = optimize,
    })).step);
    test_cmd.dependOn(&b.addRunArtifact(b.addTest(.{
        .root_source_file = b.path("src/hooks/tests.zig"),
        .target = target,
        .optimize = optimize,
    })).step);
}
