#version 330 core

layout(points) in;
layout(line_strip, max_vertices = 2) out;

uniform mat4 mvp; // Model View Projection Matrix
uniform float vec_norm_len;

in vec3 vertex_normal[];

out vec3 vertex_color;

// https://vallentin.dev/blog/post/visualizing-normals
// Cool!
void main()
{
    vec3 normal = vertex_normal[0];

    vertex_color = (normal + 1.0) * 0.5;

    vec4 v0 = gl_in[0].gl_Position;
    gl_Position = mvp * v0;
    EmitVertex();

    vec4 v1 = v0 + vec4(normal * vec_norm_len, 0.0);
    gl_Position = mvp * v1;
    EmitVertex();

    EndPrimitive();
}
