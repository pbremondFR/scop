#version 460 core

struct MaterialProperties{
	vec3	Ka;
	vec3	Kd;
	vec3	Ks;
	vec3	Tf;
	float	Ns;
	float	Tr;
	float	Ni;
	int		illum;
};

layout(std140, binding = 0) uniform uMaterials{
	MaterialProperties	materials[128];
};

uniform sampler2D ourTexture;

in vec4 Pos;
in vec2 Uv;
flat in uint Material;
in vec3 Normal;

out vec4 FragColor;

void main()
{
	// FragColor = texture(ourTexture, Uv);
	FragColor = vec4(materials[Material].Ka, 1.0);
	// FragColor = vec4(Material / 6.0, Material / 6.0, Material / 6.0, 1.0);
}
