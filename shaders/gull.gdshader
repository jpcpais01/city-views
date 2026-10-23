shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// Seagulls: the wings are single sheets that bend at the shoulder and the
// elbow in the vertex stage, so one mesh can glide, flap, dive and fold.
// INSTANCE_CUSTOM: x = shoulder angle, y = fold (1 = tucked in, standing),
// z = extra bend of the outer wing, w = legs down.
// UV.x: 0 body, 1 wing, 2 head, 3 legs. UV.y: 1 on the black wingtips.

#include "res://shaders/beam.gdshaderinc"

const float SHOULDER = 0.05;
const float INNER = 0.21;

varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	vec3 c = COLOR.rgb;
	COLOR.rgb = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	v_local = VERTEX;
	if (UV.x > 0.5 && UV.x < 1.5) {
		float s = sign(VERTEX.x);
		float r = max(abs(VERTEX.x) - SHOULDER, 0.0);
		float r1 = min(r, INNER);
		float r2 = r - r1;
		float a = INSTANCE_CUSTOM.x;
		float b = a + INSTANCE_CUSTOM.z;
		float fold = INSTANCE_CUSTOM.y;
		vec3 open = vec3(s * (SHOULDER + r1 * cos(a) + r2 * cos(b)), VERTEX.y + r1 * sin(a) + r2 * sin(b), VERTEX.z);
		// tucked: the wing lies along the flank, its tip crossing over the tail
		vec3 tucked = vec3(s * (0.058 + r * 0.035), 0.03 + VERTEX.y * 0.4 + r * 0.03, VERTEX.z * 0.55 - r * 0.62);
		VERTEX = mix(open, tucked, fold);
		float ang = r2 > 0.0 ? b : a;
		vec3 n_open = vec3(-s * sin(ang), cos(ang), 0.0);
		vec3 n_tucked = vec3(s, 0.25, 0.0);
		NORMAL = normalize(mix(n_open, n_tucked, fold));
	} else if (UV.x > 2.5) {
		// legs tuck up into the belly in flight
		VERTEX.y = mix(-0.045, VERTEX.y, INSTANCE_CUSTOM.w);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (UV.x > 0.5 && UV.x < 1.5) {
		if (UV.y > 0.5) {
			// black wingtips with the little white "mirror" spots
			float spot = 1.0 - smoothstep(0.012, 0.02, length(vec2(abs(v_local.x) - 0.445, v_local.z + 0.06)));
			base = mix(vec3(0.03, 0.03, 0.035), vec3(0.85), spot);
		} else if (!FRONT_FACING) {
			// pale underwing, with a soft grey trailing edge
			base = mix(vec3(0.86, 0.87, 0.88), vec3(0.6, 0.64, 0.68), 1.0 - smoothstep(-0.09, -0.05, v_local.z));
		} else {
			// white trailing edge on the grey upperwing
			base = mix(base, vec3(0.88), 1.0 - smoothstep(-0.09, -0.07, v_local.z));
		}
	} else if (UV.x > 1.5 && UV.x < 2.5) {
		// head: a dark eye on each side
		vec2 e = vec2(v_local.y - 0.052, v_local.z - 0.19);
		base = mix(base, vec3(0.04), (1.0 - smoothstep(0.008, 0.012, length(e))) * step(0.022, abs(v_local.x)));
	} else {
		// grey mantle on the back between the wings
		float mantle = smoothstep(0.03, 0.05, v_local.y) * (1.0 - smoothstep(0.04, 0.12, v_local.z)) * smoothstep(-0.2, -0.1, v_local.z);
		base = mix(base, vec3(0.42, 0.46, 0.5), mantle);
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = base + rim * 0.05;
	ROUGHNESS = 0.7;
	SPECULAR = 0.3;
	if (beam_count > 0) {
		EMISSION = ALBEDO * vec3(1.0, 0.9, 0.66) * beam_light(v_world) * 0.9;
	}
}
