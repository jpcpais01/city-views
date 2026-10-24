shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
// A boat's wake: churned white water behind it that breaks up into lace and
// fades as it spreads. UV.x runs across a strip, UV.y from the stern (0) to
// the end of the trail (1); COLOR.a is how strong it is.

uniform float night : hint_range(0.0, 1.0) = 0.0;

varying vec3 wp;

float w_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float w_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(w_hash(i), w_hash(i + vec2(1.0, 0.0)), f.x), mix(w_hash(i + vec2(0.0, 1.0)), w_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float along = UV.y;
	float body = 1.0 - smoothstep(0.3, 1.0, across);
	float fade = pow(1.0 - along, 2.2) * smoothstep(0.0, 0.04, along);
	float lace = w_noise(wp.xz * 2.6 + TIME * vec2(0.21, 0.17)) * 0.6 + w_noise(wp.xz * 7.3 - TIME * 0.4) * 0.4;
	// thick foam right behind the stern, breaking into lace further back
	float a = COLOR.a * body * fade * smoothstep(0.3 + along * 0.25, 0.62 + along * 0.2, lace + (1.0 - along) * 0.3);
	ALBEDO = vec3(0.92, 0.97, 1.0) * mix(1.0, 0.3, night);
	ALPHA = clamp(a, 0.0, 1.0) * 0.7;
}
