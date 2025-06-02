const std = @import("std");

const GeneralRegisters = struct {
    rbx: usize = 0,
    rcx: usize = 0,
    rdx: usize = 0,
    rsi: usize = 0,
    rdi: usize = 0,
    rbp: usize = 0,
    rsp: usize = 0,
    r8: usize = 0,
    r9: usize = 0,
    r10: usize = 0,
    r11: usize = 0,
    r12: usize = 0,
    r13: usize = 0,
    r14: usize = 0,
    r15: usize = 0,
};

// registers state, why a pointer to the value? just for you know api consistency(rax.*, eax.*, ax.* etc..)
var rax_value: usize = 0; // going to use rax register as a base for all other registers
var registers: GeneralRegisters = .{};

const rax: *usize = &rax_value;
const eax: *u32 = @ptrCast(rax);
const ax: *u16 = @ptrCast(rax);
const ah: *u8 = &(@as([*]u8, @ptrCast(rax)))[1];
const al: *u8 = @ptrCast(rax);

const rbx: *usize = &registers.rbx;
const ebx: *u32 = @ptrCast(rbx);
const bx: *u16 = @ptrCast(rbx);
const bh: *u8 = &(@as([*]u8, @ptrCast(rbx)))[1];
const bl: *u8 = @ptrCast(rbx);

const rcx: *usize = &registers.rcx;
const ecx: *u32 = @ptrCast(rcx);
const cx: *u16 = @ptrCast(rcx);
const ch: *u8 = &(@as([*]u8, @ptrCast(rcx)))[1];
const cl: *u8 = @ptrCast(rcx);

const rdx: *usize = &registers.rdx;
const edx: *u32 = @ptrCast(rdx);
const dx: *u16 = @ptrCast(rdx);
const dh: *u8 = &(@as([*]u8, @ptrCast(rdx)))[1];
const dl: *u8 = @ptrCast(rdx);

const rsi: *usize = &registers.rsi;
const esi: *u32 = @ptrCast(rsi);
const si: *u16 = @ptrCast(rsi);
const sil: *u8 = @ptrCast(rsi);

const rdi: *usize = &registers.rdi;
const edi: *u32 = @ptrCast(rdi);
const di: *u16 = @ptrCast(rdi);
const dil: *u8 = @ptrCast(rdi);

const rbp: *usize = &registers.rbp;
const ebp: *u32 = @ptrCast(rbp);
const bp: *u16 = @ptrCast(rbp);
const bpl: *u8 = @ptrCast(rbp);

const rsp: *usize = &registers.rsp;
const esp: *u32 = @ptrCast(rsp);
const sp: *u16 = @ptrCast(rsp);
const spl: *u8 = @ptrCast(rsp);

const r8: *usize = &registers.r8;
const r8d: *u32 = @ptrCast(r8);
const r8w: *u16 = @ptrCast(r8);
const r8b: *u8 = @ptrCast(r8);

const r9: *usize = &registers.r9;
const r9d: *u32 = @ptrCast(r9);
const r9w: *u16 = @ptrCast(r9);
const r9b: *u8 = @ptrCast(r9);

const r10: *usize = &registers.r10;
const r10d: *u32 = @ptrCast(r10);
const r10w: *u16 = @ptrCast(r10);
const r10b: *u8 = @ptrCast(r10);

const r11: *usize = &registers.r11;
const r11d: *u32 = @ptrCast(r11);
const r11w: *u16 = @ptrCast(r11);
const r11b: *u8 = @ptrCast(r11);

const r12: *usize = &registers.r12;
const r12d: *u32 = @ptrCast(r12);
const r12w: *u16 = @ptrCast(r12);
const r12b: *u8 = @ptrCast(r12);

const r13: *usize = &registers.r13;
const r13d: *u32 = @ptrCast(r13);
const r13w: *u16 = @ptrCast(r13);
const r13b: *u8 = @ptrCast(r13);

const r14: *usize = &registers.r14;
const r14d: *u32 = @ptrCast(r14);
const r14w: *u16 = @ptrCast(r14);
const r14b: *u8 = @ptrCast(r14);

const r15: *usize = &registers.r15;
const r15d: *u32 = @ptrCast(r15);
const r15w: *u16 = @ptrCast(r15);
const r15b: *u8 = @ptrCast(r15);

const FloatRegister = @Vector(4, f32);
const FloatingRegisters = struct {
    xmm0: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm1: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm2: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm3: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm4: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm5: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm6: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm7: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm8: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm9: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm10: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm11: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm12: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm13: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm14: FloatRegister = std.mem.zeroes(FloatRegister),
    xmm15: FloatRegister = std.mem.zeroes(FloatRegister),
};
var float_registers: FloatingRegisters = .{};

const xmm0: *FloatRegister = &float_registers.xmm0;
const xmm1: *FloatRegister = &float_registers.xmm1;
const xmm2: *FloatRegister = &float_registers.xmm2;
const xmm3: *FloatRegister = &float_registers.xmm3;
const xmm4: *FloatRegister = &float_registers.xmm4;
const xmm5: *FloatRegister = &float_registers.xmm5;
const xmm6: *FloatRegister = &float_registers.xmm6;
const xmm7: *FloatRegister = &float_registers.xmm7;
const xmm8: *FloatRegister = &float_registers.xmm8;
const xmm9: *FloatRegister = &float_registers.xmm9;
const xmm10: *FloatRegister = &float_registers.xmm10;
const xmm11: *FloatRegister = &float_registers.xmm11;
const xmm12: *FloatRegister = &float_registers.xmm12;
const xmm13: *FloatRegister = &float_registers.xmm13;
const xmm14: *FloatRegister = &float_registers.xmm14;
const xmm15: *FloatRegister = &float_registers.xmm15;

pub fn hookFn() callconv(.naked) noreturn {
    @setRuntimeSafety(false);
    // saving state....
    // One day zig will get there, one day!
    asm volatile (
        \\
        : [_] "={rax}" (rax_value),
        :
        : "rax"
    );
    asm volatile (std.fmt.comptimePrint(
            \\ mov %%rbx, {}(%[general_base])
            \\ mov %%rcx, {}(%[general_base])
            \\ mov %%rdx, {}(%[general_base])
            \\ mov %%rsi, {}(%[general_base])
            \\ mov %%rdi, {}(%[general_base])
            \\ mov %%rbp, {}(%[general_base])
            \\ mov %%rsp, {}(%[general_base])
            \\ mov %%r8, {}(%[general_base])
            \\ mov %%r9, {}(%[general_base])
            \\ mov %%r10, {}(%[general_base])
            \\ mov %%r11, {}(%[general_base])
            \\ mov %%r12, {}(%[general_base])
            \\ mov %%r13, {}(%[general_base])
            \\ mov %%r14, {}(%[general_base])
            \\ mov %%r15, {}(%[general_base])
        , .{
            @offsetOf(GeneralRegisters, "rbx"),
            @offsetOf(GeneralRegisters, "rcx"),
            @offsetOf(GeneralRegisters, "rdx"),
            @offsetOf(GeneralRegisters, "rsi"),
            @offsetOf(GeneralRegisters, "rdi"),
            @offsetOf(GeneralRegisters, "rbp"),
            @offsetOf(GeneralRegisters, "rsp"),
            @offsetOf(GeneralRegisters, "r8"),
            @offsetOf(GeneralRegisters, "r9"),
            @offsetOf(GeneralRegisters, "r10"),
            @offsetOf(GeneralRegisters, "r11"),
            @offsetOf(GeneralRegisters, "r12"),
            @offsetOf(GeneralRegisters, "r13"),
            @offsetOf(GeneralRegisters, "r14"),
            @offsetOf(GeneralRegisters, "r15"),
        })
        :
        : [general_base] "{rax}" (&registers),
        : "rax", "memory"
    );
    asm volatile (std.fmt.comptimePrint(
            \\ movups %%xmm0, {}(%[float_base])
            \\ movups %%xmm1, {}(%[float_base])
            \\ movups %%xmm2, {}(%[float_base])
            \\ movups %%xmm3, {}(%[float_base])
            \\ movups %%xmm4, {}(%[float_base])
            \\ movups %%xmm5, {}(%[float_base])
            \\ movups %%xmm6, {}(%[float_base])
            \\ movups %%xmm7, {}(%[float_base])
            \\ movups %%xmm8, {}(%[float_base])
            \\ movups %%xmm9, {}(%[float_base])
            \\ movups %%xmm10, {}(%[float_base])
            \\ movups %%xmm11, {}(%[float_base])
            \\ movups %%xmm12, {}(%[float_base])
            \\ movups %%xmm13, {}(%[float_base])
            \\ movups %%xmm14, {}(%[float_base])
            \\ movups %%xmm15, {}(%[float_base])
        , .{
            @offsetOf(FloatingRegisters, "xmm0"),
            @offsetOf(FloatingRegisters, "xmm1"),
            @offsetOf(FloatingRegisters, "xmm2"),
            @offsetOf(FloatingRegisters, "xmm3"),
            @offsetOf(FloatingRegisters, "xmm4"),
            @offsetOf(FloatingRegisters, "xmm5"),
            @offsetOf(FloatingRegisters, "xmm6"),
            @offsetOf(FloatingRegisters, "xmm7"),
            @offsetOf(FloatingRegisters, "xmm8"),
            @offsetOf(FloatingRegisters, "xmm9"),
            @offsetOf(FloatingRegisters, "xmm10"),
            @offsetOf(FloatingRegisters, "xmm11"),
            @offsetOf(FloatingRegisters, "xmm12"),
            @offsetOf(FloatingRegisters, "xmm13"),
            @offsetOf(FloatingRegisters, "xmm14"),
            @offsetOf(FloatingRegisters, "xmm15"),
        })
        :
        : [float_base] "r" (&float_registers),
        : "memory"
    );

    // custom code
    asm volatile (
        \\ callq %[onHook:P]
        :
        : [onHook] "X" (&onHook),
        : "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp", "r8", "r9", "r10", "r11", "r12", "r13", "r14", "r15", "memory"
    );

    // restoring state...
    asm volatile (std.fmt.comptimePrint(
            \\ movups {}(%[float_base]), %%xmm0
            \\ movups {}(%[float_base]), %%xmm1
            \\ movups {}(%[float_base]), %%xmm2
            \\ movups {}(%[float_base]), %%xmm3
            \\ movups {}(%[float_base]), %%xmm4
            \\ movups {}(%[float_base]), %%xmm5
            \\ movups {}(%[float_base]), %%xmm6
            \\ movups {}(%[float_base]), %%xmm7
            \\ movups {}(%[float_base]), %%xmm8
            \\ movups {}(%[float_base]), %%xmm9
            \\ movups {}(%[float_base]), %%xmm10
            \\ movups {}(%[float_base]), %%xmm11
            \\ movups {}(%[float_base]), %%xmm12
            \\ movups {}(%[float_base]), %%xmm13
            \\ movups {}(%[float_base]), %%xmm14
            \\ movups {}(%[float_base]), %%xmm15
        , .{
            @offsetOf(FloatingRegisters, "xmm0"),
            @offsetOf(FloatingRegisters, "xmm1"),
            @offsetOf(FloatingRegisters, "xmm2"),
            @offsetOf(FloatingRegisters, "xmm3"),
            @offsetOf(FloatingRegisters, "xmm4"),
            @offsetOf(FloatingRegisters, "xmm5"),
            @offsetOf(FloatingRegisters, "xmm6"),
            @offsetOf(FloatingRegisters, "xmm7"),
            @offsetOf(FloatingRegisters, "xmm8"),
            @offsetOf(FloatingRegisters, "xmm9"),
            @offsetOf(FloatingRegisters, "xmm10"),
            @offsetOf(FloatingRegisters, "xmm11"),
            @offsetOf(FloatingRegisters, "xmm12"),
            @offsetOf(FloatingRegisters, "xmm13"),
            @offsetOf(FloatingRegisters, "xmm14"),
            @offsetOf(FloatingRegisters, "xmm15"),
        })
        :
        : [float_base] "r" (&float_registers),
        : "memory"
    );
    asm volatile (std.fmt.comptimePrint(
            \\ mov {}(%[general_base]), %%rbx
            \\ mov {}(%[general_base]), %%rcx
            \\ mov {}(%[general_base]), %%rdx
            \\ mov {}(%[general_base]), %%rsi
            \\ mov {}(%[general_base]), %%rdi
            \\ mov {}(%[general_base]), %%rbp
            \\ mov {}(%[general_base]), %%rsp
            \\ mov {}(%[general_base]), %%r8
            \\ mov {}(%[general_base]), %%r9
            \\ mov {}(%[general_base]), %%r10
            \\ mov {}(%[general_base]), %%r11
            \\ mov {}(%[general_base]), %%r12
            \\ mov {}(%[general_base]), %%r13
            \\ mov {}(%[general_base]), %%r14
            \\ mov {}(%[general_base]), %%r15
        , .{
            @offsetOf(GeneralRegisters, "rbx"),
            @offsetOf(GeneralRegisters, "rcx"),
            @offsetOf(GeneralRegisters, "rdx"),
            @offsetOf(GeneralRegisters, "rsi"),
            @offsetOf(GeneralRegisters, "rdi"),
            @offsetOf(GeneralRegisters, "rbp"),
            @offsetOf(GeneralRegisters, "rsp"),
            @offsetOf(GeneralRegisters, "r8"),
            @offsetOf(GeneralRegisters, "r9"),
            @offsetOf(GeneralRegisters, "r10"),
            @offsetOf(GeneralRegisters, "r11"),
            @offsetOf(GeneralRegisters, "r12"),
            @offsetOf(GeneralRegisters, "r13"),
            @offsetOf(GeneralRegisters, "r14"),
            @offsetOf(GeneralRegisters, "r15"),
        })
        :
        : [general_base] "{rax}" (&registers),
        : "memory"
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
        :
        : [_] "{rax}" (rax_value),
    );
}

pub const name = "AllRaceAvailable";

const AssetMetadata = extern struct {
    padding: [0x30]u8,
    id: u32,
};

const EventEconomyAsset = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: i32,
    int2: i32,
    asset_name: [*:0]u8,
    prize_money: *extern struct {
        ptr1: ?*anyopaque,
        ptr2: ?*anyopaque,
        size: u32,
        start: u32,

        const PrizeList = @This();
        fn asSlice(self: *PrizeList) []u32 {
            @setRuntimeSafety(false);
            const raw_list: [*]u32 = @ptrCast(&self.start);
            return raw_list[0..self.size];
        }
    },
    ptr1: ?*anyopaque,
    prize_money_start: ?[*]u32,
    buy_in: u32,

    const metadata_id: u32 = 0x06980698;
    fn isValid(self: *const EventEconomyAsset) bool {
        if (self.metadata) |some_data| {
            return some_data.id == metadata_id;
        }
        return false;
    }
};

const ProgressionSessionData = extern struct {
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

const ProgressionEventData = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: i32,
    int2: i32,
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
    fn isValid(self: *const ProgressionEventData) bool {
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }

    const max_days_data: usize = 14;
    fn daysData(self: *ProgressionEventData) []ProgressionSessionData {
        @setRuntimeSafety(false);
        const raw_list: [*]ProgressionSessionData = @ptrCast(&self.thursday_night);
        return raw_list[0..max_days_data];
    }
};

// NOTE: the padding is needed when the @sizeOf(type) >= 8?
const EventsUnlocksList = extern struct {
    ptr1: ?*anyopaque,
    ptr2: ?*anyopaque,
    padding1: u32,
    size: u32,
    start: ?*ProgressionEventData,

    fn asSlice(self: *EventsUnlocksList) []?*ProgressionEventData {
        @setRuntimeSafety(false);
        const raw_list: [*]?*ProgressionEventData = @ptrCast(&self.start);
        return raw_list[0..self.size];
    }
};

const EventProgressionAsset = extern struct {
    vtable: ?*anyopaque,
    metadata: ?*AssetMetadata,
    int1: i32,
    int2: i32,
    asset_name: [*:0]u8,
    event_unlocks_list_start: ?[*]ProgressionEventData,
    event_unlocks_list: ?*EventsUnlocksList,

    const metadata_id: u32 = 0x06110611;
    fn isValid(self: *const EventProgressionAsset) bool {
        if (self.metadata) |data| {
            return data.id == metadata_id;
        }
        return false;
    }

    fn hasEventUnlocksList(self: *const EventProgressionAsset) bool {
        const event_unlocks_list_start: usize = @intFromPtr(self.event_unlocks_list_start);
        const event_unlocks_list: usize = @intFromPtr(self.event_unlocks_list);
        return event_unlocks_list < event_unlocks_list_start; // otherwise it has "ChildAssets"
    }
};

const interested_guids = [_][]const u8{
    // gameplay/progression/ExcaliburCampaignEvents_Milestone_01: 2240d2dc-5606-4964-a831-d402ec3424e5
    &.{ 0xDC, 0xD2, 0x40, 0x22, 0x06, 0x56, 0x64, 0x49, 0xA8, 0x31, 0xD4, 0x02, 0xEC, 0x34, 0x24, 0xE5 },
};

const interested_assets = [_][]const u8{
    "gameplay/progression/ExcaliburCampaignEvents_Milestone_01",
    "gameplay/progression/ExcaliburCampaignEvents_Milestone_02",
    "gameplay/progression/ExcaliburCampaignEvents_Milestone_03",
    "gameplay/progression/ExcaliburCampaignEvents_Milestone_04",
};

fn onHook() callconv(.c) void {
    @setRuntimeSafety(false);
    const event_progression_asset: *EventProgressionAsset = @ptrFromInt(rdi.*);

    if (!event_progression_asset.isValid()) return;
    if (!event_progression_asset.hasEventUnlocksList()) return;

    //const guid: [*]const u8 = @alignCast(@as([*]const u8, @ptrFromInt(rdi.* - 0x10)));
    for (interested_assets) |interested| {
        // if (!std.mem.eql(u8, guid[0..16], interested_guid)) {
        //     // std.debug.print("AllRaceAvailable: mismatched 0x{X}:\n  possible_start: 0x{X}\n  event_unlocks_list: 0x{X}\n", .{
        //     //     rdi.*,
        //     //     @intFromPtr(event_progression_asset.possible_start),
        //     //     @intFromPtr(event_progression_asset.event_unlocks_list),
        //     // });
        //     continue;
        // }
        if (!std.ascii.eqlIgnoreCase(std.mem.span(event_progression_asset.asset_name), interested)) continue;
        std.debug.print("AllRaceAvailable: matched = 0x{X} - {s}\n - event unlocks list size: {d}\n", .{
            rdi.*,
            event_progression_asset.asset_name,
            event_progression_asset.event_unlocks_list.?.size,
        });
        const events = event_progression_asset.event_unlocks_list.?.asSlice();
        for (events) |evt| {
            const event = evt orelse continue;
            if (!event.isValid()) continue;
            //if (event.easy == null or event.normal == null or event.hard == null) continue;

            const days_data = event.daysData();
            // first find best economy asset
            var best_economy_asset: ?*EventEconomyAsset = null;
            var best_meetup: ?*anyopaque = null;
            var lowest_non_zero_wanted_gained: f32 = 0.0;
            for (days_data) |*day| {
                const economy = day.economy_asset orelse continue;
                const meetup = day.meetup orelse continue;
                if (!economy.isValid()) continue;

                if (day.wanted_level_increase > 0.0 and day.wanted_level_increase < lowest_non_zero_wanted_gained) {
                    lowest_non_zero_wanted_gained = day.wanted_level_increase;
                }

                if (best_economy_asset) |best| {
                    if (economy.buy_in < best.buy_in) {
                        best_economy_asset = economy;
                        best_meetup = meetup;
                    } else if (best.prize_money.start > economy.prize_money.start) {
                        best_economy_asset = economy;
                        best_meetup = meetup;
                    }
                } else {
                    best_economy_asset = economy;
                    best_meetup = meetup;
                }
            }

            // set the best economy asset to the event progression asset
            for (days_data) |*day| {
                if (day.economy_asset != null and day.meetup != null) continue;
                day.economy_asset = best_economy_asset;
                day.meetup = best_meetup;
                day.is_available = true;
                day.wanted_level_increase = lowest_non_zero_wanted_gained;
            }
        }
    }
}

test "offsets" {
    try std.testing.expectEqual(0x18, @offsetOf(EventProgressionAsset, "asset_name"));
    try std.testing.expectEqual(0x20, @offsetOf(EventProgressionAsset, "possible_start"));
    try std.testing.expectEqual(0x28, @offsetOf(EventProgressionAsset, "event_unlocks_list"));

    try std.testing.expectEqual(0x14, @offsetOf(EventsUnlocksList, "size"));
    try std.testing.expectEqual(0x18, @offsetOf(EventsUnlocksList, "start"));

    try std.testing.expectEqual(0x90, @sizeOf(ProgressionSessionData));
}
