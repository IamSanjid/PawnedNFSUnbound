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

fn resourceConstructHookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile (stack_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&onResourceConstruct),
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

fn resourceMetadataCheckHookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);

    asm volatile (stack_state_saver.save_call_hook_template
        :
        : [onHook] "X" (&onResourceMetadataCheck),
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

var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
const allocator = arena.allocator();

var scanner = ba.aob.Scanner.init(allocator);

/// Initializes the *UnlockAllItems* hook with the given detour context.
pub fn init(detour: *ba.Detour) !void {
    _ = arena.reset(.free_all);

    const module = try ba.windows.getModuleInfo(allocator, base_module);
    defer module.deinit(allocator);

    // NeedForSpeedUnbound.exe+220FA36 - 48 8B C8              - mov rcx,rax
    try hookTo(detour, module.start + 0x220FA36, @intFromPtr(&loadingSceneHookFn));
    // on resource constructor call,  resource->vtable[0](resource), vtable's first function
    try hookTo(detour, module.start + 0x25A1737, @intFromPtr(&resourceConstructHookFn));
    // NeedForSpeedUnbound.exe+2313424 - 48 8B 57 08           - mov rdx,[rdi+08]
    try hookTo(detour, module.start + 0x2313424, @intFromPtr(&resourceMetadataCheckHookFn));

    try unlock_vehicles.init();
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

/// Cleans up resources allocated by the *UnlockAllItems* hook
pub fn deinit() void {
    _ = arena.reset(.free_all);
    arena.deinit();
}

pub const hook_fn_end_signature = [_]u8{ 0x90, 0xCC } ** 8;
pub const name = "UnlockAllItems";
pub const base_module = "NeedForSpeedUnbound.exe";

const sdk = @import("nfs_unbound_sdk.zig");

var mutex: std.Thread.Mutex = .{};

fn startsWithIgnoreCaseAny(asset_name: []const u8, prefixes: []const []const u8) bool {
    for (prefixes) |prefix| {
        if (std.ascii.startsWithIgnoreCase(asset_name, prefix)) {
            return true;
        }
    }
    return false;
}

fn containsIgnoreCaseAny(asset_name: []const u8, contains: []const []const u8) bool {
    for (contains) |contain| {
        if (std.ascii.indexOfIgnoreCase(asset_name, contain)) |_| {
            return true;
        }
    }
    return false;
}

const unlock_vehicles = struct {
    const max_vehicles: u32 = 1000;
    var vehicles_list: *sdk.List(*sdk.RaceItemData.c) = undefined;
    var vehicles_set: std.AutoArrayHashMap(*sdk.RaceItemData.c, void) = undefined;

    const interested_asset_prefixes = [_][]const u8{
        "Items/Bike_",
        "items/copcars/",
        "Items/secondhand_vehicles/",
        "items/trafficcars/",
    };
    const interested_asset_contains = [_][]const u8{
        "PlayerCopCar_",
        "copcar_",
        "car_bmw_m3e46gtr_2003_razernfsmwdistressed",
        "car_tools_thumbnails_2022",
    };

    fn init() !void {
        vehicles_list = try .new(allocator, max_vehicles);
        vehicles_set = .init(allocator);
    }

    fn add(vehicle: anytype) !void {
        mutex.lock();
        defer mutex.unlock();

        const VehicleType = @TypeOf(vehicle);
        if (VehicleType == *sdk.RaceVehicleItemData.c or
            VehicleType == *sdk.PreCustomizedDealershipVehicleItemData.c)
        {
            try vehicles_set.put(@ptrCast(vehicle), {});
        } else if (VehicleType == *sdk.RaceItemData.c) {
            try vehicles_set.put(vehicle, {});
        } else @compileError("Unknown vehicle type: " ++ @typeName(VehicleType));

        vehicle.unlock_asset_mp_cop = null;
        vehicle.unlock_asset_sp = null;
        vehicle.unlock_asset_mp = null;
        vehicle.purchasable = true;
    }

    fn finalize() void {
        mutex.lock();
        defer mutex.unlock();

        removal: while (true) {
            const vehicles = vehicles_set.keys();
            for (0.., vehicles) |i, vehicle| {
                const raw_ptr = @intFromPtr(vehicle);
                if (raw_ptr == 0) {
                    std.debug.print(": Ptr 0? {}\n", .{i});
                    _ = vehicles_set.swapRemoveAt(i);
                    continue :removal;
                } else if (!sdk.ResourceObject.isValidObject(@ptrCast(vehicle))) {
                    _ = vehicles_set.swapRemoveAt(i);
                    continue :removal;
                }
            }

            break;
        }

        if (vehicles_set.count() == 0) return;

        // we expand since we should have enough space, then we copy
        const max_size: usize = @min(vehicles_set.count(), max_vehicles);
        vehicles_list.setSize(@truncate(max_size));
        vehicles_list.copySlice(vehicles_set.keys());
    }

    fn unlockDefaultVehicles(asset: *sdk.VehicleProgressionAsset.c) !void {
        const default_vehicles = asset.default_unlocked_vehicles.span();
        for (default_vehicles) |race_vehicle| {
            try add(race_vehicle);
        }

        const vehicles = asset.vehicles.span();
        for (vehicles) |*vehicle| {
            const unlocked_vehicles = vehicle.unlocked_vehicles.span();
            for (unlocked_vehicles) |race_vehicle| {
                try add(race_vehicle);
            }
            vehicle.unlock = null;
        }

        finalize();

        asset.default_unlocked_vehicles = vehicles_list;
        std.debug.print("UnlockAllItems: Unlocked {} vehicles of 0x{X}\n", .{
            asset.default_unlocked_vehicles.count(),
            @intFromPtr(asset),
        });
    }

    inline fn checkVehicleAssetName(item: anytype) bool {
        const asset_name = std.mem.span(item.asset_name);
        if (!startsWithIgnoreCaseAny(asset_name, &interested_asset_prefixes) and
            !containsIgnoreCaseAny(asset_name, &interested_asset_contains))
        {
            return false;
        }
        return true;
    }

    fn processResourceConstruct(regs: *GeneralRegisters) !void {
        if (sdk.VehicleProgressionAsset.from(regs.rsi)) |asset| {
            try unlockDefaultVehicles(asset);
            return;
        }
        if (sdk.VehicleProgressionAsset.from(regs.r15)) |asset| {
            try unlockDefaultVehicles(asset);
            return;
        }

        if (sdk.PreCustomizedDealershipVehicleItemData.from(regs.rsi)) |item| {
            if (!checkVehicleAssetName(item)) {
                return;
            }
            try add(item);
            return;
        }
        if (sdk.PreCustomizedDealershipVehicleItemData.from(regs.r15)) |item| {
            if (!checkVehicleAssetName(item)) {
                return;
            }
            try add(item);
            return;
        }

        if (sdk.RaceVehicleItemData.from(regs.rsi)) |item| {
            if (!checkVehicleAssetName(item)) {
                return;
            }
            try add(item);
            return;
        }
        if (sdk.RaceVehicleItemData.from(regs.r15)) |item| {
            if (!checkVehicleAssetName(item)) {
                return;
            }
            try add(item);
            return;
        }

        return error.NotValidObject;
    }

    fn processMetadataCheck(regs: *GeneralRegisters) !void {
        if (sdk.PreCustomizedDealershipVehicleItemData.from(regs.rdi)) |item| {
            try add(item);
            return;
        }

        if (sdk.RaceVehicleItemData.from(regs.rdi)) |item| {
            try add(item);
            return;
        }

        if (sdk.VehicleProgressionAsset.from(regs.rdi)) |asset| {
            try unlockDefaultVehicles(asset);
            return;
        }

        return error.NotValidObject;
    }
};

const unlock_visualitems = struct {
    const visualitem_types = [_]type{
        sdk.TrunkLidItemData,
        sdk.BumperItemData,
        sdk.DiffuserItemData,
        sdk.ExhaustItemData,
        sdk.FendersItemData,
        sdk.GrilleItemData,
        sdk.LightsItemData,
        sdk.HoodItemData,
        sdk.WingMirrorsItemData,
        sdk.RoofItemData,
        sdk.SideSkirtsItemData,
        sdk.SplitterItemData,
        sdk.SpoilerItemData,
        sdk.RimsItemData,
    };

    fn processResourceConstruct(regs: *GeneralRegisters) !void {
        inline for (visualitem_types) |VisualItemType| {
            if (VisualItemType.from(regs.rsi)) |item| {
                item.unlock_asset_mp_cop = null;
                item.unlock_asset_sp = null;
                item.unlock_asset_mp = null;
                item.purchasable = true;
                return;
            }
            if (VisualItemType.from(regs.r15)) |item| {
                item.unlock_asset_mp_cop = null;
                item.unlock_asset_sp = null;
                item.unlock_asset_mp = null;
                item.purchasable = true;
                return;
            }
        }

        return error.NotValidObject;
    }

    fn processMetadataCheck(regs: *GeneralRegisters) !void {
        inline for (visualitem_types) |VisualItemType| {
            if (VisualItemType.from(regs.rdi)) |item| {
                item.unlock_asset_mp_cop = null;
                item.unlock_asset_sp = null;
                item.unlock_asset_mp = null;
                item.purchasable = true;
                return;
            }
        }

        return error.NotValidObject;
    }
};

fn onLoadingScene(regs: *GeneralRegisters) callconv(.c) void {
    _ = regs;

    mutex.lock();
    defer mutex.unlock();

    _ = arena.reset(.free_all);

    unlock_vehicles.init() catch {};
}

fn onResourceConstruct(regs: *GeneralRegisters) callconv(.c) void {
    if (unlock_vehicles.processResourceConstruct(regs)) {
        return;
    } else |_| {}

    if (unlock_visualitems.processResourceConstruct(regs)) {
        return;
    } else |_| {}

    if (sdk.TemplateItemData.from(regs.rsi)) |item| {
        item.unlock_asset_mp_cop = null;
        item.unlock_asset_sp = null;
        item.unlock_asset_mp = null;
        item.purchasable = true;
        return;
    }
    if (sdk.TemplateItemData.from(regs.r15)) |item| {
        item.unlock_asset_mp_cop = null;
        item.unlock_asset_sp = null;
        item.unlock_asset_mp = null;
        item.purchasable = true;
        return;
    }
}

fn onResourceMetadataCheck(regs: *GeneralRegisters) callconv(.c) void {
    if (unlock_vehicles.processMetadataCheck(regs)) {
        return;
    } else |_| {}

    if (unlock_visualitems.processMetadataCheck(regs)) {
        return;
    } else |_| {}

    if (sdk.TemplateItemData.from(regs.rdi)) |item| {
        item.unlock_asset_mp_cop = null;
        item.unlock_asset_sp = null;
        item.unlock_asset_mp = null;
        item.purchasable = true;
        return;
    }
}
