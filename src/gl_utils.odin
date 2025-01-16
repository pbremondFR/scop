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
