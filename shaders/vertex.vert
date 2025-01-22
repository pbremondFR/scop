#version 330 core
layout (location = 0) in vec3 aPos;
layout (location = 1) in vec2 aUv;
layout (location = 2) in uint aMaterial;
layout (location = 3) in vec3 aNormal;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec4 Pos;
out vec2 Uv;
out uint Material;
out vec3 Normal;

void main()
{
	gl_Position = projection * view * model * vec4(aPos, 1.0);
	Pos = vec4(aPos, 1.0);
	// I'm never gonna use 3D textures, so from here on vec3 texture coordinates
	// are becoming vec2: just UV coordinates, no W information
	Uv = aUv.xy;
	Material = aMaterial;
	Normal = aNormal;
}
