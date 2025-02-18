#+feature dynamic-literals

package main

import "core:os"
import "core:mem/virtual"
import "core:strings"
import "core:fmt"
import "core:strconv"
import "core:path/filepath"
import "core:encoding/ansi"
import "core:slice"
import "base:runtime"
import clang "core:c"

Vec2f :: [2]f32
Vec3f :: [3]f32
Vec4f :: [4]f32

Vec2d :: [2]f64
Vec3d :: [3]f64
Vec4d :: [4]f64

/*
 * Represents a single vertex in the Wavefront data format. It contains the indices of the vertex's
 * position, uv coordinates, and normals. It also contains the material's name.
 * This structure is used as an intermediate representation and will be converted to an OpenGL vertex
 * later down the pipeline.
 */
WavefrontVertexID :: struct {
	pos_idx: u32,
	uv_idx: u32,
	norm_idx: u32,
	material: ^string,
}

/*
 * Lists all of the possible illumination models in the Wavefront Object format.
 */
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

/*
 * Lists all of the supported texture types that can be found in the Wavefront Material file.
 * These can then be used in different OpenGL texture units.
 */
TextureUnit :: enum u32 {
	Map_Ka,
	Map_Kd,
	Map_Ks,
	Map_Ns,
	Map_d,
	Map_bump,
	Map_disp,
	Decal,
}

WavefrontMaterial :: struct {
	name: string "Material name",
	index: u32 "Material index",

	Ka: Vec3f "Ambient color",
	Kd: Vec3f "Diffuse color",
	Ks: Vec3f "Specular color",
	Ns: f32 "Specular exponent",
	d: f32 "Dissolve", // Also known as "Tr" (1 - dissolve)
	Tf: Vec3f "Transmission filter color",
	Ni: f32 "Index of refraction",
	illum: IlluminationModel "Illumination model",

	texture_paths: [TextureUnit]string,
}

delete_WavefrontMaterial :: proc(mtl: WavefrontMaterial) {
	// TODO: delete strings of maps if I ever get around to implementing that
	delete(mtl.name)
	for path in mtl.texture_paths {
		delete(path)
	}
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

WavefrontObjData :: struct {
	vert_positions:	[dynamic]Vec3f,
	tex_coords:	[dynamic]Vec3f,	// Usually 2D textures, no need to handle 3D textures, right?
	normals:	[dynamic]Vec3f,

	vertex_indices:	[dynamic]WavefrontVertexID,
}

delete_WavefrontObjFile :: proc(data: WavefrontObjData) {
	delete(data.vert_positions)
	delete(data.tex_coords)
	delete(data.normals)
	delete(data.vertex_indices)
}
@(private="file")
parse_vertex :: proc(obj_data: ^WavefrontObjData, split_str: []string) -> bool {
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
parse_vertex_texture :: proc(obj_data: ^WavefrontObjData, split_str: []string) -> bool {
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
parse_vertex_normal :: proc(obj_data: ^WavefrontObjData, split_str: []string) -> bool {
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
parse_easy_face :: proc(obj_data: ^WavefrontObjData, split_str: []string, material_name: ^string) -> bool {
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
parse_hard_face :: proc(obj_data: ^WavefrontObjData, split_str: []string, material_name: ^string) -> bool {
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
ParseResult :: enum {
	Ok,
	Unsupported,
	Failure,
}

/*
 * Trim Wavefront Obj statement/directive of whitespaces and comments. Split this statement into individual tokens.
 */
@(private="file")
trim_and_split_line :: proc(line: string, allocator: runtime.Allocator) -> (trimmed: string, split: []string)
{
	hash_index := strings.index_byte(line, '#')
	trimmed = line[0:(hash_index if hash_index >= 0 else len(line))]
	trimmed = strings.trim_space(trimmed)
	// Split current line into tokens with temp_allocator to parse easily
	split = strings.fields(trimmed, allocator)
	return
}

@(private="file")
parse_obj_vertex_statement :: proc(statement: string, split_statement: []string, obj_data: ^WavefrontObjData, active_material: ^string) -> ParseResult
{
	switch split_statement[0] {
		case "v":
			if !parse_vertex(obj_data, split_statement[1:]) do return .Failure
		case "vt":
			if !parse_vertex_texture(obj_data, split_statement[1:]) do return .Failure
		case "vn":
			if !parse_vertex_normal(obj_data, split_statement[1:]) do return .Failure
		case "f":
			if strings.contains_rune(statement, '/') {
				if !parse_hard_face(obj_data, split_statement[1:], active_material) do return .Failure
			} else {
				if !parse_easy_face(obj_data, split_statement[1:], active_material) do return .Failure
			}
		case: // default
			return .Unsupported
	}
	return .Ok
}

parse_obj_file :: proc(obj_file_path: string) -> (obj_data: WavefrontObjData, materials: map[string]WavefrontMaterial, ok: bool) {
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
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	it := string(file_contents)
	line_number := 0
	for line in strings.split_lines_iterator(&it) {
		line_number += 1
		trimmed, split_line := trim_and_split_line(line, context.temp_allocator)
		if (len(trimmed) == 0) {
			continue
		}

		// We should never get less than two tokens! Ignore this line as it is invalid, but don't error out.
		if len(split_line) < 2 {
			log_warning("%v:%v: incorrect .obj statement has less than 2 tokens: `%v'", obj_file_path, line_number, line)
			continue
		}

		switch split_line[0] {
			case "mtllib":
				materials = parse_mtl_file(split_line[1], working_dir, context.temp_allocator) or_return
			case "usemtl":
				if split_line[1] not_in materials {
					log_warning("%v:%v: Material `%v' is not found in current materials", file_name, line_number, split_line[1])
					active_material_name = DEFAULT_MATERIAL_NAME
				} else {
					active_material_name = materials[split_line[1]].name
				}
			case:	// Handle vertex directives in their own functions
				#partial switch parse_obj_vertex_statement(trimmed, split_line, &obj_data, &active_material_name) {
					case .Unsupported:
						log_warning("%v:%v: unsupported %v directive", file_name, line_number, split_line[0])
					case .Failure:
						log_error("%v:%v: failed to parse statement", file_name, line_number)
						return
				}
		}
	}

	fmt.printfln("=== Loaded model %v:\n=== %v vertices\n=== %v UVs\n=== %v normals\n=== %v vertex indices\n=== %v materials",
		obj_file_path, len(obj_data.vert_positions), len(obj_data.tex_coords), len(obj_data.normals), len(obj_data.vertex_indices), len(materials))

	if len(materials) == 0 {
		materials[DEFAULT_MATERIAL_NAME] = get_default_material()
	}

	// Assign each material a unique index
	index: u32 = 0
	for _, &mtl in materials {
		mtl.index = index
		index += 1
	}
	ok = true
	return
}

/*
 * Create an array containing all materials, and sets their ID according to lexicographical order
 * of the material names. The array is sorted according to the material ID.
 * This function consumes the material map and clears its contents. The ownership of the WavefrontMaterial
 * structure is passed to the array.
 */
 @(private="file")
consume_materials_map_to_array :: proc(materials_map: ^map[string]WavefrontMaterial) -> []WavefrontMaterial {
	materials_array := make([]WavefrontMaterial, len(materials_map))

	i :u32 = 0
	for key, &material in materials_map {
		materials_array[i] = material
		i += 1
	}
	compare := proc(a, b: WavefrontMaterial) -> bool {
		return a.name < b.name
	}
	slice.sort_by(materials_array, compare)
	for i = 0; i < cast(u32)len(materials_array); i += 1 {
		materials_array[i].index = i
	}
	clear(materials_map)
	return materials_array
}
