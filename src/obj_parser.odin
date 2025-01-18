package main

import "core:os"
import "core:mem/virtual"
import "core:strings"
import "core:fmt"
import "core:strconv"

Vec2f :: [2]f32
Vec3f :: [3]f32
Vec4f :: [4]f32

Vec2d :: [2]f64
Vec3d :: [3]f64
Vec4d :: [4]f64

ObjFileData :: struct {
	vertices:	[dynamic]Vec3f,
	tex_coords:	[dynamic]Vec3f,
	normals:	[dynamic]Vec3f,
	faces:		[dynamic][3]u16,
}

delete_ObjFileData :: proc(data: ObjFileData) {
	delete(data.vertices)
	delete(data.tex_coords)
	delete(data.normals)
}

parse_vertex :: proc(obj_data: ^ObjFileData, split_str: []string) -> bool {
	assert(len(split_str) == 3)
	vertex := Vec3f{
		strconv.parse_f32(split_str[0]) or_return,
		strconv.parse_f32(split_str[1]) or_return,
		strconv.parse_f32(split_str[2]) or_return,
	}
	append(&obj_data.vertices, vertex)
	return true
}

parse_vertex_texture :: proc(obj_data: ^ObjFileData, split_str: []string) -> bool {
	assert(len(split_str) == 3)
	vertex := Vec3f{
		strconv.parse_f32(split_str[0]) or_return,
		strconv.parse_f32(split_str[1]) or_else 0.0,
		strconv.parse_f32(split_str[2]) or_else 0.0,
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

parse_face :: proc(obj_data: ^ObjFileData, split_str: []string) -> bool {
	assert(len(split_str) >= 3)
	for i in 1..=len(split_str) - 2 {
		vertex := [3]u16{
			cast(u16)strconv.parse_u64(split_str[0]) or_return,
			cast(u16)strconv.parse_u64(split_str[i]) or_return,
			cast(u16)strconv.parse_u64(split_str[i + 1]) or_return,
		}
		append(&obj_data.faces, vertex)
	}
	return true
}

// To build a better parser:
// https://stackoverflow.com/questions/38279156/why-there-are-still-many-wavefront-obj-files-containing-4-vertices-in-one-face
// https://stackoverflow.com/questions/23723993/converting-quadriladerals-in-an-obj-file-into-triangles

// Very basic .obj file parser for testing

parse_obj_file :: proc(obj_file_path: string) -> (obj_data: ObjFileData, ok: bool) {
	using virtual.Map_File_Flag
	file_contents, err := virtual.map_file_from_path(obj_file_path, {.Read})
	if err != nil {
		fmt.println("Error:", err)
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
			parse_face(&obj_data, split_line[1:]) or_return
		case: // default
			fmt.println("Unrecognized line:", to_parse)
		}
	}
	ok = true
	return
}
