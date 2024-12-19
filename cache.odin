package tinyren

import array "core:container/small_array"
import "core:mem"
import "core:hash"

CELL_SIZE :: 64

Array :: array.Small_Array

Cache_Cell :: u32

Cell_Buffer :: struct {
	previous: []Cache_Cell,
	display:  []Cache_Cell,
	commands: ^Array(1024 * 8, Command),
	dirty_rects: [dynamic]Rect,

	screen_width: i32,
	screen_height: i32,
}

@private
has_screen_size_changed :: proc(r: Renderer) -> bool {
	return r.width != r.cache.screen_width || r.height != r.cache.screen_height
}

cell_buffer_create :: proc(width, height: i32, allocator := context.allocator) -> (buf: Cell_Buffer, err: mem.Allocator_Error){
	cell_width := mem.align_forward_int(auto_cast width, CELL_SIZE) / CELL_SIZE
	cell_height := mem.align_forward_int(auto_cast height, CELL_SIZE) / CELL_SIZE
	buf.screen_width = width
	buf.screen_height = height

	buf.display = make([]Cache_Cell, cell_width * cell_height, allocator) or_return
	defer if err != nil { delete(buf.display) }
	buf.previous = make([]Cache_Cell, cell_width * cell_height, allocator) or_return
	defer if err != nil { delete(buf.previous) }
	buf.commands = new(type_of(buf.commands^), allocator) or_return

	return
}

cell_buffer_destroy :: proc(buf: ^Cell_Buffer, allocator := context.allocator){
	delete(buf.display, allocator)
	delete(buf.previous, allocator)
	buf.display, buf.previous = nil, nil
}

// hash_command :: proc(current: Cache_Cell, cmd: ^Command) -> Cache_Cell {
// 	switch cmd in cmd {
// 	case Draw_Rect:
// 	case Draw_Image:
// 	case Draw_Text:
// 	case Draw_Text:
// 	}
// }

