package main

import "core:math"
import "core:math/linalg"

Mat4f :: matrix[4, 4]f32
Mat3f :: matrix[3, 3]f32
Mat2f :: matrix[2, 2]f32

UNIT_MAT4F: Mat4f: {
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 1.0, 0.0,
	0.0, 0.0, 0.0, 1.0,
}

// Literally copy-pasted my own code from ft_matrix and transposed the matrix
// Matrices in OpenGL and Odin are in column-major order. This matters!!!
// https://www.scratchapixel.com/lessons/3d-basic-rendering/perspective-and-orthographic-projection-matrix/opengl-perspective-projection-matrix.html
get_perspective_projection_matrix :: proc(fov_rad: f32, aspect_ratio: f32, near: f32, far: f32) -> Mat4f {
	top := math.tan(fov_rad / 2.0) * near;
	bottom := -top;
	right := top * aspect_ratio;
	left := -top * aspect_ratio;

	x_transform := 2.0 * near / (right - left);
	y_transform := 2.0 * near / (top - bottom);
	wtf1 := (right + left) / (right - left);	// These are always 0. Why does openGL define them like this?
	wtf2 := (top + bottom) / (top - bottom);
	far_plane := -far / (far - near);	// NDC is [0;1]
	near_plane := (-far * near) / (far - near);
	projmat := Mat4f{
		x_transform,	0.0,			wtf1,		0.0,
		0.0,			y_transform,	wtf2,		0.0,
		0.0,			0.0,			far_plane,	near_plane,
		0.0,			0.0,			-1.0,		0.0,
	};
	return projmat
}

get_rotation_matrix4_x_axis :: proc(angle_rad: f32) -> Mat4f {
	mat := UNIT_MAT4F

	sin := math.sin(angle_rad)
	cos := math.cos(angle_rad)

	mat[1, 1] = cos
	mat[1, 2] = -sin

	mat[2, 1] = sin
	mat[2, 2] = cos

	return mat
}

get_rotation_matrix4_y_axis :: proc(angle_rad: f32) -> Mat4f {
	mat := UNIT_MAT4F

	sin := math.sin(angle_rad)
	cos := math.cos(angle_rad)

	mat[0, 0] = cos
	mat[0, 2] = sin

	mat[2, 0] = -sin
	mat[2, 2] = cos

	return mat
}

get_rotation_matrix4_z_axis :: proc(angle_rad: f32) -> Mat4f {
	mat := UNIT_MAT4F

	sin := math.sin(angle_rad)
	cos := math.cos(angle_rad)

	mat[0, 0] = cos
	mat[0, 1] = sin

	mat[1, 0] = -sin
	mat[1, 1] = cos

	return mat
}
