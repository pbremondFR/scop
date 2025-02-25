package main

import gl "vendor:OpenGL"

import "core:math/linalg"
import "core:path/filepath"
import "base:runtime"

/*
            ╔══════════════╗
            ║parse_obj_file║
            ╚══╤══════════╤╝
               │          │
               │          │
               │          │
   ╭───────────▼────╮  ╭──▼─────────────────────────╮
   │WavefrontObjData│  │map[string]WavefrontMaterial│
   ╰───────────────┬╯  ╰───────────────┬────────────╯
                   │                   │
model_offset◄──────┤                   │
camera_pos         │                   │
            ╔══════▼══════════════╗    │
            ║obj_data_to_gl_models║◄───┤
            ╚════════╤════════════╝    │
                     │                 │
                 ╭───▼───╮             │
        To GPU◄──┤GlModel│             │
                 ╰───┬───╯             │
                     │      ╔══════════▼═══════════════════════════╗
                     │      ║load_textures_from_wavefront_materials║
                     │      ╚════╤════════════════════════╤════════╝
                     │           │                        │
                     │  ╭────────▼────────────╮     ╭─────▼───────╮
                     │  │map[string]GlMaterial│     │[]GlTextureID│
                     │  ╰─┬──────┬────────────╯     ╰┬────────────╯
                     │    │      │                   ╰►Textures
                     │    │      ╰►To GPU uniform      to GPU
             ╔═══════▼════▼═╗      buffer
             ║RENDERING LOOP║
             ╚══════════════╝
*/

FinalModel :: struct {
	gl_model: GlModel,
	wPosition: Mat4f,
	gl_materials: map[string]GlMaterial,
	materials_ubo: u32,
	gl_textures: []GlTextureID,
}

delete_FinalModel :: proc(model: ^FinalModel)
{
	delete_GlModel(&model.gl_model)

	for _, &material in model.gl_materials do delete(material.name)
	delete(model.gl_materials)

	gl.DeleteBuffers(1, &model.materials_ubo)

	gl.DeleteTextures(i32(len(model.gl_textures)), cast([^]u32)&model.gl_textures)
	delete(model.gl_textures)
}

load_model :: proc(obj_file_path: string) -> (model: FinalModel, ok: bool)
{
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	// obj_data and mtl_materials are allocated with scratch allocator
	obj_data, mtl_materials, obj_ok := parse_obj_file(obj_file_path, context.temp_allocator)
	if !obj_ok {
		log_error("Failed to load %v", obj_file_path)
		return
	}

	set_camera_and_light_pos(obj_data)
	model_pos := get_model_offset_matrix(obj_data)

	// === LOAD MODEL ===
	gl_model := obj_data_to_gl_objects(&obj_data, mtl_materials)
	if gl_model.vao == 0 || gl_model.vbo == 0 || gl_model.ebo == 0 {
		log_error("Failed to load data to GPU")
		return
	}
	assert(gl_model.ebo_len % 3 == 0) // Model is properly "trianglized"

	// === LOAD TEXTURES, CONVERT MATERIALS FROM WAVEFRONT TO OPENGL ===
	wavefront_root_dir := filepath.dir(obj_file_path)
	defer delete(wavefront_root_dir)
	gl_textures, gl_materials, textures_ok := load_textures_from_wavefront_materials(mtl_materials, wavefront_root_dir)
	if !textures_ok {
		log_error("Failed to load textures")
		return
	}

	// === MATERIALS UNIFORM BUFFER ===
	ubo := gl_materials_to_uniform_buffer_object(gl_materials)
	assert(ubo != 0)

	return FinalModel{gl_model, model_pos, gl_materials, ubo, gl_textures}, true
}


@(private="file")
set_camera_and_light_pos :: proc(obj_data: WavefrontObjData)
{
	state.camera.pos = get_initial_camera_pos(obj_data)
	state.camera.mat = get_camera_matrix(state.camera.pos, 0, 0)
	state.light_source_pos = Vec3f{
		-state.camera.pos.z * 2,
		-state.camera.pos.z * 2,
		0,
	}
}

@(private="file")
get_initial_camera_pos :: proc(model: WavefrontObjData) -> Vec3f {
	// Get bounding box around model
	min, max: Vec3f
	for v in model.vert_positions {
		for i in 0..<3 {
			if v[i] < min[i] do min[i] = v[i]
			if v[i] > max[i] do max[i] = v[i]
		}
	}

	// Good approximation of camera spacing around object. We don't need something ultra precise.
	offset := f32(linalg.length((max - min).xz)) * 1
	return {0.0, 0.0, -offset}
}


/*
 * Returns a matrix which offsets the position of a 3D model so that it's completely centered.
 * In other words, the object's origin becomes the geometric center of its bounding box.
 */
@(private="file")
get_model_offset_matrix :: proc(model: WavefrontObjData) -> Mat4f {
	// Get min and max points of bounding box around model
	min, max: Vec3f
	for v in model.vert_positions {
		for i in 0..<3 {
			if v[i] < min[i] do min[i] = v[i]
			if v[i] > max[i] do max[i] = v[i]
		}
	}
	half_diagonal := (max - min) /2
	offset_vec := (min + half_diagonal) * -1
	offset_mat := UNIT_MAT4F
	offset_mat[3][0] = offset_vec.x
	offset_mat[3][1] = offset_vec.y
	offset_mat[3][2] = offset_vec.z
	return offset_mat
}
