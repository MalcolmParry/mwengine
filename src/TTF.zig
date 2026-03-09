const std = @import("std");

const TTF = @This();

glyphs: []Glyph,
glyph_components: []GlyphComponent,
simple_glyphs: []SimpleGlyph,
points: []Point,
contour_end_indices: []u16,

pub const SimpleGlyph = struct {
    point_count: u16,
    contour_count: u16,
    points_offset: u32,
    contour_ends_offset: u32,

    pub fn points(glyph: SimpleGlyph, ttf: *const TTF) []Point {
        return ttf.points[glyph.points_offset .. glyph.points_offset + glyph.point_count];
    }

    pub fn contourEndIndices(glyph: SimpleGlyph, ttf: *const TTF) []u16 {
        return ttf.contour_end_indices[glyph.contour_ends_offset .. glyph.contour_ends_offset + glyph.contour_count];
    }
};

pub const Glyph = packed struct {
    /// if not compound then this is index into glyph_components otherwise it is start index into glyph_component_indices
    offset: u16,
    /// ignored if not compound
    count: u15,
    compound: bool,

    pub fn components(glyph: Glyph, ttf: *const TTF) []GlyphComponent {
        std.debug.assert(glyph.compound);
        return ttf.glyph_components[glyph.offset .. glyph.offset + glyph.count];
    }
};

pub const GlyphComponent = struct {
    index: u16,
    offset: [2]i16,
};

pub const Point = struct {
    coords: [2]i16,
    on_curve: bool,
};

pub fn parse(alloc: std.mem.Allocator, reader: *std.fs.File.Reader) !TTF {
    const offset_subtable = try reader.interface.takeStruct(OffsetSubtable, .big);

    std.log.info("table count {}", .{offset_subtable.table_count});

    var maybe_glyf_tab: ?Slice = null;
    var maybe_cmap_tab: ?Slice = null;
    var maybe_maxp_tab: ?Slice = null;
    var maybe_head_tab: ?Slice = null;
    var maybe_loca_tab: ?Slice = null;

    for (0..offset_subtable.table_count) |_| {
        const table = try reader.interface.takeStruct(TableDirEntry, .big);

        switch (tagAsU32(table.tag)) {
            tagAsU32("glyf".*) => maybe_glyf_tab = table.slice,
            tagAsU32("cmap".*) => maybe_cmap_tab = table.slice,
            tagAsU32("maxp".*) => maybe_maxp_tab = table.slice,
            tagAsU32("head".*) => maybe_head_tab = table.slice,
            tagAsU32("loca".*) => maybe_loca_tab = table.slice,
            else => {},
        }

        std.log.info("table '{s}' at {x} with len {x}", .{ table.tag, table.slice.offset, table.slice.len });
    }

    const glyf_tab_slice = if (maybe_glyf_tab) |x| x else return error.BadFile;
    const cmap_tab_slice = if (maybe_cmap_tab) |x| x else return error.BadFile;
    const maxp_tab_slice = if (maybe_maxp_tab) |x| x else return error.BadFile;
    const head_tab_slice = if (maybe_head_tab) |x| x else return error.BadFile;
    const loca_tab_slice = if (maybe_loca_tab) |x| x else return error.BadFile;
    _ = cmap_tab_slice;

    try reader.seekTo(head_tab_slice.offset + 50);
    const glyph_loc_type: GlyphLocType = switch (try reader.interface.takeInt(u16, .big)) {
        0 => .u16,
        1 => .u32,
        else => return error.BadFile,
    };

    try reader.seekTo(maxp_tab_slice.offset + 4);
    const glyph_count = try reader.interface.takeInt(u16, .big);
    std.log.info("glyph count: {}", .{glyph_count});

    var state: ParserState = .{
        .reader = reader,
        .alloc = alloc,
    };

    var glyphs: std.ArrayList(Glyph) = try .initCapacity(alloc, glyph_count);

    for (0..glyph_count) |i| {
        try reader.seekTo(loca_tab_slice.offset + i * glyph_loc_type.size());
        const glyph_offset = switch (glyph_loc_type) {
            .u16 => @as(u32, try reader.interface.takeInt(u16, .big)) * 2,
            .u32 => try reader.interface.takeInt(u32, .big),
        };

        try reader.seekTo(glyf_tab_slice.offset + glyph_offset);
        glyphs.appendAssumeCapacity(try parseGlyph(&state));
    }

    return .{
        .glyphs = try glyphs.toOwnedSlice(alloc),
        .glyph_components = try state.glyph_components.toOwnedSlice(alloc),
        .simple_glyphs = try state.simple_glyphs.toOwnedSlice(alloc),
        .points = try state.points.toOwnedSlice(alloc),
        .contour_end_indices = try state.contour_end_indices.toOwnedSlice(alloc),
    };
}

pub fn deinit(ttf: *TTF, alloc: std.mem.Allocator) void {
    alloc.free(ttf.glyphs);
    alloc.free(ttf.glyph_components);
    alloc.free(ttf.simple_glyphs);
    alloc.free(ttf.points);
    alloc.free(ttf.contour_end_indices);
}

fn parseGlyph(state: *ParserState) !Glyph {
    const reader = &state.reader.interface;
    const desc = try reader.takeStruct(GlyphDesc, .big);
    std.log.info("contour count: {}", .{desc.contour_count});

    if (desc.contour_count >= 0) {
        try state.simple_glyphs.append(state.alloc, try parseSimpleGlyph(state, desc));

        return .{
            .compound = false,
            .offset = @intCast(state.simple_glyphs.items.len - 1),
            .count = 1,
        };
    } else {
        // compound glyph
        const component_offset = state.glyph_components.items.len;
        var count: u15 = 0;

        while (true) {
            const flags = try reader.takeStruct(CompoundComponentFlags, .big);
            const index = try reader.takeInt(u16, .big);
            const offset: [2]i16 = switch (flags.arg_type) {
                .i8 => .{
                    try reader.takeInt(i8, .big),
                    try reader.takeInt(i8, .big),
                },
                .i16 => .{
                    try reader.takeInt(i16, .big),
                    try reader.takeInt(i16, .big),
                },
            };

            if (flags.has_scale or flags.has_vec2_scale or flags.has_2x2_scale) {
                return error.NotSupported;
            }

            try state.glyph_components.append(state.alloc, .{
                .index = index,
                .offset = offset,
            });
            std.log.info("{}", .{flags.more_components});
            count += 1;
            if (!flags.more_components) break;
        }

        return .{
            .compound = true,
            .offset = @intCast(component_offset),
            .count = count,
        };
    }
}

fn parseSimpleGlyph(state: *ParserState, desc: GlyphDesc) !SimpleGlyph {
    const reader = &state.reader.interface;
    const alloc = state.alloc;

    const contour_count: u16 = switch (std.math.order(desc.contour_count, 0)) {
        // should have already been handled
        .lt => unreachable,
        .eq => return .{
            .contour_count = 0,
            .contour_ends_offset = 0,
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
    const points = try state.points.addManyAsSlice(alloc, point_count);

    try parseCoords(reader, points, all_flags, .x);
    try parseCoords(reader, points, all_flags, .y);

    for (points) |point| std.log.info("point at x={} y={}", .{ point.coords[0], point.coords[1] });

    return .{
        .contour_count = contour_count,
        .contour_ends_offset = @intCast(contour_end_index_offset),
        .point_count = point_count,
        .points_offset = @intCast(point_offset),
    };
}

fn parseCoords(reader: *std.Io.Reader, points: []Point, all_flags: []const SimpleGlyphPointFlags, component: SimpleGlyphPointFlags.Component) !void {
    var last_coord: i16 = 0;

    for (points, all_flags) |*point_ptr, flags| {
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
        point_ptr.coords[@intFromEnum(component)] = coord;
        point_ptr.on_curve = flags.on_curve;
        last_coord = coord;
    }
}

const ParserState = struct {
    reader: *std.fs.File.Reader,
    alloc: std.mem.Allocator,
    points: std.ArrayList(Point) = .empty,
    contour_end_indices: std.ArrayList(u16) = .empty,
    glyph_components: std.ArrayList(GlyphComponent) = .empty,
    simple_glyphs: std.ArrayList(SimpleGlyph) = .empty,
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

const CompoundComponentFlags = packed struct(u16) {
    const ArgType = enum(u1) {
        i8 = 0,
        i16 = 1,

        fn size(t: ArgType) u8 {
            return switch (t) {
                .i8 => 1,
                .i16 => 2,
            };
        }
    };

    arg_type: ArgType,
    dont_care: u2,
    has_scale: bool,
    reserved: u1,
    more_components: bool,
    has_vec2_scale: bool,
    has_2x2_scale: bool,
    has_instructions: bool,
    dont_care_2: u7,
};

fn tagAsU32(tag: [4]u8) u32 {
    return @bitCast(tag);
}

const GlyphLocType = enum {
    u16,
    u32,

    fn size(t: GlyphLocType) usize {
        return switch (t) {
            .u16 => 2,
            .u32 => 4,
        };
    }
};
