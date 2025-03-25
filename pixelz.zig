const std = @import("std");
const builtin = @import("builtin");

pub const Texture = struct {
    width: u32 = 0,
    height: u32 = 0,
    channels: u32 = 0,
    data: []align(4) u8 = &.{},

    const Self = @This();

    pub fn as_color_slice(self: *const Self) []Color {
        var slice: []Color = undefined;
        slice.ptr = @alignCast(@ptrCast(self.data.ptr));
        slice.len = self.data.len / 4;
        return slice;
    }

    pub fn as_color_slice_mut(self: *Self) []Color {
        var slice: []Color = undefined;
        slice.ptr = @alignCast(@ptrCast(self.data.ptr));
        slice.len = self.data.len / 4;
        return slice;
    }
};

// Texture rectangle with 0,0 at the top left
pub const TextureRect = struct {
    texture: *const Texture,
    position: Vec2,
    size: Vec2,

    pub fn to_aabb(self: TextureRect) AABB {
        return .{
            .min = .{
                .x = self.position.x,
                .y = self.position.y,
            },
            .max = .{
                .x = self.position.x + self.size.x,
                .y = self.position.y + self.size.y,
            },
        };
    }
};

pub const AABB = struct {
    min: Vec2,
    max: Vec2,

    pub fn is_empty(self: AABB) bool {
        return (self.max.x - self.min.x) == 0.0 and (self.max.y - self.min.y) == 0.0;
    }

    pub fn intersects(self: AABB, other: AABB) bool {
        return !(self.max.x < other.min.x or
            other.max.x < self.min.x or
            other.max.y < self.min.y or
            self.max.y < other.min.y);
    }

    pub fn intersection(self: AABB, other: AABB) AABB {
        return .{
            .min = .{
                .x = @max(self.min.x, other.min.x),
                .y = @max(self.min.y, other.min.y),
            },
            .max = .{
                .x = @min(self.max.x, other.max.x),
                .y = @min(self.max.y, other.max.y),
            },
        };
    }

    pub fn width(self: AABB) f32 {
        return self.max.x - self.min.x;
    }

    pub fn height(self: AABB) f32 {
        return self.max.y - self.min.y;
    }
};

pub const Color = extern struct {
    format: Format = .{},

    // On web the surface format is ABGR
    pub const Format = if (builtin.os.tag == .emscripten)
        extern struct {
            r: u8 = 0,
            g: u8 = 0,
            b: u8 = 0,
            a: u8 = 0,
        }
    else
        // On descktop it is ARGB
        extern struct {
            b: u8 = 0,
            g: u8 = 0,
            r: u8 = 0,
            a: u8 = 0,
        };

    const Self = @This();

    pub const NONE = Self{ .format = .{ .r = 0, .g = 0, .b = 0, .a = 0 } };
    pub const BLACK = Self{ .format = .{ .r = 0, .g = 0, .b = 0, .a = 255 } };
    pub const WHITE = Self{ .format = .{ .r = 255, .g = 255, .b = 255, .a = 255 } };
    pub const RED = Self{ .format = .{ .r = 255, .g = 0, .b = 0, .a = 255 } };
    pub const GREEN = Self{ .format = .{ .r = 0, .g = 255, .b = 0, .a = 255 } };
    pub const GREY = Self{ .format = .{ .r = 69, .g = 69, .b = 69, .a = 255 } };
    pub const MAGENTA = Self{ .format = .{ .r = 255, .g = 0, .b = 255, .a = 255 } };
    pub const ORANGE = Self{ .format = .{ .r = 237, .g = 91, .b = 18, .a = 255 } };
    pub const BLUE = Self{ .format = .{ .r = 0, .g = 0, .b = 255, .a = 255 } };

    pub fn from_parts(r: u8, g: u8, b: u8, a: u8) Self {
        return .{
            .format = .{
                .r = r,
                .g = g,
                .b = b,
                .a = a,
            },
        };
    }

    pub fn abgr_to_argb(self: *Self) void {
        std.mem.swap(u8, &self.format.r, &self.format.b);
    }

    // Mix colors based on the alpha channel. Assumes the RGBA.
    pub fn mix(
        src: Self,
        dst: Self,
        comptime returned_alpha: enum {
            src,
            dst,
            mul,
        },
    ) Self {
        const src_a_f32 = @as(f32, @floatFromInt(src.format.a)) / 255.0;
        const c1 = src_a_f32;
        const c2 = 1.0 - src_a_f32;

        const s_r: f32 = @floatFromInt(src.format.r);
        const s_g: f32 = @floatFromInt(src.format.g);
        const s_b: f32 = @floatFromInt(src.format.b);

        const d_r: f32 = @floatFromInt(dst.format.r);
        const d_g: f32 = @floatFromInt(dst.format.g);
        const d_b: f32 = @floatFromInt(dst.format.b);

        const r = s_r * c1 + d_r * c2;
        const g = s_g * c1 + d_g * c2;
        const b = s_b * c1 + d_b * c2;

        const r_u8 = @as(u8, @intFromFloat(r));
        const g_u8 = @as(u8, @intFromFloat(g));
        const b_u8 = @as(u8, @intFromFloat(b));

        switch (returned_alpha) {
            .src => {
                return .{
                    .format = .{
                        .r = r_u8,
                        .g = g_u8,
                        .b = b_u8,
                        .a = src.format.a,
                    },
                };
            },
            .dst => {
                return .{
                    .format = .{
                        .r = r_u8,
                        .g = g_u8,
                        .b = b_u8,
                        .a = dst.format.a,
                    },
                };
            },
            .mul => {
                const dst_a_f32 = @as(f32, @floatFromInt(dst.format.a)) / 255.0;
                const mul_alpha: u8 = @intFromFloat(src_a_f32 * dst_a_f32 * 255.0);
                return .{
                    .format = .{
                        .r = r_u8,
                        .g = g_u8,
                        .b = b_u8,
                        .a = mul_alpha,
                    },
                };
            },
        }
    }
};

pub const Vec2 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub const X: Vec2 = .{ .x = 1.0, .y = 0.0 };
    pub const NEG_X: Vec2 = .{ .x = -1.0, .y = 0.0 };
    pub const Y: Vec2 = .{ .x = 0.0, .y = 1.0 };
    pub const NEG_Y: Vec2 = .{ .x = 0.0, .y = -1.0 };

    pub inline fn add(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    pub inline fn sub(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub inline fn neg(self: Vec2) Vec2 {
        return .{
            .x = -self.x,
            .y = -self.y,
        };
    }

    pub inline fn mul_f32(self: Vec2, v: f32) Vec2 {
        return .{
            .x = self.x * v,
            .y = self.y * v,
        };
    }

    pub inline fn div(self: Vec2, other: Vec2) Vec2 {
        return .{
            .x = self.x / other.x,
            .y = self.y / other.y,
        };
    }

    pub inline fn div_f32(self: Vec2, v: f32) Vec2 {
        return .{
            .x = self.x / v,
            .y = self.y / v,
        };
    }

    pub inline fn dot(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub inline fn perp(self: Vec2) Vec2 {
        return .{
            .x = -self.y,
            .y = self.x,
        };
    }
};

pub const Renderer = struct {
    surface_texture: *Texture,

    const Self = @This();

    pub fn init(
        surface_texture: *Texture,
    ) Self {
        return .{ .surface_texture = surface_texture };
    }

    pub fn clean(self: *const Self) void {
        @memset(self.surface_texture.data, 0);
    }

    pub fn as_texture_rect(self: *const Self) TextureRect {
        return .{
            .texture = self.surface_texture,
            .position = .{},
            .size = .{
                .x = @floatFromInt(self.surface_texture.width),
                .y = @floatFromInt(self.surface_texture.height),
            },
        };
    }

    pub fn draw_line(self: *Self, point_a: Vec2, point_b: Vec2, color: Color) void {
        const steps = @max(@abs(point_a.x - point_b.x), @abs(point_a.y - point_b.y));
        const steps_u32: u32 = @intFromFloat(steps);

        const delta = point_b.sub(point_a).div_f32(steps);

        const dst_pitch = self.surface_texture.width;
        const dst_data_color = self.surface_texture.as_color_slice();

        const surface_width = @as(f32, @floatFromInt(self.surface_texture.width)) - 1;
        const surface_height = @as(f32, @floatFromInt(self.surface_texture.height)) - 1;

        for (0..steps_u32) |s| {
            const point = point_a.add(delta.mul_f32(@floatFromInt(s)));

            if (point.x < 0.0 or
                surface_width < point.x or
                point.y < 0.0 or
                surface_height < point.y)
            {
                continue;
            }

            const point_x: u32 = @intFromFloat(@floor(point.x));
            const point_y: u32 = @intFromFloat(@floor(point.y));
            dst_data_color[point_x + point_y * dst_pitch] = color;
        }
    }

    pub fn draw_aabb(self: *Self, aabb: AABB, color: Color) void {
        const self_rect = self.as_texture_rect();
        const self_aabb = self_rect.to_aabb();

        if (!self_aabb.intersects(aabb)) {
            return;
        }

        const intersection = self_aabb.intersection(aabb);
        const width: u32 = @intFromFloat(intersection.width());
        const height: u32 = @intFromFloat(intersection.height());

        if (height == 0 or width == 0) {
            return;
        }

        const draw_top = intersection.max.y <= aabb.max.y;
        const draw_bot = aabb.max.y <= intersection.max.y;
        const draw_left = intersection.min.x <= aabb.min.x;
        const draw_right = aabb.max.x <= intersection.max.x;

        const dst_pitch = self.surface_texture.width;
        const dst_start_x: u32 = @intFromFloat(intersection.min.x);
        const dst_start_y: u32 = @intFromFloat(intersection.min.y);
        var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
        const dst_data_color = self.surface_texture.as_color_slice();

        if (draw_top)
            @memset(
                dst_data_color[dst_data_start .. dst_data_start + width],
                color,
            );
        if (draw_bot) {
            const dst_start = dst_data_start + (height - 1) * dst_pitch;
            @memset(
                dst_data_color[dst_start .. dst_start + width],
                color,
            );
        }

        for (0..height) |_| {
            if (draw_left)
                dst_data_color[dst_data_start] = color;
            if (draw_right)
                dst_data_color[dst_data_start + width - 1] = color;
            dst_data_start += dst_pitch;
        }
    }

    pub fn draw_texture(
        self: *Self,
        position: Vec2,
        texture_rect: *const TextureRect,
        tint: ?Color,
        no_alpha_blend: bool,
        draw_aabb_outline: bool,
    ) void {
        if (texture_rect.texture.channels == 4) {
            if (tint) |t| {
                const SrcData = struct {
                    color: []const Color,
                    tint: Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        return this.tint.mix(this.color[offset], .dst);
                    }
                };
                const src_data: SrcData = .{
                    .color = texture_rect.texture.as_color_slice(),
                    .tint = t,
                };
                self.draw_texture_inner(
                    position,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            } else {
                const SrcData = struct {
                    color: []const Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        return this.color[offset];
                    }
                };
                const src_data: SrcData = .{
                    .color = texture_rect.texture.as_color_slice(),
                };
                self.draw_texture_inner(
                    position,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            }
        } else if (texture_rect.texture.channels == 1) {
            if (tint) |t| {
                const SrcData = struct {
                    bytes: []const u8,
                    tint: Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        const b = this.bytes[offset];
                        return this.tint.mix(
                            .{ .format = .{ .r = b, .g = b, .b = b, .a = b } },
                            .dst,
                        );
                    }
                };
                const src_data: SrcData = .{
                    .bytes = texture_rect.texture.data,
                    .tint = t,
                };
                self.draw_texture_inner(
                    position,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            } else {
                const SrcData = struct {
                    bytes: []const u8,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        const b = this.bytes[offset];
                        return .{ .format = .{ .r = b, .g = b, .b = b, .a = b } };
                    }
                };
                const src_data: SrcData = .{
                    .bytes = texture_rect.texture.data,
                };
                self.draw_texture_inner(
                    position,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            }
        } else {
            std.log.warn(
                "Skipping drawing texture as channel numbers are incopatible: self: {}, texture: {}",
                .{ self.surface_texture.channels, texture_rect.texture.channels },
            );
        }
    }

    fn draw_texture_inner(
        self: *Self,
        position: Vec2,
        texture_rect: *const TextureRect,
        no_alpha_blend: bool,
        draw_aabb_outline: bool,
        src_data: anytype,
    ) void {
        const self_rect = self.as_texture_rect();
        const self_aabb = self_rect.to_aabb();
        // Positon is the center of the destination
        const dst_rect: TextureRect = .{
            .texture = undefined,
            .position = position.sub(texture_rect.size.mul_f32(0.5)),
            .size = texture_rect.size,
        };
        const dst_aabb = dst_rect.to_aabb();

        if (!self_aabb.intersects(dst_aabb)) {
            return;
        }

        const intersection = self_aabb.intersection(dst_aabb);
        const width: u32 = @intFromFloat(intersection.width());
        const height: u32 = @intFromFloat(intersection.height());

        if (height == 0 or width == 0) {
            return;
        }

        if (draw_aabb_outline)
            self.draw_aabb(intersection, Color.RED);

        const dst_pitch = self.surface_texture.width;
        const src_pitch = texture_rect.texture.width;

        const dst_start_x: u32 = @intFromFloat(intersection.min.x);
        const dst_start_y: u32 = @intFromFloat(intersection.min.y);
        const src_start_x: u32 =
            @intFromFloat(texture_rect.position.x + intersection.min.x - dst_aabb.min.x);
        const src_start_y: u32 =
            @intFromFloat(texture_rect.position.y + intersection.min.y - dst_aabb.min.y);

        var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
        var src_data_start = src_start_x + src_start_y * src_pitch;

        const dst_data_color = self.surface_texture.as_color_slice();
        if (no_alpha_blend) {
            for (0..height) |_| {
                for (0..width) |x| {
                    const src = src_data.get_src(src_data_start + @as(u32, @intCast(x)));
                    const dst = &dst_data_color[dst_data_start + x];
                    dst.* = src;
                }
                dst_data_start += dst_pitch;
                src_data_start += src_pitch;
            }
        } else {
            for (0..height) |_| {
                for (0..width) |x| {
                    const src = src_data.get_src(src_data_start + @as(u32, @intCast(x)));
                    const dst = &dst_data_color[dst_data_start + x];
                    dst.* = src.mix(dst.*, .dst);
                }
                dst_data_start += dst_pitch;
                src_data_start += src_pitch;
            }
        }
    }

    // Draws a texture into a target rect with center at `position` with `size`.
    pub fn draw_texture_with_size_and_rotation(
        self: *Self,
        position: Vec2,
        size: Vec2,
        rotation: f32,
        rotation_offset: Vec2,
        texture_rect: *const TextureRect,
        tint: ?Color,
        no_alpha_blend: bool,
        draw_aabb_outline: bool,
    ) void {
        if (texture_rect.texture.channels == 4) {
            if (tint) |t| {
                const SrcData = struct {
                    color: []const Color,
                    tint: Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        return this.tint.mix(this.color[offset], .dst);
                    }
                };
                const src_data: SrcData = .{
                    .color = texture_rect.texture.as_color_slice(),
                    .tint = t,
                };
                self.draw_texture_with_size_and_rotation_inner(
                    position,
                    size,
                    rotation,
                    rotation_offset,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            } else {
                const SrcData = struct {
                    color: []const Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        return this.color[offset];
                    }
                };
                const src_data: SrcData = .{
                    .color = texture_rect.texture.as_color_slice(),
                };
                self.draw_texture_with_size_and_rotation_inner(
                    position,
                    size,
                    rotation,
                    rotation_offset,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            }
        } else if (texture_rect.texture.channels == 1) {
            if (tint) |t| {
                const SrcData = struct {
                    bytes: []const u8,
                    tint: Color,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        const b = this.bytes[offset];
                        return this.tint.mix(
                            .{ .format = .{ .r = b, .g = b, .b = b, .a = b } },
                            .dst,
                        );
                    }
                };
                const src_data: SrcData = .{
                    .bytes = texture_rect.texture.data,
                    .tint = t,
                };
                self.draw_texture_with_size_and_rotation_inner(
                    position,
                    size,
                    rotation,
                    rotation_offset,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            } else {
                const SrcData = struct {
                    bytes: []const u8,
                    pub fn get_src(this: @This(), offset: u32) Color {
                        const b = this.bytes[offset];
                        return .{ .format = .{ .r = b, .g = b, .b = b, .a = b } };
                    }
                };
                const src_data: SrcData = .{
                    .bytes = texture_rect.texture.data,
                };
                self.draw_texture_with_size_and_rotation_inner(
                    position,
                    size,
                    rotation,
                    rotation_offset,
                    texture_rect,
                    no_alpha_blend,
                    draw_aabb_outline,
                    src_data,
                );
            }
        } else {
            std.log.warn(
                "Skipping drawing texture as channel numbers are incopatible: self: {}, texture: {}",
                .{ self.surface_texture.channels, texture_rect.texture.channels },
            );
        }
    }

    fn draw_texture_with_size_and_rotation_inner(
        self: *Self,
        position: Vec2,
        size: Vec2,
        rotation: f32,
        rotation_offset: Vec2,
        texture_rect: *const TextureRect,
        no_alpha_blend: bool,
        draw_aabb_outline: bool,
        src_data: anytype,
    ) void {
        const c = @cos(-rotation);
        const s = @sin(-rotation);
        const new_position = position.add(rotation_offset).add(
            Vec2{
                .x = c * -rotation_offset.x - s * -rotation_offset.y,
                .y = s * -rotation_offset.x + c * -rotation_offset.y,
            },
        );
        const x_axis = (Vec2{ .x = c, .y = s });
        const y_axis = (Vec2{ .x = s, .y = -c });

        const half_x = size.x / 2.0;
        const half_y = size.y / 2.0;
        const x_offset = x_axis.mul_f32(half_x);
        const y_offset = y_axis.mul_f32(half_y);
        const p_a = new_position.add(x_offset.neg()).add(y_offset.neg());
        const p_b = new_position.add(x_offset).add(y_offset.neg());
        const p_c = new_position.add(x_offset.neg()).add(y_offset);
        const p_d = new_position.add(x_offset).add(y_offset);

        const dst_aabb = AABB{
            .min = .{
                .x = @min(@min(p_a.x, p_b.x), @min(p_c.x, p_d.x)),
                .y = @min(@min(p_a.y, p_b.y), @min(p_c.y, p_d.y)),
            },
            .max = .{
                .x = @max(@max(p_a.x, p_b.x), @max(p_c.x, p_d.x)),
                .y = @max(@max(p_a.y, p_b.y), @max(p_c.y, p_d.y)),
            },
        };

        const self_rect = self.as_texture_rect();
        const self_aabb = self_rect.to_aabb();

        if (!self_aabb.intersects(dst_aabb)) {
            return;
        }

        const intersection = self_aabb.intersection(dst_aabb);
        const width: u32 = @intFromFloat(intersection.width());
        const height: u32 = @intFromFloat(intersection.height());

        if (height == 0 or width == 0) {
            return;
        }

        if (draw_aabb_outline)
            self.draw_aabb(intersection, Color.RED);

        const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
        const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));
        const src_start_x: u32 = @intFromFloat(@round(texture_rect.position.x));
        const src_start_y: u32 = @intFromFloat(@round(texture_rect.position.y));

        const ab = p_b.sub(p_a).perp();
        const bd = p_d.sub(p_b).perp();
        const dc = p_c.sub(p_d).perp();
        const ca = p_a.sub(p_c).perp();

        const scale: Vec2 = texture_rect.size.div(size);
        const texture_width: i32 = @intFromFloat(@floor(texture_rect.size.x));
        const texture_height: i32 = @intFromFloat(@floor(texture_rect.size.y));

        const dst_pitch = self.surface_texture.width;
        const src_pitch = texture_rect.texture.width;
        var dst_data_start = dst_start_x + dst_start_y * dst_pitch;
        const src_data_start = src_start_x + src_start_y * src_pitch;

        const dst_data_u32 = self.surface_texture.as_color_slice();

        if (no_alpha_blend) {
            for (0..height) |y| {
                for (0..width) |x| {
                    const p: Vec2 = .{
                        .x = intersection.min.x + @as(f32, @floatFromInt(x)),
                        .y = intersection.min.y + @as(f32, @floatFromInt(y)),
                    };
                    const ap = p.sub(p_a);
                    const bp = p.sub(p_b);
                    const dp = p.sub(p_d);
                    const cp = p.sub(p_c);

                    const ab_test = ab.dot(ap);
                    const bd_test = bd.dot(bp);
                    const dc_test = dc.dot(dp);
                    const ca_test = ca.dot(cp);

                    if (ab_test < 0.0 and bd_test < 0.0 and dc_test < 0.0 and ca_test < 0.0) {
                        var u_i32: i32 = @intFromFloat(@floor(ap.dot(x_axis)) * scale.x);
                        var v_i32: i32 = @intFromFloat(@floor(ap.dot(y_axis)) * scale.y);
                        u_i32 = @min(@max(0, u_i32), texture_width - 1);
                        v_i32 = @min(@max(0, v_i32), texture_height - 1);

                        const u: u32 = @intCast(u_i32);
                        const v: u32 = @as(u32, @intCast(texture_height - 1)) -
                            @as(u32, @intCast(v_i32));

                        const src = src_data.get_src(src_data_start +
                            u +
                            v * src_pitch);
                        const dst = &dst_data_u32[dst_data_start + x];
                        dst.* = src;
                    }
                }
                dst_data_start += dst_pitch;
            }
        } else {
            for (0..height) |y| {
                for (0..width) |x| {
                    const p: Vec2 = .{
                        .x = intersection.min.x + @as(f32, @floatFromInt(x)),
                        .y = intersection.min.y + @as(f32, @floatFromInt(y)),
                    };
                    const ap = p.sub(p_a);
                    const bp = p.sub(p_b);
                    const dp = p.sub(p_d);
                    const cp = p.sub(p_c);

                    const ab_test = ab.dot(ap);
                    const bd_test = bd.dot(bp);
                    const dc_test = dc.dot(dp);
                    const ca_test = ca.dot(cp);

                    if (ab_test < 0.0 and bd_test < 0.0 and dc_test < 0.0 and ca_test < 0.0) {
                        var u_i32: i32 = @intFromFloat(@floor(ap.dot(x_axis)) * scale.x);
                        var v_i32: i32 = @intFromFloat(@floor(ap.dot(y_axis)) * scale.y);
                        u_i32 = @min(@max(0, u_i32), texture_width - 1);
                        v_i32 = @min(@max(0, v_i32), texture_height - 1);

                        const u: u32 = @intCast(u_i32);
                        const v: u32 = @as(u32, @intCast(texture_height - 1)) -
                            @as(u32, @intCast(v_i32));

                        const src = src_data.get_src(src_data_start +
                            u +
                            v * src_pitch);
                        const dst = &dst_data_u32[dst_data_start + x];
                        dst.* = src.mix(dst.*, .dst);
                    }
                }
                dst_data_start += dst_pitch;
            }
        }
    }

    pub fn draw_color_rect(
        self: *Self,
        position: Vec2,
        size: Vec2,
        color: Color,
        no_alpha_blend: bool,
        draw_aabb_outline: bool,
    ) void {
        const x_axis = Vec2.X.mul_f32(size.x / 2.0);
        const y_axis = Vec2.NEG_Y.mul_f32(size.y / 2.0);

        const p_a = position.add(x_axis.neg()).add(y_axis.neg());
        const p_b = position.add(x_axis).add(y_axis.neg());
        const p_c = position.add(x_axis.neg()).add(y_axis);
        const p_d = position.add(x_axis).add(y_axis);

        const dst_aabb = AABB{
            .min = .{
                .x = @min(@min(p_a.x, p_b.x), @min(p_c.x, p_d.x)),
                .y = @min(@min(p_a.y, p_b.y), @min(p_c.y, p_d.y)),
            },
            .max = .{
                .x = @max(@max(p_a.x, p_b.x), @max(p_c.x, p_d.x)),
                .y = @max(@max(p_a.y, p_b.y), @max(p_c.y, p_d.y)),
            },
        };

        const self_rect = self.as_texture_rect();
        const self_aabb = self_rect.to_aabb();

        if (!self_aabb.intersects(dst_aabb)) {
            return;
        }

        const intersection = self_aabb.intersection(dst_aabb);
        const width: u32 = @intFromFloat(intersection.width());
        const height: u32 = @intFromFloat(intersection.height());

        if (height == 0 or width == 0) {
            return;
        }

        if (draw_aabb_outline)
            self.draw_aabb(intersection, Color.RED);

        const dst_pitch = self.surface_texture.width;

        const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
        const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));

        var dst_data_start = dst_start_x + dst_start_y * dst_pitch;

        const dst_data_color = self.surface_texture.as_color_slice();
        if (color.format.a == 255 or no_alpha_blend) {
            for (0..height) |_| {
                const data_slice = dst_data_color[dst_data_start .. dst_data_start + width];
                @memset(data_slice, color);
                dst_data_start += dst_pitch;
            }
        } else {
            for (0..height) |_| {
                for (0..width) |x| {
                    const dst = &dst_data_color[dst_data_start + x];
                    dst.* = color.mix(dst.*, .dst);
                }
                dst_data_start += dst_pitch;
            }
        }
    }

    pub fn draw_color_rect_with_size_and_rotation(
        self: *Self,
        position: Vec2,
        size: Vec2,
        rotation: f32,
        rotation_offset: Vec2,
        color: Color,
        no_alpha_blend: bool,
        draw_aabb_outline: bool,
    ) void {
        if (color.format.a == 255 or no_alpha_blend) {
            const SrcData = struct {
                color: Color,
                pub fn get_src(this: @This(), dst: Color) Color {
                    _ = dst;
                    return this.color;
                }
            };
            const src_data: SrcData = .{
                .color = color,
            };
            self.draw_color_rect_with_size_and_rotation_inner(
                position,
                size,
                rotation,
                rotation_offset,
                draw_aabb_outline,
                src_data,
            );
        } else {
            const SrcData = struct {
                color: Color,
                pub fn get_src(this: @This(), dst: Color) Color {
                    return this.color.mix(dst, .dst);
                }
            };
            const src_data: SrcData = .{
                .color = color,
            };
            self.draw_color_rect_with_size_and_rotation_inner(
                position,
                size,
                rotation,
                rotation_offset,
                draw_aabb_outline,
                src_data,
            );
        }
    }

    fn draw_color_rect_with_size_and_rotation_inner(
        self: *Self,
        position: Vec2,
        size: Vec2,
        rotation: f32,
        rotation_offset: Vec2,
        draw_aabb_outline: bool,
        src_data: anytype,
    ) void {
        const c = @cos(-rotation);
        const s = @sin(-rotation);
        const new_position = position.add(rotation_offset).add(
            Vec2{
                .x = c * -rotation_offset.x - s * -rotation_offset.y,
                .y = s * -rotation_offset.x + c * -rotation_offset.y,
            },
        );
        const x_axis = (Vec2{ .x = c, .y = s }).mul_f32(size.x / 2.0);
        const y_axis = (Vec2{ .x = s, .y = -c }).mul_f32(size.y / 2.0);

        const p_a = new_position.add(x_axis.neg()).add(y_axis.neg());
        const p_b = new_position.add(x_axis).add(y_axis.neg());
        const p_c = new_position.add(x_axis.neg()).add(y_axis);
        const p_d = new_position.add(x_axis).add(y_axis);

        const dst_aabb = AABB{
            .min = .{
                .x = @min(@min(p_a.x, p_b.x), @min(p_c.x, p_d.x)),
                .y = @min(@min(p_a.y, p_b.y), @min(p_c.y, p_d.y)),
            },
            .max = .{
                .x = @max(@max(p_a.x, p_b.x), @max(p_c.x, p_d.x)),
                .y = @max(@max(p_a.y, p_b.y), @max(p_c.y, p_d.y)),
            },
        };

        const self_rect = self.as_texture_rect();
        const self_aabb = self_rect.to_aabb();

        if (!self_aabb.intersects(dst_aabb)) {
            return;
        }

        const intersection = self_aabb.intersection(dst_aabb);
        const width: u32 = @intFromFloat(intersection.width());
        const height: u32 = @intFromFloat(intersection.height());

        if (height == 0 or width == 0) {
            return;
        }

        if (draw_aabb_outline)
            self.draw_aabb(intersection, Color.RED);

        const dst_pitch = self.surface_texture.width;

        const dst_start_x: u32 = @intFromFloat(@round(intersection.min.x));
        const dst_start_y: u32 = @intFromFloat(@round(intersection.min.y));

        var dst_data_start = dst_start_x + dst_start_y * dst_pitch;

        const ab = p_b.sub(p_a).perp();
        const bd = p_d.sub(p_b).perp();
        const dc = p_c.sub(p_d).perp();
        const ca = p_a.sub(p_c).perp();

        const dst_data_color = self.surface_texture.as_color_slice();
        for (0..height) |y| {
            for (0..width) |x| {
                const p: Vec2 = .{
                    .x = intersection.min.x + @as(f32, @floatFromInt(x)),
                    .y = intersection.min.y + @as(f32, @floatFromInt(y)),
                };
                const ap = p.sub(p_a);
                const bp = p.sub(p_b);
                const dp = p.sub(p_d);
                const cp = p.sub(p_c);

                const ab_test = ab.dot(ap);
                const bd_test = bd.dot(bp);
                const dc_test = dc.dot(dp);
                const ca_test = ca.dot(cp);

                if (ab_test < 0.0 and bd_test < 0.0 and dc_test < 0.0 and ca_test < 0.0) {
                    const dst = &dst_data_color[dst_data_start + x];
                    dst.* = src_data.get_src(dst.*);
                }
            }
            dst_data_start += dst_pitch;
        }
    }
};
