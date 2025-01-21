#version 330 core

in vec4 Pos;
in vec2 Uv;
in vec3 Normal;

out vec4 FragColor;

void main()
{
	// Allows to visalize face normals instead of vertex normals
	vec3 normal = normalize(cross(dFdx(Pos.xyz), dFdy(Pos.xyz)));
	FragColor = vec4((normal + 1.0) * 0.5, 1.0);
}
