#version 460 core

struct MaterialProperties{
	vec3	Ka;
	float	Ns;
	vec3	Kd;
	float	d;
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
uniform vec3 view_pos;

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
	vec3 diffuse_color = materials[MtlID].Kd;
	vec3 norm = normalize(Normal);
	if (length(norm) == 0) {
		norm = normalize(cross(dFdx(FragPos.xyz), dFdy(FragPos.xyz)));
	}
	vec3 lightDir = normalize(light_pos - FragPos);
	float diff = max(dot(norm, lightDir), 0.0);
	vec3 diffuse = diff * diffuse_color * light_color;

	// Specular lighting
	vec3 spec_color = materials[MtlID].Ks;
	float spec_exponent = materials[MtlID].Ns;
	vec3 viewDir = normalize(view_pos - FragPos);
	// TESTME: Specular highlights on wrong side of model
	// I think the second reflect() call is the correct one...
	// vec3 reflectDir = reflect(-lightDir, norm);
	vec3 reflectDir = reflect(lightDir, norm);
	float spec = pow(max(0, dot(viewDir, reflectDir)), spec_exponent);
	vec3 specular = spec * spec_color * light_color;

	vec3 final_color = (ambient + diffuse + specular);
	FragColor = vec4(final_color, 1.0);
}
