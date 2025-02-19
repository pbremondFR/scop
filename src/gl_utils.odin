package main

import "core:os"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "core:mem"
import gl "vendor:OpenGL"
import clang "core:c"

compile_shader_from_source :: proc(shader_source: string, shader_name: string, shader_type: u32) -> (shader_id: u32, ok: bool) {
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
		log_error("Failed to compile %s:\n%s", shader_name, string(error_str[:]))
	}
	else {
		ok = true
	}
	return
}

get_shader_program :: proc{
	get_shader_program_vert_frag,
	get_shader_program_vert_frag_geom,
}

// Not allowed to load shaders with a library, so no gl utils from Odin :(
get_shader_program_vert_frag :: proc(vert_shader_path: string, frag_shader_path: string) -> (program_id: u32, ok: bool) {
	vs_data := os.read_entire_file(vert_shader_path) or_return
	defer delete(vs_data)

	fs_data := os.read_entire_file(frag_shader_path) or_return
	defer delete(fs_data)

	vert_shader := compile_shader_from_source(string(vs_data), vert_shader_path, gl.VERTEX_SHADER) or_return
	defer gl.DeleteShader(vert_shader)
	fmt.printfln("Compiled %v", vert_shader_path)

	frag_shader := compile_shader_from_source(string(fs_data), frag_shader_path, gl.FRAGMENT_SHADER) or_return
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
		log_error("Failed to link shader:", string(error_str[:]))
	}

	ok = (success != 0)
	return
}

// Not allowed to load shaders with a library, so no gl utils from Odin :(
get_shader_program_vert_frag_geom :: proc(vert_shader_path, frag_shader_path, geom_shader_path: string) -> (program_id: u32, ok: bool) {
	vs_data := os.read_entire_file(vert_shader_path) or_return
	defer delete(vs_data)

	fs_data := os.read_entire_file(frag_shader_path) or_return
	defer delete(fs_data)

	gs_data := os.read_entire_file(geom_shader_path) or_return
	defer delete(gs_data)

	vert_shader := compile_shader_from_source(string(vs_data), vert_shader_path, gl.VERTEX_SHADER) or_return
	defer gl.DeleteShader(vert_shader)
	fmt.printfln("Compiled %v", vert_shader_path)

	geom_shader := compile_shader_from_source(string(gs_data),frag_shader_path, gl.GEOMETRY_SHADER) or_return
	defer gl.DeleteShader(geom_shader)
	fmt.printfln("Compiled %v", geom_shader_path)

	frag_shader := compile_shader_from_source(string(fs_data), geom_shader_path, gl.FRAGMENT_SHADER) or_return
	defer gl.DeleteShader(frag_shader)
	fmt.printfln("Compiled %v", frag_shader_path)

	program_id = gl.CreateProgram()
	gl.AttachShader(program_id, vert_shader)
	gl.AttachShader(program_id, geom_shader)
	gl.AttachShader(program_id, frag_shader)
	gl.LinkProgram(program_id)

	success: i32
	gl.GetProgramiv(program_id, gl.LINK_STATUS, &success);
	if success == 0{
		error_str: [512]u8
		assert(size_of(error_str) == 512)
		gl.GetProgramInfoLog(program_id, size_of(error_str), nil, raw_data(error_str[:]));
		log_error("Failed to link shader:", string(error_str[:]))
	}

	ok = (success != 0)
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
	obj_data: ^WavefrontObjData,
	material_index: u32,
	vertex_buffer: ^[dynamic]VertexData,
	vertex_id: WavefrontVertexID)
{
	vertex_id := vertex_id

	/*
	 * A non-existant index is signaled by a UINT32_MAX. In this case, append appropriate zero-filled
	 * vertex attribute in the corresponding array, and change that index to match that new zero-flled
	 * attribute. This way, no OOB read is done when we dereference it below.
	 */
	if vertex_id.uv_idx == clang.UINT32_MAX {
		new_idx := u32(len(obj_data.tex_coords))
		// If UV coordinates don't exist, set them to the vertex's position
		append(&obj_data.tex_coords, obj_data.vert_positions[vertex_id.pos_idx])
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

GlIndexBufferRange :: struct {
	begin: uintptr,
	length: i32,
	material_index: u32,
}

@(private="file")
ModelVerticesAndIndexes :: struct {
	vertex_buffer: []VertexData,
	index_buffer: []u32,
	index_ranges: []GlIndexBufferRange,
}

/*
 * Convert the Wavefront OBJ representation of a 3D model to a vertex & an index buffer, which can be
 * used by OpenGL to draw them.
 * This function may add data to some members of obj_data, which is why it is given as a pointer.
 */
@(private="file")
obj_data_to_vertex_buffer :: proc(obj_data: ^WavefrontObjData, materials: map[string]WavefrontMaterial) -> ModelVerticesAndIndexes {
	// Pre-allocate enough memory for the maximum amount of vertices
	vertex_buffer := make([dynamic]VertexData, 0, len(obj_data.vertex_indices))
	// I'm sorting the index buffer by the material ID, which allows me to render each material with
	// a different Draw call. I use this temporary 2D array for the occasion.
	index_buffers_by_material := make([dynamic][dynamic]u32, len(materials))
	defer {
		for buffer in index_buffers_by_material do delete(buffer)
		delete(index_buffers_by_material)
	}

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
		material_index := materials[string(vertex_identity.material)].index

		if vertex_identity not_in vertex_ebo_locations {
			// This vertex is still unique, insert it
			vertex_index := u32(len(vertex_buffer))
			vertex_ebo_locations[vertex_identity] = vertex_index
			append_vertex_in_vertex_buffer(obj_data, material_index, &vertex_buffer, vertex_identity)
			append(&index_buffers_by_material[material_index], vertex_index)
		}
		else {
			// This vertex has been seen before, just push its index in the index buffer.
			vertex_index := vertex_ebo_locations[vertex_identity]
			append(&index_buffers_by_material[material_index], vertex_index)
		}
	}

	index_buffer := make([dynamic]u32, 0, len(obj_data.vertex_indices))
	// One index range per material
	index_ranges := make([dynamic]GlIndexBufferRange, 0, len(materials))
	for indexes, i in index_buffers_by_material {
		if len(indexes) == 0 {
			continue
		}
		append(&index_ranges, GlIndexBufferRange{
			begin = uintptr(len(index_buffer)),
			length = i32(len(indexes)),
			material_index = u32(i)
		})
		append(&index_buffer, ..indexes[:])
	}

	// Release unused memory if any (due to de-duplicated vertices)
	shrink(&vertex_buffer)
	shrink(&index_buffer)
	shrink(&index_ranges)
	return ModelVerticesAndIndexes{
		vertex_buffer[:],
		index_buffer[:],
		index_ranges[:]
	}
}

GlModel :: struct {
	vao: u32,
	vbo: u32,
	vbo_len: i32,
	ebo: u32, // Also known as IBO?
	ebo_len: i32,
	index_ranges: []GlIndexBufferRange,
}

delete_GlModel :: proc(model: ^GlModel)
{
	gl.DeleteVertexArrays(1, &model.vao)
	gl.DeleteBuffers(1, &model.vbo)
	gl.DeleteBuffers(1, &model.ebo)
	delete(model.index_ranges)
}

/*
 * Converts Wavefront .obj data into OpenGL buffers.
 * This function creates a VAO, VBO, and EBO. It also gives an array of index ranges.
 * Each index range corresponds to a group of vertices belonging to the same material.
 * Segregating by material opens the door for rendering techniques like order-independant dissolve.
 */
obj_data_to_gl_objects :: proc(obj_data: ^WavefrontObjData, materials: map[string]WavefrontMaterial) -> (gl_model: GlModel) {
	buffers := obj_data_to_vertex_buffer(obj_data, materials)
	defer {
		// Once those are sent to the GPU memory, we can release them from CPU RAM
		delete(buffers.vertex_buffer)
		delete(buffers.index_buffer)
	}
	// TODO: New (openGL 4.5+) method of doing this?
	// https://github.com/fendevel/Guide-to-Modern-OpenGL-Functions?tab=readme-ov-file#glbuffer
	// https://www.reddit.com/r/opengl/comments/18rkgg3/one_vao_for_multiple_vbos/
	// TODO: Error handling if anything below this comment fails. Painful. Fuck OpenGL function signatures.

	gl_model.vbo_len = i32(len(buffers.vertex_buffer))
	gl_model.ebo_len = i32(len(buffers.index_buffer))
	gl_model.index_ranges = buffers.index_ranges

	// Generate buffers for VAO, VBO and EBO
	gl.GenVertexArrays(1, &gl_model.vao)
	gl.GenBuffers(1, &gl_model.vbo)
	gl.GenBuffers(1, &gl_model.ebo)

	// Bind to object's VAO
	gl.BindVertexArray(gl_model.vao)

	// Copy vertex data to GPU buffer object
	gl.BindBuffer(gl.ARRAY_BUFFER, gl_model.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(buffers.vertex_buffer) * size_of(buffers.vertex_buffer[0]),
		raw_data(buffers.vertex_buffer), gl.STATIC_DRAW)

	// Enable & specify vertex attributes for VBO
	gl.EnableVertexAttribArray(0)
	gl.EnableVertexAttribArray(1)
	gl.EnableVertexAttribArray(2)
	gl.EnableVertexAttribArray(3)

	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(buffers.vertex_buffer[0]), 0)
	gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(buffers.vertex_buffer[0]), offset_of(VertexData, uv))
	gl.VertexAttribIPointer(2, 1, gl.UNSIGNED_INT, size_of(buffers.vertex_buffer[0]), offset_of(VertexData, material_idx))
	gl.VertexAttribPointer(3, 3, gl.FLOAT, gl.FALSE, size_of(buffers.vertex_buffer[0]), offset_of(VertexData, norm))

	// Bind VAO to EBO and fill it with needed indices
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gl_model.ebo)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(buffers.index_buffer) * size_of(buffers.index_buffer[0]),
		raw_data(buffers.index_buffer), gl.STATIC_DRAW)

	gl.BindVertexArray(0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, 0)

	return
}

// XXX: Had to reorder members to get rid of padding & be compliant with GLSL std140 layout
GlUniformMaterialData :: struct #packed {
	Ka: Vec3f "Ambient color",
	Ns: f32 "Specular exponent",
	Kd: Vec3f "Diffuse color",
	d: f32 "Dissolve", // Also known as "Tr" (1 - dissolve)
	Ks: Vec3f "Specular color",
	Ni: f32 "Index of refraction",
	Tf: Vec3f "Transmission filter color",
	// Disable illumination model for now (not used anyway)
	// illum: IlluminationModel "Illumination model",

	// Bitfield indicating which textures are enabled. The Nth LSB bit enabled means the
	// Nth member of the TextureUnit enum is enabled for this material.
	enabled_textures_flags: u32,
}

/*
 * Converts the list of OpenGL materials to a plain buffer containing all relevant material info for OpenGL.
 * This buffer can then be copied into a uniform buffer and passed to shaders.
 */
@(private="file")
gl_materials_to_raw_uniform_data :: proc(gl_materials: map[string]GlMaterial) -> []GlUniformMaterialData {
	gl_buffer := make([]GlUniformMaterialData, len(gl_materials))
	for _, material in gl_materials {
		// Set corresponding bit to 1 if texture should be enabled
		textures_flags: u32 = 0
		for texture_unit in TextureUnit {
			textures_flags |= u32(material.textures[texture_unit] != 0) << u32(texture_unit)
		}
		data := GlUniformMaterialData{
			Ka = material.Ka,
			Kd = material.Kd,
			Ks = material.Ks,
			Ns = material.Ns,
			d = material.d,
			Tf = material.Tf,
			Ni = material.Ni,
			// illum = material.illum,
			enabled_textures_flags = textures_flags
		}
		gl_buffer[material.index] = data
	}

	return gl_buffer
}

/*
 * Tranfer all of GlMaterials into a uniform buffer object that can be used by shaders.
 */
gl_materials_to_uniform_buffer_object :: proc(gl_materials: map[string]GlMaterial) -> (ubo: u32)
{
	uniform_buffer_data := gl_materials_to_raw_uniform_data(gl_materials)
	defer delete(uniform_buffer_data)

	gl.GenBuffers(1, &ubo)
	gl.BindBuffer(gl.UNIFORM_BUFFER, ubo)
	gl.BufferData(gl.UNIFORM_BUFFER, len(uniform_buffer_data) * size_of(uniform_buffer_data[0]),
		raw_data(uniform_buffer_data), gl.STATIC_DRAW)
	gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
	gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, ubo)
	return
}

set_shader_uniform :: proc{
	set_shader_uniform_mat4f,
	set_shader_uniform_vec3f,
	set_shader_uniform_f32,
	set_shader_uniform_i32,
}

set_shader_uniform_mat4f :: proc(shader_program: u32, uniform_name: string, mat: ^Mat4f) {
	uniform_location := gl.GetUniformLocation(shader_program, strings.unsafe_string_to_cstring(uniform_name))
	// gl.UniformMatrix4fv(uniform_location, 1, gl.FALSE, &mat[0, 0])
	gl.UniformMatrix4fv(uniform_location, 1, gl.FALSE, raw_data(mat))
}

set_shader_uniform_vec3f :: proc(shader_program: u32, uniform_name: string, vec: ^Vec3f) {
	uniform_location := gl.GetUniformLocation(shader_program, strings.unsafe_string_to_cstring(uniform_name))
	gl.Uniform3fv(uniform_location, 1, raw_data(vec))
}

set_shader_uniform_f32 :: proc(shader_program: u32, uniform_name: string, value: f32) {
	uniform_location := gl.GetUniformLocation(shader_program, strings.unsafe_string_to_cstring(uniform_name))
	gl.Uniform1f(uniform_location, value)
}

set_shader_uniform_i32 :: proc(shader_program: u32, uniform_name: string, value: i32) {
	uniform_location := gl.GetUniformLocation(shader_program, strings.unsafe_string_to_cstring(uniform_name))
	gl.Uniform1i(uniform_location, value)
}
