const std = @import("std");
const gpu = @import("gpu.zig");
const math = @import("math.zig");

const c = @cImport({
    @cInclude("freetype/freetype.h");
});

pub const UnicodeCodepoint = u32;
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

    pub const Loaded = struct {
        face: *Face,
        render_mode: RenderMode,
        atlas_size: gpu.Image.Size2D,
        char_height_px: u32,

        atlases: std.ArrayList(Atlas) = .empty,
        glyphs: std.AutoHashMapUnmanaged(UnicodeCodepoint, Glyph) = .empty,
        next_glyph_start: gpu.Image.Offset2D = @splat(0),

        pub const RenderMode = enum {
            grayscale,
        };

        pub const Atlas = struct {
            image: gpu.Image,
            view: gpu.Image.View,
            sampler: gpu.Sampler,
            layout: gpu.Image.Layout = .undefined,
        };

        pub const Glyph = struct {
            atlas: u32,
            bounds: gpu.Image.Rect,
        };

        pub fn deinit(loaded: *Loaded, alloc: std.mem.Allocator, device: gpu.Device) void {
            for (loaded.atlases.items) |atlas| {
                atlas.sampler.deinit(device, alloc);
                atlas.view.deinit(device, alloc);
                atlas.image.deinit(device, alloc);
            }

            loaded.atlases.deinit(alloc);
            loaded.glyphs.deinit(alloc);
        }

        pub const LoadGlyphInfo = struct {
            alloc: std.mem.Allocator,
            device: gpu.Device,
            stage_man: *gpu.StagingManager,
            cmd_encoder: gpu.CommandEncoder,
            codepoint: UnicodeCodepoint,
        };

        pub fn loadGlyph(loaded: *Loaded, info: LoadGlyphInfo) !void {
            if (loaded.glyphs.contains(info.codepoint)) return;
            const glyph_index = c.FT_Get_Char_Index(loaded.face._ft_face, info.codepoint);
            if (glyph_index == 0) return;

            if (c.FT_Set_Pixel_Sizes(loaded.face._ft_face, 0, loaded.char_height_px) != 0) return error.BadSize;
            if (c.FT_Load_Glyph(loaded.face._ft_face, glyph_index, c.FT_LOAD_DEFAULT) != 0) return error.GlyphLoadFailed;

            const ft_glyph = loaded.face._ft_face.*.glyph;
            if (c.FT_Render_Glyph(ft_glyph, c.FT_RENDER_MODE_NORMAL) != 0) return error.GlyphRenderFailed;

            const bmp = ft_glyph.*.bitmap;
            const width: usize = bmp.width;
            const height: usize = bmp.rows;
            const y_flipped = bmp.pitch < 0;
            const size: gpu.Image.Size2D = .{ @intCast(width), @intCast(height) };

            if (width == 0 or height == 0) {
                try loaded.glyphs.put(info.alloc, info.codepoint, .{
                    .atlas = 0,
                    .bounds = .{
                        .offset = @splat(0),
                        .size = @splat(0),
                    },
                });
                return;
            }

            const glyph = try loaded.allocateAtlasSpace(info.alloc, info.device, size);
            const atlas = &loaded.atlases.items[glyph.atlas];
            const staging = try info.stage_man.allocateBytesAligned(width * height, .@"4");

            for (0..height) |uy| {
                const y = if (y_flipped) height - uy - 1 else uy;

                const src = bmp.buffer[y * width ..][0..width];
                const dst = staging.slice[y * width ..][0..width];
                @memcpy(dst, src);
            }

            info.cmd_encoder.cmdMemoryBarrier(.{
                .image_barriers = &.{.{
                    .image = atlas.image,
                    .subresource_range = .{
                        .aspect = .{ .color = true },
                    },
                    .old_layout = atlas.layout,
                    .new_layout = .transfer_dst,
                    .src_stage = .{ .pipeline_start = true },
                    .dst_stage = .{ .transfer = true },
                    .src_access = .{},
                    .dst_access = .{ .transfer_write = true },
                }},
            });

            info.cmd_encoder.cmdCopyBufferToImage(.{
                .src = staging.region,
                .dst = atlas.image,
                .region = .{
                    .offset = .{
                        glyph.bounds.offset[0],
                        glyph.bounds.offset[1],
                        0,
                    },
                    .size = .{
                        glyph.bounds.size[0],
                        glyph.bounds.size[1],
                        1,
                    },
                },
                .layout = .transfer_dst,
                .subresource = .{
                    .aspect = .{ .color = true },
                },
            });

            info.cmd_encoder.cmdMemoryBarrier(.{
                .image_barriers = &.{.{
                    .image = atlas.image,
                    .subresource_range = .{
                        .aspect = .{ .color = true },
                    },
                    .old_layout = .transfer_dst,
                    .new_layout = .shader_read_only,
                    .src_stage = .{ .transfer = true },
                    .dst_stage = .{},
                    .src_access = .{ .transfer_write = true },
                    .dst_access = .{},
                }},
            });
            atlas.layout = .shader_read_only;

            try loaded.glyphs.put(
                info.alloc,
                info.codepoint,
                glyph,
            );
        }

        fn allocateAtlasSpace(loaded: *Loaded, alloc: std.mem.Allocator, device: gpu.Device, size: gpu.Image.Size2D) !Glyph {
            std.debug.assert(@reduce(.And, loaded.atlas_size >= size));

            if (loaded.next_glyph_start[0] + size[0] > loaded.atlas_size[0]) {
                loaded.next_glyph_start[0] = 0;
                loaded.next_glyph_start[1] += loaded.char_height_px;
            }

            if (loaded.atlases.items.len == 0 or loaded.next_glyph_start[1] + size[1] > loaded.atlas_size[1]) {
                const image = try device.initImage(.{
                    .alloc = alloc,
                    .format = .r8_unorm,
                    .usage = .{ .sampled = true, .dst = true },
                    .size = loaded.atlas_size,
                    .loc = .device,
                });
                errdefer image.deinit(device, alloc);

                const view = try device.initImageView(.{
                    .alloc = alloc,
                    .image = image,
                    .kind = .@"2d",
                    .subresource_range = .{
                        .aspect = .{ .color = true },
                    },
                });
                errdefer view.deinit(device, alloc);

                const sampler = try device.initSampler(.{
                    .alloc = alloc,
                    .min_filter = .linear,
                    .mag_filter = .linear,
                    .address_mode_u = .clamp_to_edge,
                    .address_mode_v = .clamp_to_edge,
                    .address_mode_w = .clamp_to_edge,
                });
                errdefer sampler.deinit(device, alloc);

                try loaded.atlases.append(alloc, .{
                    .image = image,
                    .view = view,
                    .sampler = sampler,
                });

                loaded.next_glyph_start = @splat(0);
            }

            const pos = loaded.next_glyph_start;
            loaded.next_glyph_start[0] += size[0];

            return .{
                .atlas = @intCast(loaded.atlases.items.len - 1),
                .bounds = .{
                    .offset = pos,
                    .size = size,
                },
            };
        }
    };
};
