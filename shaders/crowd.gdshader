shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// The busy streets of Drive mode: one mesh per car body or walker, drawn
// many times over by a MultiMesh, each copy dressed and moved by its own
// INSTANCE_CUSTOM.
//
// UV.x tags what a vertex is:
//   0 plain, 1 glass, 2 headlamp, 3 tail lamp,
//   4 car paint (custom.rgb), 5 shirt, 6 trousers, 7 skin, 8 hair
//   (people: custom.x shirt, .y trousers + 8 * skin, .z hair, .w stride phase)
// UV.y on people: the limb a vertex swings with (1 left leg, 2 right leg,
//   3 left arm, 4 right arm); on cars: how hard it brakes, read from custom.w.

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec3 refl_top : source_color = vec3(0.35, 0.62, 0.92);
uniform vec3 refl_hor : source_color = vec3(0.78, 0.9, 0.98);
// hip and shoulder heights of the walkers, for swinging the limbs
uniform float hip = 0.118;
uniform float shoulder = 0.205;

const vec3 SHIRTS[12] = vec3[](vec3(0.94, 0.36, 0.36), vec3(0.29, 0.53, 0.84), vec3(0.95, 0.76, 0.31), vec3(0.25, 0.68, 0.55),
	vec3(0.94, 0.5, 0.66), vec3(0.96, 0.96, 0.95), vec3(0.2, 0.22, 0.27), vec3(0.55, 0.42, 0.75),
	vec3(0.98, 0.58, 0.3), vec3(0.45, 0.62, 0.42), vec3(0.62, 0.78, 0.92), vec3(0.72, 0.2, 0.25));
const vec3 PANTS[8] = vec3[](vec3(0.24, 0.29, 0.36), vec3(0.36, 0.29, 0.26), vec3(0.18, 0.23, 0.28), vec3(0.79, 0.71, 0.56),
	vec3(0.14, 0.15, 0.17), vec3(0.33, 0.42, 0.58), vec3(0.55, 0.52, 0.48), vec3(0.42, 0.3, 0.38));
const vec3 SKINS[4] = vec3[](vec3(0.95, 0.82, 0.71), vec3(0.85, 0.65, 0.49), vec3(0.66, 0.44, 0.31), vec3(0.48, 0.31, 0.2));
const vec3 HAIRS[6] = vec3[](vec3(0.23, 0.16, 0.13), vec3(0.42, 0.29, 0.18), vec3(0.85, 0.71, 0.42), vec3(0.12, 0.12, 0.14),
	vec3(0.62, 0.62, 0.62), vec3(0.6, 0.26, 0.15));

varying float v_tag;
varying float v_brake;
varying vec3 v_world;

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

void vertex() {
	vec3 c = COLOR.rgb;
	float tag = floor(UV.x + 0.5);
	v_tag = tag;
	v_brake = 0.0;
	if (tag == 4.0) {
		c = INSTANCE_CUSTOM.rgb;
	} else if (tag == 3.0) {
		v_brake = INSTANCE_CUSTOM.w;
	} else if (tag >= 5.0) {
		int skin = int(INSTANCE_CUSTOM.y) / 8;
		if (tag == 5.0) c = SHIRTS[int(INSTANCE_CUSTOM.x) % 12] * mix(0.92, 1.0, step(0.0, NORMAL.y));
		else if (tag == 6.0) c = PANTS[int(INSTANCE_CUSTOM.y) % 8];
		else if (tag == 7.0) c = SKINS[skin % 4];
		else c = HAIRS[int(INSTANCE_CUSTOM.z) % 6];
	}
	// people: legs and arms (and shoes and hands) swing from the hip and shoulder as they walk
	float limb = floor(UV.y + 0.5);
	if (limb > 0.5) {
		float ph = INSTANCE_CUSTOM.w;
		float side = (limb == 1.0 || limb == 4.0) ? 1.0 : -1.0;
		float arm = step(2.5, limb);
		float a = sin(ph) * side * mix(0.55, 0.45, arm);
		float py = mix(hip, shoulder, arm);
		vec2 yz = vec2(VERTEX.y - py, VERTEX.z);
		float ca = cos(a);
		float sa = sin(a);
		VERTEX.y = py + yz.x * ca - yz.y * sa;
		VERTEX.z = yz.x * sa + yz.y * ca;
		vec2 n = vec2(NORMAL.y * ca - NORMAL.z * sa, NORMAL.y * sa + NORMAL.z * ca);
		NORMAL.y = n.x;
		NORMAL.z = n.y;
	}
	COLOR.rgb = to_linear(c);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	vec3 glow = vec3(0.0);
	if (v_tag == 4.0) {
		// glossy car paint, with a little of the sky on its upper faces
		ROUGHNESS = 0.32;
		SPECULAR = 0.55;
		float up = clamp(dot(NORMAL, (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz), 0.0, 1.0);
		base = mix(base, to_linear(refl_hor) * 0.9, up * 0.08 * (1.0 - night));
	} else if (v_tag == 1.0) {
		// tinted glass mirroring the sky, more so at a glancing angle
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
		vec3 sky = mix(to_linear(refl_hor), to_linear(refl_top), 0.4) * mix(1.0, 0.12, night);
		base = mix(base, sky, 0.25 + 0.45 * fres);
		ROUGHNESS = 0.22;
		SPECULAR = 0.65;
	} else if (v_tag == 2.0) {
		glow = vec3(1.0, 0.9, 0.7) * night * 2.2;
	} else if (v_tag == 3.0) {
		glow = base * (night * 1.6 + v_brake * 2.4);
	}
	ALBEDO = base;
	EMISSION = glow;
}
