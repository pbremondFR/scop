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
out uint MtlID;
out vec3 Normal;
out vec3 FragPos;

void main()
{
	FragPos = vec3(model * vec4(aPos, 1.0));

	Pos = vec4(aPos, 1.0);
	Uv = aUv;
	MtlID = aMaterial;
	Normal = aNormal;
	// Calculate the normal matrix
	// TODO: Transfer this to the CPU and pass it through a uniform
	Normal = mat3(transpose(inverse(model))) * aNormal;
	gl_Position = projection * view * vec4(FragPos, 1.0);

}
