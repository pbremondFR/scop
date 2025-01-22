package main

import "core:os"
import "core:fmt"
import "core:math"
import gl "vendor:OpenGL"
import clang "core:c"

compile_shader_from_source :: proc(shader_source: string, shader_type: u32) -> (shader_id: u32, ok: bool) {
	shader_id = gl.CreateShader(shader_type)
	shader_source_cast := cstring(raw_data(shader_source))
	len := i32(len(shader_source))
	gl.ShaderSource(shader_id, 1, &shader_source_cast, &len)
	gl.CompileShader(shader_id)

	success: i32
	gl.GetShaderiv(shader_id, gl.COMPILE_STATUS, &success);
	if shader_id == 0 || success == 0 {
		error_str: [512]u8
		assert(size_of(error_str) == 512)
		gl.GetShaderInfoLog(shader_id, size_of(error_str), nil, raw_data(error_str[:]));
		fmt.printfln("Error compiling shader: %v", string(error_str[:]))
	}
	else {
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
	fmt.printfln("Compiled %v", vert_shader_path)

	frag_shader := compile_shader_from_source(string(fs_data), gl.FRAGMENT_SHADER) or_return
	defer gl.DeleteShader(frag_shader)
	fmt.printfln("Compiled %v", frag_shader_path)

	program_id = gl.CreateProgram()
	gl.AttachShader(program_id, vert_shader)
	gl.AttachShader(program_id, frag_shader)
	gl.LinkProgram(program_id)

	success: i32
	gl.GetProgramiv(program_id, gl.LINK_STATUS, &success);
	if success == 0{
		error_str: [512]u8
		assert(size_of(error_str) == 512)
		gl.GetProgramInfoLog(program_id, size_of(error_str), nil, raw_data(error_str[:]));
		fmt.println("Error linking shader:", string(error_str[:]))
	}

	ok = (success != 0)
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

VertexData :: struct #packed {
	pos: Vec3f "pos",
	uv: Vec2f "uv",
	material_idx: u32 "Material index",
	norm: Vec3f "norm",
}

@(private="file")
append_vertex_in_vertex_buffer :: proc(
	obj_data: ^WavefrontObjFile,
	materials: []WavefrontMaterial,
	vertex_buffer: ^[dynamic]VertexData,
	vertex_id: WavefrontVertexID)
{
	vertex_id := vertex_id

	// XXX: Assume material name always exists here, it's ensured in the obj parser atm
	material_index: u32
	for i in 0..<len(materials) {
		if materials[i].name == vertex_id.material {
			material_index = u32(i)
			break
		}
	}

	/*
	 * A non-existant index is signaled by a UINT32_MAX. In this case, append appropriate zero-filled
	 * vertex attribute in the corresponding array, and change that index to match that new zero-flled
	 * attribute. This way, no OOB read is done when we dereference it below.
	 */
	if vertex_id.uv_idx == clang.UINT32_MAX {
		new_idx := u32(len(obj_data.tex_coords))
		append(&obj_data.tex_coords, [3]f32{0, 0, 0})
		vertex_id.uv_idx = new_idx
	}
	if vertex_id.norm_idx == clang.UINT32_MAX {
		new_idx := u32(len(obj_data.normals))
		append(&obj_data.normals, [3]f32{0, 0, 0})
		vertex_id.norm_idx = new_idx
	}

	// Insert this vertex with all needed attributes in the vertex buffer. If we're here,
	// it means it's a new unique vertex, otherwise we'd just insert an index in the EBO.
	vertex := VertexData{
		pos = obj_data.vert_positions[vertex_id.pos_idx],
		uv = obj_data.tex_coords[vertex_id.uv_idx].xy,
		material_idx = material_index,
		norm = obj_data.normals[vertex_id.norm_idx],
	}
	append(vertex_buffer, vertex)
}

materials_map_to_array :: proc(materials: map[string]WavefrontMaterial) -> []WavefrontMaterial {
	output_array := make([]WavefrontMaterial, len(materials))

	i := 0
	for key, &material in materials {
		output_array[i] = material
		i += 1
	}
	return output_array
}

/*
 * Convert the Wavefront OBJ representation of a 3D model to a vertex & an index buffer, which can be
 * used by OpenGL to draw them.
 * This function may add data to some members of obj_data, which is why it is given as a pointer.
 */
obj_data_to_vertex_buffer :: proc(obj_data: ^WavefrontObjFile, materials: map[string]WavefrontMaterial) -> (vertex_buffer_: []VertexData, index_buffer_: []u32) {
	vertex_buffer := make([dynamic]VertexData)
	index_buffer := make([dynamic]u32)

	// Store materials in array so we can iterate over it faster when looking for an index
	materials_array := materials_map_to_array(materials)
	defer delete(materials_array)

	/*
	 * Preface/REMINDER: A VERTEX IS NOT JUST A POSITION. The vertex's position is only one of its ATTRIBUTES.
	 *
	 * In the Wavefront OBJ format, faces are defined as 3 (or more) indexes referring to a position,
	 * a texture coordinate (or UV), and a normal vector. These indexes refer to the .obj file's arrays,
	 * NOT OpenGL EBO indexes. A combination of these indexes (and thus vertex attributes) uniquely
	 * identifies a vertex. Of course, different faces may share a unique vertex, which makes using an
	 * index buffer (EBO) a very good idea.
	 *
	 * This map associates a unique vertex identifier with its location in the OpenGL vertex buffer (VBO).
	 * When iterating through the .obj file's faces, if a unique vertex is already stored in the
	 * vertex buffer (VBO), its index is pushed in the index buffer (EBO), thus avoiding a duplicate
	 * vertex in the VBO.
	 */
	vertex_ebo_locations := make(map[WavefrontVertexID]u32)
	defer delete(vertex_ebo_locations)

	for i in 0..<len(obj_data.vertex_indices) {
		vertex_identity := obj_data.vertex_indices[i]

		if !(vertex_identity in vertex_ebo_locations) {
			// This vertex is still unique, insert it
			vertex_index := u32(len(vertex_buffer))
			vertex_ebo_locations[vertex_identity] = vertex_index
			append_vertex_in_vertex_buffer(obj_data, materials_array, &vertex_buffer, vertex_identity)
			append(&index_buffer, vertex_index)
		}
		else {
			// This vertex has been seen before, just push its index in the index buffer.
			vertex_index := vertex_ebo_locations[vertex_identity]
			append(&index_buffer, vertex_index)
		}
	}

	return vertex_buffer[:], index_buffer[:]
}
