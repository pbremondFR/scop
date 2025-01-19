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

/* === Util wrappers to make quick type punning from raw memory === */
@(private="file")
get_u16le :: #force_inline proc "contextless" (data: []byte) -> u16 {
	return endian.unchecked_get_u16le(data)
}

@(private="file")
get_i16le :: #force_inline proc "contextless" (data: []byte) -> i16 {
	return i16(endian.unchecked_get_u16le(data))
}

@(private="file")
get_u32le :: #force_inline proc "contextless" (data: []byte) -> u32 {
	return endian.unchecked_get_u32le(data)
}

@(private="file")
get_i32le :: #force_inline proc "contextless" (data: []byte) -> i32 {
	return i32(endian.unchecked_get_u32le(data))
}
/* ================================================================ */


parse_bmp_texture :: proc(texture_path: string) -> (texture: BitmapTexture, ok: bool) {
	file_contents, map_err := virtual.map_file_from_path(texture_path, {.Read})
	if map_err != nil {
		fmt.printfln("Failed to open `%v`: %v", texture_path, map_err);
		return
	}
	defer virtual.release(raw_data(file_contents), len(file_contents))

	// Check that file is large enough and that the length in BMP header matches OS file length
	// If file is not large enough, we'd overflow when reading BMP header, so return now
	(len(file_contents) > 0x32) or_return

	// Check if valid BMP file with BITMAPINFOHEADER header (not OS/2)
	(file_contents[0] == 'B' && file_contents[1] == 'M') or_return
	(file_contents[0x0e] >= 40) or_return
	// Check that length of mapped file matches the file size in BMP header
	(cast(int)get_u32le(file_contents[0x02:]) == len(file_contents)) or_return

	// Get BMP data location, width, height, and BPP
	data_offset := get_u32le(file_contents[0x0a:])
	texture.width	= get_i32le(file_contents[0x12:])
	texture.height	= get_i32le(file_contents[0x16:])
	texture.bpp		= get_u16le(file_contents[0x1c:])

	// Error if BMP doesn't have 24 BPP or is not uncompressed
	(texture.bpp == 24) or_return
	compression := get_i32le(file_contents[0x1e:])
	(compression == 0) or_return

	// Alternative (stupider) way of doing this:
	// bmp_data_size := (cast(^u32)mem.ptr_offset(file_data, 0x22))^
	bmp_data_size := get_u32le(file_contents[0x22:])
	// Ensure that BMP raw data size == width * height * (bpp/8)
	(bmp_data_size == 0 \
		|| i32(bmp_data_size) == texture.width * texture.height * i32(texture.bpp / 8)) or_return

	// Allocate and copy to our buffer
	bmp_data := mem.ptr_offset(raw_data(file_contents), data_offset)
	copied_data := make([]byte, bmp_data_size)
	mem.copy_non_overlapping(raw_data(copied_data), bmp_data, int(bmp_data_size))

	// Looks like you can just pass ownership like that, similar to C pointers
	texture.data = copied_data
	ok = true
	return
}
