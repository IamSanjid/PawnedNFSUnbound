const std = @import("std");

const assert = std.debug.assert;

const Allocator = std.mem.Allocator;

fn bitsMaxInt(bit_count: usize) usize {
    if (bit_count == 0) return 0;
    return (1 << bit_count) - 1;
}

pub const Pattern = struct {
    bytes: []u8,
    mask: []u8,
    allocator: std.mem.Allocator,

    const Compiled = struct {
        byte: u8,
        mask: u8,
    };

    const full_wildcard_mask: u8 = 0x00;

    pub const Base = enum(u8) {
        const max_ascii_lens = [_]usize{
            @as(usize, @intFromFloat(@ceil(@log(@as(f64, std.math.maxInt(u8)) + 1) / @log(2.0)))),
            @as(usize, @intFromFloat(@ceil(@log(@as(f64, std.math.maxInt(u8)) + 1) / @log(8.0)))),
            @as(usize, @intFromFloat(@ceil(@log(@as(f64, std.math.maxInt(u8)) + 1) / @log(10.0)))),
            @as(usize, @intFromFloat(@ceil(@log(@as(f64, std.math.maxInt(u8)) + 1) / @log(16.0)))),
            // auto = max possible len
            @as(usize, @intFromFloat(@ceil(@log(@as(f64, std.math.maxInt(u8)) + 1) / @log(10.0)))),
        };
        const bit_shifts = [_]u3{
            @as(u3, @intFromFloat(@floor(@log2(2.0)))),
            @as(u3, @intFromFloat(@floor(@log2(8.0)))),
            @as(u3, @intFromFloat(@floor(@log2(10.0)))),
            @as(u3, @intFromFloat(@floor(@log2(16.0)))),
            @as(u3, @intFromFloat(@floor(@log2(10.0)))),
        };
        const lower_masks = [_]u8{
            @as(u8, @truncate(bitsMaxInt(bit_shifts[0]))),
            @as(u8, @truncate(bitsMaxInt(bit_shifts[1]))),
            @as(u8, @truncate(bitsMaxInt(bit_shifts[2]))),
            @as(u8, @truncate(bitsMaxInt(bit_shifts[3]))),
            @as(u8, @truncate(bitsMaxInt(bit_shifts[4]))),
        };
        const prefixes = [_][]const u8{ "0b", "0o", "", "0x", "" };
        const int_bases = [_]u8{ 2, 8, 10, 16, 10 };
        @"2" = 0,
        @"8" = 1,
        @"10" = 2,
        @"16" = 3,
        auto = 4,

        fn getMaxAciiLen(self: Base) usize {
            std.debug.assert(self != .auto); // should call .detect first
            return max_ascii_lens[@intFromEnum(self)];
        }

        fn getIntBase(self: Base) u8 {
            std.debug.assert(self != .auto); // should call .detect first
            return int_bases[@intFromEnum(self)];
        }

        fn detect(buf: []const u8) Base {
            for (prefixes, 0..) |prefix, i| {
                if (prefix.len == 0) continue;
                if (!std.mem.startsWith(u8, buf, prefix)) continue;
                return @enumFromInt(i);
            }

            return .@"10";
        }

        fn trimPrefix(self: Base, buf: []const u8) []const u8 {
            var base = self;
            if (base == .auto) base = Base.detect(buf);

            const prefix = switch (base) {
                .@"10", .auto => return buf,
                else => prefixes[@intFromEnum(base)],
            };

            var res = buf;
            var split = std.mem.splitSequence(u8, buf, prefix);
            while (split.next()) |s| {
                const trimmed = std.mem.trim(u8, s, &std.ascii.whitespace);
                res = trimmed;
            }
            return res;
        }

        fn autoParseInt(self: Base, buf: []const u8) ?u8 {
            var base = self;
            if (base == .auto) base = Base.detect(buf);

            const ascii = base.trimPrefix(buf);
            if (ascii.len > base.getMaxAciiLen()) return null;
            return base.parseInt(ascii);
        }

        fn parseInt(self: Base, buf: []const u8) ?u8 {
            return std.fmt.parseUnsigned(u8, buf, self.getIntBase()) catch null;
        }

        fn autoParsePartialWildcard(self: Base, buf: []const u8) ?struct { u8, u8 } {
            var base = self;
            if (base == .auto) base = Base.detect(buf);

            const max_ascii_len = base.getMaxAciiLen();

            const ascii = base.trimPrefix(buf);
            if (ascii.len > max_ascii_len) return null;

            return self.parsePartialWildcard(ascii);
        }

        fn parsePartialWildcard(base: Base, buf: []const u8) ?struct { u8, u8 } {
            const bit_shift = bit_shifts[@intFromEnum(base)];
            // doesn't support partial wildcard, kinda doesn't make sense?
            if (@mod(@bitSizeOf(u8), @as(u8, bit_shift)) == 1) return null;

            const lower_mask = lower_masks[@intFromEnum(base)];

            var byte: u8 = 0;
            var mask: u8 = 0;

            for (buf) |c| {
                const sub_buf: [*]const u8 = @ptrCast(&c);
                if (base.parseInt(sub_buf[0..1])) |digit| {
                    byte = (byte << bit_shift) + digit;
                    mask = (mask << bit_shift) | lower_mask;
                } else {
                    byte <<= bit_shift;
                    mask <<= bit_shift;
                }
            }

            return .{ byte, mask };
        }
    };

    const supported_seperators = [_][]const u8{ " ", ",", "-" };

    pub fn compile(allocator: Allocator, pattern: []const u8, base: Base) !Pattern {
        for (supported_seperators) |seperator| {
            var tokens = std.mem.tokenizeSequence(u8, pattern, seperator);

            if (try compileTokens(allocator, &tokens, base)) |p| {
                return p;
            }
        }

        if (base == .auto) {
            return error.WindowParseNotSupported;
        }

        var window = std.mem.window(u8, pattern, base.getMaxAciiLen(), base.getMaxAciiLen());
        return compileWindow(allocator, &window, base);
    }

    pub fn deinit(self: Pattern) void {
        self.allocator.free(self.bytes);
        self.allocator.free(self.mask);
    }

    fn compileTokens(allocator: Allocator, tokens: *std.mem.TokenIterator(u8, .sequence), base_in: Base) !?Pattern {
        var bytes = std.ArrayList(u8).init(allocator);
        defer bytes.deinit();

        var mask = std.ArrayList(u8).init(allocator);
        defer mask.deinit();

        var last_base = base_in;

        while (tokens.next()) |raw_token| {
            const trimmed_token = std.mem.trim(u8, raw_token, &std.ascii.whitespace);

            var base = base_in;
            if (base == .auto) {
                base = Base.detect(trimmed_token);
                // fallback to our last detected base
                if (base == .@"10" and last_base != .auto) base = last_base;
                if (base != .@"10") last_base = base;
            }

            const token = base.trimPrefix(trimmed_token);

            if (token.len > base.getMaxAciiLen()) return null;

            // normal need to check full byte
            if (base.parseInt(token)) |byte| {
                try bytes.append(byte);
                try mask.append(0xFF);
                continue;
            }

            // single unknown ascii treating it as wildcard
            if (token.len == 1) {
                try bytes.append(0x00);
                try mask.append(full_wildcard_mask);
                continue;
            }

            if (base.parsePartialWildcard(token)) |wildcard| {
                try bytes.append(wildcard.@"0");
                try mask.append(wildcard.@"1");
                continue;
            }

            return null;
        }

        return .{
            .allocator = allocator,
            .bytes = try bytes.toOwnedSlice(),
            .mask = try mask.toOwnedSlice(),
        };
    }

    fn compileWindow(allocator: Allocator, window: *std.mem.WindowIterator(u8), base: Base) !Pattern {
        var bytes = std.ArrayList(u8).init(allocator);
        defer bytes.deinit();

        var mask = std.ArrayList(u8).init(allocator);
        defer mask.deinit();

        while (window.next()) |raw_token| {
            const token = std.mem.trim(u8, raw_token, &std.ascii.whitespace);

            // normal need to check full byte
            if (base.parseInt(token)) |byte| {
                try bytes.append(byte);
                try mask.append(0xFF);
                continue;
            }

            // no partial support when windowing, come one :)

            try bytes.append(0x00);
            try mask.append(full_wildcard_mask);
        }

        return .{
            .allocator = allocator,
            .bytes = try bytes.toOwnedSlice(),
            .mask = try mask.toOwnedSlice(),
        };
    }
};

pub const Scanner = struct {
    const AddressRange = struct {
        start: usize,
        end: usize,
    };

    allocator: std.mem.Allocator,
    search_ranges: std.ArrayList(AddressRange),

    pub fn init(allocator: std.mem.Allocator) Scanner {
        return .{
            .allocator = allocator,
            .search_ranges = std.ArrayList(AddressRange).init(allocator),
        };
    }

    pub const SearchOptions = struct {
        find_one_per_range: bool = false,
    };

    pub const SearchContext = struct {
        const SearchResult = std.ArrayList(AddressRange);
        scanner: *Scanner,
        result: SearchResult,

        /// Use this for general slice, single item pointer, Pattern, struct, tagged union types.
        /// This will just try to get the raw bytes representation and search those bytes.
        ///
        /// Use `searchScalar` for more concrete premitive, enum types.
        pub fn search(self: *SearchContext, value: anytype, options: SearchOptions) !void {
            @setRuntimeSafety(false);

            const ValueType = @TypeOf(value);
            if (ValueType == Pattern) {
                return self.searchPattern(value, options);
            }

            const info = @typeInfo(ValueType);
            var bytes: []const u8 = undefined;
            switch (info) {
                .array => |array_info| {
                    const array: []const array_info.child = &value;
                    const array_bytes: [*]const u8 = @ptrFromInt(@intFromPtr(array.ptr));
                    bytes = array_bytes[0 .. @sizeOf(array_info.child) * array_info.len];
                },
                .pointer => |pointer| {
                    if (pointer.size == .one) {
                        const array_bytes: [*]const u8 = @ptrFromInt(@intFromPtr(value));
                        bytes = array_bytes[0..@sizeOf(pointer.child)];
                    } else if (pointer.size == .slice) {
                        const slice: []const pointer.child = value[0..];
                        const array_bytes: [*]const u8 = @ptrFromInt(@intFromPtr(slice.ptr));
                        bytes = array_bytes[0..(@sizeOf(pointer.child) * slice.len)];
                    } else {
                        @compileError("`value` must be a slice or a pointer to a single item.");
                    }
                },
                else => {
                    // just try to treat as raw bytes
                    const raw_bytes: [*]const u8 = @ptrFromInt(@intFromPtr(&value));
                    bytes = raw_bytes[0..@sizeOf(ValueType)];
                },
            }

            return self.searchBytes(bytes, options);
        }

        /// This is valid for any normal struct, number, enum types, mostly scalar types.
        ///
        /// Same as `search` it will just get the underlying raw bytes and search them.
        pub fn searchScalar(self: *SearchContext, comptime T: type, value: T, options: SearchOptions) !void {
            @setRuntimeSafety(false);
            const raw_bytes: [*]const u8 = @ptrFromInt(@intFromPtr(&value));
            const bytes: []const u8 = raw_bytes[0..@sizeOf(T)];
            return self.searchBytes(bytes, options);
        }

        pub fn searchPattern(self: *SearchContext, pattern: Pattern, options: SearchOptions) !void {
            @setRuntimeSafety(false);

            const result = self.result.items;
            const search_ranges = if (result.len == 0) self.scanner.search_ranges.items else result;

            var new_result = std.ArrayList(AddressRange).init(self.scanner.allocator);
            defer new_result.deinit();

            for (search_ranges) |range| {
                assert(range.start <= range.end);

                var start = range.start;
                region_loop: while (start <= range.end - pattern.bytes.len) : (start += @sizeOf(u8)) {
                    @setRuntimeSafety(false);
                    const search_memory: [*]u8 = @ptrFromInt(start);

                    for (pattern.bytes, pattern.mask, 0..) |byte, mask, i| {
                        if (mask == Pattern.full_wildcard_mask) continue;
                        if (search_memory[i] & mask != byte) continue :region_loop;
                    }

                    try new_result.append(.{ .start = start, .end = start + pattern.bytes.len });

                    if (options.find_one_per_range) {
                        break;
                    }
                }
            }

            self.result.clearRetainingCapacity();
            try self.result.appendSlice(new_result.items);
        }

        pub fn searchBytes(self: *SearchContext, bytes: []const u8, options: SearchOptions) !void {
            const result = self.result.items;
            const search_ranges = if (result.len == 0) self.scanner.search_ranges.items else result;

            var new_result = std.ArrayList(AddressRange).init(self.scanner.allocator);
            defer new_result.deinit();

            for (search_ranges) |range| {
                assert(range.start <= range.end);

                var start = range.start;
                while (start <= range.end - bytes.len) : (start += @sizeOf(u8)) {
                    @setRuntimeSafety(false);
                    const search_memory: [*]u8 = @ptrFromInt(start);

                    if (!std.mem.eql(u8, search_memory[0..bytes.len], bytes)) continue;

                    try new_result.append(.{ .start = start, .end = start + bytes.len });

                    if (options.find_one_per_range) {
                        break;
                    }
                }
            }

            self.result.clearRetainingCapacity();
            try self.result.appendSlice(new_result.items);
        }

        pub fn deinit(self: *SearchContext) void {
            self.result.deinit();
        }
    };

    pub fn newSearch(self: *Scanner) SearchContext {
        return .{
            .scanner = self,
            .result = SearchContext.SearchResult.init(self.allocator),
        };
    }

    pub fn deinit(self: Scanner) void {
        self.search_ranges.deinit();
    }
};

test "base" {
    const Base = Pattern.Base;

    var base = Base.@"2";
    try std.testing.expectEqual(0b1, Base.lower_masks[@intFromEnum(base)]);

    var wildcard = base.autoParsePartialWildcard("0b1?1");
    try std.testing.expect(wildcard != null);

    try std.testing.expectEqual(0b101, wildcard.?.@"0");
    try std.testing.expectEqual(0b101, wildcard.?.@"1");

    base = Base.@"16";
    try std.testing.expectEqual(0b1111, Base.lower_masks[@intFromEnum(base)]);

    wildcard = base.autoParsePartialWildcard("B?");
    try std.testing.expect(wildcard != null);

    try std.testing.expectEqual(0xB0, wildcard.?.@"0");
    try std.testing.expectEqual(0xF0, wildcard.?.@"1");

    wildcard = base.autoParsePartialWildcard("??");
    try std.testing.expect(wildcard != null);
}

test "basic parsing" {
    {
        const pattern = try Pattern.compile(std.testing.allocator, "0xB CA DA 0b11? 0b1?1", .auto);
        defer pattern.deinit();
        try std.testing.expectEqualSlices(u8, &.{ 0x0B, 0xCA, 0xDA, 0b110, 0b101 }, pattern.bytes);
        try std.testing.expectEqualSlices(u8, &.{ 0xFF, 0xFF, 0xFF, 0b110, 0b101 }, pattern.mask);
    }

    {
        const pattern = try Pattern.compile(std.testing.allocator, "0xD?-CA-DA-0b11?-0b1?1", .auto);
        defer pattern.deinit();
        try std.testing.expectEqualSlices(u8, &.{ 0xD0, 0xCA, 0xDA, 0b110, 0b101 }, pattern.bytes);
        try std.testing.expectEqualSlices(u8, &.{ 0xF0, 0xFF, 0xFF, 0b110, 0b101 }, pattern.mask);
    }

    {
        const pattern = try Pattern.compile(std.testing.allocator, "0xD?,CA,DA,0b11?,0b1?1", .auto);
        defer pattern.deinit();
        try std.testing.expectEqualSlices(u8, &.{ 0xD0, 0xCA, 0xDA, 0b110, 0b101 }, pattern.bytes);
        try std.testing.expectEqualSlices(u8, &.{ 0xF0, 0xFF, 0xFF, 0b110, 0b101 }, pattern.mask);
    }

    {
        const pattern = try Pattern.compile(std.testing.allocator, "DACABA", .@"16");
        defer pattern.deinit();
        try std.testing.expectEqualSlices(u8, &.{ 0xDA, 0xCA, 0xBA }, pattern.bytes);
        try std.testing.expectEqualSlices(u8, &.{ 0xFF, 0xFF, 0xFF }, pattern.mask);
    }

    {
        const pattern = try Pattern.compile(std.testing.allocator, "100200210", .@"10");
        defer pattern.deinit();
        try std.testing.expectEqualSlices(u8, &.{ 100, 200, 210 }, pattern.bytes);
        try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255 }, pattern.mask);
    }

    {
        const pattern = try Pattern.compile(std.testing.allocator, "0x69 0x4? ?? 0x69 0x42", .auto);
        defer pattern.deinit();
        try std.testing.expectEqualSlices(u8, &.{ 0x69, 0x40, 0x00, 0x69, 0x42 }, pattern.bytes);
        try std.testing.expectEqualSlices(u8, &.{ 0xFF, 0xF0, Pattern.full_wildcard_mask, 0xFF, 0xFF }, pattern.mask);
    }
}

test "Scanner" {
    var scanner = Scanner.init(std.testing.allocator);
    defer scanner.deinit();

    var mut_search_memory = [_]u8{ 0x69, 0x42, 0xFF, 0x69, 0x42, 0x00, 0x10, 0x20 };
    const search_memory: []const u8 = &mut_search_memory;

    try scanner.search_ranges.append(.{
        .start = @intFromPtr(search_memory.ptr),
        .end = @intFromPtr(search_memory.ptr) + search_memory.len,
    });

    {
        var search = scanner.newSearch();
        defer search.deinit();

        const pattern = try Pattern.compile(std.testing.allocator, "0x69 0x4? ?? 0x69 0x42", .auto);
        defer pattern.deinit();

        try search.search(pattern, .{});
        var result = search.result.items;
        try std.testing.expectEqual(1, result.len);
        try std.testing.expectEqual(@intFromPtr(search_memory.ptr), result[0].start);

        // cannot find the full memory because we searched for 5 bytes previously but full memory is 8 bytes
        try search.searchBytes(search_memory, .{});
        result = search.result.items;
        try std.testing.expectEqual(0, result.len);

        try search.searchBytes(search_memory[0..5], .{});
        result = search.result.items;
        try std.testing.expectEqual(1, result.len);
        try std.testing.expectEqual(@intFromPtr(search_memory.ptr), result[0].start);
    }

    {
        var search = scanner.newSearch();
        defer search.deinit();

        try search.searchScalar(u8, 0x69, .{});
        const result = search.result.items;
        try std.testing.expectEqual(2, result.len);
        try std.testing.expectEqual(@intFromPtr(search_memory.ptr), result[0].start);
        try std.testing.expectEqual(@intFromPtr(search_memory.ptr) + 3, result[1].start);
    }

    {
        var search = scanner.newSearch();
        defer search.deinit();

        try search.searchScalar(u16, 0xFF42, .{});
        const result = search.result.items;
        try std.testing.expectEqual(1, result.len);
        try std.testing.expectEqual(@intFromPtr(search_memory.ptr) + 1, result[0].start);
    }

    {
        var search = scanner.newSearch();
        defer search.deinit();

        try search.searchScalar(usize, 0x2010004269FF4269, .{});
        const result = search.result.items;
        try std.testing.expectEqual(1, result.len);
        try std.testing.expectEqual(@intFromPtr(search_memory.ptr), result[0].start);
    }
}
