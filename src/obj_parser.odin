#+feature dynamic-literals

package main

import "core:os"
import "core:mem/virtual"
import "core:strings"
import "core:fmt"
import "core:strconv"
import "core:path/filepath"
import "core:encoding/ansi"
import clang "core:c"

Vec2f :: [2]f32
Vec3f :: [3]f32
Vec4f :: [4]f32

Vec2d :: [2]f64
Vec3d :: [3]f64
Vec4d :: [4]f64

WavefrontVertexID :: struct {
	pos_idx: u32,
	uv_idx: u32,
	norm_idx: u32,
	material: string,
}

IlluminationModel :: enum u32 {
	ColorOnAmbientOff,
	ColorOnAmbientOn,
	HightlightOn,
	ReflectionOnRaytraceOn,
	TransparencyGlassOnReflectionRaytraceOn,
	ReflectionFresnelOnRaytraceOn,
	TransparencyRefractionOnReflectionFresnelOffRaytraceOn,
	TransparencyRefractionOnReflectionFresnelOnRaytraceOn,
	ReflectionOnRaytraceOff,
	TransparencyGlassOnRelfectionRaytraceOff,
	CastsShadowOntoInvisibleSurfaces,
}

WavefrontMaterial :: struct {
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

	map_Ka: string "Ambient texture map",
	map_Kd: string "Diffuse texture map",
	map_Ks: string "Specular color texture map",
	map_Ns: string "Specular exponent texture map",
	map_d: string "Alpha texture map",
	map_bump: string "Bump map",
	map_disp: string "Displacement map",
	decal: string "Stencil decal texture",
}

delete_WavefrontMaterial :: proc(mtl: WavefrontMaterial) {
	// TODO: delete strings of maps if I ever get around to implementing that
	delete(mtl.name)
	delete(mtl.map_Ka)
	delete(mtl.map_Kd)
	delete(mtl.map_Ks)
	delete(mtl.map_Ns)
	delete(mtl.map_d)
	delete(mtl.map_bump)
	delete(mtl.map_disp)
	delete(mtl.decal)
}

DEFAULT_MATERIAL_NAME : string : "__SCOP_DEFAULT_MATERIAL"

get_default_material :: proc(name: string = DEFAULT_MATERIAL_NAME) -> WavefrontMaterial {
	return WavefrontMaterial {
		name = strings.clone(name),

		Ka = {0.4, 0.4, 0.4},
		Kd = {0.5, 0.5, 0.5},
		Ks = {0.5, 0.5, 0.5},
		Ns = 39,
	}
}

WavefrontObjFile :: struct {
	vert_positions:	[dynamic]Vec3f,
	tex_coords:	[dynamic]Vec3f,	// Usually 2D textures, no need to handle 3D textures, right?
	normals:	[dynamic]Vec3f,

	vertex_indices:	[dynamic]WavefrontVertexID,
}

delete_ObjFileData :: proc(data: WavefrontObjFile) {
	delete(data.vert_positions)
	delete(data.tex_coords)
	delete(data.normals)
	delete(data.vertex_indices)
}
@(private="file")
parse_vertex :: proc(obj_data: ^WavefrontObjFile, split_str: []string) -> bool {
	assert(len(split_str) == 3)
	vertex := Vec3f{
		strconv.parse_f32(split_str[0]) or_return,
		strconv.parse_f32(split_str[1]) or_return,
		strconv.parse_f32(split_str[2]) or_return,
	}
	append(&obj_data.vert_positions, vertex)
	return true
}
@(private="file")
parse_vertex_texture :: proc(obj_data: ^WavefrontObjFile, split_str: []string) -> bool {
	assert(len(split_str) >= 1)
	vertex := Vec3f{
		strconv.parse_f32(split_str[0]) or_return,
		len(split_str) > 1 ? strconv.parse_f32(split_str[1]) or_return : 0.0,
		len(split_str) > 2 ? strconv.parse_f32(split_str[2]) or_return : 0.0,
	}
	append(&obj_data.tex_coords, vertex)
	return true
}
@(private="file")
parse_vertex_normal :: proc(obj_data: ^WavefrontObjFile, split_str: []string) -> bool {
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
@(private="file")
parse_easy_face :: proc(obj_data: ^WavefrontObjFile, split_str: []string, material_name: string) -> bool {
	assert(len(split_str) >= 3)
	for i in 1..=len(split_str) - 2 {
		// .obj uses 1-based indexing, OpenGL uses 0-based. Careful!
		// Get the vertex indices that make up this face.
		pos_indices := [3]u32{
			cast(u32)strconv.parse_u64(split_str[0]) or_return - 1,
			cast(u32)strconv.parse_u64(split_str[i]) or_return - 1,
			cast(u32)strconv.parse_u64(split_str[i + 1]) or_return - 1,
		}
		to_append := [3]WavefrontVertexID{
			{pos_idx = pos_indices[0], uv_idx = clang.UINT32_MAX, norm_idx = clang.UINT32_MAX, material = material_name},
			{pos_idx = pos_indices[1], uv_idx = clang.UINT32_MAX, norm_idx = clang.UINT32_MAX, material = material_name},
			{pos_idx = pos_indices[2], uv_idx = clang.UINT32_MAX, norm_idx = clang.UINT32_MAX, material = material_name}
		}
		append(&obj_data.vertex_indices, ..to_append[:])

	}
	return true
}

@(private="file")
parse_hard_face :: proc(obj_data: ^WavefrontObjFile, split_str: []string, material_name: string) -> bool {
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
		to_append := [3]WavefrontVertexID{
			{pos_idx = pos_indices[0], uv_idx = uv_indices[0], norm_idx = normals_indices[0], material = material_name},
			{pos_idx = pos_indices[1], uv_idx = uv_indices[1], norm_idx = normals_indices[1], material = material_name},
			{pos_idx = pos_indices[2], uv_idx = uv_indices[2], norm_idx = normals_indices[2], material = material_name}
		}
		append(&obj_data.vertex_indices, ..to_append[:])
	}
	return true

}

@(private="file")
parse_vec3 :: proc(split_str: []string, output: ^Vec3f) -> (ok: bool) {
	if len(split_str) < 3 {
		return
	}
	output.x = strconv.parse_f32(split_str[0]) or_return
	output.y = strconv.parse_f32(split_str[1]) or_return
	output.z = strconv.parse_f32(split_str[2]) or_return
	ok = true
	return
}

@(private="file")
parse_vec2 :: proc(split_str: []string, output: ^Vec2f) -> (ok: bool) {
	if len(split_str) < 2 {
		return
	}
	output.x = strconv.parse_f32(split_str[0]) or_return
	output.y = strconv.parse_f32(split_str[1]) or_return
	ok = true
	return
}

MAX_MATERIALS :: 128
WARNING_YELLOW_TEXT :: ansi.CSI + ansi.FG_YELLOW + ansi.SGR + "WARNING:" + ansi.CSI + ansi.RESET + ansi.SGR
ERROR_RED_TEXT :: ansi.CSI + ansi.FG_RED + ansi.SGR + "ERROR:" + ansi.CSI + ansi.RESET + ansi.SGR
NOTE_BLUE_TEXT ::ansi.CSI + ansi.FG_BLUE + ansi.SGR + "NOTE:" + ansi.CSI + ansi.RESET + ansi.SGR

parse_mtl_file :: proc(mtl_file_name: string, working_dir: string) -> (materials: map[string]WavefrontMaterial, ok: bool) {
	using virtual.Map_File_Flag

	mtl_file_path := filepath.join({working_dir, mtl_file_name})
	defer delete(mtl_file_path)

	file_contents, err := virtual.map_file_from_path(mtl_file_path, {.Read})
	if err != nil {
		fmt.printfln("Error mapping `%v`: %v", mtl_file_path, err)
		return
	}
	defer virtual.release(raw_data(file_contents), len(file_contents))

	materials[DEFAULT_MATERIAL_NAME] = get_default_material()
	active_material_name := DEFAULT_MATERIAL_NAME

	// Iterate over every line of the .mtl file
	line_number := 0
	it := string(file_contents)
	for line in strings.split_lines_iterator(&it) {
		line_number += 1
		// Slice away everything after the #
		hash_index := strings.index_byte(line, '#')
		to_parse := line[:hash_index if hash_index >= 0 else len(line)]
		to_parse = strings.trim_space(to_parse)
		// Skip rest of work if line is empty
		if (len(to_parse) == 0) {
			continue
		}

		split_line := strings.fields(to_parse, context.temp_allocator)
		// Don't free memory from temp_allocator here, it will be done by calling function!
		if len(split_line) < 2 {
			fmt.printfln(WARNING_YELLOW_TEXT + "%v:%v: incorrect .mtl statement has less than 2 tokens: `%v'", mtl_file_name, line_number, line)
			continue
		}
		active_material : ^WavefrontMaterial = &materials[active_material_name]
		assert(active_material_name in materials)

		switch split_line[0] {
		case "newmtl":
			active_material_name = split_line[1]
			new_material := get_default_material(active_material_name)
			materials[new_material.name] = new_material
		case "Ka":
			parse_vec3(split_line[1:], &active_material.Ka) or_return
		case "Kd":
			parse_vec3(split_line[1:], &active_material.Kd) or_return
		case "Ks":
			parse_vec3(split_line[1:], &active_material.Ks) or_return
		case "Ns":
			active_material.Ns = strconv.parse_f32(split_line[1]) or_else 32
		case "Tr":
			active_material.d = 1.0 - (strconv.parse_f32(split_line[1]) or_else 0.0)
		case "d":
			active_material.d = strconv.parse_f32(split_line[1]) or_else 0.0
		case "map_Ka":
			active_material.map_Ka = strings.clone(split_line[1])
		// case "map_Kd":
		// 	active_material.map_Kd = strings.clone(split_line[1])
		// case "map_Ks":
		// 	active_material.map_Ks = strings.clone(split_line[1])
		// case "map_Ns":
		// 	active_material.map_Ns = strings.clone(split_line[1])
		// case "map_d":
		// 	active_material.map_d = strings.clone(split_line[1])
		// case "map_bump", "bump":
		// 	active_material.map_bump = strings.clone(split_line[1])
		// case "disp":
		// 	active_material.map_disp = strings.clone(split_line[1])
		// case "decal":
		// 	active_material.decal = strings.clone(split_line[1])
		case: // default
				fmt.printfln(NOTE_BLUE_TEXT + " %v:%v: unsupported %v directive", mtl_file_name, line_number, split_line[0])
		}
	}
	ok = true
	return
}

// TODO: Handle more complex face definitions
parse_obj_file :: proc(obj_file_path: string) -> (obj_data: WavefrontObjFile, materials: map[string]WavefrontMaterial, ok: bool) {
	using virtual.Map_File_Flag
	file_contents, err := virtual.map_file_from_path(obj_file_path, {.Read})
	if err != nil {
		fmt.printfln("Error mapping `%v`: %v", obj_file_path, err)
		return
	}
	defer virtual.release(raw_data(file_contents), len(file_contents))

	working_dir := filepath.dir(obj_file_path)
	file_name := filepath.base(obj_file_path) // Just a slice, no alloc
	defer delete(working_dir)

	active_material_name := DEFAULT_MATERIAL_NAME

	it := string(file_contents)
	line_number := 0
	for line in strings.split_lines_iterator(&it) {
		line_number += 1
		hash_index := strings.index_byte(line, '#')
		to_parse := line[:hash_index if hash_index >= 0 else len(line)]
		to_parse = strings.trim_space(to_parse)
		// Skip rest of work if length is 0
		if len(to_parse) == 0 {
			continue
		}
		// Split current line into tokens with temp_allocator to parse easily
		split_line := strings.fields(to_parse, context.temp_allocator)
		defer free_all(context.temp_allocator)
		// We should never get less than two tokens!
		if len(split_line) < 2 {
			fmt.printfln(WARNING_YELLOW_TEXT + " %v:%v: incorrect .obj statement has less than 2 tokens: `%v'", obj_file_path, line_number, line)
			continue
		}
		switch split_line[0] {
		case "v":
			parse_vertex(&obj_data, split_line[1:]) or_return
		case "vt":
			parse_vertex_texture(&obj_data, split_line[1:]) or_return
		case "vn":
			parse_vertex_normal(&obj_data, split_line[1:]) or_return
		case "f":
			if strings.contains_rune(to_parse, '/') {
				parse_hard_face(&obj_data, split_line[1:], active_material_name) or_return
			} else {
				parse_easy_face(&obj_data, split_line[1:], active_material_name) or_return
			}
		case "mtllib":
			materials = parse_mtl_file(split_line[1], working_dir) or_return
		case "usemtl":
			// XXX: I could make it so it only stored the name of the material and tries to
			// bind to it later, so that we don't need to call "mtllib" at the top of the file,
			// but that might be overkill/beyond the Wavefront spec
			if !(split_line[1] in materials) {
				fmt.printfln(ERROR_RED_TEXT + " line %v: Material `%v' is not found in current materials", line_number, split_line[1])
				return
			}
			active_material_name = materials[split_line[1]].name
		case: // default
			fmt.printfln(NOTE_BLUE_TEXT + " %v:%v: unsupported %v directive", obj_file_path, line_number, split_line[0])
		}
	}

	fmt.printfln("=== Loaded model %v:\n=== %v vertices\n=== %v UVs\n=== %v normals\n=== %v vertex indices",
		obj_file_path, len(obj_data.vert_positions), len(obj_data.tex_coords), len(obj_data.normals), len(obj_data.vertex_indices))

	if len(materials) > MAX_MATERIALS {
		// Print limit as MAX_MATERIALS - 1 because there is always our own default material
		fmt.printfln("Error: Too many materials! Limit is %v", MAX_MATERIALS - 1)
		return
	}
	else if len(materials) == 0 {
		materials[DEFAULT_MATERIAL_NAME] = get_default_material()
	}

	ok = true
	return
}
