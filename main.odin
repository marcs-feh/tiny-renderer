package tinyren

import sdl "vendor:sdl2"
import "core:time"
import "core:c"
import "core:mem"
import "core:fmt"

W, H :: 800, 600

Color :: [4]u8

Rect :: struct {
	using pos: [2]i32,
	w, h: i32,
}

Renderer :: struct {
	window: ^sdl.Window,
	surface: ^sdl.Surface,
	width: i32,
	height: i32,
	clip: Rect,
}

Renderer_Error :: enum byte {
	None = 0,
	Argument_Error,
	Invalid_Pixel_Format,
}

renderer_create :: proc(win: ^sdl.Window) -> (rend: Renderer, err: Renderer_Error) {
	if win == nil { return {}, .None }

	rend.window = win
	rend.surface = sdl.GetWindowSurface(win)

	window_size: {
		w, h : c.int
		sdl.GetWindowSize(win, &w, &h)
		rend.width = i32(w)
		rend.height = i32(h)
		rend.clip = { w = rend.width, h = rend.height }
	}

	ok := ((sdl.PixelFormatEnum(rend.surface.format.format) == .RGB888) ||
			(sdl.PixelFormatEnum(rend.surface.format.format) ==.RGBA8888)) &&
		(rend.surface.format.BytesPerPixel == 4)

	if !ok { return {}, .Invalid_Pixel_Format }

	return
}

set_clip :: proc(rend: ^Renderer, rect: Rect){}

@private
rgb :: proc(r, g, b: u8) -> Color {
	return {b, g, r, 0xff}
}

draw_pixel :: proc(rend: Renderer, #any_int x, y: i32, color: Color){
	pixels := transmute([^]u32)rend.surface.pixels
	pixels[x + (y * (rend.surface.pitch / 4))] = transmute(u32)color
}

draw_line :: proc(rend: Renderer, x0, y0, x1, y1: i32, color: Color){
	x0, y0 := x0, y0
	color := transmute(u32)color

	// TODO: Clipping

	dx: i32 = abs(x1 - x0)
    dy: i32 = -abs(y1 - y0)
    sx: i32 = x0 < x1 ? 1 : -1
    sy: i32 = y0 < y1 ? 1 : -1
    error := dx + dy

	pixels := transmute([^]u32)rend.surface.pixels

	for {
		pixels[x0 + (y0 * rend.surface.pitch / 4)] = color
		if x0 == x1 && y0 == y1 { break }

		error2 := 2 * error
		if error2 >= dy {
			error += dy
			x0 += sx
		}

		if error2 <= dx {
			error += dx
			y0 += sy
		}
	}
}

main :: proc(){
	if sdl.Init({ .VIDEO }) < 0{
		panic("Could not initialize SDL")
	}
	defer sdl.Quit()

	window := sdl.CreateWindow("Test Window", sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED, W, H, {})
	if window == nil {
		panic("Failed to create window")
	}
	defer sdl.DestroyWindow(window)

	surface := sdl.GetWindowSurface(window)
	assert(surface.format.format == auto_cast sdl.PixelFormatEnum.RGB888, "Bad pixel format")
	assert(surface.format.BytesPerPixel == 4, "Bad byte pixel size")

	event : sdl.Event
	sdl.ShowWindow(window)

	mouse_pos : [2]i32
	desired_fps :: 60
	max_time_per_frame := (1000 / desired_fps) * time.Millisecond

	rend, ren_err := renderer_create(window)
	if ren_err != .None {
		panic("Failed to create renderer")
	}

	for {
		begin := time.now()
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				fmt.println("bye bye")
				return
			case .KEYDOWN:
				if event.key.keysym.sym == .r {
					mem.set(surface.pixels, 0, auto_cast surface.pitch * H)
				} else if event.key.keysym.sym == .ESCAPE {
					return
				}
			case .MOUSEMOTION:
				mouse_pos = {event.motion.x, event.motion.y}
			}
		}

		sdl.UpdateWindowSurface(window)
		frame_elapsed := time.since(begin)

		remaining := max_time_per_frame - frame_elapsed
		if remaining < 0 {
			fmt.println("FALLING BEHIND")
			continue
		}
		time.sleep(remaining)
	}

}
