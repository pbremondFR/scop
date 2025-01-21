#version 330 core

in vec4 Pos;
in vec2 Uv;
in vec3 Normal;

out vec4 FragColor;

uniform sampler2D ourTexture;

void main()
{
	FragColor = vec4((Normal + 1.0) * 0.5, 1.0);
}
