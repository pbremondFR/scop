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
	// Allows to visalize face normals instead of vertex normals
	vec3 normal = normalize(cross(dFdx(vs_in.pos.xyz), dFdy(vs_in.pos.xyz)));
	FragColor = vec4((normal + 1.0) * 0.5, 1.0);
}
