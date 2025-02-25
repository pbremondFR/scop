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
	MaterialProperties	materials[256];
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

in VS_OUT {
	vec3		pos;
	vec3		world_pos;
	vec2		uv;
	flat uint	mtl_id;
	mat3		TBN;
}	vs_in;

out vec4 FragColor;

bool texture_enabled(uint texture_unit)
{
	return (materials[vs_in.mtl_id].enabled_textures & (1 << texture_unit)) != 0;
}

vec3	get_normal()
{
	if (texture_enabled(MAP_BUMP))
	{
		vec3 normal = texture(texture_bump, vs_in.uv).rgb;
		normal = normal * 2.0 - 1.0;	// transform normal vector to range [-1,1]
		normal = normalize(vs_in.TBN * normal);
		// FIXME: vector sometimes becomes NaN after TBN multiplication
		if (isnan(length(normal)))
			normal = normalize(vs_in.TBN[2]);
		return normal;
	}
	else
	{
		if (length(vs_in.TBN[2]) == 0)
			return normalize(cross(dFdx(vs_in.world_pos.xyz), dFdy(vs_in.world_pos.xyz)));
		else
			return normalize(vs_in.TBN[2]);
	}
}

vec3	calc_ambient()
{
	vec3 ambient_color = materials[vs_in.mtl_id].Ka;
	if (texture_enabled(MAP_KA)) {
		vec3 texture_color = texture(texture_Ka, vs_in.uv).rgb;
		ambient_color = mix(ambient_color, ambient_color * texture_color, texture_factor);
	}
	vec3 ambient_lighting = vec3(0.2, 0.2, 0.2);
	vec3 ambient = ambient_color * ambient_lighting;

	return ambient;
}

vec3	calc_diffuse(vec3 norm, vec3 lightDir)
{
	vec3 diffuse_color = materials[vs_in.mtl_id].Kd;
	if (texture_enabled(MAP_KD)) {
		vec3 texture_color = texture(texture_Kd, vs_in.uv).rgb;
		diffuse_color = mix(diffuse_color, diffuse_color * texture_color, texture_factor);
	}
	float diff = max(dot(norm, lightDir), 0.0);
	vec3 diffuse = diff * diffuse_color * light_color;

	return diffuse;
}

// Phong reflection model
vec3	calc_specular(vec3 norm, vec3 lightDir)
{
	vec3 spec_color = materials[vs_in.mtl_id].Ks;
	float spec_exponent = materials[vs_in.mtl_id].Ns;

	if (spec_exponent == 0)
		return vec3(0.0);

	if (texture_enabled(MAP_KS)) {
		vec3 texture_color = texture(texture_Ks, vs_in.uv).rgb;
		spec_color = mix(spec_color, spec_color * texture_color, texture_factor);
	}

	vec3 viewDir = normalize(view_pos - vs_in.world_pos);
	vec3 reflectDir = reflect(lightDir, norm);
	float spec = pow(max(0, dot(viewDir, reflectDir)), 1000);

	vec3 specular = spec * spec_color * light_color;

	return specular;
}

// Blinn-Phong reflection model
// https://en.wikipedia.org/wiki/Blinn%E2%80%93Phong_reflection_model#Description
vec3	calc_specular_blinn(vec3 norm, vec3 lightDir)
{
	vec3 spec_color = materials[vs_in.mtl_id].Ks;
	// For Blinn-Phong to match Phong lighting, multiplying the exponent by 4 "will result
	// in specular highlights that very closely match the corresponding Phong reflections"
	// c.f. Wikipedia article
	float spec_exponent = materials[vs_in.mtl_id].Ns * 4;

	if (spec_exponent == 0)
		return vec3(0.0);

	if (texture_enabled(MAP_KS)) {
		vec3 texture_color = texture(texture_Ks, vs_in.uv).rgb;
		spec_color = mix(spec_color, spec_color * texture_color, texture_factor);
	}

	vec3 viewDir = normalize(view_pos - vs_in.world_pos);
	vec3 halfwayDir = normalize(lightDir + viewDir);
	float spec = pow(max(dot(norm, halfwayDir), 0.0), spec_exponent);

	vec3 specular = spec * spec_color * light_color;

	return specular;
}

void main()
{
	vec3 normal = get_normal();
	vec3 lightDir = normalize(light_pos - vs_in.world_pos);

	vec3 ambient = calc_ambient();
	vec3 diffuse = calc_diffuse(normal, lightDir);
	// vec3 specular = calc_specular(normal, lightDir);

	// HACK: Looks like something is fucked here, signs probably shouldn't be flipped like that
	// It still works though
	vec3 specular = calc_specular_blinn(-normal, -lightDir);

	vec3 final_color = (ambient + diffuse + specular);
	// XXX: DEBUG
	// if (isnan(length(normal)))
	// 	final_color = vec3(1, 0, 0);
	FragColor = vec4(final_color, 1.0);
}
