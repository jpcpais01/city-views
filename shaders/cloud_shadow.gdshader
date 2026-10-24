shader_type spatial;
render_mode unshaded, cull_disabled;
// The clouds' shadows: the same puffs, drawn only into the sun's shadow map,
// where each one faces the sun. The vapour is cut with the same drifting noise
// as the visible cloud, and only every other texel of it blocks the light, so
// after the shadow blur the ground below gets a soft, half-dark patch that
// drifts across the town with the cloud instead of a black hole.
// Vertex data as in cloud.gdshader.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float wrap = 300.0;

varying vec3 v_wc;
varying float v_r;
varying float v_base;
varying float v_seed;

void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	v_r = UV2.x * sc;
	v_wc = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_base = v_wc.y - UV2.y * sc;
	v_seed = COLOR.a * 23.0;
	vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION = PROJECTION_MATRIX * (c + vec4(UV * v_r, 0.0, 0.0));
}

void fragment() {
	vec2 d = UV;
	float l2 = dot(d, d);
	if (l2 > 1.0) {
		discard;
	}
	vec3 n = vec3(d, sqrt(1.0 - l2));
	vec3 wp = v_wc + (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz * v_r;
	vec3 np = mix(v_wc, wp, 0.55);
	vec2 q = np.xz * 0.021 + vec2(np.y * 0.031, -np.y * 0.017) + vec2(v_seed, v_seed * 0.61);
	float n1 = texture(noise_tex, q + vec2(TIME * 0.0021, TIME * 0.0013)).r;
	float n2 = texture(noise_tex, q * 2.7 + vec2(-TIME * 0.0047, TIME * 0.0031) + 0.37).r;
	float nz = n1 * 0.62 + n2 * 0.38;
	float shape = (1.0 - sqrt(l2)) * 1.25 - (nz - 0.5) * 1.1 - 0.05;
	float a = smoothstep(0.0, 0.5, shape) * (1.0 - smoothstep(0.72, 1.0, l2)) * (1.0 - smoothstep(wrap - 55.0, wrap, abs(v_wc.x)));
	// a checkerboard of the denser vapour: half the light gets through
	vec2 cell = mod(floor(FRAGCOORD.xy), 2.0);
	float th = cell.x == cell.y ? 0.35 : 2.0;
	if (a < th) {
		discard;
	}
	ALBEDO = vec3(1.0);
}
