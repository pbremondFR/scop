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

out vec4 Pos;
out vec2 Uv;
flat out uint MtlID;
out vec3 Normal;
out vec3 FragPos;
out mat3 TBN;

void main()
{
	FragPos = vec3(model * vec4(aPos, 1.0));

	Pos = vec4(aPos, 1.0);
	Uv = aUv;
	MtlID = aMaterial;
	Normal = aNormal;
	// Calculate the normal matrix
	// TODO: Transfer this to the CPU and pass it through a uniform
	// Normal = mat3(transpose(inverse(model))) * aNormal;
	Normal = normalize(vec3(model * vec4(aNormal, 0.0)));
	vec3 tangent = normalize(vec3(model * vec4(aTangent, 0.0)));
	vec3 bitangent = normalize(vec3(model * vec4(aBitangent, 0.0)));
	TBN = mat3(tangent, bitangent, Normal);

	gl_Position = projection * view * vec4(FragPos, 1.0);

}
