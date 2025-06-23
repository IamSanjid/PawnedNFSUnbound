const std = @import("std");

// ========== General ==========

pub const AssetMetadata = extern struct {
    padding: [0x30]u8,
    id: u32,
};

pub const Vec3WithPadding = extern struct {
    x: f32,
    y: f32,
    z: f32,
    padding: [4]u8,
};

pub fn List(comptime T: type) type {
    return extern struct {
        start: T,
        pub const ChildType = T;
        const Self = @This();

        pub fn count(self: *const Self) usize {
            @setRuntimeSafety(false);
            const size_ptr: *u32 = @ptrFromInt(@intFromPtr(self) - @sizeOf(u32));
            return @intCast(size_ptr.*);
        }

        pub fn at(self: *Self, index: usize) T {
            const list_size = self.count();
            std.debug.assert(index < list_size);
            {
                @setRuntimeSafety(false);
                const start_ptr: [*]T = @ptrCast(&self.start);
                return start_ptr[index];
            }
        }

        pub fn span(self: *Self) []T {
            @setRuntimeSafety(false);
            const list_size = self.count();
            if (list_size == 0) return &.{};
            const start_ptr: [*]T = @ptrCast(&self.start);
            return start_ptr[0..list_size];
        }

        pub fn dupeWithExtra(self: *Self, ally: std.mem.Allocator, extra: usize) ?*Self {
            @setRuntimeSafety(false);
            const new_size = @as(u32, @truncate(self.count())) + @as(u32, @truncate(extra));
            const new_list = Self.new(ally, new_size) orelse return null;
            @memcpy(new_list.span(), self.span());
            return new_list;
        }

        pub fn new(ally: std.mem.Allocator, size: u32) ?*Self {
            @setRuntimeSafety(false);
            const total_size = @sizeOf(u32) + @sizeOf(T) * size;
            const raw = ally.alignedAlloc(u8, .of(T), total_size) catch return null;
            const size_ptr: *u32 = @ptrFromInt(@intFromPtr(raw.ptr));
            size_ptr.* = size;
            return @ptrFromInt(@intFromPtr(raw.ptr) + @sizeOf(u32));
        }
    };
}

// ========== Event Related ==========

pub const EventEconomyAsset = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]u8,
    multiplayer_scalar_overrides: ?*anyopaque,
    participation_reward: i32,
    reward_type: enum(u32) {
        leaderboard_position = 0,
        game_mode_participation = 1,
        tier = 2,
    },
    prize_money: *List(u32),
    buy_in: u32,

    const metadata_id: u32 = 0x06980698;
    pub fn isValid(self: *const EventEconomyAsset) bool {
        if (self.metadata) |some_data| {
            return some_data.id == metadata_id;
        }
        return false;
    }
};

pub const ProgressionSessionData = extern struct {
    padding1: [0x58]u8,
    meetup: ?*anyopaque,
    owner_ptr1: ?*ProgressionEventData,
    owner_ptr2: ?*ProgressionEventData,
    economy_asset: ?*EventEconomyAsset,
    wanted_level_increase: f32,
    wanted_level_required: f32,
    maximum_metric_SRFM: f32,
    minimum_metric_SRFM: f32,
    is_available: bool,
    is_high_heat: bool,
};

pub const ProgressionEventData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    hard: ?*anyopaque,
    easy: ?*anyopaque,
    normal: ?*anyopaque,
    thursday_night: ProgressionSessionData,
    padding1: [@sizeOf(ProgressionSessionData) * 12]u8,
    friday_day: ProgressionSessionData,
    qualifier_day_meetup: ?*anyopaque,
    force_in_world_start_marker: bool,
    qualifier_day: bool,

    const metadata_id: u32 = 0x14561456;
    pub fn isValid(self: *const ProgressionEventData) bool {
        if (self.int1 != 2) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }

    const max_days_data: usize = 14;
    pub fn daysData(self: *ProgressionEventData) []ProgressionSessionData {
        @setRuntimeSafety(false);
        const raw_list: [*]ProgressionSessionData = @ptrCast(&self.thursday_night);
        return raw_list[0..max_days_data];
    }
};

pub const EventProgressionAsset = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]u8,
    event_unlocks: ?*List(*ProgressionEventData),
    child_assets: ?*anyopaque,

    const metadata_id: u32 = 0x06110611;
    pub fn isValid(self: *const EventProgressionAsset) bool {
        if (self.int1 != 2) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

// ========== Race Vehicle Related ==========

pub const RaceVehiclePerformanceModificationItemData = extern struct {
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

pub const RaceVehiclePerformanceModifierData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    performance_modifications: ?*List(RaceVehiclePerformanceModificationItemData),
};

pub const RaceVehiclePerformanceUpgradeData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    performance_modifier_data: ?*RaceVehiclePerformanceModifierData,
};

pub const RaceVehicleChassisConfigData = extern struct {
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
    pub fn isValid(self: *const RaceVehicleChassisConfigData) bool {
        if (self.int1 != 2) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const RaceVehicleEngineConfigData = extern struct {
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
    pub fn isValid(self: *const RaceVehicleEngineConfigData) bool {
        if (self.int1 != 2 or self.int2 != 0x0005B100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const RaceVehicleEngineData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    engine_config: ?*RaceVehicleEngineConfigData,
    engine_upgrades: ?*RaceVehiclePerformanceUpgradeData,
    audio_blueprint_bundle_id: u32,

    const metadata_id: u32 = 0x05EA05EA;
    pub fn isValid(self: *const RaceVehicleEngineData) bool {
        if (self.int1 != 2) return false;
        if (self.metadata) |metadata| {
            return metadata.id == metadata_id;
        }
        return false;
    }
};

pub const RaceVehicleEngineUpgradesData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    engine_upgrades: ?*List(?*RaceVehicleEngineData),
};

pub const RaceVehicleConfigData = extern struct {
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
    pub fn isValid(self: *const RaceVehicleConfigData) bool {
        if (self.int1 != 2) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

// ========== Item Data Related ==========

pub const ItemDataId = extern struct {
    id: u32,
};

pub const FrameItemData = extern struct {
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

    const metadata_id: u32 = 0x04E404E4;
    pub fn isValid(self: *const FrameItemData) bool {
        if (self.int1 != 2) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const DriveTrainItemData = extern struct {
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

    const metadata_id: u32 = 0x04E004E0;
    pub fn isValid(self: *const DriveTrainItemData) bool {
        if (self.int1 != 2) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const EngineStructureItemData = extern struct {
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
    padding5: [0x48]u8,
    grade: u32,
    padding6: [0x30]u8,
    max_level_of_subitems: u32,
    engine_upgrade_index: u32,
    min_level_of_subitems: u32,

    const metadata_id: u32 = 0x04E304E3;
    pub fn isValid(self: *const EngineStructureItemData) bool {
        if (self.int1 != 2) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const RaceVehicleItemData = extern struct {
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
    pub fn isValid(self: *const RaceVehicleItemData) bool {
        if (self.int1 != 2) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

test "offsets" {
    try std.testing.expectEqual(0x18, @offsetOf(EventProgressionAsset, "asset_name"));
    try std.testing.expectEqual(0x20, @offsetOf(EventProgressionAsset, "event_unlocks"));
    try std.testing.expectEqual(0x28, @offsetOf(EventProgressionAsset, "child_assets"));

    try std.testing.expectEqual(0x90, @sizeOf(ProgressionSessionData));

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

    try std.testing.expectEqual(0x30, @offsetOf(FrameItemData, "subitems"));
    try std.testing.expectEqual(0x48, @offsetOf(FrameItemData, "sorted_scope"));
    try std.testing.expectEqual(0x78, @offsetOf(FrameItemData, "dynamic_marketplace_attribute_hashes"));

    try std.testing.expectEqual(0x30, @offsetOf(DriveTrainItemData, "subitems"));
    try std.testing.expectEqual(0x48, @offsetOf(DriveTrainItemData, "sorted_scope"));
    try std.testing.expectEqual(0x78, @offsetOf(DriveTrainItemData, "dynamic_marketplace_attribute_hashes"));

    try std.testing.expectEqual(0x30, @offsetOf(EngineStructureItemData, "subitems"));
    try std.testing.expectEqual(0x48, @offsetOf(EngineStructureItemData, "sorted_scope"));
    try std.testing.expectEqual(0xE8, @offsetOf(EngineStructureItemData, "ui_sort_index"));
    try std.testing.expectEqual(0x134, @offsetOf(EngineStructureItemData, "grade"));
    try std.testing.expectEqual(0x168, @offsetOf(EngineStructureItemData, "max_level_of_subitems"));
    try std.testing.expectEqual(0x16C, @offsetOf(EngineStructureItemData, "engine_upgrade_index"));
    try std.testing.expectEqual(0x170, @offsetOf(EngineStructureItemData, "min_level_of_subitems"));

    try std.testing.expectEqual(0x48, @offsetOf(RaceVehicleItemData, "sorted_scope"));
    try std.testing.expectEqual(0x5F, @offsetOf(RaceVehicleItemData, "purchaseable"));
    try std.testing.expectEqual(0xA0, @offsetOf(RaceVehicleItemData, "brand_data"));
    try std.testing.expectEqual(0xB8, @offsetOf(RaceVehicleItemData, "unlock_asset_mp"));
    try std.testing.expectEqual(0xF8, @offsetOf(RaceVehicleItemData, "race_vehicle"));
}
