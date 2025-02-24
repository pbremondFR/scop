package main
import "core:strings"
import "core:fmt"
import "core:strconv"
import "core:mem/virtual"
import "core:path/filepath"
import "core:math"

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
	delete(mtl.name)
	for path in mtl.texture_paths {
		delete(path)
	}
}

DEFAULT_MATERIAL_NAME : string : "__SCOP_DEFAULT_MATERIAL"

get_default_material :: proc(name: string = DEFAULT_MATERIAL_NAME, loc := #caller_location) -> WavefrontMaterial {
	return WavefrontMaterial {
		name = strings.clone(name),

		Ka = {0.4, 0.4, 0.4},
		Kd = {0.5, 0.5, 0.5},
		Ks = {0.5, 0.5, 0.5},
		Ns = 39,
		Ni = 0.001, // Ni should be clamped between 0.001 and 10.0
	}
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

/*
 * Trim Wavefront Mtl statement/directive of whitespaces and comments. Split this statement into individual tokens.
 *
 * What's that? DRY? Nah. WET. We Enjoy Typing.
 */
@(private="file")
trim_and_split_line :: proc(line: string) -> (trimmed: string, split: []string)
{
	hash_index := strings.index_byte(line, '#')
	trimmed = line[0:(hash_index if hash_index >= 0 else len(line))]
	trimmed = strings.trim_space(trimmed)
	split = strings.fields(trimmed)
	return
}

@(private="file")
ParseResult :: enum {
	Ok,
	Unsupported,
	Failure,
}

@(private="file")
parse_mtl_statement :: proc(split_line: []string, materials: ^map[string]WavefrontMaterial,
	active_material_ptr: ^^WavefrontMaterial) -> ParseResult
{
	active_material := active_material_ptr^

	switch split_line[0] {
		case "newmtl":
			new_material := get_default_material(split_line[1])
			materials[new_material.name] = new_material
			active_material_ptr^ = &materials[new_material.name]
		case "Ka":
			if !parse_vec3(split_line[1:], &active_material.Ka) do return .Failure
		case "Kd":
			if !parse_vec3(split_line[1:], &active_material.Kd) do return .Failure
		case "Ks":
			if !parse_vec3(split_line[1:], &active_material.Ks) do return .Failure
		case "Ns":
			active_material.Ns = strconv.parse_f32(split_line[1]) or_else math.nan_f32()
			if math.is_nan(active_material.Ns) do return .Failure
		case "Tr":
			active_material.d = 1.0 - (strconv.parse_f32(split_line[1]) or_else math.nan_f32())
			if math.is_nan(active_material.d) do return .Failure
		case "d":
			active_material.d = strconv.parse_f32(split_line[1]) or_else math.nan_f32()
			if math.is_nan(active_material.d) do return .Failure
		case "map_Ka":
			active_material.texture_paths[.Map_Ka] = strings.clone(split_line[1])
		case "map_Kd":
			active_material.texture_paths[.Map_Kd] = strings.clone(split_line[1])
		case "map_Ks":
			active_material.texture_paths[.Map_Ks] = strings.clone(split_line[1])
		// case "map_Ns":
		// 	active_material.texture_paths[.Map_Ns] = strings.clone(split_line[1])
		// case "map_d":
		// 	active_material.map_d = strings.clone(split_line[1])
		case "map_bump", "bump":
			active_material.texture_paths[.Map_bump] = strings.clone(split_line[1])
		// case "disp":
		// 	active_material.map_disp = strings.clone(split_line[1])
		// case "decal":
		// 	active_material.decal = strings.clone(split_line[1])
		case: // default
			return .Unsupported
	}
	return .Ok
}

parse_mtl_file :: proc(mtl_file_name: string, working_dir: string) \
	-> (materials: map[string]WavefrontMaterial, ok: bool)
{
	mtl_file_path := filepath.join({working_dir, mtl_file_name})
	defer delete(mtl_file_path)

	file_contents, err := virtual.map_file_from_path(mtl_file_path, {.Read})
	if err != nil {
		fmt.printfln("Error mapping `%v`: %v", mtl_file_path, err)
		return
	}
	defer virtual.release(raw_data(file_contents), len(file_contents))

	materials[DEFAULT_MATERIAL_NAME] = get_default_material()
	active_material : ^WavefrontMaterial = &materials[DEFAULT_MATERIAL_NAME]

	defer if !ok {
		for _, &mtl in materials do delete_WavefrontMaterial(mtl);
		delete(materials)
	}

	// Iterate over every line of the .mtl file
	line_number := 0
	it := string(file_contents)
	for line in strings.split_lines_iterator(&it) {
		line_number += 1
		trimmed, split_line := trim_and_split_line(line)
		if (len(trimmed) == 0) {
			continue
		}

		// We should never get less than two tokens! Ignore this line as it is invalid,
		// but don't error out.
		if len(split_line) < 2 {
			log_warning("%v:%v: incorrect .mtl statement has less than 2 tokens: `%v'",
				mtl_file_name, line_number, line)
			continue
		}

		#partial switch parse_mtl_statement(split_line, &materials, &active_material) {
			case .Unsupported:
				log_note("%v:%v: unsupported %v directive", mtl_file_name, line_number, split_line[0])
			case .Failure:
				log_error("%v:%v: failed to parse statement", mtl_file_name, line_number)
				return

		}
	}
	ok = check_materials_validity(materials)
	return
}

@(private="file")
check_materials_validity :: proc(materials: map[string]WavefrontMaterial) -> (ok: bool)
{
	is_vector_normalized :: proc(vec: Vec3f) -> bool {
		return vec.x >= 0 && vec.y >= 0 && vec.z >= 0 && vec.x <= 1 && vec.y <= 1 && vec.z <= 1
	}

	has_error := false

	for _, &material in materials {
		// Check if all colors are normalized
		colors_to_check := [?]^Vec3f{&material.Ka, &material.Kd, &material.Ks, &material.Tf}
		color_names := [?]string{"Ka", "Kd", "Ks", "Tf"}
		#assert(len(colors_to_check) == len(color_names))

		for color, i in colors_to_check {
			if !is_vector_normalized(color^) {
				log_warning("material `%v': color %v is not normalized (%v)", material.name, color_names[i], color^)
			}
		}

		// Specular exponent bounds check
		if material.Ns < 0 {
			log_error("material `%v': negative specular exponent", material.name)
			has_error = true
		} else if material.Ns > 1000 {
			log_warning("material `%v': very high specular exponent", material.name)
		}
		// Dissolve/transparency bounds check
		if material.d < 0.0 || material.d > 1.0 {
			log_error("material `%v': dissolve is not normalized (%v)", material.name, material.d)
			has_error = true
		}
		// Index of refraction bounds check
		if material.Ni < 0.001 || material.Ni > 10.0 {
			log_error("material `%v': out-of-bounds index of refraction: should be in range [0.001,10], is %v",
				material.name, material.Ni)
			has_error = true
		}
	}
	return has_error == false
}
