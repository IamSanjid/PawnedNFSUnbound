const builtin = @import("builtin");
const std = @import("std");
const ba = @import("binary_analysis");

const GeneralRegisters = extern struct {
    r15: usize = 0,
    r14: usize = 0,
    r13: usize = 0,
    r12: usize = 0,
    r11: usize = 0,
    r10: usize = 0,
    r9: usize = 0,
    r8: usize = 0,
    rbp: usize = 0,
    rdi: usize = 0,
    rsi: usize = 0,
    rdx: usize = 0,
    rcx: usize = 0,
    rbx: usize = 0,
    rax: usize = 0,
    rsp: usize = 0,
};

const heap_state_saver = struct {
    const push_volatile_regs = switch (builtin.target.os.tag) {
        .windows =>
        \\ push %%rdx
        \\ push %%r8
        \\ push %%r9
        \\ push %%r10
        \\ push %%r11
        \\
        ,
        else => @compileError("TODO: Support them!"),
    };
    const pop_volatile_regs = switch (builtin.target.os.tag) {
        .windows =>
        \\ pop %%r11
        \\ pop %%r10
        \\ pop %%r9
        \\ pop %%r8
        \\ pop %%rdx
        \\
        ,
        else => @compileError("TODO: Support them!"),
    };

    const first_arg_reg = if (builtin.target.os.tag == .windows) "%%rcx" else "%%rdi";
    const not_first_arg_reg = if (builtin.target.os.tag == .windows) "%%rdi" else "%%rcx";
    const save_call_hook_template = std.fmt.comptimePrint(
        \\ push %%rsp
        \\ sub ${d}, %%rsp
        \\ push %%rax
        \\
    ++
        " push " ++ first_arg_reg ++ "\n" ++
        push_volatile_regs ++
        " push " ++ not_first_arg_reg ++ "\n" ++
        " mov ${d}, " ++ first_arg_reg ++ "\n" ++
        \\ call malloc
        \\
    ++
        " pop " ++ not_first_arg_reg ++ "\n" ++
        pop_volatile_regs ++
        \\ mov %%rax, {d}(%%rsp)
        \\
    ++
        " pop " ++ first_arg_reg ++ "\n" ++
        " mov " ++ first_arg_reg ++ ", {}(%%rax)" ++ "\n" ++
        " mov %%rax, " ++ first_arg_reg ++ "\n" ++
        \\ pop %%rax
        \\
    ++
        " mov %%rax, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%rbx, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%rdx, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%rsi, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%rbp, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov " ++ not_first_arg_reg ++ ", {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        // moving rsp to the saved rsp
        \\ mov {d}(%%rsp), %%rax
        \\
    ++
        " mov %%rax, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r8, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r9, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r10, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r11, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r12, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r13, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r14, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        " mov %%r15, {}(" ++ first_arg_reg ++ ")" ++ "\n" ++
        \\ callq %[onHook:P]
        \\
    , .{
        @sizeOf(*GeneralRegisters),
        @sizeOf(GeneralRegisters),
        @sizeOf(usize) * 2,
        @offsetOf(GeneralRegisters, first_arg_reg[2..]),
        @offsetOf(GeneralRegisters, "rax"),
        @offsetOf(GeneralRegisters, "rbx"),
        @offsetOf(GeneralRegisters, "rdx"),
        @offsetOf(GeneralRegisters, "rsi"),
        @offsetOf(GeneralRegisters, "rbp"),
        @offsetOf(GeneralRegisters, not_first_arg_reg[2..]),
        // the last 2 regs have been popped
        @sizeOf(*GeneralRegisters),
        @offsetOf(GeneralRegisters, "rsp"),
        @offsetOf(GeneralRegisters, "r8"),
        @offsetOf(GeneralRegisters, "r9"),
        @offsetOf(GeneralRegisters, "r10"),
        @offsetOf(GeneralRegisters, "r11"),
        @offsetOf(GeneralRegisters, "r12"),
        @offsetOf(GeneralRegisters, "r13"),
        @offsetOf(GeneralRegisters, "r14"),
        @offsetOf(GeneralRegisters, "r15"),
    });

    const restore_template = std.fmt.comptimePrint(
        \\ mov (%%rsp), %%rax
        \\ mov {}(%%rax), %%rbx
        \\ mov {}(%%rax), %%rcx
        \\ mov {}(%%rax), %%rdx
        \\ mov {}(%%rax), %%rsi
        \\ mov {}(%%rax), %%rdi
        \\ mov {}(%%rax), %%rbp
        //\\ mov {}(%%rax), %%rsp
        \\ mov {}(%%rax), %%r8
        \\ mov {}(%%rax), %%r9
        \\ mov {}(%%rax), %%r10
        \\ mov {}(%%rax), %%r11
        \\ mov {}(%%rax), %%r12
        \\ mov {}(%%rax), %%r13
        \\ mov {}(%%rax), %%r14
        \\ mov {}(%%rax), %%r15
        \\ mov {}(%%rax), %%rax
        \\
    ++
        " push " ++ first_arg_reg ++ "\n" ++
        " mov {d}(%%rsp), " ++ first_arg_reg ++ "\n" ++
        \\ push %%rax
        \\
    ++
        push_volatile_regs ++
        " push " ++ not_first_arg_reg ++ "\n" ++
        \\ call free
        \\
    ++
        " pop " ++ not_first_arg_reg ++ "\n" ++
        pop_volatile_regs ++
        \\ pop %%rax
        \\ 
    ++
        " pop " ++ first_arg_reg ++ "\n" ++
        \\ add ${d}, %%rsp
        \\ pop %%rsp
        \\
    , .{
        @offsetOf(GeneralRegisters, "rbx"),
        @offsetOf(GeneralRegisters, "rcx"),
        @offsetOf(GeneralRegisters, "rdx"),
        @offsetOf(GeneralRegisters, "rsi"),
        @offsetOf(GeneralRegisters, "rdi"),
        @offsetOf(GeneralRegisters, "rbp"),
        //@offsetOf(GeneralRegisters, "rsp"),
        @offsetOf(GeneralRegisters, "r8"),
        @offsetOf(GeneralRegisters, "r9"),
        @offsetOf(GeneralRegisters, "r10"),
        @offsetOf(GeneralRegisters, "r11"),
        @offsetOf(GeneralRegisters, "r12"),
        @offsetOf(GeneralRegisters, "r13"),
        @offsetOf(GeneralRegisters, "r14"),
        @offsetOf(GeneralRegisters, "r15"),
        @offsetOf(GeneralRegisters, "rax"),
        @sizeOf(*GeneralRegisters),
        @sizeOf(usize),
    });
};

const stack_state_saver = struct {
    const first_arg_reg = if (builtin.target.os.tag == .windows) "%%rcx" else "%%rdi";
    const save_call_hook_template = std.fmt.comptimePrint(
        \\ push %%rsp
        \\ push %%rax
        \\ push %%rbx
        \\ push %%rcx
        \\ push %%rdx
        \\ push %%rsi
        \\ push %%rdi
        \\ push %%rbp
        \\ push %%r8
        \\ push %%r9
        \\ push %%r10
        \\ push %%r11
        \\ push %%r12
        \\ push %%r13
        \\ push %%r14
        \\ push %%r15
        \\
    ++
        "mov %%rsp, " ++ first_arg_reg ++ "\n" ++
        \\ callq %[onHook:P]
        \\ pop %%r15
        \\ pop %%r14
        \\ pop %%r13
        \\ pop %%r12
        \\ pop %%r11
        \\ pop %%r10
        \\ pop %%r9
        \\ pop %%r8
        \\ pop %%rbp
        \\ pop %%rdi
        \\ pop %%rsi
        \\ pop %%rdx
        \\ pop %%rcx
        \\ pop %%rbx
        \\ pop %%rax
        \\ pop %%rsp
    , .{});
};

fn loadingSceneHookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile (stack_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&onLoadingScene),
        : .{ .memory = true, .cc = true });

    // our special signature to detect end of function, too lazy to detect with other means :)
    asm volatile (
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
    );
}

fn resourceConstructHookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile (stack_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&onResourceConstruct),
        : .{ .memory = true, .cc = true });

    // our special signature to detect end of function, too lazy to detect with other means :)
    asm volatile (
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
    );
}

fn resourceMetadataCheckHookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile (stack_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&onResourceMetadataCheck),
        : .{ .memory = true, .cc = true });

    // our special signature to detect end of function, too lazy to detect with other means :)
    asm volatile (
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
    );
}

fn resourceItemDataHookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    // asm volatile (stack_state_saver.save_call_hook_template
    //     :
    //     : [onHook] "X" (&onResourceItemData),
    //     : "memory", "cc"
    // );

    // our special signature to detect end of function, too lazy to detect with other means :)
    asm volatile (
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
        \\ nop
        \\ int $3
    );
}

var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
const allocator = arena.allocator();

var scanner = ba.aob.Scanner.init(allocator);

/// Initializes the *CopyRaceVehicleConfig* hook with the given detour context.
pub fn init(detour: *ba.Detour) !void {
    _ = arena.reset(.free_all);

    const module = try ba.windows.getModuleInfo(allocator, base_module);
    defer module.deinit(allocator);

    // NeedForSpeedUnbound.exe+220FA36 - 48 8B C8              - mov rcx,rax
    try hookTo(detour, module.start + 0x220FA36, @intFromPtr(&loadingSceneHookFn));
    // on resource constructor call,  resource->vtable[0](resource), vtable's first function
    try hookTo(detour, module.start + 0x25A1737, @intFromPtr(&resourceConstructHookFn));
    // NeedForSpeedUnbound.exe+137A356 - 48 8B 10              - mov rdx,[rax]
    // try hookTo(detour, module.start + 0x137A356, @intFromPtr(&resourceItemDataHookFn));
    // NeedForSpeedUnbound.exe+2313424 - 48 8B 57 08           - mov rdx,[rdi+08]
    try hookTo(detour, module.start + 0x2313424, @intFromPtr(&resourceMetadataCheckHookFn));
}

fn hookTo(detour: *ba.Detour, hook_target: usize, hook_fn_start: usize) !void {
    const attached_info = try detour.attach(hook_target, hook_fn_start);

    try scanner.search_ranges.append(.{
        .start = hook_fn_start,
        .end = hook_fn_start + 512,
    });

    var search_ctx = scanner.newSearch();
    defer search_ctx.deinit();
    try search_ctx.searchBytes(&hook_fn_end_signature, .{ .find_one_per_range = true });
    const hook_fn_end = search_ctx.result.getLast().start;

    _ = try ba.Detour.emitJmp(hook_fn_end, attached_info.trampoline, null);
}

/// Cleans up resources allocated by the *CopyRaceVehicleConfig* hook
pub fn deinit() void {
    _ = arena.reset(.free_all);
    arena.deinit();
}

pub const hook_fn_end_signature = [_]u8{ 0x90, 0xCC } ** 8;
pub const name = "CopyRaceVehicleConfig";
pub const base_module = "NeedForSpeedUnbound.exe";

const sdk = @import("nfs_unbound_sdk.zig");
const List = sdk.List;
const RaceVehiclePerformanceModificationItemData = sdk.RaceVehiclePerformanceModificationItemData;
const RaceVehicleChassisConfigData = sdk.RaceVehicleChassisConfigData;
const RaceVehicleEngineData = sdk.RaceVehicleEngineData;
const RaceVehicleConfigData = sdk.RaceVehicleConfigData;
const FrameItemData = sdk.FrameItemData;
const DriveTrainItemData = sdk.DriveTrainItemData;
const EngineStructureItemData = sdk.EngineStructureItemData;
const RaceVehicleItemData = sdk.RaceVehicleItemData;
const ItemDataId = sdk.ItemDataId;

fn RecursiveConfigableAction(comptime T: type) type {
    if (sdk.isListType(T)) {
        return union(enum) {
            skip: void,
            copy: void,
            deep_copy: []struct { usize, Configable(T.ChildType) },
            replace: void,
        };
    }
    return union(enum) {
        skip: void,
        copy: void,
        deep_copy: Configable(T),
        replace: void,
    };
}

fn ConfigableAction(comptime T: type) type {
    const type_info = @typeInfo(T);
    if (type_info == .optional and @typeInfo(type_info.optional.child) == .pointer) {
        const ChildType = @typeInfo(type_info.optional.child).pointer.child;
        const child_info = @typeInfo(ChildType);
        if (ChildType != anyopaque and child_info == .@"struct") {
            return RecursiveConfigableAction(ChildType);
        }
    } else if (type_info == .@"struct") {
        return RecursiveConfigableAction(T);
    } else if (type_info == .pointer) {
        const ChildType = type_info.pointer.child;
        const child_info = @typeInfo(ChildType);
        if (ChildType != anyopaque and child_info == .@"struct") {
            return RecursiveConfigableAction(ChildType);
        } else if (ChildType == u8) {
            return union(enum) {
                skip: void,
                copy: void,
                deep_copy: void,
                replace: T,
            };
        }
    } else if (type_info == .int or type_info == .float or type_info == .bool or type_info == .@"enum") {
        return union(enum) {
            skip: void,
            copy: void,
            deep_copy: void,
            replace: T,
        };
    }
    return union(enum) {
        skip: void,
        copy: void,
        deep_copy: void,
        replace: void,
    };
}

const DeepCopyable = struct {
    optional: bool = false,
    pointer: bool = false,
    root_type: type,
};

fn getDeepCopyableInfo(comptime T: type) ?DeepCopyable {
    const type_info = @typeInfo(T);
    if (type_info == .optional) {
        const child_copy_able = getDeepCopyableInfo(type_info.optional.child) orelse return null;
        return .{ .optional = true, .pointer = child_copy_able.pointer, .root_type = child_copy_able.root_type };
    } else if (type_info == .pointer and type_info.pointer.child != anyopaque) {
        return .{ .root_type = type_info.pointer.child, .pointer = true };
    } else if (type_info == .@"struct") {
        return .{ .root_type = T };
    }

    return null;
}

fn ConfigableType(comptime T: type) type {
    if (getDeepCopyableInfo(T)) |copyable| {
        return copyable.root_type;
    }
    @compileError("Configable must be used with a struct type or with a child struct type: " ++ @typeName(T));
}

fn Configable(comptime T: type) type {
    const type_info = @typeInfo(ConfigableType(T));
    const type_struct = type_info.@"struct";
    var fields: [type_struct.fields.len]std.builtin.Type.StructField = undefined;
    inline for (type_struct.fields, 0..) |field, i| {
        const FieldAction = ConfigableAction(field.type);
        fields[i] = std.builtin.Type.StructField{
            .name = field.name,
            .type = FieldAction,
            .alignment = @alignOf(FieldAction),
            .default_value_ptr = @ptrCast(@alignCast(&FieldAction{ .skip = {} })),
            .is_comptime = false,
        };
    }

    return @Type(std.builtin.Type{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

fn fullCopyConfigable(comptime T: type, except: anytype) Configable(T) {
    const type_info = @typeInfo(Configable(T));
    const except_type_info = @typeInfo(@TypeOf(except));
    var configable: Configable(T) = .{};

    inline for (type_info.@"struct".fields) |field| {
        @field(configable, field.name) = .copy;
    }
    if (except_type_info != .null and except_type_info == .@"struct") {
        inline for (except_type_info.@"struct".fields) |field| {
            @field(configable, field.name) = @field(except, field.name);
        }
    }

    return configable;
}

fn copyBasedOnConfig(config: anytype, from: anytype, to: anytype) !void {
    const FromType = @TypeOf(from);
    const ToType = @TypeOf(to);
    if (FromType != ToType) {
        @compileError("'from' type is '" ++ @typeName(FromType) ++ "' to type is '" ++ @typeName(ToType) ++ "', they don't match");
    }
    const copy_type_info = @typeInfo(FromType);
    if (copy_type_info != .pointer) {
        @compileError("'from' and 'to' must be a pointer type.");
    }
    const ConfigType = @TypeOf(config);
    if (ConfigType != Configable(copy_type_info.pointer.child)) {
        @compileError("'" ++ @typeName(ConfigType) ++ "' is not compatible with '" ++ @typeName(FromType) ++ "'");
    }

    const config_type_info = @typeInfo(ConfigType);
    inline for (config_type_info.@"struct".fields) |field| {
        const field_name = field.name;
        const field_value = @field(config, field_name);
        const OriginalFieldType = @TypeOf(@field(from, field_name));

        switch (field_value) {
            .skip => {},
            .copy => |copy| {
                if (@TypeOf(copy) == void) {
                    @field(to, field_name) = @field(from, field_name);
                }
            },
            .deep_copy => |deep_copy| {
                const DeepCopyType = @TypeOf(deep_copy);
                if (DeepCopyType != void) {
                    if (getDeepCopyableInfo(OriginalFieldType)) |copyable| {
                        const deep_copy_type_info = @typeInfo(DeepCopyType);
                        if (deep_copy_type_info == .pointer and deep_copy_type_info.pointer.size == .slice) {
                            const span = struct {
                                fn func(comptime T: type, comptime optional: bool, f: anytype) []T.ChildType {
                                    if (optional) {
                                        return f.?.span();
                                    } else {
                                        return f.span();
                                    }
                                }
                            }.func;
                            if (copyable.optional) {
                                if (@field(from, field_name) == null) return error.NullNotReady;
                                if (@field(to, field_name) == null) return error.NullNotReady;
                            }
                            const from_span = span(copyable.root_type, copyable.optional, @field(from, field_name));
                            const to_span = span(copyable.root_type, copyable.optional, @field(to, field_name));

                            const ElementType = @TypeOf(from_span[0]);
                            const element_type_info = @typeInfo(ElementType);

                            for (deep_copy) |at| {
                                const at_index = at.@"0";
                                const at_config = at.@"1";

                                if (at_index >= from_span.len or at_index >= to_span.len) {
                                    continue;
                                }

                                if (element_type_info == .optional) {
                                    if (@typeInfo(element_type_info.optional.child) == .pointer) {
                                        try copyBasedOnConfig(at_config, from_span[at_index].?, to_span[at_index].?);
                                    } else {
                                        try copyBasedOnConfig(at_config, &from_span[at_index].?, &to_span[at_index].?);
                                    }
                                } else if (element_type_info == .pointer) {
                                    try copyBasedOnConfig(at_config, from_span[at_index], to_span[at_index]);
                                } else {
                                    try copyBasedOnConfig(at_config, &from_span[at_index], &to_span[at_index]);
                                }
                            }
                            // by default we copy the rest of the elements
                            outer_loop: for (0..from_span.len) |index| {
                                if (index >= from_span.len or index >= to_span.len) {
                                    break;
                                }
                                // we want to save space and allocations..
                                for (deep_copy) |at| {
                                    const at_index = at.@"0";
                                    if (at_index == index) continue :outer_loop;
                                }
                                from_span[index] = to_span[index];
                            }
                        } else {
                            if (copyable.optional) {
                                if (@field(from, field_name) == null) return error.NullNotReady;
                                if (@field(to, field_name) == null) return error.NullNotReady;
                                if (copyable.pointer) {
                                    try copyBasedOnConfig(deep_copy, @field(from, field_name).?, @field(to, field_name).?);
                                } else {
                                    try copyBasedOnConfig(deep_copy, &@field(from, field_name).?, &@field(to, field_name).?);
                                }
                            } else if (copyable.pointer) {
                                try copyBasedOnConfig(deep_copy, @field(from, field_name), @field(to, field_name));
                            } else {
                                try copyBasedOnConfig(deep_copy, &@field(from, field_name), &@field(to, field_name));
                            }
                        }
                    }
                }
            },
            .replace => |replace| {
                if (@TypeOf(replace) != void) {
                    @field(to, field_name) = replace;
                }
            },
        }
    }
}

fn CopyState(comptime OT: type) type {
    const T = if (@hasDecl(OT, "c")) OT.c else OT;
    const isValid: fn (*const T) bool = OT.isValid;
    const fromAddress: fn (usize) ?*T = if (@hasDecl(T, "from")) T.from else struct {
        fn from(ptr: usize) ?*T {
            const c_opt_ptr: ?*T = @ptrFromInt(ptr);
            const c_ptr = c_opt_ptr orelse return null;
            if (!isValid(c_ptr)) return null;
            return c_ptr;
        }
    }.from;

    return struct {
        from_ident: []const u8,
        to_ident: []const u8,
        config: Configable(T) = .{},
        froms: std.AutoArrayHashMap(*T, void) = .init(allocator),
        tos: std.AutoArrayHashMap(*T, void) = .init(allocator),

        const Self = @This();

        fn reset(self: *Self) void {
            self.froms.clearRetainingCapacity();
            self.tos.clearRetainingCapacity();
        }

        fn populateHashSet(self: *Self, ptr: usize) bool {
            const data = fromAddress(ptr) orelse return false;
            if (!isValid(data)) return false;

            const asset_name = std.mem.span(data.asset_name);
            if (std.ascii.eqlIgnoreCase(asset_name, self.from_ident)) {
                if (T == RaceVehicleConfigData) {
                    std.debug.print("Found from RaceVehicleConfigData at 0x{X}\n", .{@intFromPtr(data)});
                }
                self.froms.put(data, {}) catch return false;
                return true;
            }
            if (std.ascii.eqlIgnoreCase(asset_name, self.to_ident)) {
                if (T == RaceVehicleConfigData) {
                    std.debug.print("Found to RaceVehicleConfigData at 0x{X}\n", .{@intFromPtr(data)});
                }
                self.tos.put(data, {}) catch return false;
                return true;
            }
            return false;
        }

        /// Returns copied `to` ptr.
        fn performCopy(self: *Self) ?*T {
            var from_i: usize = 0;
            var to_i: usize = 0;

            while (true) {
                const from_ptr = self.nextFrom(&from_i) orelse break;
                const to_ptr = self.nextTo(&to_i) orelse break;

                if (self.doCopy(from_ptr, to_ptr)) {
                    self.froms.clearRetainingCapacity();
                    self.tos.clearRetainingCapacity();
                    return to_ptr;
                }
            }
            return null;
        }

        fn nextFrom(self: *Self, i: *usize) ?*T {
            var ptrs = self.froms.keys();
            while (i.* < ptrs.len) {
                const ptr = ptrs[i.*];
                i.* += 1;

                if (self.isFrom(ptr)) {
                    return ptr;
                } else {
                    _ = self.froms.swapRemove(ptr);
                    ptrs = self.froms.keys();
                    i.* = 0;
                }
            }
            return null;
        }

        fn nextTo(self: *Self, i: *usize) ?*T {
            var ptrs = self.tos.keys();
            while (i.* < ptrs.len) {
                const ptr = ptrs[i.*];
                i.* += 1;

                if (self.isTo(ptr)) {
                    return ptr;
                } else {
                    _ = self.tos.swapRemove(ptr);
                    ptrs = self.tos.keys();
                    i.* = 0;
                }
            }
            return null;
        }

        fn isFrom(self: Self, data: *T) bool {
            if (!isValid(data)) return false;
            const asset_name = std.mem.span(data.asset_name);
            return std.ascii.eqlIgnoreCase(asset_name, self.from_ident);
        }

        fn isTo(self: Self, data: *T) bool {
            if (!isValid(data)) return false;
            const asset_name = std.mem.span(data.asset_name);
            return std.ascii.eqlIgnoreCase(asset_name, self.to_ident);
        }

        fn doCopy(self: *Self, from_config: *T, to_config: *T) bool {
            if (!self.isFrom(from_config) or !self.isTo(to_config)) {
                std.debug.print("Unreachable?\n", .{});
                return false;
            }

            copyBasedOnConfig(self.config, from_config, to_config) catch {
                return false;
            };

            std.debug.print("Done copying (" ++ @typeName(T) ++ ") from `0x{X}` to `0x{X}`\n", .{
                @intFromPtr(from_config),
                @intFromPtr(to_config),
            });
            return true;
        }
    };
}

//
// Example of how List(T) can be used with ConfigableAction
//
// const PerformanceModification = struct { usize, Configable(RaceVehiclePerformanceModificationItemData) };
// var performance_modifications = [_]PerformanceModification{
//     .{ 0, fullCopyConfigable(RaceVehiclePerformanceModificationItemData, .{
//         .value = ConfigableAction(f32){ .replace = 198.5 },
//     }) },
// };
// const Items1Upgrade = struct { usize, Configable(RaceVehiclePerformanceUpgradeData) };
// var items1_upgrades = [_]Items1Upgrade{
//     .{ 0, fullCopyConfigable(RaceVehiclePerformanceUpgradeData, .{
//         .performance_modifier_data = ConfigableAction(RaceVehiclePerformanceModifierData){
//             .deep_copy = fullCopyConfigable(RaceVehiclePerformanceModifierData, .{
//                 .performance_modifications = ConfigableAction(List(RaceVehiclePerformanceModificationItemData)){
//                     .deep_copy = &performance_modifications,
//                 },
//             }),
//         },
//     }) },
// };
// var items1_upgrades = [_]Items1Upgrade{
//     .{ 0, fullCopyConfigable(RaceVehiclePerformanceUpgradeData, .{
//         .performance_modifier_data = ConfigableAction(RaceVehiclePerformanceModifierData){
//             .deep_copy = fullCopyConfigable(RaceVehiclePerformanceModifierData, null),
//         },
//     }) },
// };

const CopyRaceVechicle = struct {
    config_copy: CopyState(RaceVehicleConfigData),
    item_copy: CopyState(RaceVehicleItemData),
    to_configs: std.ArrayList(*RaceVehicleConfigData) = .init(allocator),
    from_scope_ids: std.AutoArrayHashMap(u32, void) = .init(allocator),
    to_scope_ids: std.AutoArrayHashMap(u32, void) = .init(allocator),
    copied_engines: ?*List(ItemDataId) = null,

    fn reset(self: *CopyRaceVechicle) void {
        self.to_configs.clearRetainingCapacity();
        self.from_scope_ids.clearRetainingCapacity();
        self.config_copy.reset();
        self.item_copy.reset();
    }

    fn performConfigCopy(self: *CopyRaceVechicle) void {
        if (self.config_copy.performCopy()) |to_config| {
            self.to_configs.append(to_config) catch {};
        }
    }

    fn performItemCopy(self: *CopyRaceVechicle, e_items: EngineItems, skip_ids: []const u32) void {
        if (self.to_configs.items.len == 0) return;
        var i: usize = self.to_configs.items.len - 1;
        while (true) : (i -= 1) {
            const to_config = self.to_configs.items[i];
            if (!to_config.isValid()) {
                std.debug.print("not proper RaceVehicleConfigData? 0x{X}\n", .{@intFromPtr(to_config)});
                _ = self.to_configs.orderedRemove(i);
                if (i == 0) break else continue;
            }

            const engine_upgrades = to_config.engine_upgrades orelse continue;
            const engine_upgrades_list = engine_upgrades.engine_upgrades orelse continue;
            const engines = engine_upgrades_list.span();
            if (e_items.count() + 10 < engines.len) {
                return; // need more engine structure items
            }

            froms_loop: while (true) {
                const froms = self.item_copy.froms.keys();
                for (froms) |from| {
                    if (!self.item_copy.isFrom(from)) {
                        // std.debug.print("NotFrom RaceVehicleItemData: 0x{X}? \n\n", .{@intFromPtr(from)});
                        _ = self.item_copy.froms.swapRemove(from);
                        continue :froms_loop;
                    }
                    const sorted_scope_list = from.sorted_scope orelse continue;
                    const sorted_scope = sorted_scope_list.span();

                    const last_count = self.from_scope_ids.count();

                    for (sorted_scope) |item_db| {
                        if (!e_items.contains(item_db.id)) continue;
                        if (std.mem.containsAtLeastScalar(u32, skip_ids, 1, item_db.id)) {
                            continue;
                        }
                        self.from_scope_ids.put(item_db.id, {}) catch return;
                    }
                    if (last_count != self.from_scope_ids.count()) {
                        std.debug.print("Found FromScopeIds({}):\n", .{self.from_scope_ids.count()});
                        for (self.from_scope_ids.keys()) |id| {
                            std.debug.print("  {}\n", .{id});
                        }
                    }
                    break;
                }
                break;
            }

            if (self.from_scope_ids.count() > 0) {
                const from_scope_ids = self.from_scope_ids.keys();
                var j: usize = 0;

                tos_loop: while (true) {
                    const tos = self.item_copy.tos.keys();

                    for (tos) |to| {
                        if (!self.item_copy.isTo(to)) {
                            _ = self.item_copy.tos.swapRemove(to);
                            continue :tos_loop;
                        }
                        const sorted_scope_list = to.sorted_scope orelse continue;
                        const sorted_scope = sorted_scope_list.span();
                        for (sorted_scope) |*item_db| {
                            if (!e_items.contains(item_db.id)) continue;
                            if (std.mem.containsAtLeastScalar(u32, skip_ids, 1, item_db.id)) {
                                continue;
                            }
                            if (j >= from_scope_ids.len) break :tos_loop;
                            std.debug.print("setting: {} to {}\n", .{ item_db.id, from_scope_ids[j] });
                            item_db.id = from_scope_ids[j];
                            j += 1;
                        }
                        if (j < from_scope_ids.len) {
                            const amount_left = from_scope_ids.len - j;
                            // TODO: Test the list dupeWithExtra throughly
                            // if (sorted_scope_list.dupeWithExtra(allocator, amount_left)) |new_scope_list| {
                            //     const new_scope = new_scope_list.span();
                            //     var start_idx: usize = new_scope.len - amount_left;
                            //     for (0..amount_left) |_| {
                            //         new_scope[start_idx].id = from_scope_ids[j];
                            //         start_idx += 1;
                            //         j += 1;
                            //     }
                            // }

                            var end_idx: usize = sorted_scope.len;
                            for (0..amount_left) |_| {
                                end_idx -= 1;
                                std.debug.print("setting: {} to {}\n", .{ sorted_scope[end_idx].id, from_scope_ids[j] });
                                sorted_scope[end_idx].id = from_scope_ids[j];
                                j += 1;
                            }
                        }
                        std.mem.sort(ItemDataId, sorted_scope_list.span(), {}, struct {
                            fn lessThanFn(_: void, lhs: ItemDataId, rhs: ItemDataId) bool {
                                return lhs.id < rhs.id;
                            }
                        }.lessThanFn);

                        _ = self.item_copy.tos.swapRemove(to);
                        continue :tos_loop;
                    }
                    break;
                }
            }

            if (i == 0) break;
        }
    }
};

var engine_data_copies = [_]CopyState(RaceVehicleEngineData){
    .{
        .from_ident = "Vehicles/Tuning/EngineData/Car_Ford_MustangBoss302_1969_EngineData",
        .to_ident = "Vehicles/Tuning/EngineData/Car_BMW_M3E46GTRRazerNFSMW_2003_EngineData",
        .config = .{
            .engine_config = .copy,
            .engine_upgrades = .copy,
        },
    },
};

var race_vehicle_copies = [_]CopyRaceVechicle{
    .{
        .config_copy = .{
            .from_ident = "vehicles/player/car_audi_r8v10_2019/car_audi_r8v10_2019_racevehicleconfig",
            .to_ident = "vehicles/player/car_bmw_m3e46_2003/car_bmw_m3e46gtrrazernfsmw_2003_racevehicleconfig",
            .config = fullCopyConfigable(RaceVehicleConfigData, .{
                .asset_name = ConfigableAction([*:0]const u8).skip,
                .chassis = ConfigableAction(RaceVehicleChassisConfigData){
                    .deep_copy = fullCopyConfigable(RaceVehicleChassisConfigData, .{
                        // .track_width_front = ConfigableAction(f32).skip,
                        // .track_width_rear = ConfigableAction(f32).skip,
                        .wheel_base = ConfigableAction(f32).skip,
                        .front_axle = ConfigableAction(f32).skip,
                        // .mass = ConfigableAction(f32).copy,
                    }),
                },
            }),
        },
        .item_copy = .{
            .from_ident = "Items/car_audi_r8v10_2019/car_audi_r8v10_2019",
            .to_ident = "items/car_bmw_m3e46_2003/car_bmw_m3e46gtr_2003_razernfsmwdistressed",
            .config = .{},
        },
    },
};

var engine_structure_copies = [_]CopyState(EngineStructureItemData){
    .{
        .from_ident = "items/performanceitems/engines/car_ford_mustangboss302_1969_enginestructure",
        .to_ident = "items/performanceitems/engines/car_bmw_m3e46gtr_2003_razernfsmw_enginestructure",
        .config = fullCopyConfigable(EngineStructureItemData, .{
            // .ui_sort_index = ConfigableAction(u32).skip,
            .asset_name = ConfigableAction([*:0]const u8).skip,
            .item_ui = ConfigableAction(?*anyopaque).skip,
            .id = ConfigableAction(u32).skip,
            .engine_upgrade_index = ConfigableAction(u32).skip,
        }),
    },
};

var frame_copies = [_]CopyState(FrameItemData){
    .{
        .from_ident = "items/performanceitems/frames/car_audi_r8v10_2019_frame",
        .to_ident = "items/performanceitems/frames/car_bmw_m3e46gtr_2003_razernfsmw_2003_frame",
        .config = fullCopyConfigable(FrameItemData, .{
            .asset_name = ConfigableAction([*:0]const u8).skip,
            .item_ui = ConfigableAction(?*anyopaque).skip,
            .id = ConfigableAction(u32).skip,
        }),
    },
};

var drive_train_copies = [_]CopyState(DriveTrainItemData){
    .{
        .from_ident = "items/performanceitems/drivetrains/car_audi_r8v10_2019_drivetrain",
        .to_ident = "items/performanceitems/drivetrains/car_bmw_m3e46gtr_2003_razernfsmw_drivetrain",
        .config = fullCopyConfigable(DriveTrainItemData, .{
            .asset_name = ConfigableAction([*:0]const u8).skip,
            .item_ui = ConfigableAction(?*anyopaque).skip,
            .id = ConfigableAction(u32).skip,
        }),
    },
};

const EngineItems = std.AutoArrayHashMap(u32, *EngineStructureItemData);
var engine_items = EngineItems.init(allocator);
var skip_engine_items = [_]u32{
    64962069, // items/performanceitems/engines/car_bmw_m3e46gtr_2003_razernfsmw_enginestructure
    20426296, // items/performanceitems/engines/car_ford_mustangboss302_1969_enginestructure
};

var mutex = std.Thread.Mutex{};

fn onLoadingScene(regs: *GeneralRegisters) callconv(.c) void {
    _ = regs;

    mutex.lock();
    defer mutex.unlock();

    std.debug.print("onLoadingScene called, resetting!\n", .{});

    for (&engine_data_copies) |*copy| {
        copy.reset();
    }

    for (&race_vehicle_copies) |*copy| {
        copy.reset();
    }

    engine_items.clearRetainingCapacity();

    for (&engine_structure_copies) |*copy| {
        copy.reset();
    }

    for (&frame_copies) |*copy| {
        copy.reset();
    }

    for (&drive_train_copies) |*copy| {
        copy.reset();
    }
}

fn onResourceConstruct(regs: *GeneralRegisters) callconv(.c) void {
    // std.debug.print("rdx: {}\n", .{regs.rdi});
    // const my_guid = [_]u8{ 0x4B, 0x95, 0x36, 0xB1, 0x39, 0xF4, 0x55, 0x45, 0xBA, 0x16, 0x87, 0x65, 0x85, 0x1C, 0x42, 0x0D };
    // if (regs.rdi == 0) return;
    // const guid: [*]u8 = @ptrFromInt(regs.rdi - 0x10);
    // if (!std.mem.eql(u8, guid[0..16], &my_guid)) return;
    // std.debug.print("RaceConfigCopy hook called\n", .{});

    // EngineStructure :)
    {
        const es_item_ptr1: ?*EngineStructureItemData = @ptrFromInt(regs.rsi);
        const es_item_ptr2: ?*EngineStructureItemData = @ptrFromInt(regs.r15);
        const es_item = blk: {
            if (es_item_ptr1) |ptr| {
                if (ptr.isValid()) {
                    break :blk ptr;
                }
            }
            if (es_item_ptr2) |ptr| {
                if (ptr.isValid()) {
                    break :blk ptr;
                }
            }
            return;
        };

        const es_item_asset_name = std.mem.span(es_item.asset_name);
        // At this point we probably don't have enough information to distinguish between "engine structure" items,
        if (std.ascii.startsWithIgnoreCase(es_item_asset_name, "items/performanceitems/engines/")) {
            mutex.lock();
            defer mutex.unlock();

            engine_items.put(es_item.id, es_item) catch return;
        }
    }
}

fn onResourceMetadataCheck(regs: *GeneralRegisters) callconv(.c) void {
    mutex.lock();
    defer mutex.unlock();

    for (&engine_data_copies) |*copy| {
        const found = copy.populateHashSet(regs.rdi);
        _ = copy.performCopy();
        if (found) {
            return;
        }
    }

    for (&race_vehicle_copies) |*copy| {
        const found = copy.config_copy.populateHashSet(regs.rdi) or
            copy.item_copy.populateHashSet(regs.rdi);
        copy.performConfigCopy();
        if (found) {
            std.debug.print("Found items: froms: {} tos: {}\n", .{ copy.item_copy.froms.count(), copy.item_copy.tos.count() });
            std.debug.print("total performanceitems engins: {}\n", .{engine_items.count()});
            copy.performItemCopy(engine_items, &skip_engine_items);
            return;
        }
    }

    for (&frame_copies) |*copy| {
        const found = copy.populateHashSet(regs.rdi);
        _ = copy.performCopy();
        if (found) {
            return;
        }
    }

    for (&drive_train_copies) |*copy| {
        const found = copy.populateHashSet(regs.rdi);
        _ = copy.performCopy();
        if (found) {
            return;
        }
    }

    for (&engine_structure_copies) |*copy| {
        const found = copy.populateHashSet(regs.rdi);
        _ = copy.performCopy();
        if (found) {
            return;
        }
    }
}

test "configable" {
    const ConfigableActionAnyopaque = union(enum) {
        skip: void,
        copy: void,
    };
    const dp: *const anyopaque = @ptrCast(@alignCast(&ConfigableActionAnyopaque{ .skip = {} }));
    const fields: [1]std.builtin.Type.StructField = .{
        .{
            .name = "a",
            .type = ConfigableActionAnyopaque,
            .alignment = @alignOf(ConfigableActionAnyopaque),
            .default_value_ptr = dp,
            .is_comptime = false,
        },
    };
    const ConfigableAnyopaque = @Type(std.builtin.Type{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
    const anyopaque_value: ConfigableAnyopaque = .{ .a = .{ .copy = {} } };
    try std.testing.expectEqual(ConfigableAnyopaque{
        .a = .{
            .copy = {},
        },
    }, anyopaque_value);

    const Foo = struct {
        a: ?*anyopaque,
    };
    const ConfigableFoo = Configable(Foo);
    const foo_value: ConfigableFoo = .{ .a = .{ .copy = {} } };
    try std.testing.expectEqual(ConfigableFoo{
        .a = .{ .copy = {} },
    }, foo_value);
    const ConfigableRaceVehicleConfigData = Configable(RaceVehicleConfigData);
    var configable: ConfigableRaceVehicleConfigData = .{};
    configable.engine = .{
        .deep_copy = .{
            .engine_resistance = .{ .replace = -450 },
        },
    };
    configable.asset_name = .{
        .replace = "Test",
    };
    const expected_configable: ConfigableRaceVehicleConfigData = .{
        .engine = .{
            .deep_copy = .{
                .engine_resistance = .{ .replace = -450 },
            },
        },
        .asset_name = .{ .replace = "Test" },
    };
    try std.testing.expectEqual(expected_configable, configable);
}
