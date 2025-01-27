package main

import "core:os"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:encoding/endian"
import "core:strings"
import "core:path/filepath"
import "base:runtime"
import gl "vendor:OpenGL"
// TODO: Somehow conditionnaly import with feature flag, define, or something like that
import "core:image/png"
import "core:image/bmp"
import "core:image"

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

/*
 * For bonuses and testing purposes, as I'm using Odin's standard library to be able to load PNGs
 * in addition to BMPs.
 */
parse_any_texture_bonus :: proc(texture_path: string) -> (texture: BitmapTexture, ok: bool) {
	img, load_err := image.load_from_file(texture_path)
	if load_err == .Unable_To_Read_File {
		// Load "missing" texture
		img, load_err = image.load_from_file("resources/pbremond.bmp")
	}
	if load_err != nil {
		fmt.printfln("Failed to load texture `%v': %v", texture_path, load_err)
		return
	}
	defer image.destroy(img)

	texture.data = make([]byte, len(img.pixels.buf))
	image.alpha_drop_if_present(img)

	num_pixels := len(img.pixels.buf) / 3
	assert(num_pixels == img.width * img.height)

	for i in 0..<img.height {
		dest := mem.ptr_offset(raw_data(texture.data), img.width * 3 * (img.height - i))
		src := mem.ptr_offset(raw_data(img.pixels.buf), img.width * 3 * i)
		mem.copy_non_overlapping(dest, src, img.width * 3)
	}

	texture.width = i32(img.width)
	texture.height = i32(img.height)
	texture.bpp = 32
	ok = true
	return
}

parse_bmp_texture :: proc(texture_path: string) -> (texture: BitmapTexture, ok: bool) {
	if !strings.ends_with(texture_path, ".bmp") && !strings.ends_with(texture_path, ".dib") {
		fmt.printfln("`%v': Only Windows Bitmap files are allowed", texture_path)
		return
	}
	file_contents, map_err := virtual.map_file_from_path(texture_path, {.Read})
	if map_err != nil {
		file_contents, map_err = virtual.map_file_from_path("resources/pbremond.bmp", {.Read})
	}
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

/*
 * Get a single OpenGL texture (just an identifier with width & height info) from a texture path. Only accepts BMP.
 */
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

/*
 * Take as input list of wavefront materials, load all of the required textures in the GPU VRAM,
 * and return a new map of materials, which describe a material in OpenGL instead of Wavefront format.
 */
load_textures_from_wavefront_materials :: proc(materials: map[string]WavefrontMaterial, root_dir: string) -> (gl_textures: []GlTextureID, gl_materials: map[string]GlMaterial, ok: bool) {
	BitmapTextureAndMaterialName :: struct {
		bmp: BitmapTexture,
		gl_texture: GlTextureID,
	}
	// Associate a certain texture file name with a bitmap texture
	bitmaps: map[string]BitmapTextureAndMaterialName
	defer {
		for _, &bitmap in bitmaps do delete_BitmapTexture(bitmap.bmp)
		delete(bitmaps)
	}
	temp_guard := runtime.default_temp_allocator_temp_begin()
	defer runtime.default_temp_allocator_temp_end(temp_guard)

	// Open and load all bitmap textures present in materials list. If texture is already loaded, skip it.
	// Each loaded texture is mapped with its name from the .mtl file.
	for material_name, mtl in materials {
		for texture_unit in TextureUnit {
			if len(mtl.texture_paths[texture_unit]) == 0 || mtl.texture_paths[texture_unit] in bitmaps {
				continue
			}
			full_file_path := filepath.join({root_dir, mtl.texture_paths[texture_unit]}, context.temp_allocator)
			bitmaps[mtl.texture_paths[texture_unit]] = {
				// TODO: ONLY FOR BONUSES!!!!!
				// parse_bmp_texture(full_file_path) or_return,
				parse_any_texture_bonus(full_file_path) or_return,
				0
			}
		}
	}

	// Generate OpenGL textures identifiers
	gl_textures = make([]GlTextureID, len(bitmaps))
	gl.GenTextures(i32(len(gl_textures)), cast([^]u32)raw_data(gl_textures))

	// Load each texture into the GPU VRAM
	i :u32 = 0
	for _, &bitmap in bitmaps {
		gl.BindTexture(gl.TEXTURE_2D, cast(u32)gl_textures[i])
		// Texture parameters
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
		// Transfer texture to GPU
		gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, bitmap.bmp.width, bitmap.bmp.height, 0, gl.RGB,
			gl.UNSIGNED_BYTE, raw_data(bitmap.bmp.data))
		gl.GenerateMipmap(gl.TEXTURE_2D)
		gl.BindTexture(gl.TEXTURE_2D, 0)
		// Assign this specific bitmap to the next available Gl texture ID
		bitmap.gl_texture = gl_textures[i]
		i += 1
	}
	// Convert Wavefront (.mtl) material data to Gl material data (texture IDs instead of paths)
	for _, &wavefront_material in materials {
		new_gl_material := GlMaterial{
			name = strings.clone(wavefront_material.name),
			index = wavefront_material.index,
			Ka = wavefront_material.Ka,
			Kd = wavefront_material.Kd,
			Ks = wavefront_material.Ks,
			Ns = wavefront_material.Ns,
			d = wavefront_material.d,
			Tf = wavefront_material.Tf,
			Ni = wavefront_material.Ni,
			illum = wavefront_material.illum
		}
		// Assign the corresponding texture ID for each material's texture.
		// 0 means no texture is to be applied.
		for texture_name, texture_unit in wavefront_material.texture_paths {
			new_gl_material.textures[texture_unit] = bitmaps[texture_name].gl_texture
		}
		gl_materials[new_gl_material.name] = new_gl_material
	}
	ok = true
	return
}
