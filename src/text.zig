const std = @import("std");
const gpu = @import("gpu/gpu.zig");
const math = @import("math.zig");

const c = @cImport({
    @cInclude("freetype/freetype.h");
});

pub const UnicodeCodepoint = u21;
pub const Face = struct {
    _ft_lib: c.FT_Library,
    _ft_face: c.FT_Face,

    pub fn init(path: [*:0]const u8) !Face {
        var lib: c.FT_Library = null;
        if (c.FT_Init_FreeType(&lib) != 0) return error.FreeTypeInitFailed;
        errdefer _ = c.FT_Done_FreeType(lib);

        var face: c.FT_Face = null;
        if (c.FT_New_Face(lib, path, 0, &face) != 0) return error.BadFont;
        errdefer _ = c.FT_Done_Face(face);

        return .{
            ._ft_lib = lib,
            ._ft_face = face,
        };
    }

    pub fn deinit(face: *Face) void {
        _ = c.FT_Done_Face(face._ft_face);
        _ = c.FT_Done_FreeType(face._ft_lib);
    }
};

pub const GlyphCache = struct {
    alloc: std.mem.Allocator,
    stage_man: *gpu.StagingManager,
    atlas_size: gpu.Image.Size2D,
    atlases: std.ArrayList(Atlas) = .empty,
    glyphs: std.AutoHashMapUnmanaged(InternalGlyphDesc, Glyph) = .empty,

    current_atlas_id: u32 = 0,
    next_glyph_start: gpu.Image.Offset2D = @splat(0),
    row_highest: u32 = 0,

    copies: std.ArrayList(Copy) = .empty,
    /// whether it is written to in copies array
    atlas_dirty: std.AutoHashMapUnmanaged(u32, void) = .empty,

    pub const Copy = struct {
        loc: Glyph.Loc,
        staging: gpu.Buffer.Region,
    };

    pub const Atlas = struct {
        image: gpu.Image,
        view: gpu.Image.View,
        layout: gpu.Image.Layout = .undefined,
    };

    const InternalGlyphDesc = struct {
        _ft_face_ptr: usize,
        height: u16,
        codepoint: UnicodeCodepoint,
    };

    pub const Glyph = struct {
        pub const Loc = struct {
            atlas_id: u32,
            bounds: gpu.Image.Rect,
        };

        loc: Loc,
        size: [2]u16,
        advance: [2]i16,
        bearing: [2]i16,
    };

    pub const GlyphDesc = struct {
        face: *Face,
        height: u16,
        codepoint: UnicodeCodepoint,
    };

    pub fn deinit(cache: *GlyphCache, device: gpu.Device) void {
        cache.atlas_dirty.deinit(cache.alloc);
        cache.copies.deinit(cache.alloc);
        cache.glyphs.deinit(cache.alloc);

        for (cache.atlases.items) |atlas| {
            atlas.view.deinit(device, cache.alloc);
            atlas.image.deinit(device, cache.alloc);
        }

        cache.atlases.deinit(cache.alloc);
    }

    pub fn upload(cache: *GlyphCache, device: gpu.Device, cmd_encoder: gpu.CommandEncoder) !void {
        if (cache.copies.items.len == 0) return;

        const required_atlas_count = cache.current_atlas_id + 1;
        const loaded_atlas_count = cache.atlases.items.len;
        try cache.atlases.resize(cache.alloc, required_atlas_count);

        // TODO: handle errors correctly
        for (loaded_atlas_count..required_atlas_count) |atlas_id| {
            const image = try device.initImage(.{
                .alloc = cache.alloc,
                .format = .r8_unorm,
                .usage = .{ .sampled = true, .dst = true },
                .loc = .device,
                .size = cache.atlas_size,
            });
            errdefer image.deinit(device, cache.alloc);

            const view = try device.initImageView(.{
                .alloc = cache.alloc,
                .image = image,
                .kind = .@"2d",
                .component_mapping = .{
                    .r = .r,
                    .g = .r,
                    .b = .r,
                    .a = .r,
                },
                .subresource_range = .{
                    .aspect = .{ .color = true },
                },
            });
            errdefer view.deinit(device, cache.alloc);

            cache.atlases.items[atlas_id] = .{
                .image = image,
                .view = view,
                .layout = .undefined,
            };
        }

        var image_barriers: std.ArrayList(gpu.ImageBarrier) = try .initCapacity(cache.alloc, required_atlas_count);
        defer image_barriers.deinit(cache.alloc);

        var dirty_iter = cache.atlas_dirty.iterator();
        while (dirty_iter.next()) |entry| {
            const atlas = &cache.atlases.items[entry.key_ptr.*];

            image_barriers.appendAssumeCapacity(.{
                .image = atlas.image,
                .subresource_range = .{
                    .aspect = .{ .color = true },
                },
                .old_layout = atlas.layout,
                .new_layout = .transfer_dst,
                .src_stage = switch (atlas.layout) {
                    .undefined => .{ .pipeline_start = true },
                    .shader_read_only => .{ .pixel_shader = true },
                    else => unreachable,
                },
                .src_access = switch (atlas.layout) {
                    .undefined => .{},
                    .shader_read_only => .{ .shader_read = true },
                    else => unreachable,
                },
                .dst_stage = .{ .transfer = true },
                .dst_access = .{ .transfer_write = true },
            });
            atlas.layout = .transfer_dst;
        }
        cmd_encoder.cmdMemoryBarrier(.{ .image_barriers = image_barriers.items });

        for (cache.copies.items) |copy| {
            const atlas = &cache.atlases.items[copy.loc.atlas_id];

            cmd_encoder.cmdCopyBufferToImage(.{
                .src = copy.staging,
                .dst = atlas.image,
                .layout = atlas.layout,
                .subresource = .{
                    .aspect = .{ .color = true },
                },
                .region = .{
                    .offset = .{
                        copy.loc.bounds.offset[0],
                        copy.loc.bounds.offset[1],
                        0,
                    },
                    .size = .{
                        copy.loc.bounds.size[0],
                        copy.loc.bounds.size[1],
                        1,
                    },
                },
            });
        }

        image_barriers.clearRetainingCapacity();
        dirty_iter = cache.atlas_dirty.iterator();
        while (dirty_iter.next()) |entry| {
            const atlas = &cache.atlases.items[entry.key_ptr.*];

            image_barriers.appendAssumeCapacity(.{
                .image = atlas.image,
                .subresource_range = .{
                    .aspect = .{ .color = true },
                },
                .old_layout = atlas.layout,
                .new_layout = .shader_read_only,
                .src_stage = .{ .transfer = true },
                .src_access = .{ .transfer_write = true },
                .dst_stage = .{ .pixel_shader = true },
                .dst_access = .{ .shader_read = true },
            });
            atlas.layout = .shader_read_only;
        }
        cmd_encoder.cmdMemoryBarrier(.{ .image_barriers = image_barriers.items });

        cache.copies.clearRetainingCapacity();
        cache.atlas_dirty.clearRetainingCapacity();
    }

    pub fn getGlyph(cache: *GlyphCache, desc: GlyphDesc) ?Glyph {
        const internal_desc: InternalGlyphDesc = .{
            ._ft_face_ptr = @intFromPtr(desc.face._ft_face),
            .height = desc.height,
            .codepoint = desc.codepoint,
        };

        return cache.glyphs.get(internal_desc);
    }

    pub fn getOrLoadGlyph(cache: *GlyphCache, desc: GlyphDesc) !Glyph {
        try cache.loadGlyph(desc);
        return cache.getGlyph(desc) orelse unreachable;
    }

    pub fn loadGlyph(cache: *GlyphCache, desc: GlyphDesc) !void {
        const ft_face = desc.face._ft_face;
        const internal_desc: InternalGlyphDesc = .{
            ._ft_face_ptr = @intFromPtr(ft_face),
            .height = desc.height,
            .codepoint = desc.codepoint,
        };
        if (cache.glyphs.contains(internal_desc)) return;

        const glyph_index = c.FT_Get_Char_Index(ft_face, desc.codepoint);
        if (glyph_index == 0) return;

        if (c.FT_Set_Pixel_Sizes(ft_face, 0, desc.height) != 0) return error.BadHeight;
        if (c.FT_Load_Glyph(ft_face, glyph_index, c.FT_LOAD_DEFAULT) != 0) return error.GlyphLoadFailed;

        const ft_glyph = ft_face.*.glyph;
        if (c.FT_Render_Glyph(ft_glyph, c.FT_RENDER_MODE_NORMAL) != 0) return error.GlyphRenderFailed;

        const bmp = ft_glyph.*.bitmap;
        const width: usize = bmp.width;
        const height: usize = bmp.rows;
        const y_flipped = bmp.pitch < 0;
        const size: gpu.Image.Size2D = .{ @intCast(width), @intCast(height) };
        const pitch: usize = @abs(bmp.pitch);
        const bytes_per_pixel = 1;

        const loc: Glyph.Loc = if (width != 0 and height != 0) blk: {
            const loc = try cache.allocateAtlasSpace(size);
            const staging = try cache.stage_man.allocateBytesAligned(width * height * bytes_per_pixel, .@"4");

            for (0..height) |uy| {
                const y = if (y_flipped) height - uy - 1 else uy;

                const src = bmp.buffer[y * pitch ..][0 .. width * bytes_per_pixel];
                const dst = staging.slice[uy * width * bytes_per_pixel ..][0 .. width * bytes_per_pixel];
                @memcpy(dst, src);
            }

            try cache.atlas_dirty.put(cache.alloc, loc.atlas_id, {});
            try cache.copies.append(cache.alloc, .{
                .loc = loc,
                .staging = staging.region,
            });

            break :blk loc;
        } else .{
            .atlas_id = 0,
            .bounds = .{
                .offset = @splat(0),
                .size = @splat(0),
            },
        };

        try cache.glyphs.put(cache.alloc, internal_desc, .{
            .loc = loc,
            .size = @as(@Vector(2, u16), @intCast(size)),
            .advance = .{
                @intCast(ft_glyph.*.advance.x >> 6),
                @intCast(ft_glyph.*.advance.y >> 6),
            },
            .bearing = .{
                @intCast(ft_glyph.*.bitmap_left),
                @intCast(ft_glyph.*.bitmap_top),
            },
        });
    }

    fn allocateAtlasSpace(cache: *GlyphCache, size: gpu.Image.Size2D) !Glyph.Loc {
        if (@reduce(.Or, size > cache.atlas_size)) return error.AtlasAllocationTooBig;

        if (cache.next_glyph_start[0] + size[0] > cache.atlas_size[0]) {
            cache.next_glyph_start[0] = 0;
            cache.next_glyph_start[1] += cache.row_highest;
            cache.row_highest = 0;
        }

        if (cache.next_glyph_start[1] + size[1] > cache.atlas_size[1]) {
            cache.current_atlas_id += 1;
            cache.next_glyph_start = @splat(0);
            cache.row_highest = 0;
        }

        const pos = cache.next_glyph_start;
        cache.next_glyph_start[0] += size[0];
        cache.row_highest = @max(cache.row_highest, size[1]);

        return .{
            .atlas_id = cache.current_atlas_id,
            .bounds = .{
                .offset = pos,
                .size = size,
            },
        };
    }
};

pub const PositionedGlyph = struct {
    atlas_id: u32,
    pos_tl: [2]i16,
    size: [2]u16,
    /// unorm
    uv_tl: [2]u16,
    /// unorm
    uv_br: [2]u16,
};

pub const PositionedGlyphIterator = struct {
    cache: *GlyphCache,
    face: *Face,
    height: u16,
    text: std.unicode.Utf8Iterator,

    pen: [2]i16 = @splat(0),

    const i16x2 = @Vector(2, i16);
    const invalid_char: UnicodeCodepoint = 0xfffd;
    pub fn next(iter: *PositionedGlyphIterator) !?PositionedGlyph {
        const codepoint = iter.text.nextCodepoint() orelse return null;

        const glyph = try iter.cache.getOrLoadGlyph(.{
            .face = iter.face,
            .height = iter.height,
            .codepoint = codepoint,
        });

        const pen: i16x2 = iter.pen;
        iter.pen[0] += glyph.advance[0];
        const bearing: i16x2 = glyph.bearing;
        const pos_tl = pen + bearing;

        const uv_tl = glyph.loc.bounds.offset;
        const uv_br = uv_tl + glyph.loc.bounds.size;

        const uv_tl_f: math.Vec2 = @floatFromInt(uv_tl);
        const uv_br_f: math.Vec2 = @floatFromInt(uv_br);

        const atlas_size: math.Vec2 = @floatFromInt(iter.cache.atlas_size);
        const uv_tl_n = uv_tl_f / atlas_size;
        const uv_br_n = uv_br_f / atlas_size;

        return .{
            .atlas_id = glyph.loc.atlas_id,
            .pos_tl = pos_tl,
            .size = glyph.size,
            .uv_tl = .{
                math.normFromFloat(u16, uv_tl_n[0]),
                math.normFromFloat(u16, uv_tl_n[1]),
            },
            .uv_br = .{
                math.normFromFloat(u16, uv_br_n[0]),
                math.normFromFloat(u16, uv_br_n[1]),
            },
        };
    }
};
