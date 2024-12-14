package tinyren

import sdl "vendor:sdl2"
import "core:time"
import "core:c"
import "core:mem"
import "core:fmt"

W, H :: 800, 600

@private
rgb :: #force_inline proc "contextless"(r, g, b: u8) -> Color {
	return {b, g, r, 0xff}
}

@private
rgba :: #force_inline proc "contextless"(r, g, b, a: u8) -> Color {
	return {b, g, r, a}
}

import "core:image"
import "core:image/png"

pepis :: #load("pepis.png", []byte)

test_image : Image

loadimg :: proc(){
	i, err := image.load_from_bytes(pepis)
	assert(err == nil, "shiet")
	// test_image = i^

	test_image.w = auto_cast i.width
	test_image.h = auto_cast i.height
	test_image.pixels = make([]Color, i.width * i.height)

	assert(i.depth == 8)
	if !image.alpha_add_if_missing(i) {
		panic("damn")
	}

	mem.copy_non_overlapping(raw_data(test_image.pixels), raw_data(i.pixels.buf), i.width * i.height * 4)

	for &px in test_image.pixels {
		px = px.bgra
	}
}

main :: proc(){
	loadimg()
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
		draw_clear(rend, rgb(20, 20, 20))

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

		draw_image(rend, test_image, mouse_pos.x, mouse_pos.y, Rect{{30, 30}, 250, 250})

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

