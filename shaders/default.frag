#version 460 core

struct MaterialProperties{
	vec3	Ka;
	float	Ns;
	vec3	Kd;
	float	d;
	vec3	Ks;
	float	Ni;
	vec3	Tf;
	uint	enabled_textures;
};

layout(std140, binding = 0) uniform uMaterials{
	MaterialProperties	materials[128];
};

uniform vec3 light_pos;
uniform vec3 light_color;
uniform vec3 view_pos;

#define MAP_KA		0
#define MAP_KD		1
#define MAP_KS		2
#define MAP_NS		3
#define MAP_D		4
#define MAP_BUMP	5
#define MAP_DISP	6
#define DECAL		7

uniform sampler2D[8] textures;

in vec4 Pos;
in vec2 Uv;
flat in uint MtlID;
in vec3 Normal;
in vec3 FragPos;

out vec4 FragColor;

vec3 get_texture_vec3(uint texture_unit)
{
	return texture(textures[8 - texture_unit], Uv).xyz;
}

bool texture_enabled(uint texture_unit)
{
	return (materials[MtlID].enabled_textures & (1 << texture_unit)) != 0;
}

void main()
{
	// Ambient lighting
	vec3 ambient_color = materials[MtlID].Ka;
	vec3 ambient_lighting = vec3(0.2, 0.2, 0.2);
	vec3 ambient = ambient_color * ambient_lighting;
	if (texture_enabled(MAP_KA))
		ambient *= get_texture_vec3(MAP_KA);

	// Diffuse lighting
	vec3 diffuse_color = materials[MtlID].Kd;
	vec3 norm = normalize(Normal);
	if (length(norm) == 0)
		norm = normalize(cross(dFdx(FragPos.xyz), dFdy(FragPos.xyz)));
	vec3 lightDir = normalize(light_pos - FragPos);
	float diff = max(dot(norm, lightDir), 0.0);
	vec3 diffuse = diff * diffuse_color * light_color;
	if (texture_enabled(MAP_KD))
		diffuse *= get_texture_vec3(MAP_KD);

	// Specular lighting
	vec3 spec_color = materials[MtlID].Ks;
	float spec_exponent = materials[MtlID].Ns;
	vec3 viewDir = normalize(view_pos - FragPos);
	vec3 reflectDir = reflect(lightDir, norm);
	float spec = pow(max(0, dot(viewDir, reflectDir)), spec_exponent);
	vec3 specular = spec * spec_color * light_color;
	if (texture_enabled(MAP_KS))
		specular *= get_texture_vec3(MAP_KS);

	vec3 final_color = (ambient + diffuse + specular);
	FragColor = vec4(final_color, 1.0);
}
