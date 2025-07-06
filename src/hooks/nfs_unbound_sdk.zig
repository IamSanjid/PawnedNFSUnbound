const std = @import("std");

// it should be fine but can be increased if needed, the main purpose is to prevent reading undefined memory
const max_ref_count: u32 = 10;

// ========== General ==========

pub const Metadata = extern struct {
    padding: [0x30]u8,
    id: u32,
};

pub const ResourceObject = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
    int2: u32,

    pub inline fn isValid(self: *const ResourceObject) bool {
        return self.ref_count > 0 and
            self.ref_count <= max_ref_count and
            self.int2 & 0xB100 == 0xB100;
    }
};

pub const DataContainerAssetPolicy = WithInheritance(&.{ResourceObject}, extern struct {
    asset_name: [*:0]const u8,
}, 0x00);

pub const Guid = [16]u8;

pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Vec3WithPadding = WithEndPadding(Vec3, 0x4);

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
            const start_ptr: [*]T = @ptrCast(&self.start);
            return start_ptr[index];
        }

        pub fn span(self: *Self) []T {
            const list_size = self.count();
            if (list_size == 0) return &.{};
            const start_ptr: [*]T = @ptrCast(&self.start);
            return start_ptr[0..list_size];
        }

        pub fn readonlySpan(self: *const Self) []const T {
            const list_size = self.count();
            if (list_size == 0) return &.{};
            const start_ptr: [*]const T = @ptrCast(&self.start);
            return start_ptr[0..list_size];
        }

        pub fn copySlice(self: *Self, slice: []const T) void {
            std.debug.assert(slice.len <= self.count());
            const dst = self.span()[0..slice.len];
            @memcpy(dst, slice.ptr);
        }

        pub fn setSize(self: *Self, new_size: u32) void {
            @setRuntimeSafety(false);
            const size_ptr: *u32 = @ptrFromInt(@intFromPtr(self) - @sizeOf(u32));
            size_ptr.* = new_size;
        }

        pub fn dupeWithExtra(self: *const Self, allocator: std.mem.Allocator, extra: usize) !*Self {
            const new_size = @as(u32, @truncate(self.count())) + @as(u32, @truncate(extra));
            const new_list = try Self.new(allocator, new_size);
            @memcpy(new_list.span(), self.readonlySpan().ptr);
            return new_list;
        }

        pub fn new(allocator: std.mem.Allocator, size: u32) !*Self {
            @setRuntimeSafety(false);
            const total_size = @sizeOf(u32) + @sizeOf(T) * size;
            const raw = try allocator.alignedAlloc(u8, .of(T), total_size);
            const size_ptr: *u32 = @ptrFromInt(@intFromPtr(raw.ptr));
            size_ptr.* = size;
            return @ptrFromInt(@intFromPtr(raw.ptr) + @sizeOf(u32));
        }
    };
}

pub fn isListType(comptime T: type) bool {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct" or !@hasDecl(T, "ChildType")) return false;
    if (T != List(T.ChildType)) return false;
    return true;
}

// ========== Event/Progression/Campaign/Freedrive Related ==========

pub const Tier = enum(c_uint) {
    d = 0,
    c = 1,
    b = 2,
    a = 3,
    s = 4,
    count = 5,
    invalid = std.math.maxInt(c_uint),
};

pub const EventEconomyAsset = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
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

pub const CalendarAvailability = extern struct {
    thursday_night: ProgressionSessionData,
    friday_night: ProgressionSessionData,
    sunday_night: ProgressionSessionData,
    sunday_day: ProgressionSessionData,
    thursday_day: ProgressionSessionData,
    tuesday_day: ProgressionSessionData,
    wednesday_night: ProgressionSessionData,
    wednesday_day: ProgressionSessionData,
    monday_day: ProgressionSessionData,
    saturday_night: ProgressionSessionData,
    saturday_day: ProgressionSessionData,
    monday_night: ProgressionSessionData,
    tuesday_night: ProgressionSessionData,
    friday_day: ProgressionSessionData,
    qualifier_day_meetup: ?*anyopaque,
    force_in_world_start_marker: bool,
    qualifier_day: bool,

    const max_session_data_count: usize = 14;
    pub fn sessionDataSlice(self: *CalendarAvailability) []ProgressionSessionData {
        @setRuntimeSafety(false);
        const slice: [*]ProgressionSessionData = @ptrCast(&self.thursday_night);
        return slice[0..max_session_data_count];
    }
};

pub const ProgressionEventData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
    int2: u32,
    hard: ?*anyopaque,
    easy: ?*anyopaque,
    normal: ?*anyopaque,
    calendar_availability: CalendarAvailability,
    playlist: ?*anyopaque,
    gifted_items: ?*anyopaque,
    phone_call_settings: ?*anyopaque,
    xp_reward_asset: ?*anyopaque,
    unlock_playable: ?*anyopaque,
    on_fail_unlocks: ?*anyopaque,
    game_mode: ?*anyopaque,
    gifted_vehicle_list: ?*anyopaque,
    unlock_lists: ?*anyopaque,
    phone_call_rival_override: ?*anyopaque,
    unlock_unavailable: ?*anyopaque,
    unlock_visible: ?*anyopaque,
    dynamic_event_settings: ?*anyopaque,
    voice_over_asset: ?*anyopaque,
    rivals_override: ?*anyopaque,
    tier: Tier,
    rival_template_override_tag_id: i32,
    is_permanent_for_session: bool,
    phone_call_rival_is_overridden: bool,
    is_new: bool,
    is_debug: bool,

    const metadata_id: u32 = 0x14561456;
    pub fn isValid(self: *const ProgressionEventData) bool {
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const EventProgressionAsset = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
    int2: u32,
    asset_name: [*:0]u8,
    event_unlocks: ?*List(*ProgressionEventData),
    child_assets: ?*anyopaque,

    const metadata_id: u32 = 0x06110611;
    pub fn isValid(self: *const EventProgressionAsset) bool {
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const UnlockAsset = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    debug_unlock_id: [*:0]const u8,
    available_for_player: enum(c_uint) {
        all = 0,
        human_player_only = 1,
        ai_only = 2,
    },
    identifier: u32,

    const metadata_id: u32 = 0x05A0059F;
    pub fn isValid(self: *const UnlockAsset) bool {
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const VehicleProgressionData = extern struct {
    unlock: ?*UnlockAsset,
    unlocked_vehicles: *List(*RaceItemData.c),
};

pub const VehicleProgressionAsset = WithInheritance(&.{DataContainerAssetPolicy.c}, extern struct {
    default_unlocked_vehicles: *List(*RaceItemData.c),
    vehicles: *List(VehicleProgressionData),
}, 0x05630563);

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
    metadata: ?*Metadata,
    ref_count: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    performance_modifications: ?*List(RaceVehiclePerformanceModificationItemData),
};

pub const RaceVehiclePerformanceUpgradeData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    performance_modifier_data: ?*RaceVehiclePerformanceModifierData,
};

pub const RaceVehicleChassisConfigData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
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
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const RaceVehicleEngineConfigData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
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
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const RaceVehicleEngineData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    engine_config: ?*RaceVehicleEngineConfigData,
    engine_upgrades: ?*RaceVehiclePerformanceUpgradeData,
    audio_blueprint_bundle_id: u32,

    const metadata_id: u32 = 0x05EA05EA;
    pub fn isValid(self: *const RaceVehicleEngineData) bool {
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.metadata) |metadata| {
            return metadata.id == metadata_id;
        }
        return false;
    }
};

pub const RaceVehicleEngineUpgradesData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
    int2: u32,
    asset_name: [*:0]const u8,
    engine_upgrades: ?*List(?*RaceVehicleEngineData),
};

pub const RaceVehicleConfigData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
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
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

// ========== Item Data Related ==========

pub const MarketplaceItemType = enum(c_uint) {
    stackable = 0,
    individual = 1,
    count = 2,
};

pub const ItemGarage = enum(c_uint) {
    racer = 0,
    cop = 1,
    count = 2,
};

pub const ItemRarity = enum(c_uint) {
    none = 0,
    common = 1,
    rare = 2,
    epic = 3,
    legendary = 4,
};

pub const ArchetypeData = enum(c_uint) {
    none = 0,
    racer = 1,
    drift = 2,
    gymkhana = 3,
    offroad = 4,
    drag = 5,
    sleeper = 6,
};

pub const ItemLocation = enum(c_uint) {
    front = 0,
    rear = 1,
    none = 2,
};

pub const NFSAttachedCustomizationType = enum(c_int) {
    gesture = 1147168681,
    charm = 1555285787,
    emote = 1557700216,
    signatureStyleVFX = -1466887083,
    idle = -1124296246,
    @"test" = -1123537064,
    pose = -1123408569,
    invalid = -1,
};

pub const ItemDataId = extern struct {
    id: u32,
};

pub const FrameItemData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
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
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const DriveTrainItemData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
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
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const EngineStructureItemData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*Metadata,
    ref_count: u32,
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
        if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
        if (self.int2 & 0xB100 != 0xB100) return false;
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }
};

pub const ItemDataBase = WithInheritance(&.{DataContainerAssetPolicy.c}, extern struct {
    item_ui: ?*anyopaque,
    id: u32,
    deprecated: bool,
}, 0x00);

pub const GstItemData = WithInheritance(&.{ItemDataBase.c}, extern struct {
    subitems: ?*anyopaque,
    additional_items: ?*anyopaque,
    sorted_restrictions: ?*anyopaque,
    sorted_scope: ?*List(ItemDataId),
    buy_price: i32,
    quantity: i32,
    sell_price: i32,
    sellable: bool,
    optional: bool,
    is_consumable: bool,
    purchasable: bool,
}, 0x00);

pub const MarketplaceMetaData = extern struct {
    quantity_limit: u64,
    item_type: MarketplaceItemType,
    export_to_marketplace: bool,
    item_type_overrideable: bool,
    grantable: bool,
    quantity_limit_overridable: bool,
    consumable: bool,
};
pub const MarketplaceItemData = WithInheritance(&.{GstItemData.c}, extern struct {
    marketplace_meta_data: MarketplaceMetaData,
    dynamic_marketplace_attribute_hashes: ?*anyopaque,
}, 0x00);

pub const NFSItemTags = extern struct {
    tags: ?*anyopaque,
    tags_id: ?*anyopaque,
    has_been_built: bool,
};
pub const NFSItemData = WithInheritance(&.{MarketplaceItemData.c}, extern struct {
    categorization_tags: NFSItemTags,
    unlock_asset_mp_cop: ?*anyopaque,
    brand_data: ?*anyopaque,
    unlock_asset_sp: ?*anyopaque,
    licensed_by: ?*anyopaque,
    unlock_asset_mp: ?*anyopaque,
    allowed_garages: u32,
    awarded_garage: ItemGarage,
    user_award_flags: i32,
    rarity: ItemRarity,
    use_mp_cop_unlock_asset: bool,
    enable_item_scope_check_filter: bool,
    is_mp: bool,
}, 0x00);

pub const RaceItemData = WithInheritance(&.{NFSItemData.c}, extern struct {
    hidden_from_purchase_by_unlock: ?*anyopaque,
    item_tags: ?*anyopaque,
    ui_sort_index: u32,
    super_archetype_exclusive_type: ArchetypeData,
    allow_item_type_duplicates: bool,
}, 0x00);

pub const GstControllableItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    race_vehicle: ?*anyopaque,
    interaction_point_data: ?*anyopaque,
    category_items_count: ?*anyopaque,
    is_loaner_car: bool,
}, 0x00);

pub const RaceVehicleItemData = WithInheritance(&.{GstControllableItemData.c}, extern struct {
    padding7: [0x44]u8,
    default_license_plate_text: [*:0]const u8,
}, 0x04C804C8);

pub const PreCustomizedDealershipVehicleItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    base_vehicle: ?*RaceVehicleItemData.c,
    customizations: ?*anyopaque,
    post_customizations: ?*anyopaque,
    max_hp: i32,
    quarter_mile_time: f32,
    max_torque: i32,
    quarter_mile_mph: i32,
    performance_tier: f32,
    hundred_to_two_hundred: f32,
    top_speed_mph: i32,
    zero_to_sixty: f32,
}, 0x05360536);

pub const TemplateItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    types_to_remove: ?*anyopaque,
    property_modifications: ?*anyopaque,
}, 0x0540053D);

pub const CustomizationItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    performance_modifier: ?*anyopaque,
    mesh_blueprint_permutations: ?*anyopaque,
    performance_modifier_index: u32,
    uses_item_constraints: bool,
    is_player_facing: bool,
    wide_collision: bool,
}, 0x00);

pub const VisualCustomizationItemData = WithInheritance(&.{CustomizationItemData.c}, extern struct {}, 0x00);

pub const SpatialCustomizationItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {
    location: ItemLocation,
}, 0x00);

pub const TrunkLidItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {}, 0x05290529);

pub const BumperItemData = WithInheritance(&.{SpatialCustomizationItemData.c}, extern struct {}, 0x05110511);

pub const DiffuserItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {}, 0x05180518);

pub const ExhaustItemAudioData = extern struct {
    exhaust_tip_length: i32,
    exhaust_tip_girth: i32,
};

pub const ExhaustItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {
    audio: ExhaustItemAudioData,
}, 0x05150515);

pub const FendersItemData = WithInheritance(&.{SpatialCustomizationItemData.c}, extern struct {
    inner_diameter_override: f32,
    wheel_diameter_override: f32,
    max_trackwidth: f32,
    rim_width: f32,
    max_body_y_offset: f32,
    override_rim_width: bool,
}, 0x05140514);

pub const GrilleItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {}, 0x05260526);

pub const LightsItemData = WithInheritance(&.{SpatialCustomizationItemData.c}, extern struct {
    light_set_id: u32,
    animation_extent: f32,
    tint: Vec3,
    light_color: Vec3,
    use_custom_light_color: bool,
}, 0x050F050F);

pub const HoodItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {}, 0x05220522);

pub const WingMirrorsItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {}, 0x05200520);

pub const RoofItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {}, 0x051F051F);

pub const SideSkirtsItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {}, 0x05230523);

pub const SplitterItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {}, 0x05190519);

pub const SpoilerItemData = WithInheritance(&.{VisualCustomizationItemData.c}, extern struct {
    spoiler_tuning: ?*anyopaque,
    animation_id: i32,
    global_asset_list_index: u32,
    animation_extent: f32,
}, 0x05250525);

pub const RimsItemData = WithInheritance(&.{SpatialCustomizationItemData.c}, extern struct {
    size_options: ?*List(f32),
    secondary_material: Vec3,
    secondary_paint: Vec3,
    primary_material: Vec3,
    primary_paint: Vec3,
    brake_disc_x_offset: f32,
    diameter: f32,
    rim_selection: u32,
    radial_blur_thickness: f32,
    lip_size: f32,
    width: f32,
    brake_disc_ratio: f32,
    double_sided_radial_blur: bool,
    allow_width_override: bool,
}, 0x050D050D);

pub const NFSControllableItemData = WithInheritance(&.{NFSItemData.c}, extern struct {
    controllable_type: ?*anyopaque,
    customisation_items: ?*anyopaque,
}, 0x00);

pub const NFSCharacterItemData = WithInheritance(&.{NFSControllableItemData.c}, extern struct {
    voice_id: i32,
    pronoun: i32,
    voice_pitch: f32,
    can_customize: bool,
}, 0x05530553);

pub const BannerArtItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    border_texture: ?*anyopaque,
    background_color: Vec3,
    fullscreen_texture: ?*anyopaque,
    player_tag_texture: ?*anyopaque,
}, 0x05470547);

pub const BannerAudioItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    sound_patch_config_guid: Guid,
}, 0x05440544);

pub const BannerPoseItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    pose_index: i32,
}, 0x054C054C);

pub const StaticBannerCustomizationItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    sticker_texture: ?*anyopaque,
    snapshot_texture: ?*anyopaque,
}, 0x04C404C4);

pub const BannerTitleItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    localized_title: [*:0]const u8,
    background_texture: ?*anyopaque,
}, 0x04C504C5);

pub const BannerTraitItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    slot: i32,
}, 0x04C604C6);

pub const NFSCustomizationItemData = WithInheritance(&.{NFSItemData.c}, extern struct {
    tags: NFSItemTags,
    slots: ?*anyopaque,
}, 0x00);

pub const NFSAttachedCustomizationItemData = WithInheritance(&.{NFSCustomizationItemData.c}, extern struct {
    customization_properties: ?*anyopaque,
    customization_type: NFSAttachedCustomizationType,
    audio_signature_style_pack_value: i32,
    bundle_id: u32,
}, 0x05560556);

pub const LiveryDecalSwatchPackItemData = WithInheritance(&.{RaceItemData.c}, extern struct {
    decal_swatch_pack: ?*anyopaque,
    badge_type: i32,
    first_swatch_index: u32,
    num_swatches: i32,
    show_unused_swatches: bool,
    show_when_locked: bool,
}, 0x053B053B);

// pub const RaceVehicleItemData = extern struct {
//     vtable: ?*anyopaque,
//     metadata: ?*AssetMetadata,
//     ref_count: u32,
//     int2: u32,
//     asset_name: [*:0]const u8,
//     // ItemDataBase
//     item_ui: ?*anyopaque,
//     id: u32,
//     deprecated: bool,
//     // padding: [3]u8,
//     // GstItemData
//     subitems: ?*anyopaque,
//     additional_items: ?*anyopaque,
//     sorted_restrictions: ?*anyopaque,
//     sorted_scope: ?*List(ItemDataId),
//     buy_price: i32,
//     quantity: i32,
//     sell_price: i32,
//     sellable: bool,
//     optional: bool,
//     is_consumable: bool,
//     purchasable: bool,
//     // MarketplaceItemData
//     marketplace_meta_data: MarketplaceMetaData,
//     dynamic_marketplace_attribute_hashes: ?*anyopaque,
//     // NFSItemData
//     categorization_tags: NFSItemTags,
//     unlock_asset_mp_cop: ?*anyopaque,
//     brand_data: ?*anyopaque,
//     unlock_asset_sp: ?*anyopaque,
//     licensed_by: ?*anyopaque,
//     unlock_asset_mp: ?*anyopaque,
//     allowed_garages: u32,
//     awarded_garage: ItemGarage,
//     user_award_flags: i32,
//     rarity: ItemRarity,
//     use_mp_cop_unlock_asset: bool,
//     enable_item_scope_check_filter: bool,
//     is_mp: bool,
//     // RaceItemData
//     hidden_from_purchase_by_unlock: ?*anyopaque,
//     item_tags: ?*anyopaque,
//     ui_sort_index: u32,
//     super_archetype_exclusive_type: ArchetypeData,
//     allow_item_type_duplicates: bool,
//     // GstControllableItemData
//     race_vehicle: ?*anyopaque,
//     interaction_point_data: ?*anyopaque,
//     category_items_count: ?*anyopaque,
//     is_loaner_car: bool,
//     // padding: [0x3]u8,
//     padding7: [0x44]u8,
//     default_license_plate_text: [*:0]const u8,

//     const metadata_id: u32 = 0x04C804C8;
//     pub fn isValid(self: *const RaceVehicleItemData) bool {
//         if (self.ref_count == 0 or self.ref_count > max_ref_count) return false;
//         if (self.int2 & 0xB100 != 0xB100) return false;
//         if (self.metadata) |data| {
//             return data.id == metadata_id;
//         }
//         return false;
//     }
// };

// Utils

fn WithEndPadding(comptime T: type, comptime padding_size: usize) type {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct" or type_info.@"struct".is_tuple or type_info.@"struct".layout != .@"extern") {
        @compileError("Expected a extern struct type found: " ++ @typeName(T));
    }
    var fields: [type_info.@"struct".fields.len + 1]std.builtin.Type.StructField = undefined;
    var offset: usize = 0;
    for (type_info.@"struct".fields) |field| {
        fields[offset] = field;
        offset += 1;
    }
    fields[offset] = std.builtin.Type.StructField{
        .name = "padding",
        .type = [padding_size]u8,
        .alignment = @alignOf([padding_size]u8),
        .default_value_ptr = null,
        .is_comptime = false,
    };
    return @Type(std.builtin.Type{
        .@"struct" = .{
            .layout = .@"extern",
            .decls = &.{},
            .fields = &fields,
            .is_tuple = false,
        },
    });
}

fn counFields(comptime Ts: []const type) usize {
    var count: usize = 0;
    for (Ts) |T| {
        const type_info = @typeInfo(T);
        if (type_info == .@"struct" and
            !type_info.@"struct".is_tuple and
            type_info.@"struct".layout == .@"extern")
        {
            count += type_info.@"struct".fields.len;
        } else {
            @compileError("Expected a extern struct type found: " ++ @typeName(T));
        }
    }
    return count;
}

fn comptimeAddElement(comptime T: type, comptime arr: []const T, comptime element: T) [arr.len + 1]T {
    var result: [arr.len + 1]T = undefined;
    for (arr, 0..) |item, i| {
        result[i] = item;
    }
    result[arr.len] = element;
    return result;
}

fn WithInheritance(comptime parents: []const type, comptime T: type, comptime m_id: u32) type {
    var fields: [counFields(&comptimeAddElement(type, parents, T))]std.builtin.Type.StructField = undefined;
    var offset: usize = 0;
    for (parents) |parent| {
        const type_info = @typeInfo(parent);
        if (type_info == .@"struct" and
            !type_info.@"struct".is_tuple and
            type_info.@"struct".layout == .@"extern")
        {
            for (type_info.@"struct".fields) |field| {
                fields[offset] = field;
                offset += 1;
            }
        } else {
            @compileError("Expected a extern struct type found: " ++ @typeName(parent));
        }
    }
    const type_info = @typeInfo(T);
    if (type_info == .@"struct" and
        !type_info.@"struct".is_tuple and
        type_info.@"struct".layout == .@"extern")
    {
        for (type_info.@"struct".fields) |field| {
            fields[offset] = field;
            offset += 1;
        }
    } else {
        @compileError("Expected a extern struct type found: " ++ @typeName(T));
    }
    const NativeType = @Type(std.builtin.Type{
        .@"struct" = .{
            .layout = .@"extern",
            .decls = &.{},
            .fields = &fields,
            .is_tuple = false,
        },
    });
    const inherited_resource_object = @hasField(NativeType, "vtable") and
        @hasField(NativeType, "metadata") and
        @hasField(NativeType, "ref_count") and
        @hasField(NativeType, "int2");
    if (!inherited_resource_object) {
        return struct {
            pub const metadata_id: u32 = m_id;
            pub const c = NativeType;
            pub fn isValid(self: *const c) bool {
                _ = self;
                return true;
            }
            pub inline fn from(ptr: usize) ?*c {
                const c_ptr: ?*c = @ptrFromInt(ptr);
                return c_ptr;
            }
        };
    } else {
        return struct {
            pub const metadata_id: u32 = m_id;
            pub const c = NativeType;
            pub fn isValid(self: *const c) bool {
                if (!ResourceObject.isValid(@ptrCast(self))) return false;
                if (self.metadata) |metadata| {
                    return metadata.id == metadata_id;
                }
                return false;
            }
            pub inline fn from(ptr: usize) ?*c {
                const c_opt_ptr: ?*c = @ptrFromInt(ptr);
                const c_ptr = c_opt_ptr orelse return null;
                if (!isValid(c_ptr)) return null;
                return c_ptr;
            }
        };
    }
}

test "offsets" {
    try std.testing.expectEqual(0x18, @offsetOf(EventProgressionAsset, "asset_name"));
    try std.testing.expectEqual(0x20, @offsetOf(EventProgressionAsset, "event_unlocks"));
    try std.testing.expectEqual(0x28, @offsetOf(EventProgressionAsset, "child_assets"));

    try std.testing.expectEqual(0x90, @sizeOf(ProgressionSessionData));

    // try std.testing.expectEqual(0x810, @offsetOf(ProgressionEventData, "qualifier_day_meetup"));
    try std.testing.expectEqual(0x890, @offsetOf(ProgressionEventData, "rivals_override"));
    try std.testing.expectEqual(0x89C, @offsetOf(ProgressionEventData, "rival_template_override_tag_id"));
    try std.testing.expectEqual(0x8A3, @offsetOf(ProgressionEventData, "is_debug"));

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

    // try std.testing.expectEqual(0x48, @offsetOf(RaceVehicleItemData, "sorted_scope"));
    // try std.testing.expectEqual(0x5F, @offsetOf(RaceVehicleItemData, "purchasable"));
    // try std.testing.expectEqual(0x78, @offsetOf(RaceVehicleItemData, "dynamic_marketplace_attribute_hashes"));
    // try std.testing.expectEqual(0xA0, @offsetOf(RaceVehicleItemData, "brand_data"));
    // try std.testing.expectEqual(0xB8, @offsetOf(RaceVehicleItemData, "unlock_asset_mp"));
    // try std.testing.expectEqual(0xF8, @offsetOf(RaceVehicleItemData, "race_vehicle"));
    // try std.testing.expectEqual(0x158, @offsetOf(RaceVehicleItemData, "default_license_plate_text"));

    try std.testing.expectEqual(0x48, @offsetOf(RaceVehicleItemData.c, "sorted_scope"));
    try std.testing.expectEqual(0x5F, @offsetOf(RaceVehicleItemData.c, "purchasable"));
    try std.testing.expectEqual(0x78, @offsetOf(RaceVehicleItemData.c, "dynamic_marketplace_attribute_hashes"));
    try std.testing.expectEqual(0xA0, @offsetOf(RaceVehicleItemData.c, "brand_data"));
    try std.testing.expectEqual(0xB8, @offsetOf(RaceVehicleItemData.c, "unlock_asset_mp"));
    try std.testing.expectEqual(0xF8, @offsetOf(RaceVehicleItemData.c, "race_vehicle"));
    try std.testing.expectEqual(0x158, @offsetOf(RaceVehicleItemData.c, "default_license_plate_text"));
}
