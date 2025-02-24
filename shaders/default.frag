#version 420 core

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
uniform float texture_factor;	// Multiply each texture color by this factor

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

vec3	get_normal()
{
	// if (texture_enabled(MAP_BUMP))
	// {
	// 	vec3 normal = texture(texture_bump, Uv).rgb;
	// 	// transform normal vector to range [-1,1]
	// 	normal = normalize(normal * 2.0 - 1.0);
	// 	return normal;
	// }
	// else
	if (length(Normal) == 0)
		// return vec3(0, 1, 0);
		return normalize(cross(dFdx(FragPos.xyz), dFdy(FragPos.xyz)));
	else
		return normalize(Normal);
	// {
	// 	vec3 normal = normalize(Normal);
	// 	if (length(normal) == 0) // No vertex normal, calc face normal
	// 		// normal = vec3(0, 1, 0);
	// 		normal = normalize(cross(dFdx(FragPos.xyz), dFdy(FragPos.xyz)));
	// 	return normal;
	// }
}

vec3	calc_ambient()
{
	vec3 ambient_color = materials[MtlID].Ka;
	if (texture_enabled(MAP_KA)) {
		vec3 texture_color = texture(texture_Ka, Uv).rgb;
		ambient_color = mix(ambient_color, ambient_color * texture_color, texture_factor);
	}
	vec3 ambient_lighting = vec3(0.2, 0.2, 0.2);
	vec3 ambient = ambient_color * ambient_lighting;

	return ambient;
}

vec3	calc_diffuse(vec3 norm, vec3 lightDir)
{
	vec3 diffuse_color = materials[MtlID].Kd;
	if (texture_enabled(MAP_KD)) {
		vec3 texture_color = texture(texture_Kd, Uv).rgb;
		diffuse_color = mix(diffuse_color, diffuse_color * texture_color, texture_factor);
	}
	float diff = max(dot(norm, lightDir), 0.0);
	vec3 diffuse = diff * diffuse_color * light_color;

	return diffuse;
}

vec3	calc_specular(vec3 norm, vec3 lightDir)
{
	vec3 spec_color = materials[MtlID].Ks;
	float spec_exponent = materials[MtlID].Ns;
	if (spec_exponent == 0)
		return vec3(0.0);
	if (texture_enabled(MAP_KS)) {
		vec3 texture_color = texture(texture_Ks, Uv).rgb;
		spec_color = mix(spec_color, spec_color * texture_color, texture_factor);
	}
	// XXX: Disable all scalar textures, can't be bothered
	// if (texture_enabled(MAP_NS))
	// 	spec_exponent *= length(texture(texture_Ns, Uv).xyz);
	vec3 viewDir = normalize(view_pos - FragPos);
	vec3 reflectDir = reflect(lightDir, norm);
	float spec = pow(max(0, dot(viewDir, reflectDir)), spec_exponent);
	vec3 specular = spec * spec_color * light_color;

	return specular;
}

void main()
{
	// Calculate fragment's normal
	vec3 normal = get_normal();
	// Calculate light source's direction
	vec3 lightDir = normalize(light_pos - FragPos);

	vec3 ambient = calc_ambient();
	vec3 diffuse = calc_diffuse(normal, lightDir);
	vec3 specular = calc_specular(normal, lightDir);

	vec3 final_color = (ambient + diffuse + specular);
	// FIXME: It looks like specular lighting does not work on Linux???
	FragColor = vec4(ambient + diffuse + specular, 1.0);
}
