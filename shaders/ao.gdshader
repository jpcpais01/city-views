shader_type spatial;
// Hyper graphics (photo mode only): ambient occlusion from the depth buffer.
// A screen-covering quad that darkens creases, the feet of buildings, the
// gaps between them and the undersides of eaves, the way soft skylight is
// blocked in real life. Multiplied over the opaque scene, before the sea.
render_mode unshaded, blend_mul, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float strength = 0.85;
// how far the occlusion reaches, in metres, near and as a share of the depth
uniform float radius = 0.9;
uniform float radius_grow = 0.004;
uniform float night = 0.0;

const int SAMPLES = 24;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float d = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return v.xyz / v.w;
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 p = view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float ao = 1.0;
	if (-p.z < 2500.0) {
		// the normal from the closer of each pair of neighbours, so edges stay sharp
		vec3 l = view_pos(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
		vec3 r = view_pos(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
		vec3 b = view_pos(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
		vec3 t = view_pos(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
		vec3 dx = abs(r.z - p.z) < abs(p.z - l.z) ? r - p : p - l;
		vec3 dy = abs(t.z - p.z) < abs(p.z - b.z) ? t - p : p - b;
		vec3 n = normalize(cross(dx, dy));
		if (dot(n, p) > 0.0) n = -n;
		vec3 tx = normalize(abs(n.y) < 0.9 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, vec3(1.0, 0.0, 0.0)));
		vec3 ty = cross(n, tx);
		float rad = radius + radius_grow * -p.z;
		float rot = ign(FRAGCOORD.xy) * 6.2831853;
		float occ = 0.0;
		for (int i = 0; i < SAMPLES; i++) {
			float fi = (float(i) + 0.5) / float(SAMPLES);
			// a spiral over the hemisphere, denser near the surface point
			float a = rot + float(i) * 2.3999632;
			float s = sqrt(fi);
			vec3 h = vec3(cos(a) * s, sin(a) * s, sqrt(max(1.0 - fi, 0.0)) * 0.9 + 0.1);
			float len = mix(0.15, 1.0, fract(fi * 7.31 + ign(FRAGCOORD.yx)));
			vec3 q = p + (tx * h.x + ty * h.y + n * h.z) * rad * len;
			vec4 c = PROJECTION_MATRIX * vec4(q, 1.0);
			vec2 uv = c.xy / c.w * 0.5 + 0.5;
			if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) continue;
			float sz = view_pos(uv, INV_PROJECTION_MATRIX).z;
			// blocked when the scene there stands in front of the sample, by a
			// believable amount (a tower far in front shades nothing here)
			float range = smoothstep(0.0, 1.0, rad / max(abs(p.z - sz), 1e-4));
			occ += (sz >= q.z + 0.02 * rad ? 1.0 : 0.0) * range;
		}
		occ /= float(SAMPLES);
		ao = 1.0 - occ * strength * (1.0 - 0.6 * night);
		// a far-off landscape keeps a little of it, never a dark smear
		ao = mix(ao, 1.0, smoothstep(900.0, 2500.0, -p.z));
		ao = clamp(ao, 0.0, 1.0);
		ao = ao * ao * (3.0 - 2.0 * ao) * 0.35 + ao * 0.65;
	}
	ALBEDO = vec3(ao);
}
