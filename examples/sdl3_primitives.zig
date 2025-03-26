const std = @import("std");

const pixelz = @import("pixelz_lib");

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

    var surface_texture = pixelz.Texture{
        .width = @intCast(window_surface.w),
        .height = @intCast(window_surface.h),
        .channels = 4,
        .data = surface_data,
    };

    var some_texture_data: [64]u32 = .{0} ** 64;
    var some_texture = pixelz.Texture{
        .width = 8,
        .height = 8,
        .channels = 4,
        .data = @ptrCast(&some_texture_data),
    };
    var some_texture_colors = some_texture.as_color_slice_mut();
    some_texture_colors[3] = .GREEN;
    some_texture_colors[4] = .GREEN;
    some_texture_colors[10] = .GREEN;
    some_texture_colors[13] = .GREEN;
    some_texture_colors[17] = .GREEN;
    some_texture_colors[22] = .GREEN;
    some_texture_colors[24] = .GREEN;
    some_texture_colors[31] = .GREEN;
    some_texture_colors[32] = .GREEN;
    some_texture_colors[39] = .GREEN;
    some_texture_colors[41] = .GREEN;
    some_texture_colors[46] = .GREEN;
    some_texture_colors[50] = .GREEN;
    some_texture_colors[53] = .GREEN;
    some_texture_colors[59] = .GREEN;
    some_texture_colors[60] = .GREEN;

    const some_texture_rect = pixelz.TextureRect{
        .texture = &some_texture,
        .position = .{},
        .size = .{ .x = 8, .y = 8 },
    };

    var renderer = pixelz.Renderer.init(&surface_texture);

    var t = @as(f32, @floatFromInt(sdl.SDL_GetTicksNS())) / 1000 / 1000;
    var acc: f32 = 0.0;
    var sdl_event: sdl.SDL_Event = undefined;
    while (true) {
        while (sdl.SDL_PollEvent(&sdl_event)) {
            if (sdl_event.type == sdl.SDL_EVENT_QUIT)
                return;
        }

        const now = @as(f32, @floatFromInt(sdl.SDL_GetTicksNS())) / 1000 / 1000;
        const dt = t - now;
        t = now;

        acc += dt;

        renderer.clean();
        renderer.draw_aabb(
            .{
                .min = .{ .x = 20.0, .y = 20.0 },
                .max = .{ .x = 40.0, .y = 40.0 },
            },
            .RED,
        );
        renderer.draw_line(
            .{ .x = 50.0, .y = 50.0 },
            .{ .x = 300.0, .y = 50.0 },
            .ORANGE,
        );
        renderer.draw_line(
            .{ .x = 50.0, .y = 80.0 },
            .{ .x = 300.0, .y = 80.0 },
            .ORANGE,
        );
        renderer.draw_line(
            .{ .x = 50.0, .y = 110.0 },
            .{ .x = 300.0, .y = 110.0 },
            .ORANGE,
        );
        const s = @sin(acc * 0.001);
        renderer.draw_texture(
            .{ .x = 200.0 + s * 50, .y = 200.0 },
            &some_texture_rect,
            null,
            true,
            false,
        );
        renderer.draw_texture_with_size_and_rotation(
            .{ .x = 400.0, .y = 400.0 },
            .{ .x = s * 200.0, .y = s * 200.0 },
            acc * 0.002,
            .{},
            &some_texture_rect,
            .MAGENTA,
            true,
            false,
        );

        _ = sdl.SDL_UpdateWindowSurface(window);
    }
}
