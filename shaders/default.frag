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

// Representation of the TextureUnit enum in the Odin code. Corresponds to the N-th
// least-significant bit of the material's `enabled_textures`. If the bit is set,
// the texture is enabled on this material. Otherwise, it is not to be applied.
#define MAP_KA		0
#define MAP_KD		1
#define MAP_KS		2
#define MAP_NS		3
#define MAP_D		4
#define MAP_BUMP	5
#define MAP_DISP	6
#define DECAL		7

// Caveman solution, but I really don't want to fiddle with another uniform buffer
uniform sampler2D texture_Ka;
uniform sampler2D texture_Kd;
uniform sampler2D texture_Ks;
uniform sampler2D texture_Ns;
uniform sampler2D texture_d;
uniform sampler2D texture_bump;
uniform sampler2D texture_disp;
uniform sampler2D texture_decal;

in vec4 Pos;
in vec2 Uv;
flat in uint MtlID;
in vec3 Normal;
in vec3 FragPos;

out vec4 FragColor;

bool texture_enabled(uint texture_unit)
{
	return (materials[MtlID].enabled_textures & (1 << texture_unit)) != 0;
}

void main()
{
	// Ambient lighting
	vec3 ambient_color = materials[MtlID].Ka;
	if (texture_enabled(MAP_KA))
		ambient_color *= texture(texture_Ka, Uv).xyz;
	vec3 ambient_lighting = vec3(0.2, 0.2, 0.2);
	vec3 ambient = ambient_color * ambient_lighting;

	// Diffuse lighting
	vec3 diffuse_color = materials[MtlID].Kd;
	if (texture_enabled(MAP_KD))
		diffuse_color *= texture(texture_Kd, Uv).xyz;
	vec3 norm = normalize(Normal);
	if (length(norm) == 0)
		norm = normalize(cross(dFdx(FragPos.xyz), dFdy(FragPos.xyz)));
	vec3 lightDir = normalize(light_pos - FragPos);
	float diff = max(dot(norm, lightDir), 0.0);
	vec3 diffuse = diff * diffuse_color * light_color;

	// Specular lighting
	vec3 spec_color = materials[MtlID].Ks;
	if (texture_enabled(MAP_KS))
		spec_color *= texture(texture_Ks, Uv).xyz;
	float spec_exponent = materials[MtlID].Ns;
	if (texture_enabled(MAP_NS))
		spec_exponent *= length(texture(texture_Ns, Uv).xyz);
	vec3 viewDir = normalize(view_pos - FragPos);
	vec3 reflectDir = reflect(lightDir, norm);
	float spec = pow(max(0, dot(viewDir, reflectDir)), spec_exponent);
	vec3 specular = spec * spec_color * light_color;

	vec3 final_color = (ambient + diffuse + specular);
	FragColor = vec4(final_color, 1.0);
}
