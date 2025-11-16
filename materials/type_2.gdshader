shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D texture_albedo : repeat_enable;
uniform sampler2D texture_normal : repeat_enable, hint_normal;
uniform sampler2D texture_parallax : repeat_enable;
uniform vec3 uv_scale;

const float p_normal = 1.340000000;
const float p_offset_scale = 0.260000000;
const int p_iter = 24;

void vertex() {
	UV=UV*uv_scale.xy;
}

void fragment() {
	vec2 base_uv = UV;
	
	int texture_size = textureSize(texture_albedo, 0).x;
	if (texture_size < 256) {
		base_uv = floor(float(texture_size)*base_uv+0.5)/float(texture_size);
	}
	
	vec4 parallax = vec4(0.0);
	{
		float t = sin(TIME) * PI / 4.0;
		mat2 normal_rot = mat2(vec2(cos(t), -sin(t)), vec2(sin(t), cos(t)));
		vec3 view_dir = normalize(vec3(normal_rot * vec2(0.0, 0.25), 1.0));
		for (int j = 0; j < p_iter; j++) {
			float ratio = float(j) / float(p_iter);
			
			parallax += texture(texture_parallax, base_uv - mix(0.0, p_offset_scale, ratio) * view_dir.xy) * mix(1.0, 0.0, ratio);
		}
		
		parallax /= float(p_iter);
	}
	
	vec4 albedo_tex = texture(texture_albedo, base_uv);
	COLOR = albedo_tex;
	COLOR += parallax;
	COLOR.a = 1.0;
	NORMAL_MAP = texture(texture_normal, base_uv).rgb;
	NORMAL_MAP_DEPTH = p_normal;
}



