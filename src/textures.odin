package main

import "core:os"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:encoding/endian"

BitmapTexture :: struct {
	width: i32,
	height: i32,
	bpp: u16,
	data: []byte,
}

delete_BitmapTexture :: proc(texture: BitmapTexture) {
	delete(texture.data)
}

// TODO: Some easier to read way of doing all of those "or_return" checks?
// Most of the ones of endian.get_* are unnecessary anyway, we can check the length
// of the file when mapping it, no need for all of these bounds checks
parse_bmp_texture :: proc(texture_path: string) -> (texture: BitmapTexture, ok: bool) {
	file_contents, map_err := virtual.map_file_from_path(texture_path, {.Read})
	if map_err != nil {
		fmt.printfln("Failed to open `%v`: %v", texture_path, map_err);
		return
	}
	defer virtual.release(raw_data(file_contents), len(file_contents))

	// Check if valid BMP file with BITMAPINFOHEADER header (not OS/2)
	(file_contents[0] == 'B' && file_contents[1] == 'M') or_return
	(file_contents[0x0e] >= 40) or_return

	data_offset := endian.get_u32(file_contents[0x0a:], .Little) or_return
	texture.width = endian.get_i32(file_contents[0x12:], .Little) or_return
	texture.height = endian.get_i32(file_contents[0x16:], .Little) or_return
	texture.bpp = endian.get_u16(file_contents[0x1c:], .Little) or_return

	// Error if BMP doesn't have 24 BPP or is not uncompressed
	(texture.bpp == 24) or_return
	compression := endian.get_i32(file_contents[0x1e:], .Little) or_return
	(compression == 0) or_return

	// Alternative (stupider) way of doing this:
	// bmp_data_size := (cast(^u32)mem.ptr_offset(file_data, 0x22))^
	bmp_data_size := endian.get_u32(file_contents[0x22:], .Little) or_return
	(bmp_data_size == 0 \
		|| i32(bmp_data_size) == texture.width * texture.height * i32(texture.bpp / 8)) or_return

	bmp_data := mem.ptr_offset(raw_data(file_contents), data_offset)
	copied_data := make([]byte, bmp_data_size)
	mem.copy_non_overlapping(raw_data(copied_data), bmp_data, int(bmp_data_size))
	// Looks like you can just pass ownership like that, similar to C pointers
	texture.data = copied_data
	ok = true
	return
}
