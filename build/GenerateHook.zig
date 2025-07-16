const std = @import("std");

step: std.Build.Step,
builder: *std.Build,
hook_name: ?[]const u8 = null,
// TODO: These should be part of a config file
hook_offset: ?usize = null,
hook_base_module: []const u8,

const Self = @This();
const src_dir: []const u8 = "src";
const output_dir: []const u8 = "hooks";

pub const Options = struct {
    name: ?[]const u8 = null,
    offset: ?usize,
    base_module: []const u8,
};

pub fn create(b: *std.Build, options: Options) *Self {
    const self = b.allocator.create(Self) catch @panic("OOM");
    self.* = .{
        .step = std.Build.Step.init(.{
            .id = .update_source_files,
            .name = "generate-hook",
            .owner = b,
            .makeFn = make,
        }),
        .builder = b,
        .hook_name = options.name,
        .hook_offset = options.offset,
        .hook_base_module = options.base_module,
    };

    return self;
}

fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
    _ = options;
    const self: *Self = @fieldParentPtr("step", step);

    if (self.hook_name == null or self.hook_offset == null) {
        std.log.err("Please provide enough arguments, name and offset, try `zig build -h` for more information.", .{});
        return error.NotEnoughArguments;
    }

    const allocator = self.builder.allocator;

    const hook_src_path = try self.generateHookFile(allocator);
    defer allocator.free(hook_src_path);
    try modifyHooks(allocator, hook_src_path);
}

fn generateHookFile(self: *Self, allocator: std.mem.Allocator) ![]const u8 {
    std.fs.cwd().makePath(src_dir ++ "/" ++ output_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const hook_template = @embedFile("hook_template.zig");
    const hook_content = blk: {
        const hook_name_replaced = try std.mem.replaceOwned(u8, allocator, hook_template, "${HOOK_NAME}", self.hook_name.?);
        defer allocator.free(hook_name_replaced);

        const offset_str = try std.fmt.allocPrint(allocator, "0x{X}", .{self.hook_offset orelse 0});
        defer allocator.free(offset_str);

        const hook_offset_replaced = try std.mem.replaceOwned(u8, allocator, hook_name_replaced, "${HOOK_OFFSET}", offset_str);
        defer allocator.free(hook_offset_replaced);

        const hook_base_module_replaced = try std.mem.replaceOwned(u8, allocator, hook_offset_replaced, "${HOOK_BASE_MODULE}", self.hook_base_module);
        break :blk hook_base_module_replaced;
    };
    defer allocator.free(hook_content);

    const hook_file_name = try std.fmt.allocPrint(allocator, "{s}.zig", .{self.hook_name.?});
    defer allocator.free(hook_file_name);

    const hook_file_path = try std.fs.path.join(allocator, &.{ src_dir, output_dir, hook_file_name });
    defer allocator.free(hook_file_path);

    const file = try std.fs.cwd().createFile(hook_file_path, .{});
    defer file.close();

    try file.writeAll(hook_content);
    std.log.info("Generated hook file: {s}", .{hook_file_path});

    const rel_hook_file_path = try std.fs.path.relative(allocator, src_dir, hook_file_path);
    std.mem.replaceScalar(u8, rel_hook_file_path, '\\', '/');
    return rel_hook_file_path;
}

fn modifyHooks(allocator: std.mem.Allocator, hook_src_path: []const u8) !void {
    const hooks_file_path = src_dir ++ "/Hooks.zig";
    const hooks_source_file = try std.fs.cwd().openFile(hooks_file_path, .{});
    defer hooks_source_file.close();

    const source_code = try std.zig.readSourceFileToEndAlloc(allocator, hooks_source_file, null);
    defer allocator.free(source_code);

    const final_source = blk: {
        const modified_for_hooks_init = try modifyHooksInit(allocator, source_code, hook_src_path);
        defer allocator.free(modified_for_hooks_init);
        const modified_for_hooks_deinit = try modifyHooksDeinit(allocator, modified_for_hooks_init, hook_src_path);
        break :blk modified_for_hooks_deinit;
    };
    defer allocator.free(final_source);

    // const final_source = try self.modifyHooksGetAddressForHook(allocator, modified_source);
    // defer allocator.free(final_source);

    const file = try std.fs.cwd().createFile(hooks_file_path, .{});
    defer file.close();
    try file.writeAll(final_source);
    std.log.info("Updated src/Hooks.zig accordingly.", .{});
}

fn modifyHooksInit(allocator: std.mem.Allocator, source_code_z: [:0]const u8, hooks_src_path: []const u8) ![:0]u8 {
    var ast = std.zig.Ast.parse(allocator, source_code_z, .zig) catch |err| {
        std.log.err("Failed to parse Hooks.zig: {}", .{err});
        return err;
    };
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        std.log.err("Parse errors found in Hooks.zig:", .{});
        for (ast.errors) |parse_error| {
            std.log.err("  {}", .{parse_error});
        }
        return error.ParseError;
    }

    for (ast.rootDecls()) |idx| {
        const tag = ast.nodeTag(idx);
        if (tag != .fn_decl) {
            continue;
        }
        var buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = ast.fullFnProto(&buffer, idx) orelse continue;
        const name = ast.tokenSlice(fn_proto.ast.fn_token + 1);

        if (std.ascii.eqlIgnoreCase(name, "init")) {
            const last_token = ast.lastToken(idx);

            const last_token_tag = ast.tokenTag(last_token);
            if (last_token_tag != .r_brace) {
                std.log.err("Couldn't find the ending of the `init` function", .{});
                return error.FnEndNotFound;
            }

            const end = ast.tokenStart(last_token);

            const before_insertion = ast.source[0..end];
            const after_insertion = ast.source[end..];
            const insertion_code = try std.fmt.allocPrint(
                allocator,
                \\    // Auto-Generated!!!
                \\    try @import("{s}").init(&detour.?);
            ,
                .{hooks_src_path},
            );
            defer allocator.free(insertion_code);
            return try std.fmt.allocPrintSentinel(allocator, "{s}\n{s}\n{s}", .{ before_insertion, insertion_code, after_insertion }, 0);
        }
    }

    return error.InitFnNotFound;
}

fn modifyHooksDeinit(allocator: std.mem.Allocator, source_code_z: [:0]const u8, hooks_src_path: []const u8) ![:0]u8 {
    var ast = std.zig.Ast.parse(allocator, source_code_z, .zig) catch |err| {
        std.log.err("Failed to parse Hooks.zig: {}", .{err});
        return err;
    };
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        std.log.err("Parse errors found in Hooks.zig:", .{});
        for (ast.errors) |parse_error| {
            std.log.err("  {}", .{parse_error});
        }
        return error.ParseError;
    }

    for (ast.rootDecls()) |idx| {
        const tag = ast.nodeTag(idx);
        if (tag != .fn_decl) {
            continue;
        }
        var buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = ast.fullFnProto(&buffer, idx) orelse continue;
        const name = ast.tokenSlice(fn_proto.ast.fn_token + 1);

        if (std.ascii.eqlIgnoreCase(name, "deinit")) {
            const proto_last_token = ast.lastToken(fn_proto.ast.proto_node);
            const token_tag = ast.tokenTag(proto_last_token + 1);
            if (token_tag != .l_brace) {
                std.log.err("Couldn't find the start of the `deinit` function, token tag: {s}", .{@tagName(token_tag)});
                return error.FnEndNotFound;
            }

            var start = ast.tokenStart(proto_last_token + 1) + 1; // +1 to skip the `{` token
            if (ast.source[start] == '\n') {
                start += 1; // skip the newline after the `{`
            }

            const before_insertion = ast.source[0..start];
            const after_insertion = ast.source[start..];
            const insertion_code = try std.fmt.allocPrint(
                allocator,
                \\    // Auto-Generated!!!
                \\    @import("{s}").deinit();
            ,
                .{hooks_src_path},
            );
            defer allocator.free(insertion_code);
            return try std.fmt.allocPrintSentinel(allocator, "{s}{s}\n{s}", .{ before_insertion, insertion_code, after_insertion }, 0);
        }
    }

    return error.InitFnNotFound;
}

fn modifyHooksGetAddressForHook(self: *Self, allocator: std.mem.Allocator, source_code_z: [:0]const u8) ![:0]u8 {
    var ast = std.zig.Ast.parse(allocator, source_code_z, .zig) catch |err| {
        std.log.err("Failed to parse Hooks.zig: {}", .{err});
        return err;
    };
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        std.log.err("Parse errors found in Hooks.zig:", .{});
        for (ast.errors) |parse_error| {
            std.log.err("  {}", .{parse_error});
        }
        return error.ParseError;
    }

    for (ast.rootDecls()) |idx| {
        const tag = ast.nodeTag(idx);
        if (tag != .fn_decl) {
            continue;
        }
        var buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = ast.fullFnProto(&buffer, idx) orelse continue;
        const name = ast.tokenSlice(fn_proto.ast.fn_token + 1);

        if (std.ascii.eqlIgnoreCase(name, "getAddressForHook")) {
            const first_token = ast.firstToken(idx);
            var last_token = ast.lastToken(idx);
            // trying to find `return null;`, `return`
            while (ast.tokenTag(last_token) != .keyword_return) {
                last_token -= 1;
                if (last_token <= first_token) {
                    std.log.err("Couldn't find the ending of the `getAddressForHook` function", .{});
                    return error.FnEndNotFound;
                }
            }

            const end = ast.tokenStart(last_token);

            const before_insertion = ast.source[0..end];
            const after_insertion = ast.source[end..];
            const insertion_code = try std.fmt.allocPrint(
                allocator,
                \\// Auto-Generated!!!
                \\    if (std.ascii.eqlIgnoreCase(hook_name, "{s}")) {{
                \\        return module_addr + 0x{X};
                \\    }}
            ,
                .{ self.hook_name.?, self.hook_offset.? },
            );
            defer allocator.free(insertion_code);
            // the spaces are there for formatting :)
            return try std.fmt.allocPrintZ(allocator, "{s}{s}\n    {s}", .{ before_insertion, insertion_code, after_insertion });
        }
    }

    return error.GetAddressForHookFnNotFound;
}
