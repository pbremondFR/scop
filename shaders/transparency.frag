#version 420 core

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
	MaterialProperties    materials[128];
};

uniform vec3 light_pos;
uniform vec3 light_color;
uniform vec3 view_pos;
uniform sampler2D ourTexture;

in VS_OUT {
	vec3		pos;
	vec3		world_pos;
	vec2		uv;
	flat uint	mtl_id;
	mat3		TBN;
}	vs_in;

out vec4 FragColor;

// Exploring order-independant transparency:
// https://stackoverflow.com/questions/37780345/opengl-how-to-create-order-independent-transparency/37783085#37783085
// http://casual-effects.blogspot.com/2014/03/weighted-blended-order-independent.html
// https://jcgt.org/published/0002/02/09/
void main()
{
	// Ambient lighting
	vec3 ambient_color = materials[vs_in.mtl_id].Ka;
	vec3 ambient = ambient_color * vec3(0.2, 0.2, 0.2);

	// Diffuse lighting
	vec3 diffuse_color = materials[vs_in.mtl_id].Kd;
	vec3 norm = normalize(vs_in.TBN[2]);
	if (length(norm) == 0) {
		norm = normalize(cross(dFdx(vs_in.world_pos.xyz), dFdy(vs_in.world_pos.xyz)));
	}
	vec3 lightDir = normalize(light_pos - vs_in.world_pos);
	float diff = max(dot(norm, lightDir), 0.0);
	vec3 diffuse = diff * diffuse_color * light_color;

	// Specular lighting
	vec3 spec_color = materials[vs_in.mtl_id].Ks;
	float spec_exponent = materials[vs_in.mtl_id].Ns;
	vec3 viewDir = normalize(view_pos - vs_in.world_pos);
	vec3 reflectDir = reflect(lightDir, norm);
	float spec = pow(max(0, dot(viewDir, reflectDir)), spec_exponent);
	vec3 specular = spec * spec_color * light_color;
	if (spec_exponent == 0)
		specular = vec3(0);

	vec4 texture_color = texture(ourTexture, vs_in.uv);

	vec3 final_color3 = (ambient + diffuse + specular);// * texture_color.rgb;

	vec4 color = vec4(final_color3, materials[vs_in.mtl_id].d);
	// float z = 100;
	// float weight =
	// 	max(
	// 		min(
	// 			1.0,
	// 			max(
	// 				max(color.r, color.g),
	// 				color.b
	// 			) * color.a
	// 		),
	// 		color.a
	// 	) * clamp(0.03 / (1e-5 + pow(z / 200, 4.0)), 1e-2, 3e3);

	// // gl_FragData[0] = vec4(color.rgb * color.a, color.a) * weight;
	// FragColor = vec4(color.rgb * color.a, color.a) * weight;

	FragColor = vec4(color.rgb * color.a, color.a);
	// FragColor = vec4(color.rgb, color.a);
}
