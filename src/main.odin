package main

import gl "vendor:OpenGL"
import "vendor:glfw"

import "core:fmt"
import "core:strings"
import "core:slice"
import "core:os"
import "core:math"

// For tracking allocator (debug)
import "core:mem"
// Silence unused import warning when in release mode
_ :: mem

WINDOW_NAME :: "ft_scop"

GL_MAJOR_VERSION :: 4
GL_MINOR_VERSION :: 2

PLAYER_TRANSLATE_SPEED	:f32 : 30
PLAYER_ROTATION_SPEED	:f32 : 2
PLAYER_FOV_SPEED		:f32 : 1

ShaderProgram :: enum {
	DefaultShader,
	FaceNormals,
	VertNormals,
	TransparencyShader,
	// XXX: LEAVE THESE ONES LAST AND IN THIS ORDER
	VertNormVectors,
	LightSource,
}

State :: struct {
	window_size: [2]i32,
	fov: f32,
	dt: f64,
	glfw_inputs: map[i32]bool,

	camera: PlayerCamera,
	light_source_pos: Vec3f,
	enable_model_spin: bool,
	shader_program: ShaderProgram,
	enable_normals_view: bool,
	normals_view_length: f32,
	show_textures: bool,
	texture_factor: f32,
}

state := State{
	window_size = {1024, 1024},
	fov = math.to_radians_f32(70.0),
	shader_program = .DefaultShader,
	normals_view_length = 1.0,
	show_textures = true,
	texture_factor = 1.0,
}

main :: proc() {

	// Odin tracking allocator to detect leaks and double frees.
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	if len(os.args) != 2 || !strings.ends_with(os.args[1], ".obj") {
		fmt.printfln("usage: %v obj_file.obj", os.args[0]);
		return
	}

	// === INIT OPENGL ===
	window, opengl_ok := init_OpenGL()
	if !opengl_ok do return
	defer {
		glfw.Terminate()
		glfw.DestroyWindow(window)
	}

	// ===== SHADERS =====
	shader_programs := [ShaderProgram]u32 {
		.DefaultShader		= get_shader_program("shaders/vertex.vert", "shaders/default.frag") or_else 0,
		.FaceNormals		= get_shader_program("shaders/vertex.vert", "shaders/face_normals.frag") or_else 0,
		.VertNormals		= get_shader_program("shaders/vertex.vert", "shaders/vert_normals.frag") or_else 0,
		.TransparencyShader	= get_shader_program("shaders/vertex.vert", "shaders/transparency.frag") or_else 0,
		.VertNormVectors	= get_shader_program("shaders/vert_norm_vectors.vert", "shaders/vert_norm_vectors.frag", "shaders/vert_norm_vectors.geom") or_else 0,
		.LightSource		= get_shader_program("shaders/light_source.vert", "shaders/light_source.frag") or_else 0,
	}
	if slice.contains(slice.enumerated_array(&shader_programs), 0) do return
	// Braces here are optional, but better for readability IMO
	defer { for id in shader_programs do gl.DeleteProgram(id) }

	// === LOAD LIGHT CUBE ===
	light_vao, light_vbo, light_ok := create_light_cube()
	if !light_ok do return
	defer {
		gl.DeleteVertexArrays(1, &light_vao)
		gl.DeleteBuffers(1, &light_vbo)
	}

	// Assign texture units to shader uniforms. They don't need to be dynamic, so they just match the enum.
	gl.UseProgram(shader_programs[.DefaultShader])
	set_shader_uniform(shader_programs[.DefaultShader], "texture_Ka", i32(TextureUnit.Map_Ka))
	set_shader_uniform(shader_programs[.DefaultShader], "texture_Kd", i32(TextureUnit.Map_Kd))
	set_shader_uniform(shader_programs[.DefaultShader], "texture_Ks", i32(TextureUnit.Map_Ks))
	set_shader_uniform(shader_programs[.DefaultShader], "texture_Ns", i32(TextureUnit.Map_Ns))
	set_shader_uniform(shader_programs[.DefaultShader], "texture_d", i32(TextureUnit.Map_d))
	set_shader_uniform(shader_programs[.DefaultShader], "texture_bump", i32(TextureUnit.Map_bump))
	set_shader_uniform(shader_programs[.DefaultShader], "texture_disp", i32(TextureUnit.Map_disp))
	set_shader_uniform(shader_programs[.DefaultShader], "texture_decal", i32(TextureUnit.Decal))
	gl.UseProgram(shader_programs[state.shader_program])

	// === LOAD MAIN MODEL ===
	main_model, model_ok := load_model(os.args[1])
	if !model_ok {
		return
	}
	defer delete_FinalModel(&main_model)

	// Enable backface culling
	// gl.Enable(gl.CULL_FACE)
	// gl.CullFace(gl.BACK)

	gl.Enable(gl.BLEND);
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

	gl.Enable(gl.DEPTH_TEST)
	gl.ClearColor(0.0, 0.0, 0.0, 1.0)

	old_time, time: f64 = glfw.GetTime(), glfw.GetTime()

	for (!glfw.WindowShouldClose(window)) {
		glfw.PollEvents()

		// Calculate delta-time since last frame
		time = glfw.GetTime()
		state.dt = time - old_time
		old_time = time

		process_player_movements()

		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		// gl.BindTexture(gl.TEXTURE_2D, texture.id)
		gl.UseProgram(shader_programs[state.shader_program])

		aspect_ratio := f32(state.window_size.x) / f32(state.window_size.y)

		@(static) time_accum: f64 = 0
		if state.enable_model_spin {
			time_accum += state.dt
		}
		model_matrix := get_rotation_matrix4_y_axis(cast(f32)time_accum) * main_model.wPosition
		// TODO: Determine far plane distance based on object size?
		proj_matrix := get_perspective_projection_matrix(state.fov, aspect_ratio, 0.1, 1500)
		state.texture_factor += f32(state.dt if state.show_textures else -state.dt)
		state.texture_factor = clamp(state.texture_factor, 0.0, 1.0)

		set_shader_uniform(shader_programs[state.shader_program], "model", &model_matrix)
		set_shader_uniform(shader_programs[state.shader_program], "view", &state.camera.mat)
		set_shader_uniform(shader_programs[state.shader_program], "projection", &proj_matrix)
		set_shader_uniform(shader_programs[state.shader_program], "light_pos", &state.light_source_pos)
		set_shader_uniform(shader_programs[state.shader_program], "light_color", &Vec3f{1, 1, 1})
		set_shader_uniform(shader_programs[state.shader_program], "view_pos", &state.camera.pos)
		set_shader_uniform(shader_programs[state.shader_program], "texture_factor", state.texture_factor)
		// Precomputing the MVP matrix saves a lot of computation time on the GPU
		mvp_matrix := proj_matrix * state.camera.mat * model_matrix
		set_shader_uniform(shader_programs[state.shader_program], "mvp", &mvp_matrix)

		gl.BindVertexArray(main_model.gl_model.vao)

		// OLD WAY: DRAW EVERYTHING
		// gl.DrawElements(gl.TRIANGLES, main_model.gl_model.ebo_len, gl.UNSIGNED_INT, nil)

		// NEW WIP WAY: DRAW EACH MATERIAL SEPARATELY (will be useful for transparency)
		// Is also used so that different materials with different textures can be used
		for range in main_model.gl_model.index_ranges {
			material :^GlMaterial = main_model.gl_materials_by_index[range.material_index]
			// Activate & bind relevant texture units for this material
			for unit in TextureUnit {
				if material.textures[unit] != 0 {
					gl.ActiveTexture(gl.TEXTURE0 + u32(unit))
					gl.BindTexture(gl.TEXTURE_2D, u32(material.textures[unit]))
				}
			}
			gl.DrawElements(gl.TRIANGLES, range.length, gl.UNSIGNED_INT, rawptr(range.begin * size_of(u32)))
		}

		// === VISUALIZE VERTEX NORMAL VECTORS ===
		if state.enable_normals_view {
			gl.UseProgram(shader_programs[.VertNormVectors])
			set_shader_uniform(shader_programs[.VertNormVectors], "mvp", &mvp_matrix)
			set_shader_uniform(shader_programs[.VertNormVectors], "vec_norm_len", state.normals_view_length)
			gl.DrawElements(gl.POINTS, main_model.gl_model.ebo_len, gl.UNSIGNED_INT, nil)
		}

		// === DRAW LIGHT CUBE ===
		draw_light_cube(light_vao, shader_programs[.LightSource], &proj_matrix, f32(time))

		glfw.SwapBuffers(window)
	}

}

size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
	state.window_size = {width, height}
}

init_OpenGL :: proc() -> (window: glfw.WindowHandle, ok: bool) {
	if(glfw.Init() != true){
		log_error("Failed to initialize GLFW")
		return
	}
	glfw.WindowHint(glfw.RESIZABLE, 1)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)

	window = glfw.CreateWindow(state.window_size.x, state.window_size.y, WINDOW_NAME, nil, nil)

	if window == nil {
		log_error("Failed to create window")
		return
	}

	glfw.MakeContextCurrent(window)

	// Enable vsync
	glfw.SwapInterval(1)

	glfw.SetKeyCallback(window, key_callback)

	glfw.SetFramebufferSizeCallback(window, size_callback)

	gl.load_up_to(GL_MAJOR_VERSION, GL_MINOR_VERSION, glfw.gl_set_proc_address)
	ok = true
	return
}
