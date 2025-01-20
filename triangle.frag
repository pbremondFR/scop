#version 330 core

in vec4 vertex_pos;
in vec2 Uv;
in vec3 Normal;

out vec4 FragColor;

uniform sampler2D ourTexture;

void main()
{
	// FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
	// FragColor = vec4(vertex_pos.xyz, 1.0f);

	// // Thanks claude for that debugging snippet, very cool
	// // vec3 normal = normalize(cross(dFdx(vertex_pos.xyz), dFdy(vertex_pos.xyz)));
	vec3 normal = normalize(Normal);
	// Branching in a shader. Probably a really shitty idea.
	if (length(normal) == 0) {
		normal = normalize(cross(dFdx(vertex_pos.xyz), dFdy(vertex_pos.xyz)));
	}
	FragColor = vec4((normal + 1.0) * 0.5, 1.0);

	FragColor = texture(ourTexture, Uv);
	// FragColor = vec4((vec3(Uv, 0.0) + 1.0) * 0.5, 1.0);
}
