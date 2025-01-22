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

uniform vec3 light_pos;
uniform vec3 light_color;
uniform sampler2D ourTexture;

in vec4 Pos;
in vec2 Uv;
flat in uint MtlID;
in vec3 Normal;
in vec3 FragPos;

out vec4 FragColor;

void main()
{
	// Ambient lighting
	vec3 ambient_color = materials[MtlID].Ka;
	vec3 ambient = ambient_color * vec3(0.2, 0.2, 0.2);

	// Diffuse lighting
	// TODO: Integrate diffuse color from material
	vec3 norm = normalize(Normal);
	vec3 lightDir = normalize(light_pos - FragPos);
	float diff = max(dot(norm, lightDir), 0.0);
	vec3 diffuse = diff * light_color;

	vec4 texture_color = texture(ourTexture,  Uv);

	// FIXME: Shading stays fixed when model rotates
	vec3 final_color = (ambient + diffuse) * texture_color.xyz;
	FragColor = vec4(final_color, 1.0);
}
