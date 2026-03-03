const std = @import("std");

const TTF = @This();

simple_glyphs: []SimpleGlyph,
points: [][2]i16,
contour_end_indices: []u16,

pub const SimpleGlyph = struct {
    point_count: u16,
    contour_count: u16,
    points_offset: u32,
    countour_ends_offset: u32,

    pub fn points(glyph: SimpleGlyph, ttf: *const TTF) [][2]i16 {
        return ttf.points[glyph.point_offset .. glyph.point_offset + glyph.point_count];
    }

    pub fn contourEndIndices(glyph: SimpleGlyph, ttf: *const TTF) []u16 {
        return ttf.contour_end_indices[glyph.contour_ends_offset .. glyph.countour_ends_offsets + glyph.contour_count];
    }
};

pub fn parse(alloc: std.mem.Allocator, reader: *std.fs.File.Reader) !void {
    const offset_subtable = try reader.interface.takeStruct(OffsetSubtable, .big);

    std.log.info("table count {}", .{offset_subtable.table_count});

    var maybe_glyf_tab: ?Slice = null;
    var maybe_cmap_tab: ?Slice = null;
    var maybe_maxp_tab: ?Slice = null;

    for (0..offset_subtable.table_count) |_| {
        const table = try reader.interface.takeStruct(TableDirEntry, .big);

        switch (tagAsU32(table.tag)) {
            tagAsU32("glyf".*) => maybe_glyf_tab = table.slice,
            tagAsU32("cmap".*) => maybe_cmap_tab = table.slice,
            tagAsU32("maxp".*) => maybe_maxp_tab = table.slice,
            else => {},
        }

        std.log.info("table '{s}' at {x} with len {x}", .{ table.tag, table.slice.offset, table.slice.len });
    }

    const glyf_tab_slice = if (maybe_glyf_tab) |x| x else return error.BadFile;
    const cmap_tab_slice = if (maybe_cmap_tab) |x| x else return error.BadFile;
    const maxp_tab_slice = if (maybe_maxp_tab) |x| x else return error.BadFile;
    _ = cmap_tab_slice;

    try reader.seekTo(maxp_tab_slice.offset + 4);
    const glyph_count = try reader.interface.takeInt(u16, .big);
    std.log.info("glyph count: {}", .{glyph_count});

    var state: ParserState = .{
        .reader = reader,
        .alloc = alloc,
    };
    defer {
        state.points.deinit(alloc);
        state.contour_end_indices.deinit(alloc);
    }

    try reader.seekTo(glyf_tab_slice.offset);
    for (0..glyph_count) |_| {
        std.log.info("", .{});
        _ = try parseSimpleGlyph(&state);
    }
}

fn parseSimpleGlyph(state: *ParserState) !SimpleGlyph {
    const reader = &state.reader.interface;
    const alloc = state.alloc;

    const desc = try reader.takeStruct(GlyphDesc, .big);
    std.log.info("{}", .{desc.contour_count});

    const contour_count: u16 = switch (std.math.order(desc.contour_count, 0)) {
        .lt => return error.Unsupported,
        .eq => return .{
            .contour_count = 0,
            .countour_ends_offset = 0,
            .point_count = 0,
            .points_offset = 0,
        },
        .gt => @intCast(desc.contour_count),
    };

    const contour_end_index_offset = state.contour_end_indices.items.len;
    const contour_end_indices = try state.contour_end_indices.addManyAsSlice(alloc, contour_count);
    try reader.readSliceEndian(u16, contour_end_indices, .big);

    for (contour_end_indices) |x| std.log.info("contour end at index {}", .{x});

    const point_count = std.math.add(u16, contour_end_indices[contour_count - 1], 1) catch return error.BadFile;
    std.log.info("point count: {}", .{point_count});

    // skip instructions
    try state.reader.seekBy(try reader.takeInt(u16, .big));

    // read flags
    const all_flags = try alloc.alloc(SimpleGlyphPointFlags, point_count);
    defer alloc.free(all_flags);

    var i: usize = 0;
    while (i < point_count) : (i += 1) {
        const flag_byte = try reader.takeByte();
        const flags: SimpleGlyphPointFlags = @bitCast(flag_byte);
        all_flags[i] = flags;

        if (flags.repeat) {
            const copies = try reader.takeByte();
            for (0..copies) |_| {
                i += 1;
                if (i >= point_count) return error.BadFile;
                all_flags[i] = flags;
            }
        }
    }

    // read coords
    const point_offset = state.points.items.len;
    const coords = try state.points.addManyAsSlice(alloc, point_count);

    try parseCoords(reader, coords, all_flags, .x);
    try parseCoords(reader, coords, all_flags, .y);

    for (coords) |coord| std.log.info("point at x={} y={}", .{ coord[0], coord[1] });

    return .{
        .contour_count = contour_count,
        .countour_ends_offset = @intCast(contour_end_index_offset),
        .point_count = point_count,
        .points_offset = @intCast(point_offset),
    };
}

fn parseCoords(reader: *std.Io.Reader, coords: [][2]i16, all_flags: []const SimpleGlyphPointFlags, component: SimpleGlyphPointFlags.Component) !void {
    var last_coord: i16 = 0;

    for (coords, all_flags) |*coord_ptr, flags| {
        const offset: i16 = switch (flags.getType(component)) {
            .u8 => blk: {
                const unsigned_offset: i16 = try reader.takeByte();
                const positive = flags.getSignOrRepeat(component);
                break :blk if (positive) unsigned_offset else -unsigned_offset;
            },
            .i16 => if (!flags.getSignOrRepeat(component))
                try reader.takeInt(i16, .big)
            else
                0,
        };

        const coord = std.math.add(i16, offset, last_coord) catch return error.BadFile;
        coord_ptr.*[@intFromEnum(component)] = coord;
        last_coord = coord;
    }
}

const ParserState = struct {
    reader: *std.fs.File.Reader,
    alloc: std.mem.Allocator,
    points: std.ArrayList([2]i16) = .empty,
    contour_end_indices: std.ArrayList(u16) = .empty,
};

const OffsetSubtable = extern struct {
    scaler_type: u32,
    table_count: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
};

const TableDirEntry = extern struct {
    tag: [4]u8,
    checksum: u32,
    slice: Slice,
};

const GlyphDesc = extern struct {
    /// if negative then compound
    contour_count: i16,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

const Slice = extern struct {
    offset: u32,
    len: u32,
};

const SimpleGlyphPointFlags = packed struct(u8) {
    const OffsetType = enum(u1) { u8 = 1, i16 = 0 };
    const Component = enum { x, y };

    fn getType(flags: SimpleGlyphPointFlags, component: Component) OffsetType {
        return switch (component) {
            .x => flags.x_type,
            .y => flags.y_type,
        };
    }

    fn getSignOrRepeat(flags: SimpleGlyphPointFlags, component: Component) bool {
        return switch (component) {
            .x => flags.x_sign_or_repeat,
            .y => flags.y_sign_or_repeat,
        };
    }

    on_curve: bool,
    x_type: OffsetType,
    y_type: OffsetType,
    repeat: bool,
    x_sign_or_repeat: bool,
    y_sign_or_repeat: bool,
    reserved: u2 = 0,
};

fn tagAsU32(tag: [4]u8) u32 {
    return @bitCast(tag);
}
