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
main_font :: #load("fonts/noto.ttf", []byte)

test_image : Image

loadimg :: proc(){
	i, err := image.load_from_bytes(pepis)
	assert(err == nil, "shiet")
	defer image.destroy(i)
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
	when ODIN_DEBUG {
		tracker : mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		context.allocator = mem.tracking_allocator(&tracker)

		defer for k, v in tracker.allocation_map {
			fmt.println(k, v)
		}
	}

	loadimg()
	defer image_destroy(&test_image)

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

	font, f_err := font_load(main_font, 23)
	defer font_unload(font)

	assert(f_err == nil)

	rend, ren_err := renderer_create(window)

	if ren_err != .None {
		panic("Failed to create renderer")
	}

	for {
		begin := time.now()
		draw_clear(rend, rgb(60, 60, 60))

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

		draw_text(rend, font, "大切な物を protect my balls", mouse_pos.x, mouse_pos.y + 250, rgb(0xf0, 0x50, 0x40))

		sdl.UpdateWindowSurface(window)
		frame_elapsed := time.since(begin)

		remaining := max_time_per_frame - frame_elapsed
		if remaining < 0 {
			fmt.println("Skipped 1 frame(s)")
			continue
		}
		time.sleep(remaining)
	}
}

