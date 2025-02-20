#version 420 core

layout (location = 0) in vec3 aPos;

uniform vec3 light_pos;
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

void main()
{
	// mat4 model = mat4(1.0);
	// model[3].xyz = light_pos;
	gl_Position = projection * view * model * vec4(aPos, 1.0);
}
