shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_col : source_color = vec3(0.36, 0.86, 0.85);
uniform vec3 deep_col : source_color = vec3(0.08, 0.38, 0.62);
uniform vec3 foam_col : source_color = vec3(1.0, 1.0, 1.0);
uniform float night : hint_range(0.0, 1.0) = 0.0;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(w_pos.x * 0.35 + TIME * 1.1) * 0.04 + cos(w_pos.z * 0.3 + TIME * 0.9) * 0.04;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float diff = clamp(VERTEX.z - view.z, 0.0, 20.0);

	vec2 p = w_pos.xz;
	float n1 = vnoise(p * 0.6 + vec2(TIME * 0.12, TIME * 0.07));
	float n2 = vnoise(p * 1.3 - vec2(TIME * 0.09, -TIME * 0.11));
	float ripple = n1 * 0.6 + n2 * 0.4;

	float shore = 1.0 - smoothstep(0.0, 0.55, diff);
	float bands = smoothstep(0.55, 0.75, sin(diff * 9.0 - TIME * 2.2 + ripple * 3.0) * 0.5 + 0.5) * (1.0 - smoothstep(0.0, 1.1, diff));
	float foam = clamp(shore * (0.6 + 0.4 * ripple) + bands * 0.6, 0.0, 1.0);
	foam = step(0.45, foam);

	vec3 col = mix(shallow_col, deep_col, smoothstep(0.0, 2.6, diff));
	col += (ripple - 0.5) * 0.06;
	col = mix(col, col * vec3(0.25, 0.32, 0.55), night * 0.75);
	col = mix(col, foam_col * mix(1.0, 0.45, night), foam * 0.9);

	ALBEDO = col;
	ALPHA = mix(0.62, 0.95, smoothstep(0.0, 3.0, diff));
	ALPHA = max(ALPHA, foam);
	ROUGHNESS = 0.06 + foam * 0.6;
	SPECULAR = 0.75;
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.35, 1.0, (n2 - 0.5) * 0.35));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(nrm, 0.0)).xyz, 0.6));
}
