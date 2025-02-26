package main

import gl "vendor:OpenGL"

@(private="file")
get_light_cube_model_matrix :: proc(cube_position: Vec3f, time: f32) -> (cube_model_matrix: Mat4f) {
	cube_model_matrix = UNIT_MAT4F
	cube_model_matrix[3].xyz = cube_position
	return cube_model_matrix * get_rotation_matrix4_x_axis(time) * get_rotation_matrix4_y_axis(time)
}

draw_light_cube :: proc(vao: u32, light_source_shader: u32, proj_matrix: ^Mat4f, time: f32)
{
	gl.UseProgram(light_source_shader)

	cube_model_matrix := get_light_cube_model_matrix(state.light_source_pos, time)
	set_shader_uniform(light_source_shader, "light_pos", &state.light_source_pos)
	set_shader_uniform(light_source_shader, "light_color", &Vec3f{1, 1, 1})
	set_shader_uniform(light_source_shader, "model", &cube_model_matrix)
	set_shader_uniform(light_source_shader, "view", &state.camera.mat)
	set_shader_uniform(light_source_shader, "projection", proj_matrix)

	gl.BindVertexArray(vao)
	gl.DrawArrays(gl.TRIANGLES, 0, 36)
}

LightCube :: struct {
	vao, vbo: u32
}

create_light_cube :: proc() -> (light_vao, light_vbo: u32, ok: bool) {
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

	// TODO: Better error checking (with dedicated OpenGL error check functions)?
	gl.GenBuffers(1, &light_vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, light_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(cube_vertices) * size_of(cube_vertices[0]),
		raw_data(cube_vertices[:]), gl.STATIC_DRAW)
	defer if !ok { gl.DeleteBuffers(1, &light_vbo) }

	gl.GenVertexArrays(1, &light_vao)
	gl.BindVertexArray(light_vao)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, 3 * size_of(f32), 0)
	gl.EnableVertexAttribArray(0)
	defer if !ok { gl.DeleteVertexArrays(1, &light_vao) }

	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
	gl.BindVertexArray(0)

	ok = (light_vao != 0 && light_vbo != 0)
	if !ok {
		log_error("Failed to send light cube to GPU")
	}
	return
}
