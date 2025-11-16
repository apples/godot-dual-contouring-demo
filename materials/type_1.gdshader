shader_type canvas_item;
render_mode skip_vertex_transform;

uniform sampler3D noise_texture: repeat_enable, filter_linear;

uniform mat3 noise_rotation;

varying vec2 position;

void vertex() {
	VERTEX = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	position = VERTEX.xy / 160.0;
}

void fragment() {
	COLOR = texture(noise_texture, noise_rotation * vec3(position, TIME / 2.0));
}
