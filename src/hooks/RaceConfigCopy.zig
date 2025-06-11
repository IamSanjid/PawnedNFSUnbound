const builtin = @import("builtin");
const std = @import("std");

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

pub fn hookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile (stack_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&onHook),
        : "memory", "cc"
    );

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

pub fn hookFn2() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile (stack_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&performReset),
        : "memory", "cc"
    );

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

pub const name = "RaceConfigCopy";

var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
const allocator = arena.allocator();

const AssetMetadata = extern struct {
    padding: [0x30]u8,
    id: u32,
};

const Vec3WithPadding = extern struct {
    x: f32,
    y: f32,
    z: f32,
    padding: [4]u8,
};

fn List(comptime T: type) type {
    return extern struct {
        start: T,
        pub const ChildType = T;
        const ListSelf = @This();

        fn count(self: *const ListSelf) usize {
            @setRuntimeSafety(false);
            const size_ptr: *u32 = @ptrFromInt(@intFromPtr(self) - @sizeOf(u32));
            return @intCast(size_ptr.*);
        }

        fn span(self: *ListSelf) []T {
            @setRuntimeSafety(false);
            const list_size = self.count();
            if (list_size == 0) return &.{};
            const start_ptr: [*]T = @ptrCast(&self.start);
            return start_ptr[0..list_size];
        }

        fn dupeWithExtra(self: *ListSelf, extra: usize) ?*ListSelf {
            @setRuntimeSafety(false);
            const new_size = self.count() + extra;
            const ptr = ListSelf.new(new_size) orelse return null;
            @memcpy(ptr.span(), self.span());
        }

        fn new(size: usize) ?*ListSelf {
            @setRuntimeSafety(false);
            const total_size = @sizeOf(u32) + @sizeOf(T) * size;
            const raw = allocator.alloc(u8, total_size) catch return null;
            return @ptrFromInt(@intFromPtr(raw.ptr) + @sizeOf(u32));
        }
    };
}

const RaceVehiclePerformanceModificationItemData = extern struct {
    value: f32,
    attribute_to_modify: enum(c_uint) {
        engine_torque = 0,
        rev_limiter_time = 11,
        min_tire_traction_to_shift_up = 22,
        min_tire_traction_to_shift_up_first_gear = 23,
    },
    modification_type: enum(c_uint) {
        scalar = 0,
        addition = 1,
        override = 2,
    },
};

const RaceVehiclePerformanceModifierData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    performance_modifications: ?*List(RaceVehiclePerformanceModificationItemData),
};

const RaceVehiclePerformanceUpgradeData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    performance_modifier_data: ?*RaceVehiclePerformanceModifierData,
};

const RaceVehicleChassisConfigData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    inertia_box_vehicle_physics: Vec3WithPadding,
    roll_center: ?*anyopaque,
    front_weight_bias: ?*anyopaque,
    track_width_rear: f32,
    track_width_front: f32,
    terrain_bottom_out_friction: f32,
    wheel_base: f32,
    mass: f32,
    front_axle: f32,

    const metadata_id: u32 = 0x06690669;
    fn isValid(self: *const RaceVehicleChassisConfigData) bool {
        if (self.int1 != 2) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

const RaceVehicleEngineConfigData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    torque_noise: ?*anyopaque,
    engine_braking_vs_gear: ?*anyopaque,
    torque: ?*anyopaque,
    engine_friction_torque: ?*anyopaque,
    full_load_torque_noise: f32,
    speed_limiter_reverse: f32,
    max_rpm: f32,
    perfect_start_range_scale: f32,
    engine_resistance: f32,
    speed_limiter: f32,
    launch_control_max_rpm: f32,
    red_line: f32,
    fly_wheel_mass: f32,
    zero_load_torque_noise: f32,
    ignition_sequence_length: f32,
    perfect_start_range_shift: f32,
    engine_off_max_rpm: f32,
    engine_load_lerp: f32,
    speed_limiter_nos: f32,
    engine_off_max_speed: f32,
    rev_limiter_time: f32,
    engine_rev_full_throttle_duration: f32,
    engine_rev_sequence_length: f32,
    idle: f32,
    launch_control_min_rpm: f32,
    min_load_at_top_speed: f32,

    const metadata_id: u32 = 0x049F049F;
    fn isValid(self: *const RaceVehicleEngineConfigData) bool {
        if (self.int1 != 2 or self.int2 != 0x0005B100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

const RaceVehicleEngineData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    engine_config: ?*RaceVehicleEngineConfigData,
    engine_upgrades: ?*RaceVehiclePerformanceUpgradeData,
    audio_blueprint_bundle_id: u32,

    const metadata_id: u32 = 0x05EA05EA;
    fn isValid(self: *const RaceVehicleEngineData) bool {
        if (self.int1 != 2) return false;
        if (self.metadata) |metadata| {
            return metadata.id == metadata_id;
        }
        return false;
    }
};

const RaceVehicleEngineUpgradesData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    engine_upgrades: ?*List(?*RaceVehicleEngineData),
};

const RaceVehicleConfigData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    padding1: [224]u8,
    performance_modifiers: ?*anyopaque,
    engine_upgrades: ?*RaceVehicleEngineUpgradesData,
    forced_induction_upgrades: ?*anyopaque,
    x_bike: ?*anyopaque,
    onroad_upgrades: ?*anyopaque,
    transmission: ?*anyopaque,
    drag_upgrades: ?*anyopaque,
    performance_modifier_data: ?*anyopaque,
    item1_upgrades: ?*List(?*RaceVehiclePerformanceUpgradeData),
    steering: ?*anyopaque,
    tcs: ?*anyopaque,
    offroad_upgrades: ?*anyopaque,
    suspension: ?*anyopaque,
    abs: ?*anyopaque,
    drift_upgrades: ?*anyopaque,
    chassis: ?*RaceVehicleChassisConfigData,
    grip_upgrades: ?*anyopaque,
    esc: ?*anyopaque,
    tumble: ?*anyopaque,
    tuning_assets: ?*anyopaque,
    aerodynamics: ?*anyopaque,
    drift: ?*anyopaque,
    brakes: ?*anyopaque,
    forced_induction: ?*anyopaque,
    tire: ?*anyopaque,
    engine: ?*RaceVehicleEngineConfigData,
    fight_upgrades: ?*anyopaque,
    steering_wheel: ?*anyopaque,
    x_car: ?*anyopaque,
    padding2: [0x50]u8,
    vehicle_mode_at_reset: enum(c_uint) {
        idle = 0,
        entering = 1,
        entered = 2,
        starting = 3,
        started = 4,
        stopping = 5,
        leaving = 6,
    },
    vehicle_scoring_top_speed_mph: f32,
    stock_top_speed: f32,
    vehicle_mode_change_entering_time: f32,
    static_friction_break_velocity_mod: f32,
    vehicle_mode_change_stopping_time: f32,
    static_friction_break_collision_mod: f32,
    vehicle_mode_change_leaving_time: f32,
    vehicle_mode_change_starting_time: f32,
    engine_position: enum(c_uint) {
        rear = 0,
        mid = 1,
        front = 2,
    },
    is_a_truck: bool,
    is_a_bike: bool,
    is_convertible: bool,

    const metadata_id: u32 = 0x06B006B0;
    fn isValid(self: *const RaceVehicleConfigData) bool {
        if (self.int1 != 2) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

const ItemDataId = extern struct {
    id: u32,
};

const EngineStructureItemData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    item_ui: ?*anyopaque,
    id: u32,
    int3: u32,
    subitems: ?*anyopaque,
    padding1: [2]?*anyopaque,
    sorted_scope: ?*List(ItemDataId),
    buy_price: u32,
    int4: u32,
    sell_price: u32,
    padding2: [5]u32,
    ptr1: ?*anyopaque,
    dynamic_marketplace_attribute_hashes: ?*anyopaque,
    padding3: [2]?*anyopaque,
    padding4: [0x58]u8,
    ui_sort_index: u32,
    padding5: [0x80]u8,
    engine_upgrade_index: u32,
    int5: u32,

    const metadata_id: u32 = 0x04E304E3;
    fn isValid(self: *const EngineStructureItemData) bool {
        if (self.int1 != 2) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

const RaceVehicleItemData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    item_ui: ?*anyopaque,
    id: u32,
    int3: u32,
    subitems: ?*anyopaque,
    padding1: [2]?*anyopaque,
    sorted_scope: ?*List(ItemDataId),
    buy_price: u32,
    int4: u32,
    sell_price: u32,
    bool1: bool,
    bool2: bool,
    bool3: bool,
    purchaseable: bool,
    padding2: [6]u32,
    dynamic_marketplace_attribute_hashes: ?*anyopaque,
    tags: ?*anyopaque,
    tags_id: ?*anyopaque,
    has_been_built: bool,
    padding3: [0x3]u8,
    padding4: [0x3]u32,
    brand_data: ?*anyopaque,
    padding5: [0x2]?*anyopaque,
    unlock_asset_mp: ?*anyopaque,
    padding6: [0x34]u8,
    race_vehicle: ?*anyopaque,
    interaction_point_data: ?*anyopaque,
    category_items_count: ?*anyopaque,
    padding7: [0x48]u8,
    default_license_plate_text: [*:0]const u8,

    const metadata_id: u32 = 0x04C804C8;
    fn isValid(self: *const RaceVehicleItemData) bool {
        if (self.int1 != 2) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

fn isListType(comptime T: type) bool {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct" or !@hasDecl(T, "ChildType")) return false;
    if (T != List(T.ChildType)) return false;
    return true;
}

fn RecursiveConfigableAction(comptime T: type) type {
    if (isListType(T)) {
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

fn CopyState(comptime T: type) type {
    return struct {
        from_ident: []const u8,
        to_ident: []const u8,
        config: Configable(T) = .{},
        froms: std.AutoArrayHashMap(*T, void) = .init(allocator),
        tos: std.AutoArrayHashMap(*T, void) = .init(allocator),

        const Self = @This();

        fn populateHashSet(self: *Self, data_ptr: ?*T) bool {
            @setRuntimeSafety(false);
            const data = data_ptr orelse return false;
            if (!data.isValid()) return false;

            const asset_name = std.mem.span(data.asset_name);
            if (std.ascii.eqlIgnoreCase(asset_name, self.from_ident)) {
                self.froms.put(data, {}) catch return false;
                return true;
            }
            if (std.ascii.eqlIgnoreCase(asset_name, self.to_ident)) {
                self.tos.put(data, {}) catch return false;
                return true;
            }
            return false;
        }

        fn performCopy(self: *Self) ?*T {
            var from_i: usize = 0;
            var to_i: usize = 0;

            while (true) {
                const from_ptr = self.nextFrom(&from_i) orelse break;
                const to_ptr = self.nextTo(&to_i) orelse break;

                if (self.doCopy(from_ptr, to_ptr)) {
                    self.froms.clearAndFree();
                    self.tos.clearAndFree();
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
            if (!data.isValid()) return false;
            const asset_name = std.mem.span(data.asset_name);
            return std.ascii.eqlIgnoreCase(asset_name, self.from_ident);
        }

        fn isTo(self: Self, data: *T) bool {
            if (!data.isValid()) return false;
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

const PerformanceModification = struct { usize, Configable(RaceVehiclePerformanceModificationItemData) };
var performance_modifications = [_]PerformanceModification{
    .{ 0, fullCopyConfigable(RaceVehiclePerformanceModificationItemData, .{
        .value = ConfigableAction(f32){ .replace = 198.5 },
    }) },
};

const Items1Upgrade = struct { usize, Configable(RaceVehiclePerformanceUpgradeData) };
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
var items1_upgrades = [_]Items1Upgrade{
    .{ 0, fullCopyConfigable(RaceVehiclePerformanceUpgradeData, .{
        .performance_modifier_data = ConfigableAction(RaceVehiclePerformanceModifierData){
            .deep_copy = fullCopyConfigable(RaceVehiclePerformanceModifierData, null),
        },
    }) },
};
var rv_config_copies = [_]CopyState(RaceVehicleConfigData){
    .{
        .from_ident = "vehicles/player/car_audi_r8v10_2019/car_audi_r8v10_2019_racevehicleconfig",
        .to_ident = "vehicles/player/car_bmw_m3e46_2003/car_bmw_m3e46gtrrazernfsmw_2003_racevehicleconfig",
        .config = fullCopyConfigable(RaceVehicleConfigData, .{
            .chassis = ConfigableAction(RaceVehicleChassisConfigData){
                .deep_copy = fullCopyConfigable(RaceVehicleChassisConfigData, .{
                    .front_axle = ConfigableAction(f32).skip,
                    .track_width_front = ConfigableAction(f32).skip,
                    .track_width_rear = ConfigableAction(f32).skip,
                    .wheel_base = ConfigableAction(f32).skip,
                    // .mass = ConfigableAction(f32).copy,
                }),
            },
        }),
        // .config = .{
        //     .item1_upgrades = .{
        //         .deep_copy = &items1_upgrades,
        //     },
        //     .transmission = .copy,
        //     .engine = .copy,
        //     // .chassis = .copy,
        //     // .engine = .{
        //     //     .deep_copy = .{
        //     //         .max_rpm = .{ .replace = 7800 },
        //     //         .red_line = .{ .replace = 7550 },
        //     //         .engine_rev_sequence_length = .copy,
        //     //         .ignition_sequence_length = .copy,
        //     //         .perfect_start_range_shift = .copy,
        //     //         .rev_limiter_time = .copy,
        //     //         .engine_rev_full_throttle_duration = .copy,
        //     //     },
        //     // },
        //     .chassis = .{
        //         .deep_copy = fullCopyConfigable(RaceVehicleChassisConfigData, .{
        //             .front_axle = ConfigableAction(f32).skip,
        //             .track_width_front = ConfigableAction(f32).skip,
        //             .track_width_rear = ConfigableAction(f32).skip,
        //             .wheel_base = ConfigableAction(f32).skip,
        //             // .mass = ConfigableAction(f32).copy,
        //         }),
        //     },
        //     .stock_top_speed = ConfigableAction(f32){ .replace = 190 },
        // },
    },
};

var es_copies = [_]CopyState(EngineStructureItemData){
    .{
        .from_ident = "items/performanceitems/engines/car_ford_mustangboss302_1969_enginestructure",
        .to_ident = "items/performanceitems/engines/car_bmw_m3e46gtr_2003_razernfsmw_enginestructure",
        .config = fullCopyConfigable(EngineStructureItemData, .{
            .ui_sort_index = ConfigableAction(u32).skip,
            .asset_name = ConfigableAction([*:0]const u8).skip,
            .item_ui = ConfigableAction(?*anyopaque).skip,
            .id = ConfigableAction(u32).skip,
            .engine_upgrade_index = ConfigableAction(u32).skip,
        }),
    },
};

var ed_copies = [_]CopyState(RaceVehicleEngineData){
    .{
        .from_ident = "Vehicles/Tuning/EngineData/Car_Ford_MustangBoss302_1969_EngineData",
        .to_ident = "Vehicles/Tuning/EngineData/Car_BMW_M3E46GTRRazerNFSMW_2003_EngineData",
        .config = .{
            .engine_config = .copy,
            .engine_upgrades = .copy,
        },
    },
};

const CopyRaceVechicle = struct {
    config_copy: CopyState(RaceVehicleConfigData),
    item_copy: CopyState(RaceVehicleItemData),
    to_configs: std.ArrayList(*RaceVehicleConfigData) = .init(allocator),
    copied_engines: ?*List(ItemDataId) = null,

    fn performCopy(self: *CopyRaceVechicle, e_items: EngineItems, skip_ids: []const u32) void {
        if (self.config_copy.performCopy()) |to_config| {
            self.to_configs.append(to_config) catch {};
        }

        for (self.to_configs.items) |to_config| {
            if (!self.config_copy.isTo(to_config)) continue;
            const engine_upgrades = to_config.engine_upgrades orelse continue;
            const engine_upgrades_list = engine_upgrades.engine_upgrades orelse continue;
            const engines = engine_upgrades_list.span();
            if (e_items.count() < engines.len - 10) return;
            var from_i: usize = 0;
            //var to_i: usize = 0;
            while (true) {
                const from_ptr = self.item_copy.nextFrom(&from_i) orelse break;
                std.debug.print("Engine Items Collected: {}, engines_list: {}\n", .{ e_items.count(), engines.len });
                //const to_ptr = self.item_copy.nextTo(&to_i) orelse break;

                var sorted_scope = from_ptr.sorted_scope orelse continue;
                scope_loop: for (sorted_scope.span()) |item_data| {
                    for (skip_ids) |skip| if (skip == item_data.id) continue :scope_loop;

                    // const engine_item = e_items.get(item_data.id) orelse continue;
                    // if (!engine_item.isValid()) continue;

                    // std.debug.print("Found Engine Item: {s}\n", .{engine_item.asset_name});

                    // replace_engine_items[i] = engine_item.id;
                    // i += 1;
                    // if (i >= replace_engine_items.len) {
                    //     std.debug.print("Too many engine items to replace, skipping...\n", .{});
                    //     break;
                    // }
                }

                // sorted_scope = to_ptr.sorted_scope orelse continue;
                // scope_loop: for (sorted_scope.span()) |item_data| {
                //     for (skip_ids) |skip| if (skip == item_data.id) continue :scope_loop;

                //     const engine_item = e_items.get(item_data.id) orelse continue;
                //     if (!engine_item.isValid()) continue;

                //     std.debug.print("Found Engine Item: {s}\n", .{engine_item.asset_name});

                //     // replace_engine_items[i] = engine_item.id;
                //     // i += 1;
                //     // if (i >= replace_engine_items.len) {
                //     //     std.debug.print("Too many engine items to replace, skipping...\n", .{});
                //     //     break;
                //     // }
                // }
            }
            // var replace_engine_items: [16]u32 = undefined;
            // var i: usize = 0;
            // for (self.item_copy.froms.keys()) |item| {
            //     const sorted_scope = item.sorted_scope orelse continue;
            //     scope_loop: for (sorted_scope.span()) |item_data| {
            //         for (skip_ids) |skip| if (skip == item_data.id) continue :scope_loop;

            //         const engine_item = e_items.get(item_data.id) orelse continue;
            //         if (!engine_item.isValid()) continue;

            //         std.debug.print("Found Engine Item: {s}\n", .{engine_item.asset_name});

            //         replace_engine_items[i] = engine_item.id;
            //         i += 1;
            //         if (i >= replace_engine_items.len) {
            //             std.debug.print("Too many engine items to replace, skipping...\n", .{});
            //             break;
            //         }
            //     }
            // }

            // var j: usize = 0;
            // for (self.item_copy.tos.keys()) |item| {
            //     const sorted_scope = item.sorted_scope orelse continue;
            //     scope_loop: for (sorted_scope.span()) |*item_data| {
            //         for (skip_ids) |skip| if (skip == item_data.id) continue :scope_loop;

            //         const engine_item = e_items.get(item_data.id) orelse continue;
            //         if (!engine_item.isValid()) continue;
            //         item_data.id = replace_engine_items[j];
            //         j += 1;
            //         if (j >= i) {
            //             break;
            //         }
            //     }
            // }
        }
    }
};

var rv_item_copies = [_]CopyRaceVechicle{
    .{
        .config_copy = .{
            .from_ident = "vehicles/player/car_audi_r8v10_2019/car_audi_r8v10_2019_racevehicleconfig",
            .to_ident = "vehicles/player/car_bmw_m3e46_2003/car_bmw_m3e46gtrrazernfsmw_2003_racevehicleconfig",
            .config = fullCopyConfigable(RaceVehicleConfigData, .{
                // .asset_name = ConfigableAction([*:0]const u8).skip,
                .chassis = ConfigableAction(RaceVehicleChassisConfigData){
                    .deep_copy = fullCopyConfigable(RaceVehicleChassisConfigData, .{
                        .front_axle = ConfigableAction(f32).skip,
                        .track_width_front = ConfigableAction(f32).skip,
                        .track_width_rear = ConfigableAction(f32).skip,
                        .wheel_base = ConfigableAction(f32).skip,
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
const EngineItems = std.AutoArrayHashMap(u32, *EngineStructureItemData);
var engine_items = EngineItems.init(allocator);
var skip_engine_items = [_]u32{
    64962069, //items/performanceitems/engines/car_bmw_m3e46gtr_2003_razernfsmw_enginestructure
};

var mutex = std.Thread.Mutex{};

var thread_started = false;
var ready = false;
var first_time = false;

fn performReset(regs: *GeneralRegisters) callconv(.c) void {
    _ = regs;

    mutex.lock();
    defer mutex.unlock();

    if (arena.state.end_index == 0) {
        // first time..
        first_time = true;
    } else {
        first_time = false;
        ready = !ready;
    }

    if (ready) {
        std.debug.print("Ready!\n", .{});
    } else {
        std.debug.print("NotReady!\n", .{});
    }

    _ = arena.reset(.free_all);
}

fn onHook(regs: *GeneralRegisters) callconv(.c) void {
    //std.debug.print("rdx: {}\n", .{regs.rdi});
    // const my_guid = [_]u8{ 0x4B, 0x95, 0x36, 0xB1, 0x39, 0xF4, 0x55, 0x45, 0xBA, 0x16, 0x87, 0x65, 0x85, 0x1C, 0x42, 0x0D };
    // if (regs.rdi == 0) return;
    // const guid: [*]u8 = @ptrFromInt(regs.rdi - 0x10);
    // if (!std.mem.eql(u8, guid[0..16], &my_guid)) return;
    // std.debug.print("RaceConfigCopy hook called\n", .{});

    mutex.lock();
    defer mutex.unlock();

    if (!ready and !first_time) return;

    for (&es_copies) |*copy| {
        const found = copy.populateHashSet(@ptrFromInt(regs.rsi));
        _ = copy.performCopy();
        if (found) return;
    }

    for (&ed_copies) |*copy| {
        const found = copy.populateHashSet(@ptrFromInt(regs.rsi));
        _ = copy.performCopy();
        if (found) return;
    }

    for (&rv_item_copies) |*copy| {
        const found = copy.config_copy.populateHashSet(@ptrFromInt(regs.rsi)) or
            copy.item_copy.populateHashSet(@ptrFromInt(regs.rsi));
        copy.performCopy(engine_items, &skip_engine_items);
        if (found) return;
    }

    // for (&rv_config_copies) |*copy| {
    //     const found = copy.populateHashSet(@ptrFromInt(regs.rsi));
    //     _ = copy.performCopy();

    //     if (found) {
    //         return;
    //     }
    //     // if (copy.performCopy() and !thread_started) {
    //     //     // if (std.Thread.spawn(.{}, scopedItemsCopier, .{})) |thread| {
    //     //     //     thread_started = true;
    //     //     //     thread.detach();
    //     //     // }
    //     // }
    // }

    const es_item_ptr: ?*EngineStructureItemData = @ptrFromInt(regs.rsi);
    const es_item = es_item_ptr orelse return;
    if (!es_item.isValid()) return;
    const es_item_asset_name = std.mem.span(es_item.asset_name);
    // At this point we probably don't have enough information to distinguish between "engine structure" items,
    if (std.ascii.startsWithIgnoreCase(es_item_asset_name, "items/performanceitems/engines/")) {
        engine_items.put(es_item.id, es_item) catch {};
    }
}

fn scopedItemsCopier() void {
    var replace_engine_items: [16]u32 = undefined;
    var i: usize = 0;

    main_loop: while (true) {
        std.Thread.sleep(1 * std.time.ns_per_s);
        i = 0;

        mutex.lock();
        defer mutex.unlock();

        // we only care about engine structure items...
        for (&rv_item_copies) |*copy| {
            for (copy.hashset.keys()) |rv_item| {
                if (copy.isFrom(rv_item)) {
                    const scoped_items = rv_item.sorted_scope orelse continue;
                    for (scoped_items.span()) |item_id| {
                        const item = engine_items.get(item_id) orelse continue :main_loop;
                        if (!item.isValid()) continue;
                        replace_engine_items[i] = item.id;
                        i += 1;
                        if (i >= replace_engine_items.len) {
                            std.debug.print("Too many engines? RV_ID: {}\n", .{rv_item.id});
                            return;
                        }
                    }
                }
            }
        }

        for (&rv_item_copies) |*copy| {
            for (copy.hashset.keys()) |rv_item| {
                if (copy.isTo(rv_item)) {
                    const scoped_items = rv_item.sorted_scope orelse continue;
                    const item_ids = scoped_items.span();

                    var j: usize = 0;
                    for (item_ids) |*item_id| {
                        const item = engine_items.get(item_id) orelse continue :main_loop;
                        if (!item.isValid()) continue;
                        if (j >= i) {
                            std.debug.print("Too many engines? RV_ID: {}\n", .{rv_item.id});
                            return;
                        }
                        item_id.* = replace_engine_items[j];
                        j += 1;
                    }
                }
            }
        }
    }
}

test "offsets" {
    try std.testing.expectEqual(0x18, @offsetOf(RaceVehicleConfigData, "asset_name"));
    try std.testing.expectEqual(0x100, @offsetOf(RaceVehicleConfigData, "performance_modifiers"));
    try std.testing.expectEqual(0x180, @offsetOf(RaceVehicleConfigData, "grip_upgrades"));
    try std.testing.expectEqual(0x1E0, @offsetOf(RaceVehicleConfigData, "x_car"));
    try std.testing.expectEqual(0x238, @offsetOf(RaceVehicleConfigData, "vehicle_mode_at_reset"));
    try std.testing.expectEqual(0x25C, @offsetOf(RaceVehicleConfigData, "engine_position"));

    try std.testing.expectEqual(0x20, @offsetOf(RaceVehicleEngineConfigData, "torque_noise"));
    try std.testing.expectEqual(0x30, @offsetOf(RaceVehicleEngineConfigData, "torque"));
    try std.testing.expectEqual(0x50, @offsetOf(RaceVehicleEngineConfigData, "engine_resistance"));
    try std.testing.expectEqual(0x60, @offsetOf(RaceVehicleEngineConfigData, "fly_wheel_mass"));

    try std.testing.expectEqual(0x20, @offsetOf(RaceVehicleChassisConfigData, "inertia_box_vehicle_physics"));
    try std.testing.expectEqual(0x30, @offsetOf(RaceVehicleChassisConfigData, "roll_center"));
    try std.testing.expectEqual(0x38, @offsetOf(RaceVehicleChassisConfigData, "front_weight_bias"));
    try std.testing.expectEqual(0x54, @offsetOf(RaceVehicleChassisConfigData, "front_axle"));

    try std.testing.expectEqual(0x30, @offsetOf(EngineStructureItemData, "subitems"));
    try std.testing.expectEqual(0x48, @offsetOf(EngineStructureItemData, "sorted_scope"));
    try std.testing.expectEqual(0xE8, @offsetOf(EngineStructureItemData, "ui_sort_index"));
    try std.testing.expectEqual(0x16C, @offsetOf(EngineStructureItemData, "engine_upgrade_index"));
    try std.testing.expectEqual(0x170, @offsetOf(EngineStructureItemData, "int5"));

    try std.testing.expectEqual(0x48, @offsetOf(RaceVehicleItemData, "sorted_scope"));
    try std.testing.expectEqual(0x5F, @offsetOf(RaceVehicleItemData, "purchaseable"));
    try std.testing.expectEqual(0xA0, @offsetOf(RaceVehicleItemData, "brand_data"));
    try std.testing.expectEqual(0xB8, @offsetOf(RaceVehicleItemData, "unlock_asset_mp"));
    try std.testing.expectEqual(0xF8, @offsetOf(RaceVehicleItemData, "race_vehicle"));
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
