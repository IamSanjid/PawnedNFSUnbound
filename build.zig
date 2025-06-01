const std = @import("std");

fn addDetourSourceFiles(lib: *std.Build.Step.Compile, detours_src_dir: std.Build.LazyPath, optimize: std.builtin.OptimizeMode) !void {
    const exclude_files = [_][]const u8{
        "uimports.cpp",
    };

    const b = lib.step.owner;
    const path = detours_src_dir.getPath3(b, &lib.step);
    var dir = try path.openDir("", .{ .iterate = true });
    var dir_iter = dir.iterate();
    defer dir.close();

    outer_loop: while (try dir_iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.ascii.endsWithIgnoreCase(entry.name, ".cpp")) continue;
        for (exclude_files) |exclude_file| {
            if (std.ascii.eqlIgnoreCase(entry.name, exclude_file)) continue :outer_loop;
        }

        const source_file_path = try detours_src_dir.join(b.allocator, entry.name);
        const deotour_debug_flag = if (optimize == .Debug) "-DDETOUR_DEBUG=1" else "-DDETOUR_DEBUG=0";
        lib.addCSourceFile(.{
            .file = source_file_path,
            .language = null,
            .flags = &.{
                "-DWIN32_LEAN_AND_MEAN",
                "-D_WIN32_WINNT=0x501",
                "-fno-sanitize=undefined", // TODO: Fix the undefined behaviour sanitizer issue?
                deotour_debug_flag,
            },
        });
    }
}

fn addStaticDetours(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !*std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "detours",
        .target = target,
        .optimize = optimize,
    });

    try addDetourSourceFiles(lib, b.path("Detours"), optimize);

    lib.linkLibC();
    if (target.result.abi != .msvc) {
        lib.linkLibCpp();
    }

    return lib;
}

fn getDetoursLibPath(b: *std.Build, optimize: std.builtin.OptimizeMode) std.Build.LazyPath {
    const detours_lib_path = b.path("Detours-Built");
    if (optimize != .Debug) {
        return detours_lib_path.join(b.allocator, "lib.X64") catch @panic("Can't allocate");
    } else {
        return detours_lib_path.join(b.allocator, "lib.Debug.X64") catch @panic("Can't allocate");
    }
}

pub fn build(b: *std.Build) !void {
    const use_prebuilt_detour = b.option(bool, "use-prebuilt-detour", "Use prebuilt detours static library") orelse false;

    const hook_cmd = b.step("hook", "Generates hook template source in `src/hooks` directory");
    const hook_name_option = b.option([]const u8, "hook-name", "Name for the generated hook");
    const hook_offset_option = blk: {
        if (b.option([]const u8, "hook-offset", "The offset")) |v| {
            break :blk std.fmt.parseInt(usize, v, 0) catch break :blk null;
        }
        break :blk null;
    };
    const hook_overwrite_bytes_option = b.option(usize, "hook-overwrite-bytes", "The number of bytes to overwrite at the hook address");
    const hook_base_module = b.option([]const u8, "hook-base-module", "The base module eg. `something.exe`") orelse "NeedForSpeedUnbound.exe";
    var generate_hook = @import("build/GenerateHook.zig").create(
        b,
        hook_name_option,
        hook_offset_option,
        hook_overwrite_bytes_option,
        hook_base_module,
    );
    hook_cmd.dependOn(&generate_hook.step);

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .os_tag = .windows,
            .cpu_arch = .x86_64,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    if (!use_prebuilt_detour and target.result.abi != .msvc and !target.result.isMinGW()) {
        return error.OnlyMSVC_GNU;
    }

    if (use_prebuilt_detour and target.result.abi != .msvc) {
        return error.OnlyMSVC;
    }

    if (target.result.cpu.arch != .x86_64) {
        return error.Onlyx86_64;
    }

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

    // linking Detours...
    if (!use_prebuilt_detour) {
        const detours = try addStaticDetours(b, target, optimize);

        pawned.linkLibrary(detours);
        pawned.addIncludePath(b.path("Detours"));
    } else {
        pawned.addLibraryPath(getDetoursLibPath(b, optimize));
        pawned.linkSystemLibrary("detours");
        pawned.addIncludePath(b.path("Detours-Built/include"));
    }
    // pawned.addWin32ResourceFile(.{ .file = b.path("res/resource.rc") });

    b.installArtifact(pawned);

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
}
