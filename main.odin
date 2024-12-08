package tinyren

import sdl "vendor:sdl2"
import "core:time"
import "core:c"
import "core:mem"
import "core:fmt"

W, H :: 800, 600

@private
rgb :: proc(r, g, b: u8) -> Color {
	return {b, g, r, 0xff}
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
		draw_clear(rend, rgb(100, 0, 0))
		frame_elapsed := time.since(begin)

		remaining := max_time_per_frame - frame_elapsed
		if remaining < 0 {
			fmt.println("FALLING BEHIND")
			continue
		}
		time.sleep(remaining)
	}
}

