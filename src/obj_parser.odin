package main

import "core:os"
import "core:mem/virtual"
import "core:strings"
import "core:fmt"
import "core:strconv"
import clang "core:c"

Vec2f :: [2]f32
Vec3f :: [3]f32
Vec4f :: [4]f32

Vec2d :: [2]f64
Vec3d :: [3]f64
Vec4d :: [4]f64

ObjFileVertexIndices :: struct {
	pos_idx: u32,
	uv_idx: u32,
	norm_idx: u32,
}

ObjFileData :: struct {
	vert_positions:	[dynamic]Vec3f,
	tex_coords:	[dynamic]Vec3f,	// Usually 2D textures, no need to handle 3D textures, right?
	normals:	[dynamic]Vec3f,

	vertex_indices:	[dynamic]ObjFileVertexIndices,
}

delete_ObjFileData :: proc(data: ObjFileData) {
	delete(data.vert_positions)
	delete(data.tex_coords)
	delete(data.normals)
	delete(data.vertex_indices)
}

parse_vertex :: proc(obj_data: ^ObjFileData, split_str: []string) -> bool {
	assert(len(split_str) == 3)
	vertex := Vec3f{
		strconv.parse_f32(split_str[0]) or_return,
		strconv.parse_f32(split_str[1]) or_return,
		strconv.parse_f32(split_str[2]) or_return,
	}
	append(&obj_data.vert_positions, vertex)
	return true
}

parse_vertex_texture :: proc(obj_data: ^ObjFileData, split_str: []string) -> bool {
	assert(len(split_str) >= 1)
	vertex := Vec3f{
		strconv.parse_f32(split_str[0]) or_return,
		len(split_str) > 1 ? strconv.parse_f32(split_str[1]) or_return : 0.0,
		len(split_str) > 2 ? strconv.parse_f32(split_str[2]) or_return : 0.0,
	}
	append(&obj_data.tex_coords, vertex)
	return true
}

parse_vertex_normal :: proc(obj_data: ^ObjFileData, split_str: []string) -> bool {
	assert(len(split_str) == 3)
	vertex := Vec3f{
		strconv.parse_f32(split_str[0]) or_return,
		strconv.parse_f32(split_str[1]) or_return,
		strconv.parse_f32(split_str[2]) or_return,
	}
	append(&obj_data.normals, vertex)
	return true
}

// Use this very simple algorithm to decompose a 4+ indices polygon into triangles
// https://stackoverflow.com/questions/38279156/why-there-are-still-many-wavefront-obj-files-containing-4-vertices-in-one-face
// https://stackoverflow.com/questions/23723993/converting-quadriladerals-in-an-obj-file-into-triangles
parse_easy_face :: proc(obj_data: ^ObjFileData, split_str: []string) -> bool {
	assert(len(split_str) >= 3)
	for i in 1..=len(split_str) - 2 {
		// .obj uses 1-based indexing, OpenGL uses 0-based. Careful!
		// Get the vertex indices that make up this face.
		pos_indices := [3]u32{
			cast(u32)strconv.parse_u64(split_str[0]) or_return - 1,
			cast(u32)strconv.parse_u64(split_str[i]) or_return - 1,
			cast(u32)strconv.parse_u64(split_str[i + 1]) or_return - 1,
		}
		to_append := [3]ObjFileVertexIndices{
			{pos_idx = pos_indices[0], uv_idx = clang.UINT32_MAX, norm_idx = clang.UINT32_MAX},
			{pos_idx = pos_indices[1], uv_idx = clang.UINT32_MAX, norm_idx = clang.UINT32_MAX},
			{pos_idx = pos_indices[2], uv_idx = clang.UINT32_MAX, norm_idx = clang.UINT32_MAX}
		}
		append(&obj_data.vertex_indices, ..to_append[:])

	}
	return true
}

parse_hard_face :: proc(obj_data: ^ObjFileData, split_str: []string) -> bool {
	assert(len(split_str) >= 3)
	// For each vertex, parse index data (v/vt/vn). UVs and normals are optional
	// .obj uses 1-based indexing, OpenGL uses 0-based. Careful!
	for i in 1..=len(split_str) - 2 {

		// Attribute indexes of points A, B, C on the currently parsed triangle
		indexes_a := strings.split(split_str[0], "/", context.temp_allocator)
		indexes_b := strings.split(split_str[i], "/", context.temp_allocator)
		indexes_c := strings.split(split_str[i + 1], "/", context.temp_allocator)

		// "or_return -1" -> weird syntax. Means parsed u64 -1, or_return on error.
		pos_indices := [3]u32{
			(cast(u32)strconv.parse_u64(indexes_a[0]) or_return) -1,
			(cast(u32)strconv.parse_u64(indexes_b[0]) or_return) -1,
			(cast(u32)strconv.parse_u64(indexes_c[0]) or_return) -1,
		}
		// XXX: If UV or normal indices aren't specified, they're set to UINT32_MAX.
		// This is because integer underflow is well-defined in Odin (0 - 1 will go to UINT32_MAX)
		// The parsing pipeline further down MUST recognize this and handle it.
		uv_indices := [3]u32{
			u32(strconv.parse_u64(indexes_a[1]) or_else 0) - 1,
			u32(strconv.parse_u64(indexes_b[1]) or_else 0) - 1,
			u32(strconv.parse_u64(indexes_c[1]) or_else 0) - 1,
		}
		normals_indices : [3]u32
		if len(indexes_a) > 2 {
			normals_indices = [3]u32{
				u32(strconv.parse_u64(indexes_a[2]) or_else 0) - 1,
				u32(strconv.parse_u64(indexes_b[2]) or_else 0) - 1,
				u32(strconv.parse_u64(indexes_c[2]) or_else 0) - 1,
			}
		}
		else {
			normals_indices = [3]u32{clang.UINT32_MAX, clang.UINT32_MAX, clang.UINT32_MAX}
		}
		to_append := [3]ObjFileVertexIndices{
			{pos_idx = pos_indices[0], uv_idx = uv_indices[0], norm_idx = normals_indices[0]},
			{pos_idx = pos_indices[1], uv_idx = uv_indices[1], norm_idx = normals_indices[1]},
			{pos_idx = pos_indices[2], uv_idx = uv_indices[2], norm_idx = normals_indices[2]}
		}
		append(&obj_data.vertex_indices, ..to_append[:])
	}
	return true

}

// TODO: Handle more complex face definitions
// TODO: Define a behaviour when .obj does not define some stuff like UVs or normals
//       so I can include all of these in the EBO regardless of .obj format
// TODO: .mtl support somewhere?
parse_obj_file :: proc(obj_file_path: string) -> (obj_data: ObjFileData, ok: bool) {
	using virtual.Map_File_Flag
	file_contents, err := virtual.map_file_from_path(obj_file_path, {.Read})
	if err != nil {
		fmt.printfln("Error mapping `%v`: %v", obj_file_path, err)
		return
	}
	defer virtual.release(raw_data(file_contents), len(file_contents))

	it := string(file_contents)
	for line in strings.split_lines_iterator(&it) {
		hash_index := strings.index_byte(line, '#')
		to_parse := line[:hash_index if hash_index >= 0 else len(line)]
		to_parse = strings.trim_space(to_parse)
		// Skip rest of work if length is 0
		(len(to_parse) > 0) or_continue

		split_line := strings.fields(to_parse, context.temp_allocator)
		defer free_all(context.temp_allocator)

		switch split_line[0] {
		case "v":
			parse_vertex(&obj_data, split_line[1:]) or_return
		case "vt":
			parse_vertex_texture(&obj_data, split_line[1:]) or_return
		case "vn":
			parse_vertex_normal(&obj_data, split_line[1:]) or_return
		case "f":
			if strings.contains_rune(to_parse, '/') {
				parse_hard_face(&obj_data, split_line[1:]) or_return
			} else {
				parse_easy_face(&obj_data, split_line[1:]) or_return
			}
		case: // default
			fmt.println("Unrecognized line:", to_parse)
		}
	}

	// assert(len(obj_data.face_texture_idx) == len(obj_data.face_normal_idx))
	// fmt.println(len(obj_data.vertices), len(obj_data.tex_coords))
	// assert(len(obj_data.vertices) == len(obj_data.tex_coords))
	// assert(len(obj_data.normals) == len(obj_data.tex_coords))

	fmt.printfln("=== Loaded model %v:\n=== %v vertices\n=== %v UVs\n=== %v normals\n=== %v vertex indices",
		obj_file_path, len(obj_data.vert_positions), len(obj_data.tex_coords), len(obj_data.normals), len(obj_data.vertex_indices))
	// fmt.printfln("=== Vertex indices: %v\n=== UV indices: %v\n=== Normal indices: %v",
	// 	len(obj_data.face_vertex_idx), len(obj_data.face_texture_idx), len(obj_data.face_normal_idx))

	max: [2]f32
	for i in 0..<len(obj_data.tex_coords) {
	// for vt in obj_data.tex_coords {
		vt := obj_data.tex_coords[i]
		error_message := fmt.aprintfln("Error at vt %v", i)
		// assert(vt.x >= 0 && vt.x <= 1 && vt.y >= 0 && vt.y <= 1, error_message)
		if vt.x > max.x do max.x = vt.x
		if vt.y > max.y do max.y = vt.y
		delete(error_message)
	}
	fmt.printfln("Max VT: %v", max)

	ok = true
	return
}
