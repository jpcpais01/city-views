shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;
// Sea: Gerstner swell, refraction of the real seabed through the surface,
// depth-based light absorption (clear turquoise shallows, deep blue offshore),
// animated caustics on the sand, crest glow and breaking foam at the shore.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// one small tiling noise texture replaces all procedural noise (much cheaper on phones)
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 scatter_col : source_color = vec3(0.02, 0.2, 0.42);
uniform vec3 shallow_tint : source_color = vec3(0.55, 1.0, 0.92);
uniform vec3 crest_col : source_color = vec3(0.25, 0.85, 0.75);
uniform vec3 foam_col : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 absorb = vec3(0.75, 0.3, 0.17);
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float wave_scale = 0.16;
uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform float grid_size = 128.0;

varying vec3 w_pos;
varying float crest;

// metres from the nearest coastline (smoothed from the tile distance map)
float shore_dist(vec2 xz) {
	float v = texture(shore_tex, xz / grid_size + 0.5).r * 8.0;
	return (v - 0.5) * 2.0;
}

// direction (xy), wavelength, steepness
const vec4 WAVES[4] = vec4[](
	vec4(0.86, 0.5, 13.0, 0.16),
	vec4(-0.3, 0.95, 8.5, 0.14),
	vec4(0.55, -0.83, 5.7, 0.12),
	vec4(-0.95, -0.2, 3.9, 0.1)
);

void vertex() {
	vec3 p = VERTEX;
	// calmer far from the island so the horizon stays clean
	float sd = shore_dist(p.xz);
	float fade = (1.0 - smoothstep(120.0, 260.0, length(p.xz))) * wave_scale * (0.25 + 0.75 * smoothstep(0.0, 5.0, sd));
	vec3 off = vec3(0.0);
	vec3 tx = vec3(1.0, 0.0, 0.0);
	vec3 tz = vec3(0.0, 0.0, 1.0);
	for (int i = 0; i < 4; i++) {
		vec2 d = normalize(WAVES[i].xy);
		float k = 6.28318 / WAVES[i].z;
		float c = sqrt(9.8 / k) * 0.55;
		float a = WAVES[i].w / k * fade;
		float f = k * (dot(d, p.xz) - c * TIME);
		float s = sin(f);
		float co = cos(f);
		off += vec3(d.x * a * co * 0.6, a * s, d.y * a * co * 0.6);
		tx += vec3(-d.x * d.x * k * a * s * 0.6, d.x * k * a * co, -d.x * d.y * k * a * s * 0.6);
		tz += vec3(-d.x * d.y * k * a * s * 0.6, d.y * k * a * co, -d.y * d.y * k * a * s * 0.6);
	}
	p += off;
	crest = off.y;
	w_pos = p;
	VERTEX = p;
	NORMAL = normalize(cross(tz, tx));
}

float nz2(vec2 p) {
	return texture(noise_tex, p).r;
}

// slope of a two-octave ripple field from the noise texture's gradient
vec2 ripple_slope(vec2 p, float t) {
	vec2 a = p * 0.11 + vec2(t * 0.025, t * 0.016);
	vec2 b = p * 0.26 - vec2(t * 0.02, -t * 0.03);
	float e = 0.004;
	float h0 = nz2(a) + nz2(b) * 0.45;
	float hx = nz2(a + vec2(e, 0.0)) + nz2(b + vec2(e, 0.0)) * 0.45;
	float hz = nz2(a + vec2(0.0, e)) + nz2(b + vec2(0.0, e)) * 0.45;
	return vec2(hx - h0, hz - h0) / e * 0.11;
}

// caustic web: where two drifting noise layers cross their mid level
float caustic(vec2 p, float t) {
	float a = nz2(p * 0.04 + vec2(t * 0.006, t * 0.004));
	float b = nz2(p * 0.052 - vec2(t * 0.005, -t * 0.006) + 0.37);
	float c = 1.0 - abs(a - b) * 5.0;
	return clamp(c, 0.0, 1.0) * clamp(c, 0.0, 1.0) * clamp(c, 0.0, 1.0) * 1.6;
}

vec3 scene_world(vec2 uv, mat4 inv_proj, mat4 inv_view, out float view_z) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	v.xyz /= v.w;
	view_z = v.z;
	return (inv_view * vec4(v.xyz, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	// surface normal: swell from the vertex stage plus fine ripples
	vec2 sl = ripple_slope(w_pos.xz, t);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	n_world = normalize(n_world + vec3(-sl.x, 0.0, -sl.y) * 0.22);
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// what lies under the surface right here
	float sz;
	vec3 sp = scene_world(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, sz);
	float depth0 = clamp(w_pos.y - sp.y, 0.0, 40.0);

	// bend the view through the surface; refuse samples of things above the water
	vec2 ruv = SCREEN_UV + n_view.xz * 0.045 * clamp(depth0 * 0.8, 0.0, 1.0);
	float rz;
	vec3 rp = scene_world(ruv, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, rz);
	if (rz > VERTEX.z || rp.y > w_pos.y) {
		ruv = SCREEN_UV;
		rp = sp;
		rz = sz;
	}
	float depth = clamp(w_pos.y - rp.y, 0.0, 40.0);
	float path = clamp(VERTEX.z - rz, 0.0, 60.0);

	vec3 below = textureLod(screen_tex, ruv, 0.0).rgb;
	// sunlight dancing on the sand, strongest in the shallows
	float cz = caustic(rp.xz, t);
	float c_amt = (1.0 - night) * smoothstep(0.02, 0.25, depth) * exp(-depth * 0.55);
	below *= 1.0 + cz * c_amt * 1.4;
	below *= mix(vec3(1.0), shallow_tint, smoothstep(0.0, 0.6, depth));

	// light absorption along the path through the water (Beer-Lambert)
	vec3 trans = exp(-absorb * (path * 0.55 + depth * 0.8));
	vec3 body = scatter_col * mix(1.0, 0.25, night);
	vec3 col = below * trans + body * (1.0 - trans);
	// sun through the crests
	float cr = smoothstep(0.0, 0.07, crest);
	col += crest_col * cr * 0.12 * (1.0 - night);

	// foam: a soft lace at the waterline plus bands rolling towards the beach
	float nz = nz2(w_pos.xz * 0.2 + vec2(t * 0.04, -t * 0.027)) * 0.6 + nz2(w_pos.xz * 0.5 - t * 0.05) * 0.4;
	float sd = shore_dist(w_pos.xz);
	float edge = max(1.0 - smoothstep(0.0, 0.1 + nz * 0.1, depth0), 1.0 - smoothstep(0.05, 0.3 + nz * 0.45, sd));
	float roll = sin(sd * 3.4 + t * 1.7 + nz * 2.2) * 0.5 + 0.5;
	float bands = smoothstep(0.8, 0.95, roll) * (1.0 - smoothstep(0.3, 2.6, sd)) * smoothstep(0.3, 0.55, nz);
	float caps = smoothstep(0.075, 0.095, crest) * smoothstep(0.62, 0.8, nz) * 0.5;
	float foam = clamp(max(edge, bands) + caps, 0.0, 1.0);
	foam = smoothstep(0.35, 0.6, foam);

	// reflection comes from the engine (sky radiance + sun specular); weight the body by Fresnel
	float ndv = clamp(dot(n_view, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	EMISSION = col * (1.0 - fres) * (1.0 - foam);
	ALBEDO = foam_col * foam;
	NORMAL = n_view;
	ROUGHNESS = mix(0.035, 0.8, foam);
	SPECULAR = mix(0.6, 0.2, foam);
	METALLIC = 0.0;
	// melt into the sand instead of a hard line
	ALPHA = smoothstep(0.0, 0.035, depth0);
}
