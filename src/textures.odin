package main

import "core:os"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:encoding/endian"
import gl "vendor:OpenGL"

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

GlTexture :: struct {
	id: u32,
	width: i32,
	height: i32,
}

get_gl_texture :: proc(texture_path: string) -> (texture: GlTexture, ok: bool) {
	bmp := parse_bmp_texture(texture_path) or_return
	defer delete_BitmapTexture(bmp)

	// Checks if number is a power of 2. Useful to check for some types of textures/generate mipmaps
	// is_pow_2 := proc(n: i32) -> bool {
	// 	return (n & (n - 1)) == 0;
	// }

	texture.width = bmp.width
	texture.height = bmp.height

	gl.GenTextures(1, &texture.id)
	gl.BindTexture(gl.TEXTURE_2D, texture.id)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

	// Copied texture to GPU buffer, we can now free memory here
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, texture.width, texture.height, 0, gl.BGR,
		gl.UNSIGNED_BYTE, raw_data(bmp.data))
	gl.GenerateMipmap(gl.TEXTURE_2D)

	// XXX: Unbind texture for next callers?
	gl.BindTexture(gl.TEXTURE_2D, 0)

	ok = true
	return
}

GlTextureID :: distinct u32

GlMaterial :: struct {
	name: string "Material name",
	index: u32 "Material index",

	Ka: Vec3f "Ambient color",
	Kd: Vec3f "Diffuse color",
	Ks: Vec3f "Specular color",
	Ns: f32 "Specular exponent",
	d: f32 "Dissolve", // Also known as "Tr" (1 - dossolve)
	Tf: Vec3f "Transmission filter color",
	Ni: f32 "Index of refraction",
	illum: IlluminationModel "Illumination model",

	// Enum array of texture IDs. If ID is 0, no texture is present.
	textures: [TextureUnit]GlTextureID,
}

// Load all mentionned textures in the materials list into the GPU VRAM
load_texture_data :: proc(materials: map[string]WavefrontMaterial) -> (textures: []GlTexture, gl_materials: []GlMaterial, ok: bool) {
	BitmapTextureAndMaterialName :: struct {
		bmp: BitmapTexture,
		material_name: string,
	}
	bitmaps: map[string]BitmapTextureAndMaterialName
	defer delete(bitmaps)

	for name, mtl in materials {
		if mtl.texture_paths[.Map_Ka] not_in bitmaps do bitmaps[mtl.texture_paths[.Map_Ka]] = {parse_bmp_texture(mtl.texture_paths[.Map_Ka]) or_return, name}
		if mtl.texture_paths[.Map_Kd] not_in bitmaps do bitmaps[mtl.texture_paths[.Map_Kd]] = {parse_bmp_texture(mtl.texture_paths[.Map_Kd]) or_return, name}
		if mtl.texture_paths[.Map_Ks] not_in bitmaps do bitmaps[mtl.texture_paths[.Map_Ks]] = {parse_bmp_texture(mtl.texture_paths[.Map_Ks]) or_return, name}
		if mtl.texture_paths[.Map_Ns] not_in bitmaps do bitmaps[mtl.texture_paths[.Map_Ns]] = {parse_bmp_texture(mtl.texture_paths[.Map_Ns]) or_return, name}
		if mtl.texture_paths[.Map_d] not_in bitmaps do bitmaps[mtl.texture_paths[.Map_d]] = {parse_bmp_texture(mtl.texture_paths[.Map_d]) or_return, name}
		if mtl.texture_paths[.Map_bump] not_in bitmaps do bitmaps[mtl.texture_paths[.Map_bump]] = {parse_bmp_texture(mtl.texture_paths[.Map_bump]) or_return, name}
		if mtl.texture_paths[.Map_disp] not_in bitmaps do bitmaps[mtl.texture_paths[.Map_disp]] = {parse_bmp_texture(mtl.texture_paths[.Map_disp]) or_return, name}
		if mtl.texture_paths[.Decal] not_in bitmaps do bitmaps[mtl.texture_paths[.Decal]] = {parse_bmp_texture(mtl.texture_paths[.Decal]) or_return, name}
	}

	textures = make([]GlTexture, len(bitmaps))
	texture_IDs := make([]u32, len(bitmaps))
	defer delete(texture_IDs)

	gl.GenTextures(i32(len(bitmaps)), raw_data(texture_IDs))

	i :u32 = 0
	for _, &bitmap in bitmaps {
		textures[i].id = texture_IDs[i]
		gl.BindTexture(gl.TEXTURE_2D, textures[i].id)
		// Texture parameters
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
		// Transfer texture to GPU
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, textures[i].width, textures[i].height, 0, gl.BGR,
			gl.UNSIGNED_BYTE, raw_data(bitmap.bmp.data))
		gl.GenerateMipmap(gl.TEXTURE_2D)

		assert(bitmap.material_name in materials)
		current_material := &materials[bitmap.material_name]
		// TODO: Create another material struct that represents a GL material with texture IDs
		// instead of texture paths, and return that struct to be used.
		i += 1
	}
	ok = true
	return
}
