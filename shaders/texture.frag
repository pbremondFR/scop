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
flat in uint Material;
in vec3 Normal;

out vec4 FragColor;

void main()
{
	// FragColor = texture(ourTexture, Uv);
	FragColor = vec4(materials[Material].Ka, 1.0);
	// FragColor = vec4(Material / 6.0, Material / 6.0, Material / 6.0, 1.0);
	float tr = materials[Material].Tr;
	FragColor = vec4(tr, tr, tr, 1.0);
	int illum = materials[Material].illum;
	FragColor = vec4(illum / 10.0, illum / 10.0, illum / 10.0, 1.0);
}
