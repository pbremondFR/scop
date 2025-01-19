package main

import "core:os"
import "core:fmt"
import gl "vendor:OpenGL"

compile_shader_from_source :: proc(shader_source: string, shader_type: u32) -> (shader_id: u32, ok: bool) {
	shader_id = gl.CreateShader(shader_type)
	shader_source_cast := cstring(raw_data(shader_source))
	len := i32(len(shader_source))
	gl.ShaderSource(shader_id, 1, &shader_source_cast, &len)
	gl.CompileShader(shader_id)
	if shader_id != 0 {
		ok = true
	}
	return
}

// Not allowed to load shaders with a library, so no gl utils from Odin :(
get_shader_program :: proc(vert_shader_path: string, frag_shader_path: string) -> (program_id: u32, ok: bool) {
	vs_data := os.read_entire_file(vert_shader_path) or_return
	defer delete(vs_data)

	fs_data := os.read_entire_file(frag_shader_path) or_return
	defer delete(fs_data)

	vert_shader := compile_shader_from_source(string(vs_data), gl.VERTEX_SHADER) or_return
	defer gl.DeleteShader(vert_shader)

	frag_shader := compile_shader_from_source(string(fs_data), gl.FRAGMENT_SHADER) or_return
	defer gl.DeleteShader(frag_shader)

	program_id = gl.CreateProgram()
	gl.AttachShader(program_id, vert_shader)
	gl.AttachShader(program_id, frag_shader)
	gl.LinkProgram(program_id)

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
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, texture.width, texture.height, 0, gl.RGB,
		gl.UNSIGNED_BYTE, raw_data(bmp.data))
	gl.GenerateMipmap(gl.TEXTURE_2D)

	// XXX: Unbind texture for next callers?
	gl.BindTexture(gl.TEXTURE_2D, 0)

	ok = true
	return
}
