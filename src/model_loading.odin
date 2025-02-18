package main

import gl "vendor:OpenGL"

import "core:strings"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "base:runtime"

/*
            ╔══════════════╗
            ║parse_obj_file║
            ╚══════════════╝
               │          │
               │          │
               │          │
   ┌───────────▼────┐  ┌──▼─────────────────────────┐
   │WavefrontObjData│  │map[string]WavefrontMaterial│
   └───────────────┬┘  └───────────────┬────────────┘
                   │                   │
model_offset◄──────┼                   │
camera_pos         │                   │
            ╔══════▼══════════════╗    │
            ║obj_data_to_gl_models║◄───┼
            ╚═════════════════════╝    │
                     │                 │
                 ┌───▼───┐             │
        To GPU◄──┤GlModel│             │
                 └───┬───┘             │
                     │      ╔══════════▼═══════════════════════════╗
                     │      ║load_textures_from_wavefront_materials║
                     │      ╚════┬════════════════════════┬════════╝
                     │           │                        │
                     │  ┌────────▼────────────┐     ┌─────▼───────┐
                     │  │map[string]GlMaterial│     │[]GlTextureID│
                     │  └─┬──────┬────────────┘     └┬────────────┘
                     │    │      │                   └►Textures
                     │    │      └►To GPU uniform      to GPU
             ╔═══════▼════▼═╗      buffer
             ║RENDERING LOOP║
             ╚══════════════╝
*/

load_model :: proc(obj_file_path: string) -> (model: GlModel, materials: map[string]GlMaterial, textures: []GlTextureID, ok: bool)
{
	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	obj_data, mtl_materials, obj_ok := parse_obj_file(obj_file_path, context.temp_allocator)
	// XXX: These defer calls are fine even in case of error
	defer {
		// delete_WavefrontObjFile(obj_data)
		for _, &mtl in mtl_materials do delete_WavefrontMaterial(mtl)
		delete(mtl_materials)
	}
	if !obj_ok {
		fmt.printfln("Failed to load `%v`", obj_file_path)
		return
	}

	set_camera_and_model_pos(obj_data)

	// === LOAD MODEL ===
	gl_model := obj_data_to_gl_objects(&obj_data, mtl_materials)
	assert(gl_model.vao != 0 && gl_model.vbo != 0 && gl_model.ebo != 0)

	// === LOAD TEXTURES, CONVERT MATERIALS FROM WAVEFRONT TO OPENGL ===
	wavefront_root_dir := filepath.dir(obj_file_path)
	defer delete(wavefront_root_dir)
	gl_textures, gl_materials, textures_ok := load_textures_from_wavefront_materials(mtl_materials, wavefront_root_dir)
	if !textures_ok {
		fmt.println("Error loading textures")
		return
	}
	// defer {
	// 	gl.DeleteTextures(i32(len(gl_textures)), cast([^]u32)&gl_textures)
	// 	delete(gl_textures)
	// 	for _, &material in gl_materials do delete(material.name)
	// 	delete(gl_materials)
	// }

	// === MATERIALS UNIFORM BUFFER ===
	ubo := gl_materials_to_uniform_buffer_object(gl_materials)
	defer gl.DeleteBuffers(1, &ubo)
	assert(ubo != 0)

	return gl_model, gl_materials, gl_textures, true
}


@(private="file")
set_camera_and_model_pos :: proc(obj_data: WavefrontObjData)
{
	state.model_offset = get_model_offset_matrix(obj_data)
	state.camera.pos = get_initial_camera_pos(obj_data)
	state.camera.mat = get_camera_matrix(state.camera.pos, 0, 0)
	state.light_source_pos = Vec3f{
		-state.camera.pos.z * 2,
		-state.camera.pos.z * 2,
		0,
	}
}
