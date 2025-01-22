package main

import "core:math"
import "core:math/linalg"

PlayerCamera :: struct {
	pos: Vec3f,
	pitch: f32,
	yaw: f32,
	mat: Mat4f,
}

/*
 * Get the camera matrix from the desired position, pitch, and roll.
 */
get_camera_matrix :: proc(pos: Vec3f, pitch_rad: f32, yaw_rad: f32) -> Mat4f {
	alpha := pitch_rad
	beta := yaw_rad
	// gamma :f32 = 0

	// Translation matrix to position
	pos_matrix := UNIT_MAT4F
	pos_matrix[3].xyz = pos

	// EXTRINSIC rotation matrix that keeps the camera's roll at 0
	Rx := get_rotation_matrix4_x_axis(alpha)
	Ry := get_rotation_matrix4_y_axis(beta)
	// Rz := get_rotation_matrix4_z_axis(gamma)

	// XXX: Odin evaluates matrix multiplication from LEFT to RIGHT. This is expected from a
	// programming language, but care must be taken when coming from maths.
	camera_matrix := Rx * Ry * pos_matrix
	return camera_matrix
}
