#version 420 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 aUv;
layout (location = 2) in uint aMaterial;
layout (location = 3) in vec3 aNormal;
layout (location = 4) in vec3 aTangent;
layout (location = 5) in vec3 aBitangent;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out VS_OUT {
	vec3		pos;
	vec3		world_pos;
	vec2		uv;
	flat uint	mtl_id;
	mat3		TBN;
}	vs_out;

void main()
{
	vec3 T = normalize(vec3(model * vec4(aTangent, 0.0)));
	vec3 B = normalize(vec3(model * vec4(aBitangent, 0.0)));
	vec3 N;
	if (length(aNormal) != 0)
		N = normalize(vec3(model * vec4(aNormal, 0.0)));
	else
		N = vec3(0);

	vs_out.pos = aPos;
	vs_out.world_pos = vec3(model * vec4(aPos, 1.0));
	vs_out.uv = aUv;
	vs_out.mtl_id = aMaterial;
	vs_out.TBN = mat3(T, B, N);

	gl_Position = projection * view * vec4(vs_out.world_pos, 1.0);
}
