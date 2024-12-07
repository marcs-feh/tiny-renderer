package tinyren

import sdl "vendor:sdl2"
import "core:time"
import "core:mem"
import "core:fmt"

W, H :: 800, 600

Color :: [4]u8

@private
rgb :: proc(r, g, b: u8) -> Color {
	return {b, g, r, 0xff}
}

draw_pixel :: proc(surf: ^sdl.Surface, #any_int x, y: i32, color: Color){
	pixels := transmute([^]u32)surf.pixels
	pixels[x + (y * surf.pitch / 4)] = transmute(u32)color
}

// plotLine(x0, y0, x1, y1)
//     dx = abs(x1 - x0)
//     sx = x0 < x1 ? 1 : -1
//     dy = -abs(y1 - y0)
//     sy = y0 < y1 ? 1 : -1
//     error = dx + dy
//
//     while true
//         plot(x0, y0)
//         if x0 == x1 && y0 == y1 break
//         e2 = 2 * error
//         if e2 >= dy
//             error = error + dy
//             x0 = x0 + sx
//         end if
//         if e2 <= dx
//             error = error + dx
//             y0 = y0 + sy
//         end if
//     end while

draw_line :: proc(surf: ^sdl.Surface, x0, y0, x1, y1: i32, color: Color){
	x0, y0 := x0, y0
	color := transmute(u32)color

	dx : i32 = abs(x1 - x0)
    dy : i32 = -abs(y1 - y0)
    sx : i32 = x0 < x1 ? 1 : -1
    sy : i32 = y0 < y1 ? 1 : -1
    error := dx + dy

	pixels := transmute([^]u32)surf.pixels

	for {
		pixels[x0 + (y0 * surf.pitch / 4)] = color
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
	max_time_per_frame := 16 * time.Millisecond

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
				}
				fmt.println("KEDOWN")
			case .MOUSEMOTION:
				mouse_pos = {event.motion.x, event.motion.y}
				draw_line(surface, 0, 0, mouse_pos.x, mouse_pos.y, rgb(100, 200, 100))
				draw_line(surface, W-1, 0, mouse_pos.x, mouse_pos.y, rgb(100, 100, 200))
				draw_line(surface, W-1, H-1, mouse_pos.x, mouse_pos.y, rgb(200, 100, 100))
				draw_line(surface, 0, H-1, mouse_pos.x, mouse_pos.y, rgb(200, 200, 100))
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
