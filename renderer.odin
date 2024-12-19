package tinyren

import "base:intrinsics"
import "core:time"
import "core:math"
import "core:slice"
import "core:mem"
import "core:fmt"
import "core:c"
import sdl "vendor:sdl2"
import stbtt "vendor:stb/truetype"

GLYPHS_PER_SET :: 256

MAX_GLYPH_SETS :: 256

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
	cache: Cell_Buffer,
}

Image :: struct {
	w, h: i32,
	pixels: []Color,
}

Glyph_Set :: struct {
	bitmap: Image,
	chars: [GLYPHS_PER_SET]stbtt.bakedchar,
}

Font :: struct {
	data: []byte,
	info: stbtt.fontinfo,
	sets: [MAX_GLYPH_SETS]^Glyph_Set,
	height: i32,
	size: f32,
}

Renderer_Error :: enum byte {
	None = 0,
	Argument_Error,
	Invalid_Pixel_Format,
	Memory_Error,
}

Command :: union {
	Draw_Rect,
	Draw_Image,
	Draw_Text,
	Set_Clip,
}

Set_Clip :: struct {
	clip: Rect,
}

Draw_Image :: struct {
	image: Image,
	sub: Rect,
	blend_color: Color,
}

Draw_Rect :: struct {
	rect: Rect,
	color: Color,
}

Draw_Text :: struct {
	text: string,
	font: ^Font,
	pos: [2]i32,
	color: Color,
}

update_surface_rects :: proc(rend: Renderer, rects: []Rect){
	sdl.UpdateWindowSurfaceRects(rend.window, transmute([^]sdl.Rect)raw_data(rects), auto_cast len(rects))
}

// draw_pixel :: #force_inline proc "contextless" (rend: Renderer, #any_int x, y: i32, color: Color){
// 	pixels := _get_surface_pixels(rend)
// 	pixels[x + (y * rend.width)] = color
// }

@private
_get_surface_pixels :: #force_inline proc "contextless" (rend: Renderer) -> []Color {
	surf := sdl.GetWindowSurface(rend.window)
	raw_px := transmute([^]Color)surf.pixels
	pixels := raw_px[:surf.w * surf.h]
	return pixels
}

draw_clear :: proc(rend: Renderer, color: Color){
	pixels := _get_surface_pixels(rend)
	slice.fill(pixels, color)
}

draw_image :: proc {
	draw_image_sub,
	draw_image_no_blend,
	draw_image_whole,
}

draw_image_no_blend :: proc(rend: Renderer, img: Image, x, y: i32, sub: Rect){
	draw_image_sub(rend, img, x, y, Color{0xff, 0xff, 0xff, 0xff}, sub)
}

draw_image_sub :: proc(rend: Renderer, img: Image, x, y: i32, blend_color: Color, sub: Rect){
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
			#no_bounds_check pixels[surf_index] = color_blend2(pixels[surf_index], img.pixels[img_index], blend_color)
			img_index += 1
			surf_index += 1
		}
		img_index += img_row_skip
		surf_index += surf_row_skip
	}
}

draw_image_whole :: proc(rend: Renderer, img: Image, x, y: i32, blend_color: Color){
	draw_image_sub(rend, img, x, y, blend_color, Rect{ pos = {0, 0}, w = img.w, h = img.h })
}

draw_text :: proc(rend: Renderer, font: ^Font, text: string, x, y: i32, color: Color){
	x, y := x, y

	for r in text {
		set, _ := glyphset_get(font, r)
		baked_char := set.chars[r % GLYPHS_PER_SET]
		rect := Rect {
			x = i32(baked_char.x0),
			y = i32(baked_char.y0),
			w = i32(baked_char.x1 - baked_char.x0),
			h = i32(baked_char.y1 - baked_char.y0),
		}
		draw_image(rend, set.bitmap, x + i32(baked_char.xoff), y + i32(baked_char.yoff), color,rect)
		x += i32(baked_char.xadvance)
	}
}

draw_rect :: proc(rend: Renderer, rect: Rect, color: Color){
	if color.a == 0 { return } // Fully transparent, no need to draw

	// Clip
	x0 := max(rect.x, rend.clip.left)
	y0 := max(rect.y, rend.clip.top)
	x1 := min(rect.x + rect.w, rend.clip.right)
	y1 := min(rect.y + rect.h, rend.clip.bottom)

	pixels := _get_surface_pixels(rend)

	 #no_bounds_check draw: {
		 if color.a == 0xff {
			 for y in y0..<y1 {
				 y_off := y * rend.width
				 row := pixels[x0 + y_off:x1 + y_off]
				 slice.fill(row, color)
			 }
		 }
		 else {
			 for y in y0..<y1 {
				 y_off := y * rend.width
				 for x in x0..<x1 {
					 blended := color_blend(pixels[x + y_off], color)
					 pixels[x + y_off] = blended;
				 }
			 }
		 }
	}
}

renderer_create :: proc(win: ^sdl.Window, allocator := context.allocator) -> (rend: Renderer, err: Renderer_Error) {
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
	cache, mem_err := cell_buffer_create(allocator)
	if mem_err != nil {
		return rend, .Memory_Error
	}
	rend.cache = cache

	ok := ((sdl.PixelFormatEnum(surface.format.format) == .RGB888) ||
			(sdl.PixelFormatEnum(surface.format.format) ==.RGBA8888)) &&
		(surface.format.BytesPerPixel == 4)

	if !ok { return {}, .Invalid_Pixel_Format }

	return
}

font_load :: proc(data: []byte, size: f32) -> (font: ^Font, err: mem.Allocator_Error) {
	font = new(Font) or_return
	font.size = size
	font.data = data

	if !stbtt.InitFont(&font.info, raw_data(font.data), 0){
		panic("Failed to init font")
	}

	ascent, descent, linegap : i32
	stbtt.GetFontVMetrics(&font.info, &ascent, &descent, &linegap)
	scale := stbtt.ScaleForMappingEmToPixels(&font.info, size)
	font.height = i32(f32(ascent - descent + linegap) * scale + 0.5)

	// Prevent tab and linefeed from being shown as corrupted chars by making them zero-width
	set, g_err := glyphset_get(font, '\n')
	assert(g_err == nil)

	set.chars['\n'].x1 = set.chars['\n'].x0
	set.chars['\t'].x1 = set.chars['\t'].x0

	return
}

font_unload :: proc(font: ^Font){
	for &set in font.sets {
		if set != nil {
			image_destroy(&set.bitmap)
			free(set)
			set = nil
		}
	}
	free(font)
}

glyphset_get :: proc(font: ^Font, codepoint: rune) -> (set: ^Glyph_Set, err: mem.Allocator_Error){
	pos: i32 = (i32(codepoint) / MAX_GLYPH_SETS) % GLYPHS_PER_SET
	if font.sets[pos] == nil {
		font.sets[pos] = glyphset_load(font, pos) or_return
	}
	return font.sets[pos], nil
}


image_create :: proc(width, height: i32, allocator := context.allocator) -> (img: Image, err: mem.Allocator_Error) {
	pixels := make([]Color, width * height, allocator) or_return
	img.pixels = pixels
	img.w = width
	img.h = height
	return
}


image_destroy :: proc(img: ^Image, allocator := context.allocator){
	delete(img.pixels, allocator)
	img.pixels = nil
}

glyphset_load :: proc(font: ^Font, index: i32) -> (set: ^Glyph_Set, err: mem.Allocator_Error) {
	INITIAL_GLYPHSET_DIMENSIONS :: 128

	width : i32 = INITIAL_GLYPHSET_DIMENSIONS
	height : i32 = INITIAL_GLYPHSET_DIMENSIONS

	set = new(Glyph_Set) or_return
	defer if err != nil { free(set) }


	retry: for {
		set.bitmap = image_create(width, height) or_return

		inv_scale := stbtt.ScaleForMappingEmToPixels(&font.info, 1) / stbtt.ScaleForPixelHeight(&font.info, 1)

		result := stbtt.BakeFontBitmap(
			raw_data(font.data), 0,
			font.size * inv_scale,
			transmute([^]u8)raw_data(set.bitmap.pixels),
			width, height,
			index * MAX_GLYPH_SETS, GLYPHS_PER_SET,
			raw_data(set.chars[:]))

		if result < 0 {
			image_destroy(&set.bitmap)
			width = max(INITIAL_GLYPHSET_DIMENSIONS * 2, (width * 3) / 2)
			height = max(INITIAL_GLYPHSET_DIMENSIONS * 2, (height * 3) / 2)
		}
		else {
			break
		}
	}

	// Ensure proper yoffset and xadvance's
	ascent, descent, linegap : i32
	stbtt.GetFontVMetrics(&font.info, &ascent, &descent, &linegap)
	scale := stbtt.ScaleForMappingEmToPixels(&font.info, font.size)
	scaled_ascent := i32(f32(ascent) * scale + 0.5)
	for &glyph in set.chars {
		glyph.yoff += f32(scaled_ascent)
		glyph.xadvance = math.floor(glyph.xadvance)
	}

	// Convert fro 8bit grayscale to 32bit RGBA
	gray_pixels := (transmute([^]u8)raw_data(set.bitmap.pixels))[:len(set.bitmap.pixels) * size_of(Color)]

	for i := (width * height) - 1; i >= 0; i -= 1 {
		alpha := gray_pixels[i]
		set.bitmap.pixels[i] = rgba(0xff, 0xff, 0xff, alpha)
	}

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

color_blend2 :: proc(dst, src, col: Color) -> Color {
	res := dst
	ia := u32(0xff - src.a)
	a  := (u32(src.a) * u32(col.a)) >> 8

	res.r = u8((((u32(src.r) * u32(col.r) * a)) >> 16) + ((u32(dst.r) * ia) >> 8))
	res.g = u8((((u32(src.g) * u32(col.g) * a)) >> 16) + ((u32(dst.g) * ia) >> 8))
	res.b = u8((((u32(src.b) * u32(col.b) * a)) >> 16) + ((u32(dst.b) * ia) >> 8))
	return res
}

// Ensure that our odin style rect is compatible with SDl's rect SDL_Rect{x, y, w, h: c.int}
#assert(size_of(Rect) == size_of(sdl.Rect) && align_of(Rect) == align_of(sdl.Rect))
#assert(offset_of(Rect, pos) == offset_of(sdl.Rect, x))
#assert(offset_of(Rect, pos) + size_of(i32) == offset_of(sdl.Rect, y))
#assert(offset_of(Rect, w) == offset_of(sdl.Rect, w))
#assert(offset_of(Rect, h) == offset_of(sdl.Rect, h))

// Ensure that the glyph indexing will work
#assert(GLYPHS_PER_SET == 256, "This must be 256")
#assert((MAX_GLYPH_SETS & (MAX_GLYPH_SETS - 1)) == 0, "MAX_GLYPH_SETS must be a power of 2")

