#version 420 core

in VS_OUT {
	vec3		pos;
	vec3		world_pos;
	vec2		uv;
	flat uint	mtl_id;
	mat3		TBN;
}	vs_in;

out vec4 FragColor;

void main()
{
	FragColor = vec4((vs_in.TBN[2] + 1.0) * 0.5, 1.0);
}
