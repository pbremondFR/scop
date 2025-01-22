#version 330 core

in vec4 Pos;
in vec2 Uv;
flat in uint Material;
in vec3 Normal;

out vec4 FragColor;

uniform sampler2D ourTexture;

void main()
{
	FragColor = vec4((Normal + 1.0) * 0.5, 1.0);
	// Debug to see different material IDs as color
	// FragColor = vec4(Material / 10.0, Material / 10.0, Material / 10.0, 1.0);
}
