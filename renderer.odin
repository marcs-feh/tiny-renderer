package tinyren

import "base:intrinsics"
import "core:time"
import "core:slice"
import "core:mem"
import "core:fmt"
import "core:c"
import sdl "vendor:sdl2"

Color :: distinct [4]u8

Rect :: struct {
	using pos: [2]i32,
	w, h: i32,
}

Clip :: struct {
	left, right, top, bottom: i32,
}

Renderer :: struct {
	window: ^sdl.Window,
	width: i32,
	height: i32,
	clip: Clip,
}

Image :: struct {
	w, h: i32,
	pixels: []Color,
}

Renderer_Error :: enum byte {
	None = 0,
	Argument_Error,
	Invalid_Pixel_Format,
}

update_surface_rects :: proc(rend: Renderer, rects: []Rect){
	sdl.UpdateWindowSurfaceRects(rend.window, transmute([^]sdl.Rect)raw_data(rects), auto_cast len(rects))
}

draw_pixel :: #force_inline proc "contextless" (rend: Renderer, #any_int x, y: i32, color: Color){
	surface := _get_surface(rend)
	pixels := transmute([^]u32)surface.pixels
	pixels[x + (y * (surface.pitch / 4))] = transmute(u32)color
}

@private
_get_surface :: #force_inline proc "contextless" (rend: Renderer) -> ^sdl.Surface{
	return sdl.GetWindowSurface(rend.window)
}

@private
_get_surface_pixels :: #force_inline proc "contextless" (rend: Renderer) -> []Color {
	surf := sdl.GetWindowSurface(rend.window)
	raw_px := transmute([^]Color)surf.pixels
	pixels := raw_px[:surf.w * surf.h]
	return pixels
}

draw_clear :: proc(rend: Renderer, color: Color){
	surface := _get_surface(rend)
	pixels := (transmute([^]u32)surface.pixels)[0:(surface.pitch / 4) * surface.h]
	slice.fill(pixels, transmute(u32)color)
}

draw_image :: proc {
	draw_image_sub,
	draw_image_whole,
}


draw_image_sub :: proc(rend: Renderer, img: Image, x, y: i32, sub: Rect){
	sub, x, y := sub, x, y

	pixels := _get_surface_pixels(rend)
	clip_image: {
		if n := rend.clip.left - x; n > 0 { sub.w -= n; sub.x += n; x += n }
		if n := rend.clip.top - y; n > 0  { sub.h -= n; sub.y += n; y += n }
		if n := x + sub.w - rend.clip.right; n > 0  { sub.w -= n }
		if n := y + sub.h - rend.clip.bottom; n > 0 { sub.h -= n }
	}

	if sub.w <= 0 || sub.h <= 0 { return }

	img_index := sub.x + (sub.y * img.w)
	surf_index := x + (y * rend.width)

	img_row_skip := img.w - sub.w
	surf_row_skip := rend.width - sub.w

	for _ in 0..<sub.h {
		for _ in 0..<sub.w {
			// #no_bounds_check \
			pixels[surf_index] = color_blend(pixels[surf_index], img.pixels[img_index])
			img_index += 1
			surf_index += 1
		}
		img_index += img_row_skip
		surf_index += surf_row_skip
	}
}

draw_image_whole :: proc(rend: Renderer, img: Image, x, y: i32){
	draw_image_sub(rend, img, x, y, Rect{ pos = {0, 0}, w = img.w, h = img.h })
}

draw_rect :: proc(rend: Renderer, rect: Rect, color: Color){
	if color.a == 0 { return } // Fully transparent, no need to draw

	// Clip
	x0 := max(rect.x, rend.clip.left)
	y0 := max(rect.y, rend.clip.top)
	x1 := min(rect.x + rect.w, rend.clip.right)
	y1 := min(rect.y + rect.h, rend.clip.bottom)

	surface := _get_surface(rend)
	pixels := transmute([^]u32)surface.pixels

	 #no_bounds_check draw: {
		 if color.a == 0xff {
			 for y in y0..<y1 {
				 y_off := (y * (surface.pitch / 4))
				 row := pixels[x0 + y_off:x1 + y_off]
				 slice.fill(row, transmute(u32)color)
			 }
		 }
		 else {
			 for y in y0..<y1 {
				 y_off := (y * (surface.pitch / 4))
				 for x in x0..<x1 {
					 blended := color_blend(transmute(Color)pixels[x + y_off], color)
					 pixels[x + y_off] = transmute(u32)blended;
				 }
			 }
		 }
	}
}

renderer_create :: proc(win: ^sdl.Window) -> (rend: Renderer, err: Renderer_Error) {
	if win == nil { return {}, .None }

	rend.window = win
	surface := sdl.GetWindowSurface(win)

	window_size: {
		w, h : c.int
		sdl.GetWindowSize(win, &w, &h)
		rend.width = i32(w)
		rend.height = i32(h)
		rend.clip = { top = 0, bottom = rend.height, left = 0, right = rend.width }
	}

	ok := ((sdl.PixelFormatEnum(surface.format.format) == .RGB888) ||
			(sdl.PixelFormatEnum(surface.format.format) ==.RGBA8888)) &&
		(surface.format.BytesPerPixel == 4)

	if !ok { return {}, .Invalid_Pixel_Format }

	return
}

rect_intersect :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.w, b.x + b.w)
	y1 := min(a.y + a.h, b.y + b.h)
	return { pos = {x0, y0}, w = max(0, x1 - x0), h = max(0, y1 - y0) }
}

rect_merge :: proc(a, b: Rect) -> Rect {
	x0 := min(a.x, b.x)
	y0 := min(a.y, b.y)
	x1 := max(a.x + a.w, b.x + b.w)
	y1 := max(a.y + a.h, b.y + b.h)
	return { pos = {x0, y0}, w = max(0, x1 - x0), h = max(0, y1 - y0) }
}

set_clip :: proc(rend: ^Renderer, rect: Rect){
	rend.clip.left   = rect.x
	rend.clip.right  = rect.x + rect.w
	rend.clip.top    = rect.y
	rend.clip.bottom = rect.y + rect.h
}

reset_clip :: proc(rend: ^Renderer){
	rend.clip = { top = 0, bottom = rend.width, left = 0, right = rend.height }
}

color_blend :: proc(dst, src: Color) -> Color {
	res := dst
	ia := u32(0xff - src.a)
	a  := u32(src.a)

	res.r = u8(((u32(dst.r) * ia) + (u32(src.r) * a)) >> 8)
	res.g = u8(((u32(dst.g) * ia) + (u32(src.g) * a)) >> 8)
	res.b = u8(((u32(dst.b) * ia) + (u32(src.b) * a)) >> 8)
	return res
}

// Ensure that our odin style rect is compatible with SDl's rect
#assert(size_of(Rect) == size_of(sdl.Rect) && align_of(Rect) == align_of(sdl.Rect))
#assert(offset_of(Rect, pos) == offset_of(sdl.Rect, x))
#assert(offset_of(Rect, pos) + size_of(i32) == offset_of(sdl.Rect, y))
#assert(offset_of(Rect, w) == offset_of(sdl.Rect, w))
#assert(offset_of(Rect, h) == offset_of(sdl.Rect, h))

