shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front, shadows_disabled;
// Volumetric cumulus: each cloud is a box the shader marches a ray through,
// gathering vapour shaped by 3D noise (cloud.gdshaderinc). Every step lights
// the vapour by how much of it lies between there and the sun (Beer's law,
// with the "powder" darkening of the dense insides seen from the sun's side),
// scattered mostly forwards so a cloud in front of the sun gets a silver
// lining, and by the sky above and the ground's bounce below, so the tops are
// bright white, the sides soft grey and the flat bases blue-grey. The march
// stops at whatever stands inside the cloud (a tower pokes into the vapour)
// and the vapour thins round the camera. Drawn from the box's back faces with
// the depth test off, so it works from inside a cloud too.

#include "res://shaders/cloud.gdshaderinc"

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// towards the sun (or moon), its light (colour times energy), the sky's
// light from above and from the horizon, how dark the night is
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.3);
// (linear, already times the light's energy)
uniform vec3 sun_light = vec3(1.8, 1.7, 1.55);
uniform vec3 sky_top : source_color = vec3(0.35, 0.55, 0.85);
uniform vec3 sky_hor : source_color = vec3(0.75, 0.85, 0.95);
uniform float night = 0.0;

const int STEPS = 14;
// how thick the vapour is: extinction per metre at full density
const float SIGMA = 0.2;

varying float v_seed;

void vertex() {
	v_seed = COLOR.a * 7.0;
}

float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.566 * pow(1.0 + g2 - 2.0 * g * c, 1.5));
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 back = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize(back - cam);
	// the ray in the box's own space
	mat4 inv = inverse(MODEL_MATRIX);
	vec3 ro_l = (inv * vec4(cam, 1.0)).xyz;
	vec3 rd_l = (inv * vec4(rd, 0.0)).xyz;
	vec3 lo = vec3(-1.0, 0.0, -1.0);
	vec3 hi = vec3(1.0, 1.0, 1.0);
	vec3 inv_d = 1.0 / rd_l;
	vec3 t0 = (lo - ro_l) * inv_d;
	vec3 t1 = (hi - ro_l) * inv_d;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	float t_in = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	float t_out = min(min(tmax.x, tmax.y), tmax.z);
	// stop at the scene: a tower or hill inside the cloud
	float sd = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, sd, 1.0);
	float scene_t = length(sv.xyz / sv.w);
	t_out = min(t_out, scene_t);
	if (t_out <= t_in) {
		discard;
	}
	float len = t_out - t_in;
	float dt = len / float(STEPS);
	// a different start in each pixel hides the steps (the blur of the eye does the rest)
	float jitter = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	float cos_t = dot(rd, sun_dir);
	// mostly forward (the silver lining), a little back towards the sun
	float phase = min(mix(hg(cos_t, 0.6), hg(cos_t, -0.25), 0.3) * 12.566, 3.0);
	vec3 amb_top = sky_top * 0.65 + sky_hor * 0.3;
	vec3 amb_low = sky_hor * 0.32 + vec3(0.05, 0.06, 0.05);
	float trans = 1.0;
	vec3 col = vec3(0.0);
	for (int i = 0; i < STEPS; i++) {
		float t = t_in + (float(i) + jitter) * dt;
		vec3 wp = cam + rd * t;
		vec3 q = ro_l + rd_l * t;
		float d = cloud_density(q, wp, v_seed, true);
		// thin out round the camera rather than fill the screen with fog
		d *= smoothstep(1.5, 14.0, t);
		if (d > 0.002) {
			// vapour between here and the sun
			vec3 w1 = wp + sun_dir * 4.0;
			vec3 w2 = wp + sun_dir * 13.0;
			float od = cloud_density((inv * vec4(w1, 1.0)).xyz, w1, v_seed, false) * 6.0
				+ cloud_density((inv * vec4(w2, 1.0)).xyz, w2, v_seed, false) * 9.0;
			float to_sun = exp(-od * SIGMA);
			// dense insides seen from the sun's side darken (the powder effect)
			float powder = 1.0 - exp(-d * 2.6);
			vec3 light = sun_light * to_sun * mix(1.0, powder * 1.6, 0.5) * phase;
			light += mix(amb_low, amb_top, smoothstep(0.0, 0.85, q.y)) * (0.55 + 0.45 * d);
			float ext = d * SIGMA * dt;
			float a = 1.0 - exp(-ext);
			col += trans * a * light;
			trans *= 1.0 - a;
			if (trans < 0.02) {
				break;
			}
		}
	}
	float alpha = 1.0 - trans;
	if (alpha < 0.004) {
		discard;
	}
	col /= max(alpha, 0.0001);
	// moonlit at night: dim and cool
	col = mix(col, col * vec3(0.55, 0.62, 0.8), night * 0.6);
	ALBEDO = col;
	ALPHA = alpha;
}
