#version 330 core
in vec4 vertex_pos;
out vec4 FragColor;

void main()
{
	// FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
	// FragColor = vec4(vertex_pos.xyz, 1.0f);

	// Thanks claude for that debugging snippet, very cool
	vec3 normal = normalize(cross(dFdx(vertex_pos.xyz), dFdy(vertex_pos.xyz)));
    FragColor = vec4((normal + 1.0) * 0.5, 1.0);
}
