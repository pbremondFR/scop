package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "base:runtime"

import gl "vendor:OpenGL"
import "vendor:glfw"

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
	else if (key >= glfw.KEY_1 && key <= glfw.KEY_4) && action == glfw.PRESS {
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
	else if key == glfw.KEY_T && action == glfw.PRESS {
		state.show_textures = !state.show_textures
	}

	if action == glfw.PRESS {
		state.glfw_inputs[key] = true
	}
	else if action == glfw.RELEASE {
		state.glfw_inputs[key] = false
	}
}
