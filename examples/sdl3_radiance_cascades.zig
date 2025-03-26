const std = @import("std");
const Allocator = std.mem.Allocator;

const pixelz = @import("pixelz_lib");
const Vec2 = pixelz.Vec2;
const Color = pixelz.Color;
const Texture = pixelz.Texture;

const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub const WINDOW_WIDTH = 1280;
pub const WINDOW_HEIGHT = 720;

pub fn main() !void {
    if (!sdl.SDL_Init(sdl.SDL_INIT_AUDIO)) {
        std.log.err("Cannot init SDL: {s}", .{sdl.SDL_GetError()});
        return error.SDLInit;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow(
        "pixels_test",
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        0,
    ) orelse {
        std.log.err("Cannot create a window: {s}", .{sdl.SDL_GetError()});
        return error.SDLCreateWindow;
    };
    defer sdl.SDL_DestroyWindow(window);

    const window_surface: *sdl.SDL_Surface = sdl.SDL_GetWindowSurface(window);

    if (!sdl.SDL_ShowWindow(window)) {
        std.log.err("Cannot show a window: {s}", .{sdl.SDL_GetError()});
        return error.SDLShowWindow;
    }

    var surface_data: []align(4) u8 = undefined;
    surface_data.ptr = @alignCast(@ptrCast(window_surface.pixels));
    surface_data.len = @intCast(window_surface.pitch * window_surface.h);
    var surface_texture = Texture{
        .width = @intCast(window_surface.w),
        .height = @intCast(window_surface.h),
        .channels = 4,
        .data = surface_data,
    };
    var renderer = pixelz.Renderer.init(&surface_texture);

    const DebugAllocator = std.heap.DebugAllocator(.{
        .enable_memory_limit = true,
    });
    var debug_alloc = DebugAllocator{};
    var alloc = debug_alloc.allocator();

    const cascades_needed = Cascade.cascades_needed(WINDOW_WIDTH, WINDOW_HEIGHT);
    var cascades: []Cascade = alloc.alloc(Cascade, cascades_needed.n) catch unreachable;
    for (cascades, 0..) |*cascade, level| {
        cascade.* = Cascade.init(
            alloc,
            cascades_needed.width,
            cascades_needed.height,
            @intCast(level),
        ) catch unreachable;
    }

    var circles = [_]Circle{
        .{
            .center = .{
                .x = @as(f32, @floatFromInt(WINDOW_WIDTH)) / 2.0,
                .y = @as(f32, @floatFromInt(WINDOW_HEIGHT)) / 2.0,
            },
            .radius = 25.0,
            .color = Color.ORANGE,
        },
        .{
            .center = .{
                .x = @as(f32, @floatFromInt(WINDOW_WIDTH)) / 2.0,
                .y = @as(f32, @floatFromInt(WINDOW_HEIGHT)) / 2.0 - 100.0,
            },
            .radius = 50.0,
            .color = Color.WHITE,
        },
        .{
            .center = .{
                .x = @as(f32, @floatFromInt(WINDOW_WIDTH)) / 2.0,
                .y = @as(f32, @floatFromInt(WINDOW_HEIGHT)) / 2.0 + 100.0,
            },
            .radius = 30.0,
            .color = Color.BLUE,
        },
        .{
            .center = .{
                .x = @as(f32, @floatFromInt(WINDOW_WIDTH)) / 2.0 + 100.0,
                .y = @as(f32, @floatFromInt(WINDOW_HEIGHT)) / 2.0,
            },
            .radius = 40.0,
            .color = Color.NONE,
        },
    };

    var sdl_event: sdl.SDL_Event = undefined;
    while (true) {
        while (sdl.SDL_PollEvent(&sdl_event)) {
            if (sdl_event.type == sdl.SDL_EVENT_QUIT)
                return;
            if (sdl_event.type == sdl.SDL_EVENT_KEY_DOWN) {
                if (sdl_event.key.scancode == sdl.SDL_SCANCODE_A)
                    circles[0].center.x -= 1.0;
                if (sdl_event.key.scancode == sdl.SDL_SCANCODE_D)
                    circles[0].center.x += 1.0;
                if (sdl_event.key.scancode == sdl.SDL_SCANCODE_W)
                    circles[0].center.y -= 1.0;
                if (sdl_event.key.scancode == sdl.SDL_SCANCODE_S)
                    circles[0].center.y += 1.0;
            }
        }

        // For each cascade level go over all samples and for each angle fill corresponding
        // element in the texture with a sample of the scene.
        for (cascades) |*cascade| {
            cascade.clean();
            cascade.sample(&circles);
        }

        // Merge cascades in reverse order.
        // For each angle in the lower cascade sample find 4 closes angles in the 4
        // closest samples from next cascade and calculate average for those 16 angles.
        for (0..cascades.len - 1) |l| {
            const level: u32 = @intCast(cascades.len - 2 - l);
            const next_cascade = &cascades[level + 1];
            const current_cascade = &cascades[level];
            current_cascade.merge(next_cascade);
        }

        renderer.clean();
        // For each pixel find the sample from cascade_0 it is closest to
        // and use average of values from that sample.
        cascades[0].draw_to_the_texture(renderer.surface_texture);

        _ = sdl.SDL_UpdateWindowSurface(window);
    }
}

const Vec4 = @Vector(4, f32);
fn color_to_vec4(color: *const Color) Vec4 {
    return .{
        @as(f32, @floatFromInt(color.format.r)),
        @as(f32, @floatFromInt(color.format.g)),
        @as(f32, @floatFromInt(color.format.b)),
        @as(f32, @floatFromInt(color.format.a)),
    };
}
fn scalar_to_vec4(v: f32) Vec4 {
    return @splat(v);
}

const Circle = struct {
    center: Vec2,
    radius: f32,
    color: Color,
};

const Cascade = struct {
    data: []Color,
    data_width: u32,
    level: u32,

    point_offset: f32,
    ray_length: f32,
    sample_size: u32,
    samples_per_row: u32,
    samples_per_column: u32,
    level_sample_point_offset: u32,

    // The screen size is `width` and `height`
    // The resolution in ELEMENTS of the level_0 cascade is `width / 2` and `height / 2`
    // BUT the resolution in SAMPLES is HALF again `width / 4` and `height / 4`
    // because 4 ELEMENTS are used for 4 directions
    // For highter cascades the divisor is 16, 64 and so on
    const PIXEL_SIZE = 4;
    const LEVEL_0_INTERVAL = 25.0;

    const Self = @This();

    const CascadesNeedeResult = struct {
        width: u32,
        height: u32,
        n: u32,
    };
    fn cascades_needed(width: u32, height: u32) CascadesNeedeResult {
        const c_width = @divFloor(width, Self.PIXEL_SIZE);
        const c_height = @divFloor(height, Self.PIXEL_SIZE);

        // nuber of cascades is dependent on the screen size
        const diagonal = @sqrt(@as(f32, @floatFromInt(width * width)) +
            @as(f32, @floatFromInt(height * height)));
        const n: u32 =
            @intFromFloat(@ceil(std.math.log(f32, 4, diagonal / Self.LEVEL_0_INTERVAL)));
        return .{
            .width = c_width,
            .height = c_height,
            .n = n,
        };
    }

    fn init(allocator: Allocator, width: u32, height: u32, level: u32) !Self {
        const data = try allocator.alloc(Color, width * height);
        @memset(data, .BLACK);

        // const cascade_level_data = cascade_level_datas[level];
        // For each level the rays have an offset from the center of the sample and
        // a maximum distance the ray samples at. Each level must have 2 times longer ray length
        // and 2 times more granual angular stepping.
        const point_offset = (LEVEL_0_INTERVAL *
            (1.0 - @as(f32, @floatFromInt(std.math.pow(u32, 4, level))))) / -3.0;
        const ray_length = LEVEL_0_INTERVAL *
            @as(f32, @floatFromInt(std.math.pow(u32, 4, level)));
        // The amount of samples can fit in the cascade data layer is inverse proportional to
        // the level;
        // level 0 uses 4 elements (4 angles), so divisor will be 2 (for width and height)
        // level 1 uses 16 enements, so divisor will be 4
        const sample_size = std.math.pow(u32, 2, 1 + level);
        const samples_per_row = width / sample_size;
        const samples_per_column = height / sample_size;
        const level_sample_point_offset = PIXEL_SIZE * std.math.pow(u32, 2, level);

        return .{
            .data = data,
            .data_width = width,
            .level = level,
            .point_offset = point_offset,
            .ray_length = ray_length,
            .sample_size = sample_size,
            .samples_per_row = samples_per_row,
            .samples_per_column = samples_per_column,
            .level_sample_point_offset = level_sample_point_offset,
        };
    }

    fn data_point(
        self: *const Self,
        x: usize,
        y: usize,
        index: usize,
    ) *const Color {
        // elements are stored contigiously in memory
        const ss = self.sample_size * self.sample_size;
        return &self.data[
            x * ss + y * self.samples_per_row * ss + index
        ];
    }

    fn data_point_mut(
        self: *Self,
        x: usize,
        y: usize,
        index: usize,
    ) *Color {
        // elements are stored contigiously in memory
        const ss = self.sample_size * self.sample_size;
        return &self.data[
            x * ss + y * self.samples_per_row * ss + index
        ];
    }

    fn avg_in_direction(
        self: *const Self,
        x: usize,
        y: usize,
        index: usize,
    ) @Vector(4, f32) {
        var avg: @Vector(4, f32) = @splat(0.0);
        var valid: u8 = 0;
        for (index * 4..index * 4 + 4) |i| {
            const p = self.data_point(
                x,
                y,
                i,
            );
            if (p.format.a != 0) {
                const v = color_to_vec4(p);
                avg = avg + v;
                valid += 1;
            }
        }
        if (valid != 0)
            avg = avg * scalar_to_vec4(1.0 / @as(f32, @floatFromInt(valid)));
        return avg;
    }

    fn clean(self: *Self) void {
        @memset(self.data, .BLACK);
    }

    fn sample(self: *Self, circles: []const Circle) void {
        for (0..self.samples_per_column) |y| {
            for (0..self.samples_per_row) |x| {
                const screen_position = Vec2{
                    .x = @floatFromInt(x * Self.PIXEL_SIZE * self.sample_size +
                        self.level_sample_point_offset),
                    .y = @floatFromInt(y * Self.PIXEL_SIZE * self.sample_size +
                        self.level_sample_point_offset),
                };
                // Go over all angles for a sample
                const ss = self.sample_size * self.sample_size;
                for (0..ss) |i| {
                    const cascale_data_point = self.data_point_mut(x, y, i);
                    const ss_f32: f32 = @floatFromInt(ss);
                    const angle = std.math.pi / ss_f32 +
                        @as(f32, @floatFromInt(i)) * std.math.pi / ss_f32 * 2;
                    const ray_direction = Vec2{ .x = @cos(angle), .y = @sin(angle) };
                    const ray_origin = screen_position.add(ray_direction.mul_f32(self.point_offset));
                    for (circles) |circle| {
                        const circle_radius_2 = circle.radius * circle.radius;
                        const to_circle = circle.center.sub(ray_origin);
                        // check if the ray originates within circle
                        if (to_circle.dot(to_circle) <= circle_radius_2) {
                            cascale_data_point.* = circle.color;
                        } else {
                            const t = ray_direction.dot(to_circle);
                            if (0.0 < t) {
                                const distance = @min(t, self.ray_length);
                                const p = ray_origin.add(ray_direction.mul_f32(distance));
                                const p_to_circle = circle.center.sub(p);
                                if (p_to_circle.dot(p_to_circle) <= circle_radius_2) {
                                    cascale_data_point.* = circle.color;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fn merge(noalias current: *Self, noalias next: *const Self) void {
        const color_normalize: f32 = 1.0 / 255.0;
        const w_1 = @as(i32, @intCast(current.samples_per_row - 1));
        const h_1 = @as(i32, @intCast(current.samples_per_column - 1));
        for (0..current.samples_per_column) |y| {
            const y_mix: f32 = if (y % 2 == 0) 0.75 else 0.25;
            for (0..current.samples_per_row) |x| {
                const x_mix: f32 = if (x % 2 == 0) 0.75 else 0.25;

                const x_i32 = @as(i32, @intCast(x));
                const y_i32 = @as(i32, @intCast(y));
                const next_x: u32 = @min(
                    @as(u32, @intCast(@divFloor(@min(x_i32 + 1, w_1), 2))),
                    next.samples_per_row - 1,
                );
                const prev_x: u32 = @intCast(@divFloor(@max(x_i32 - 1, 0), 2));
                const next_y: u32 = @min(
                    @as(u32, @intCast(@divFloor(@min(y_i32 + 1, h_1), 2))),
                    next.samples_per_column - 1,
                );
                const prev_y: u32 = @intCast(@divFloor(@max(y_i32 - 1, 0), 2));

                for (0..current.sample_size * current.sample_size) |i| {
                    const current_p = current.data_point_mut(x, y, i);

                    const p_00 = next.avg_in_direction(prev_x, prev_y, i);
                    const p_01 = next.avg_in_direction(prev_x, next_y, i);
                    const p_10 = next.avg_in_direction(next_x, prev_y, i);
                    const p_11 = next.avg_in_direction(next_x, next_y, i);

                    const p_00_10_mix = p_00 * scalar_to_vec4(x_mix) +
                        p_10 * scalar_to_vec4(1.0 - x_mix);
                    const p_01_11_mix = p_01 * scalar_to_vec4(x_mix) +
                        p_11 * scalar_to_vec4(1.0 - x_mix);
                    const avg_mix = p_00_10_mix * scalar_to_vec4(y_mix) +
                        p_01_11_mix * scalar_to_vec4(1.0 - y_mix);

                    const avg = avg_mix * scalar_to_vec4(color_normalize);
                    // const curr = current_p.to_vec4().mul_f32(color_normalize);

                    var curr = color_to_vec4(current_p);
                    curr *= scalar_to_vec4(color_normalize);

                    const current_color: Color = .{
                        .format = .{
                            .r = @intFromFloat(@min((avg[0] * curr[3] + curr[0]) * 255.0, 255.0)),
                            .g = @intFromFloat(@min((avg[1] * curr[3] + curr[1]) * 255.0, 255.0)),
                            .b = @intFromFloat(@min((avg[2] * curr[3] + curr[2]) * 255.0, 255.0)),
                            .a = @intFromFloat(@min(curr[3] * avg[3], 255.0)),
                        },
                    };
                    current_p.* = current_color;
                }
            }
        }
    }

    fn draw_to_the_texture(self: *const Self, texture: *Texture) void {
        const colors = texture.as_color_slice();
        const px_width = Self.PIXEL_SIZE * self.sample_size;
        const px_heigth = Self.PIXEL_SIZE * self.sample_size;
        for (0..self.samples_per_column) |y| {
            for (0..self.samples_per_row) |x| {
                var r: f32 = 0;
                var g: f32 = 0;
                var b: f32 = 0;
                for (0..4) |i| {
                    const p = self.data_point(
                        x,
                        y,
                        i,
                    );
                    r += @floatFromInt(p.format.r);
                    g += @floatFromInt(p.format.g);
                    b += @floatFromInt(p.format.b);
                }
                r /= 4.0;
                g /= 4.0;
                b /= 4.0;
                const sample_avg_color: Color = .{
                    .format = .{
                        .r = @intFromFloat(r),
                        .g = @intFromFloat(g),
                        .b = @intFromFloat(b),
                        .a = 0,
                    },
                };

                var px_start = x * px_width + y * self.samples_per_row * px_width * px_heigth;
                for (0..px_heigth) |_| {
                    const row = colors[px_start .. px_start + px_width];
                    @memset(row, sample_avg_color);
                    px_start += self.samples_per_row * px_width;
                }
            }
        }
    }
};
