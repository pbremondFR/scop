package main
import "core:strings"
import "core:fmt"
import "core:strconv"
import "core:mem/virtual"
import "core:path/filepath"
import "base:runtime"

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
	 // Split current line into tokens with temp_allocator to parse easily
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
			active_material_name := split_line[1]
			new_material := get_default_material(active_material_name)
			materials[new_material.name] = new_material
			active_material_ptr^ = &materials[new_material.name]
		case "Ka":
			if !parse_vec3(split_line[1:], &active_material.Ka) do return .Failure
		case "Kd":
			if !parse_vec3(split_line[1:], &active_material.Kd) do return .Failure
		case "Ks":
			if !parse_vec3(split_line[1:], &active_material.Ks) do return .Failure
		case "Ns":
			active_material.Ns = strconv.parse_f32(split_line[1]) or_else 32
		case "Tr":
			active_material.d = 1.0 - (strconv.parse_f32(split_line[1]) or_else 0.0)
		case "d":
			active_material.d = strconv.parse_f32(split_line[1]) or_else 0.0
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

parse_mtl_file :: proc(mtl_file_name: string, working_dir: string) -> (materials: map[string]WavefrontMaterial, ok: bool) {
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

		// We should never get less than two tokens! Ignore this line as it is invalid, but don't error out.
		if len(split_line) < 2 {
			log_warning("%v:%v: incorrect .mtl statement has less than 2 tokens: `%v'", mtl_file_name, line_number, line)
			continue
		}

		#partial switch parse_mtl_statement(split_line, &materials, &active_material) {
			case .Unsupported:
				log_note("%v:%v: unsupported %v directive", mtl_file_name, line_number, split_line[0])
			case .Failure:
				log_error("%v:%v: failed to parse statement", mtl_file_name, line_number)

		}
	}
	ok = true
	return
}
