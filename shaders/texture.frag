#version 460 core

struct MaterialProperties{
	vec3	Ka;
	float	Ns;
	vec3	Kd;
	float	Tr;
	vec3	Ks;
	float	Ni;
	vec3	Tf;
	int		illum;
};

layout(std140, binding = 0) uniform uMaterials{
	MaterialProperties	materials[128];
};

uniform sampler2D ourTexture;

in vec4 Pos;
in vec2 Uv;
flat in uint MtlID;
in vec3 Normal;

out vec4 FragColor;

void main()
{
	vec3 ambient_lighting = vec3(0.2, 0.2, 0.2);
	vec3 ambient_color = materials[MtlID].Ka;

	vec4 texture_color = texture(ourTexture,  Uv);

	vec3 final_color = ambient_color * ambient_lighting * texture_color.xyz;
	FragColor = vec4(final_color, 1.0);
}
