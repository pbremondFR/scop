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
}

State :: struct {
	window_size: [2]i32,
	fov: f32,
	dt: f64,
	glfw_inputs: map[i32]bool,
	player_cam: Mat4f,
	enable_model_spin: bool,
	shader_program: ShaderProgram,
}

state := State{
	window_size = {1024, 1024},
	fov = math.to_radians_f32(70.0),
	// TODO: Initialize player camera to a position that adapts to the object's size
	player_cam = {
		1.0, 0.0, 0.0, 0.0,
		0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, -15.0,
		0.0, 0.0, 0.0, 1.0,
	},
	shader_program = .FaceNormals,
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
	defer glfw.Terminate()

	// https://www.glfw.org/docs/3.3/group__window.html#ga3555a418df92ad53f917597fe2f64aeb
	window := glfw.CreateWindow(state.window_size.x, state.window_size.y, WINDOW_NAME, nil, nil)
	// https://www.glfw.org/docs/latest/group__window.html#gacdf43e51376051d2c091662e9fe3d7b2
	defer glfw.DestroyWindow(window)

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

	// Get desired .obj file from program arguments. main() doesn't take args,
	// it's nore like in Python with os.args
	file_path := os.args[1]
	obj_data, obj_ok := parse_obj_file(file_path)
	if !obj_ok {
		fmt.printfln("Failed to load `%v`", file_path)
		return
	}
	defer delete_ObjFileData(obj_data)

	model_offset := get_model_offset_matrix(obj_data)

	// ===== SHADERS =====
	shader_programs := [ShaderProgram]u32 {
		.FaceNormals = get_shader_program("shaders/vertex.vert", "shaders/face_normals.frag") or_else 0,
		.VertNormals = get_shader_program("shaders/vertex.vert", "shaders/vert_normals.frag") or_else 0,
		.Texture = get_shader_program("shaders/vertex.vert", "shaders/texture.frag") or_else 0,
	}
	if shader_programs[.FaceNormals] == 0 || shader_programs[.VertNormals] == 0 \
		|| shader_programs[.Texture] == 0
	{
		fmt.printfln("Error creating shaders")
		return
	}
	defer {
		for id in shader_programs do gl.DeleteProgram(id)
	}

	// Setup VAO, VBO, EBO
	vao, vbo, ebo: u32
	gl.GenVertexArrays(1, &vao)
	defer gl.DeleteVertexArrays(1, &vao)
	gl.GenBuffers(1, &vbo)
	defer gl.DeleteBuffers(1, &vbo)
	gl.GenBuffers(1, &ebo)
	defer gl.DeleteBuffers(1, &ebo)

	gl.BindVertexArray(vao)

	vertex_buffer, index_buffer := obj_data_to_vertex_buffer(&obj_data)

	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(vertex_buffer) * size_of(vertex_buffer[0]),
		raw_data(vertex_buffer), gl.STATIC_DRAW)
	// Copied to VRAM, we can now release memory on the CPU side
	delete(vertex_buffer)

	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(vertex_buffer[0]), 0)
	gl.EnableVertexAttribArray(0)

	gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of(vertex_buffer[0]), offset_of(VertexData, uv))
	gl.EnableVertexAttribArray(1)

	gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, size_of(vertex_buffer[0]), offset_of(VertexData, norm))
	gl.EnableVertexAttribArray(2)

	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(index_buffer) * size_of(index_buffer[0]),
		raw_data(index_buffer), gl.STATIC_DRAW)
	// Copied to VRAM, we can now release memory on the CPU side
	delete(index_buffer)

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	// === TEXTURES ===
	// texture, texture_ok := get_gl_texture("resources/monki.bmp")
	texture, texture_ok := get_gl_texture("resources/uvchecker.bmp")
	if !texture_ok {
		fmt.println("Failed to load texture")
		return
	}
	defer gl.DeleteTextures(1, &texture.id)

	// Enable/disable backface culling
	// gl.Enable(gl.CULL_FACE)
	// gl.CullFace(gl.BACK)

	gl.Enable(gl.DEPTH_TEST)
	gl.ClearColor(0.2, 0.3, 0.3, 1.0)

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

		gl.BindTexture(gl.TEXTURE_2D, texture.id)
		gl.UseProgram(shader_programs[state.shader_program])

		aspect_ratio := f32(state.window_size.x) / f32(state.window_size.y)

		@(static) time_accum: f64 = 0
		if state.enable_model_spin {
			time_accum += state.dt
		}
		model_matrix := get_rotation_matrix4_y_axis(cast(f32)time_accum) * model_offset
		view_matrix := state.player_cam
		proj_matrix := get_perspective_projection_matrix(state.fov, aspect_ratio, 0.1, 500)

		model_loc := gl.GetUniformLocation(shader_programs[state.shader_program], "model")
		gl.UniformMatrix4fv(model_loc, 1, gl.FALSE, &model_matrix[0, 0])

		view_loc := gl.GetUniformLocation(shader_programs[state.shader_program], "view")
		gl.UniformMatrix4fv(view_loc, 1, gl.FALSE, &view_matrix[0, 0])

		proj_loc := gl.GetUniformLocation(shader_programs[state.shader_program], "projection")
		gl.UniformMatrix4fv(proj_loc, 1, gl.FALSE, &proj_matrix[0, 0])

		gl.BindVertexArray(vao)
		gl.DrawElements(gl.TRIANGLES, cast(i32)len(index_buffer) * 3, gl.UNSIGNED_INT, nil)

		glfw.SwapBuffers(window)
	}

}

get_model_offset_matrix :: proc(model: ObjFileData) -> Mat4f {
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

// TODO: Gimball lock world-coordinates roll so we don't roll our virtual head? Like in FPS games
process_player_movements :: proc() {
	movement: Vec3f = {0, 0, 0}
	look: Vec3f = {0, 0, 0}
	fov_delta: f32 = 0
	pitch, yaw, roll: f32

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

	pitch = look.y
	yaw = look.x
	roll = look.z

	movement_mat := UNIT_MAT4F
	// XXX: CAREFUL WITH THE WAY YOU INDEX MATRICES IN ODIN!
	// These two was are equivalent!!!
	// First one is in column-major order, second in row-major
	// I guess because first one is on the programming side while second one is similar to math notation...
	// movement_mat[3][0] = movement.x
	// movement_mat[3][1] = movement.y
	// movement_mat[3][2] = movement.z
	movement_mat[0, 3] = movement.x
	movement_mat[1, 3] = movement.y
	movement_mat[2, 3] = movement.z

	pitch_mat := get_rotation_matrix4_x_axis(pitch)
	yaw_mat := get_rotation_matrix4_y_axis(yaw)
	roll_mat := get_rotation_matrix4_z_axis(roll)

	look_mat := roll_mat * yaw_mat * pitch_mat

	state.player_cam = look_mat * movement_mat * state.player_cam
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
	else if (key >= glfw.KEY_1 && key <= glfw.KEY_3) && action == glfw.PRESS {
		selected_shader := cast(ShaderProgram)(key - glfw.KEY_1)
		state.shader_program = selected_shader
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
