package main

import "core:math"
import "core:math/linalg"

PlayerCamera :: struct {
	pos: Vec3f,
	pitch: f32,
	yaw: f32,
	// direction: Vec3f, // Logically direction would be -mat.z
	mat: Mat4f,
}

// Cool effect, maybe what they ask in the subject, but useless for me.
get_camera_matrix :: proc(pos: Vec3f, pitch_rad: f32, yaw_rad: f32) -> Mat4f {
	alpha := pitch_rad
	beta := yaw_rad
	gamma :f32 = 0

	pos_matrix := UNIT_MAT4F
	pos_matrix[3].xyz = pos

	Rx := get_rotation_matrix4_x_axis(alpha)
	Ry := get_rotation_matrix4_y_axis(beta)
	Rz := get_rotation_matrix4_z_axis(gamma)

	camera_matrix := Rz * Rx * Ry
	camera_matrix *= pos_matrix
	return camera_matrix
}
