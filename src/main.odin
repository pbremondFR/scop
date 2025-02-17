// GLFW and OpenGL example with very verbose comments and links to documentation for learning
// By Soren Saket

// semi-colons ; are not requied in odin
//

// Every Odin script belongs to a package
// Define the package with the package [packageName] statement
// The main package name is reserved for the program entry point package
// You cannot have two different packages in the same directory
// If you want to create another package create a new directory and name the package the same as the directory
// You can then import the package with the import keyword
// https://odin-lang.org/docs/overview/#packages
package main

// Import statement
// https://odin-lang.org/docs/overview/#packages

// Odin by default has two library collections. Core and Vendor
// Core contains the default library all implemented in the Odin language
// Vendor contains bindings for common useful packages aimed at game and software development
// https://odin-lang.org/docs/overview/#import-statement

// fmt contains formatted I/O procedures.
// https://pkg.odin-lang.org/core/fmt/
import "core:fmt"
// C interoperation compatibility
import "core:c"

// Here we import OpenGL and rename it to gl for short
import gl "vendor:OpenGL"
// We use GLFW for cross platform window creation and input handling
import "vendor:glfw"

import "core:strings"
import "base:runtime"

import "core:os"
import "core:math/linalg"
import "core:math"
import "core:path/filepath"

// You can set constants with ::
WINDOW_NAME :: "ft_scop"

// GL_VERSION define the version of OpenGL to use. Here we use 4.6 which is the newest version
// You might need to lower this to 3.3 depending on how old your graphics card is.
// Constant with explicit type for example
GL_MAJOR_VERSION : c.int : 4
// Constant with type inference
GL_MINOR_VERSION :: 6

PLAYER_TRANSLATE_SPEED	:f32 : 30
PLAYER_ROTATION_SPEED	:f32 : 2
PLAYER_FOV_SPEED		:f32 : 1

ShaderProgram :: enum {
	FaceNormals,
	VertNormals,
	Texture,
	RawMaterial,
	DefaultShader,
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
}

state := State{
	window_size = {1024, 1024},
	fov = math.to_radians_f32(70.0),
	shader_program = .DefaultShader,
	normals_view_length = 1.0,
}

// For tracking allocator below (leaks/double free debugging)
import "core:mem"

main :: proc() {

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

	if len(os.args) < 2 {
		fmt.println("Please give the 3D model .obj as an argument")
		return
	}

	// Get desired .obj file from program arguments. main() doesn't take args,
	// it's more like in Python with os.args
	file_path := os.args[1]
	obj_data, mtl_materials, obj_ok := parse_obj_file(file_path)
	// XXX: These defer calls are fine even in case of error
	defer {
		delete_ObjFileData(obj_data)
		for _, &mtl in mtl_materials do delete_WavefrontMaterial(mtl)
		delete(mtl_materials)
	}
	if !obj_ok {
		fmt.printfln("Failed to load `%v`", file_path)
		return
	}

	model_offset := get_model_offset_matrix(obj_data)
	state.camera.pos = get_initial_camera_pos(obj_data)
	state.camera.mat = get_camera_matrix(state.camera.pos, 0, 0)
	state.light_source_pos = Vec3f{
		-state.camera.pos.z * 2,
		-state.camera.pos.z * 2,
		0,
	}

	// === INIT OPENGL ===
	window, opengl_ok := init_OpenGL()
	if !opengl_ok {
		return
	}
	defer {
		glfw.Terminate()
		glfw.DestroyWindow(window)
	}

	// ===== SHADERS =====
	shader_programs := [ShaderProgram]u32 {
		.FaceNormals		= get_shader_program("shaders/vertex.vert", "shaders/face_normals.frag") or_else 0,
		.VertNormals		= get_shader_program("shaders/vertex.vert", "shaders/vert_normals.frag") or_else 0,
		.Texture			= get_shader_program("shaders/vertex.vert", "shaders/texture.frag") or_else 0,
		.RawMaterial		= get_shader_program("shaders/vertex.vert", "shaders/raw_material.frag") or_else 0,
		.DefaultShader		= get_shader_program("shaders/vertex.vert", "shaders/default.frag") or_else 0,
		.TransparencyShader	= get_shader_program("shaders/vertex.vert", "shaders/transparency.frag") or_else 0,
		.VertNormVectors	= get_shader_program("shaders/vert_norm_vectors.vert", "shaders/vert_norm_vectors.frag", "shaders/vert_norm_vectors.geom") or_else 0,
		.LightSource		= get_shader_program("shaders/light_source.vert", "shaders/light_source.frag") or_else 0,
	}
	for program in shader_programs {
		if program == 0 {
			fmt.println("Error creating shaders")
			return
		}
	}
	defer {
		for id in shader_programs do gl.DeleteProgram(id)
	}

	// === LOAD MAIN MODEL ===
	main_model: GlModel = obj_data_to_gl_objects(&obj_data, mtl_materials)
	assert(main_model.vao != 0 && main_model.vbo != 0 && main_model.ebo != 0)
	defer {
		gl.DeleteVertexArrays(1, &main_model.vao)
		gl.DeleteBuffers(1, &main_model.vbo)
		gl.DeleteBuffers(1, &main_model.ebo)
		delete(main_model.index_ranges)
	}

	// === LOAD LIGHT CUBE ===
	light_vao, light_vbo := create_light_source()
	assert(light_vao != 0 && light_vbo != 0)
	defer {
		gl.DeleteVertexArrays(1, &light_vao)
		gl.DeleteBuffers(1, &light_vbo)
	}

	// === LOAD TEXTURES, CONVERT MATERIALS FROM WAVEFRONT TO OPENGL
	wavefront_root_dir := filepath.dir(os.args[1])
	defer delete(wavefront_root_dir)
	gl_textures, gl_materials, textures_ok := load_textures_from_wavefront_materials(mtl_materials, wavefront_root_dir)
	if !textures_ok {
		fmt.println("Error loading textures")
		return
	}
	defer {
		gl.DeleteTextures(i32(len(gl_textures)), cast([^]u32)&gl_textures)
		delete(gl_textures)
		for _, &material in gl_materials do delete(material.name)
		delete(gl_materials)
	}
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

	// === MATERIALS UNIFORM BUFFER ===
	ubo: u32
	gl.GenBuffers(1, &ubo)
	gl.BindBuffer(gl.UNIFORM_BUFFER, ubo)
	uniform_buffer_data := gl_materials_to_uniform_buffer(gl_materials)
	gl.BufferData(gl.UNIFORM_BUFFER, len(uniform_buffer_data) * size_of(uniform_buffer_data[0]),
		raw_data(uniform_buffer_data), gl.STATIC_DRAW)
	gl.BindBuffer(gl.UNIFORM_BUFFER, 0)
	gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, ubo)
	delete(uniform_buffer_data)

	// Enable backface culling
	// gl.Enable(gl.CULL_FACE)
	// gl.CullFace(gl.BACK)

	gl.Enable(gl.BLEND);
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

	gl.Enable(gl.DEPTH_TEST)
	gl.ClearColor(0.2, 0.3, 0.3, 1.0)
	gl.ClearColor(0.0, 0.0, 0.0, 1.0)

	old_time, time: f64 = glfw.GetTime(), glfw.GetTime()

	// There is only one kind of loop in Odin called for
	// https://odin-lang.org/docs/overview/#for-statement
	for (!glfw.WindowShouldClose(window)) {
		// Process waiting events in queue
		// https://www.glfw.org/docs/3.3/group__window.html#ga37bd57223967b4211d60ca1a0bf3c832
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
		model_matrix := get_rotation_matrix4_y_axis(cast(f32)time_accum) * model_offset
		// TODO: Determine far plane distance based on object size?
		proj_matrix := get_perspective_projection_matrix(state.fov, aspect_ratio, 0.1, 1500)

		set_shader_uniform(shader_programs[state.shader_program], "model", &model_matrix)
		set_shader_uniform(shader_programs[state.shader_program], "view", &state.camera.mat)
		set_shader_uniform(shader_programs[state.shader_program], "projection", &proj_matrix)
		set_shader_uniform(shader_programs[state.shader_program], "light_pos", &state.light_source_pos)
		set_shader_uniform(shader_programs[state.shader_program], "light_color", &Vec3f{1, 1, 1})
		set_shader_uniform(shader_programs[state.shader_program], "view_pos", &state.camera.pos)
		// Precomputing the MVP matrix saves a lot of computation time on the GPU
		mvp_matrix := proj_matrix * state.camera.mat * model_matrix
		set_shader_uniform(shader_programs[state.shader_program], "mvp", &mvp_matrix)

		gl.BindVertexArray(main_model.vao)

		// TODO: Measure performance impact of these two methods
		// OLD WAY: DRAW EVERYTHING
		// gl.DrawElements(gl.TRIANGLES, main_model.ebo_len, gl.UNSIGNED_INT, nil)

		// NEW WAY: DRAW EACH MATERIAL SEPARATELY (will be useful for transparency)
		for range in main_model.index_ranges {
			for _, &material in gl_materials {
				if material.index == range.material_index {
					for unit in TextureUnit {
						if material.textures[unit] == 0 {
							continue
						}
						gl.ActiveTexture(gl.TEXTURE0 + u32(unit))
						gl.BindTexture(gl.TEXTURE_2D, u32(material.textures[unit]))
					}
				}
			}
			gl.DrawElements(gl.TRIANGLES, range.length, gl.UNSIGNED_INT, rawptr(range.begin * size_of(u32)))
		}

		// === VISUALIZE VERTEX NORMAL VECTORS ===
		if state.enable_normals_view {
			gl.UseProgram(shader_programs[.VertNormVectors])
			set_shader_uniform(shader_programs[.VertNormVectors], "mvp", &mvp_matrix)
			set_shader_uniform(shader_programs[.VertNormVectors], "vec_norm_len", state.normals_view_length)
			gl.DrawElements(gl.POINTS, main_model.ebo_len, gl.UNSIGNED_INT, nil)
		}

		// === DRAW LIGHT CUBE ===
		gl.UseProgram(shader_programs[.LightSource])

		cube_model_matrix := get_light_cube_model_matrix(state.light_source_pos, f32(time))
		set_shader_uniform(shader_programs[.LightSource], "light_pos", &state.light_source_pos)
		set_shader_uniform(shader_programs[.LightSource], "light_color", &Vec3f{1, 1, 1})
		set_shader_uniform(shader_programs[.LightSource], "model", &cube_model_matrix)
		set_shader_uniform(shader_programs[.LightSource], "view", &state.camera.mat)
		set_shader_uniform(shader_programs[.LightSource], "projection", &proj_matrix)

		gl.BindVertexArray(light_vao)
		gl.DrawArrays(gl.TRIANGLES, 0, 36)

		glfw.SwapBuffers(window)
	}

}

get_initial_camera_pos :: proc(model: WavefrontObjFile) -> Vec3f {
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

get_model_offset_matrix :: proc(model: WavefrontObjFile) -> Mat4f {
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

get_light_cube_model_matrix :: proc(cube_position: Vec3f, time: f32) -> (cube_model_matrix: Mat4f) {
	cube_model_matrix = UNIT_MAT4F
	cube_model_matrix[3].xyz = cube_position
	return cube_model_matrix * get_rotation_matrix4_x_axis(time) * get_rotation_matrix4_y_axis(time)
}

create_light_source :: proc() -> (light_vao, light_vbo: u32) {
	cube_vertices := [?]f32{
		// Back face
		-0.5, -0.5, -0.5, // Bottom-left
		0.5, -0.5, -0.5, // bottom-right
		0.5,  0.5, -0.5, // top-right
		0.5,  0.5, -0.5, // top-right
		-0.5,  0.5, -0.5, // top-left
		-0.5, -0.5, -0.5, // bottom-left
		// Front face
		-0.5, -0.5,  0.5, // bottom-left
		0.5,  0.5,  0.5, // top-right
		0.5, -0.5,  0.5, // bottom-right
		0.5,  0.5,  0.5, // top-right
		-0.5, -0.5,  0.5, // bottom-left
		-0.5,  0.5,  0.5, // top-left
		// Left face
		-0.5,  0.5,  0.5, // top-right
		-0.5, -0.5, -0.5, // bottom-left
		-0.5,  0.5, -0.5, // top-left
		-0.5, -0.5, -0.5, // bottom-left
		-0.5,  0.5,  0.5, // top-right
		-0.5, -0.5,  0.5, // bottom-right
		// Right face
		0.5,  0.5,  0.5, // top-left
		0.5,  0.5, -0.5, // top-right
		0.5, -0.5, -0.5, // bottom-right
		0.5, -0.5, -0.5, // bottom-right
		0.5, -0.5,  0.5, // bottom-left
		0.5,  0.5,  0.5, // top-left
		// Bottom face
		-0.5, -0.5, -0.5, // top-right
		0.5, -0.5,  0.5, // bottom-left
		0.5, -0.5, -0.5, // top-left
		0.5, -0.5,  0.5, // bottom-left
		-0.5, -0.5, -0.5, // top-right
		-0.5, -0.5,  0.5, // bottom-right
		// Top face
		-0.5,  0.5, -0.5, // top-left
		0.5,  0.5, -0.5, // top-right
		0.5,  0.5,  0.5, // bottom-right
		0.5,  0.5,  0.5, // bottom-right
		-0.5,  0.5,  0.5, // bottom-left
		-0.5,  0.5, -0.5  // top-left
	}

	// TODO: Error checking?
	gl.GenBuffers(1, &light_vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, light_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(cube_vertices) * size_of(cube_vertices[0]),
		raw_data(cube_vertices[:]), gl.STATIC_DRAW)

	gl.GenVertexArrays(1, &light_vao)
	gl.BindVertexArray(light_vao)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * size_of(f32), 0)
	gl.EnableVertexAttribArray(0)

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	return
}

process_player_movements :: proc() {
	movement: Vec3f = {0, 0, 0}
	look: Vec3f = {0, 0, 0}
	fov_delta: f32 = 0

	PITCH_LIMIT :: 1.55334

	if state.glfw_inputs[glfw.KEY_W]			do movement.z += 1
	if state.glfw_inputs[glfw.KEY_S]			do movement.z -= 1
	if state.glfw_inputs[glfw.KEY_D]			do movement.x -= 1
	if state.glfw_inputs[glfw.KEY_A]			do movement.x += 1
	if state.glfw_inputs[glfw.KEY_SPACE]		do movement.y -= 1
	if state.glfw_inputs[glfw.KEY_LEFT_SHIFT]	do movement.y += 1

	if state.glfw_inputs[glfw.KEY_UP]		do look.y -= 1
	if state.glfw_inputs[glfw.KEY_DOWN]		do look.y += 1
	if state.glfw_inputs[glfw.KEY_LEFT]		do look.x -= 1
	if state.glfw_inputs[glfw.KEY_RIGHT]	do look.x += 1
	if state.glfw_inputs[glfw.KEY_Q]		do look.z += 1
	if state.glfw_inputs[glfw.KEY_E]		do look.z -= 1

	if state.glfw_inputs[glfw.KEY_Z]	do fov_delta += 1
	if state.glfw_inputs[glfw.KEY_X]	do fov_delta -= 1

	if length := linalg.length(movement); length != 0 {
		movement /= length
		movement *= f32(state.dt) * PLAYER_TRANSLATE_SPEED
	}
	if length := linalg.length(look); length != 0 {
		look /= length
		look *= f32(state.dt) * PLAYER_ROTATION_SPEED
	}

	pitch := look.y
	yaw := look.x

	// Clamp pitch to a limit, like in FPS games
	state.camera.pitch = math.clamp(state.camera.pitch + pitch, -PITCH_LIMIT, PITCH_LIMIT)
	state.camera.yaw += yaw

	// Stabilize movement vector on horizontal plane
	upwards_camera := get_rotation_matrix4_x_axis(-state.camera.pitch) * state.camera.mat
	state.camera.pos += movement * Mat3f(upwards_camera)

	// Apply camera matrix transformation
	state.camera.mat = get_camera_matrix(state.camera.pos, state.camera.pitch, state.camera.yaw)
	state.fov += fov_delta * f32(state.dt) * PLAYER_FOV_SPEED
}


key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()

	// Exit program on escape pressed
	if key == glfw.KEY_ESCAPE {
		glfw.SetWindowShouldClose(window, true)
	}
	else if key == glfw.KEY_ENTER && action == glfw.PRESS {
		// Static variables are like in C
		@(static) wireframe := false
		wireframe = !wireframe
		// Odin-style ternary (looks cool, but a bit weird coming from C, order is different)
		gl.PolygonMode(gl.FRONT_AND_BACK, gl.LINE if wireframe else gl.FILL)
		// You can also use C-style ternaries! YAAAAY
		// gl.PolygonMode(gl.FRONT_AND_BACK, wireframe ? gl.LINE : gl.FILL)
		if wireframe {
			gl.Disable(gl.CULL_FACE)
		} else {
			gl.Enable(gl.CULL_FACE)
		}
	}
	else if key == glfw.KEY_R && action == glfw.PRESS {
		state.enable_model_spin = !state.enable_model_spin
	}
	else if key == glfw.KEY_F && action == glfw.PRESS {
		state.light_source_pos = -state.camera.pos
	}
	else if (key >= glfw.KEY_1 && key <= glfw.KEY_6) && action == glfw.PRESS {
		selected_shader := cast(ShaderProgram)(key - glfw.KEY_1)
		fmt.println("Selecting shader", selected_shader)
		state.shader_program = selected_shader
	}
	else if key == glfw.KEY_N && action == glfw.PRESS {
		state.enable_normals_view = !state.enable_normals_view
	}
	else if (key == glfw.KEY_COMMA || key == glfw.KEY_PERIOD) {
		STEP :: 0.25
		delta :f32 = -STEP if key == glfw.KEY_COMMA else STEP;
		state.normals_view_length = math.max(state.normals_view_length + delta, 0 + STEP)
	}

	if action == glfw.PRESS {
		state.glfw_inputs[key] = true
	}
	else if action == glfw.RELEASE {
		state.glfw_inputs[key] = false
	}
}

size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	gl.Viewport(0, 0, width, height)
	state.window_size = {width, height}
}

init_OpenGL :: proc() -> (window: glfw.WindowHandle, ok: bool) {
	// GLFW_TRUE if successful, or GLFW_FALSE if an error occurred.
	if(glfw.Init() != true){
		fmt.println("Failed to initialize GLFW")
		return
	}
	// Set Window Hints
	// https://www.glfw.org/docs/3.3/window_guide.html#window_hints
	// https://www.glfw.org/docs/3.3/group__window.html#ga7d9c8c62384b1e2821c4dc48952d2033
	glfw.WindowHint(glfw.RESIZABLE, 1)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, GL_MAJOR_VERSION)
	glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, GL_MINOR_VERSION)
	glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
	// https://www.glfw.org/docs/3.1/group__init.html#gaaae48c0a18607ea4a4ba951d939f0901

	// https://www.glfw.org/docs/3.3/group__window.html#ga3555a418df92ad53f917597fe2f64aeb
	window = glfw.CreateWindow(state.window_size.x, state.window_size.y, WINDOW_NAME, nil, nil)
	// https://www.glfw.org/docs/latest/group__window.html#gacdf43e51376051d2c091662e9fe3d7b2

	// If the window pointer is invalid
	if window == nil {
		fmt.println("Unable to create window")
		return
	}

	// https://www.glfw.org/docs/3.3/group__context.html#ga1c04dc242268f827290fe40aa1c91157
	glfw.MakeContextCurrent(window)

	// Enable vsync
	// https://www.glfw.org/docs/3.3/group__context.html#ga6d4e0cdf151b5e579bd67f13202994ed
	glfw.SwapInterval(1)

	// This function sets the key callback of the specified window, which is called when a key is pressed, repeated or released.
	// https://www.glfw.org/docs/3.3/group__input.html#ga1caf18159767e761185e49a3be019f8d
	glfw.SetKeyCallback(window, key_callback)

	// This function sets the framebuffer resize callback of the specified window, which is called when the framebuffer of the specified window is resized.
	// https://www.glfw.org/docs/3.3/group__window.html#gab3fb7c3366577daef18c0023e2a8591f
	glfw.SetFramebufferSizeCallback(window, size_callback)

	// Set OpenGL Context bindings using the helper function
	// See Odin Vendor source for specifc implementation details
	// https://github.com/odin-lang/Odin/tree/master/vendor/OpenGL
	// https://www.glfw.org/docs/3.3/group__context.html#ga35f1837e6f666781842483937612f163

	// casting the c.int to int
	// This is needed because the GL_MAJOR_VERSION has an explicit type of c.int
	gl.load_up_to(int(GL_MAJOR_VERSION), GL_MINOR_VERSION, glfw.gl_set_proc_address)
	ok = true
	return
}
