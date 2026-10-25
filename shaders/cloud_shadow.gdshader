shader_type spatial;
render_mode unshaded, cull_disabled;
// The clouds' shadows: the cloud's box drawn only into the sun's shadow map.
// Each texel looks along the sunlight through the same vapour the visible
// cloud is made of (cloud.gdshaderinc) and blocks the light in a dither that
// follows how much vapour it passes, so after the shadow blur the ground below
// gets a soft patch, darkest under the thick middle and fraying at the edges,
// that drifts and changes shape with the cloud.

#include "res://shaders/cloud.gdshaderinc"

varying float v_seed;

void vertex() {
	v_seed = COLOR.a * 7.0;
}

void fragment() {
	vec3 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// the sun's shadow camera is orthogonal: every ray runs the same way
	vec3 rd = -normalize(INV_VIEW_MATRIX[2].xyz);
	mat4 inv = inverse(MODEL_MATRIX);
	vec3 ro_l = (inv * vec4(p - rd * 400.0, 1.0)).xyz;
	vec3 rd_l = (inv * vec4(rd, 0.0)).xyz;
	vec3 inv_d = 1.0 / rd_l;
	vec3 t0 = (vec3(-1.0, 0.0, -1.0) - ro_l) * inv_d;
	vec3 t1 = (vec3(1.0) - ro_l) * inv_d;
	float t_in = max(max(min(t0.x, t1.x), min(t0.y, t1.y)), min(t0.z, t1.z));
	float t_out = min(min(max(t0.x, t1.x), max(t0.y, t1.y)), max(t0.z, t1.z));
	if (t_out <= t_in) {
		discard;
	}
	float dt = (t_out - t_in) / 5.0;
	float od = 0.0;
	for (int i = 0; i < 5; i++) {
		float t = t_in + (float(i) + 0.5) * dt;
		od += cloud_density(ro_l + rd_l * t, p - rd * 400.0 + rd * t, v_seed, false) * dt;
	}
	float a = 1.0 - exp(-od * 0.14);
	// at most about two texels in three block the light: a soft, see-through shadow
	vec2 cell = mod(floor(FRAGCOORD.xy), 2.0);
	float th = cell.x + cell.y * 2.0 == 0.0 ? 0.25 : (cell.x + cell.y * 2.0 == 3.0 ? 0.5 : (cell.x + cell.y * 2.0 == 1.0 ? 0.75 : 2.0));
	if (a < th) {
		discard;
	}
	ALBEDO = vec3(1.0);
}
