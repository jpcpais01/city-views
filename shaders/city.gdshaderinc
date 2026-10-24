
// 0 = day, 1 = deep night. Driven by the day/night cycle.
uniform float night : hint_range(0.0, 1.0) = 0.0;
// fraction of windows that are lit (varies through the night)
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.7;
uniform vec3 warm_light : source_color = vec3(1.0, 0.74, 0.42);
uniform vec3 frame_col : source_color = vec3(0.97, 0.97, 0.95);
// what glass mirrors: the sky (World._update_sky keeps these in step with it)
uniform vec3 refl_top : source_color = vec3(0.35, 0.62, 0.92);
uniform vec3 refl_hor : source_color = vec3(0.78, 0.9, 0.98);
uniform vec3 refl_sun_col : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 refl_sun_dir = vec3(0.0, 0.8, 0.6);
uniform float refl_amount = 1.0;

#include "res://shaders/beam.gdshaderinc"
#ifndef GROUND
// ground height of every tile, so walls, trunks and kerbs darken where they meet the ground
uniform sampler2D height_tex : filter_nearest, repeat_disable;
uniform float grid_size = 128.0;
// the height map stores (y + range.y) / range.x
uniform vec2 height_range = vec2(2.5, 0.5);
#endif

#ifdef GROUND
// which fields are farmed (Land.update_farm), sampled at each field's middle
uniform sampler2D farm_tex : filter_linear, repeat_disable;
uniform float farm_angle = 0.0;
uniform float grid_size = 384.0;
// the painted town's tint while the Grow brush is in hand (Land.update_tint),
// one texel per ground sample
uniform bool show_zone = false;
uniform sampler2D tint_tex : source_color, filter_linear, repeat_disable;
#endif

varying float v_emit;
varying float v_rand;
varying vec3 v_world;
varying vec3 v_wnorm;

float g_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float g_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(g_hash(i), g_hash(i + vec2(1.0, 0.0)), f.x), mix(g_hash(i + vec2(0.0, 1.0)), g_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

#ifndef GROUND
// What a pane of glass mirrors along `r` (world space): the sky, brightest
// round the sun, the far side of town as a ragged band of rooftops along the
// horizon (dotted with lit windows at night), and the ground below it. All
// worked out from the direction alone, so it costs a few instructions a pixel.
vec3 sky_reflect(vec3 r) {
	float up = r.y;
	float aw = fwidth(up) + 0.002;
	vec3 sky = mix(refl_hor, refl_top, smoothstep(0.0, 0.55, up));
	sky += refl_sun_col * pow(max(dot(r, refl_sun_dir), 0.0), 18.0) * 0.7 * (1.0 - night);
	float az = atan(r.z, r.x) * 2.5465;
	float a1 = floor(az * 4.0);
	float a2 = floor(az * 9.0 + 0.5);
	float roof = 0.015 + 0.13 * pow(g_hash(vec2(a1, 1.3)), 2.0);
	roof = max(roof, 0.01 + 0.07 * g_hash(vec2(a2, 7.1)));
	vec3 town = refl_hor * mix(0.5, 0.62, g_hash(vec2(a2, 3.3))) + vec3(0.02);
	// lit windows in the far towers at night
	vec2 wq = vec2(az * 60.0, up * 140.0);
	float lit = step(0.86, g_hash(floor(wq))) * step(0.3, fract(wq.x)) * step(0.35, fract(wq.y));
	town = mix(town * 0.35, town * 0.25 + warm_light * lit * 0.8, night);
	vec3 ground = mix(vec3(0.16, 0.19, 0.15), refl_hor * 0.4, 0.4) * mix(1.0, 0.35, night);
	vec3 low = mix(ground, town, smoothstep(-aw, aw, up + 0.01));
	return mix(low, sky, smoothstep(roof - aw, roof + aw, up));
}
#endif

void vertex() {
	// vertex colours are authored in sRGB
	vec3 c = COLOR.rgb;
	COLOR.rgb = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	v_emit = UV.x;
	v_rand = UV.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Daylight look of a window pane at (u, v): sky reflected brighter at the top,
// a soft diagonal sheen, and on some windows blinds or curtains behind the glass.
// cover returns how much of the pane they hide, cover_col their colour.
vec3 pane(vec3 col, float u, float v, float r, out float cover, out vec3 cover_col) {
	vec3 g = col * mix(0.72, 1.18, smoothstep(0.0, 1.0, v)) + vec3(0.04, 0.05, 0.06) * smoothstep(0.55, 1.0, v);
	float sheen = fract(u * 0.55 + v * 0.35 + r * 5.0);
	g += vec3(0.1) * smoothstep(0.0, 0.08, sheen) * (1.0 - smoothstep(0.14, 0.3, sheen));
	cover = 0.0;
	cover_col = vec3(0.9, 0.86, 0.78);
	float pick = fract(r * 7.31);
	if (pick < 0.3) {
		// roller blind pulled part way down, with faint slats
		float drop = 0.2 + 0.6 * fract(r * 3.7);
		float aa = fwidth(v);
		cover = smoothstep(1.0 - drop - aa, 1.0 - drop + aa, v);
		cover_col *= 0.92 + 0.08 * step(0.5, fract(v * 14.0));
	} else if (pick < 0.55) {
		// curtains drawn to the sides
		vec3 cols[4] = vec3[](vec3(0.86, 0.42, 0.38), vec3(0.93, 0.88, 0.76), vec3(0.55, 0.7, 0.58), vec3(0.45, 0.58, 0.82));
		cover_col = cols[int(fract(r * 13.1) * 4.0)];
		float w = 0.14 + 0.12 * fract(r * 5.3);
		float aa = fwidth(u);
		cover = 1.0 - smoothstep(w - aa, w + aa, u) * smoothstep(w - aa, w + aa, 1.0 - u);
		cover_col *= 0.9 + 0.1 * sin(u * 60.0);
	}
	return mix(g, cover_col * 0.8, cover);
}

void fragment() {
	vec3 base = COLOR.rgb;
#ifdef GROUND
	{
		vec2 p = v_world.xz;
		// broad patches that wander across tiles: lusher and drier grass, damp and dry sand
		float broad = g_noise(p * 0.13) * 0.55 + g_noise(p * 0.37 + 17.0) * 0.3 + g_noise(p * 0.9 + 5.0) * 0.15;
		float grass = smoothstep(0.02, 0.12, base.g - max(base.r, base.b));
		vec3 lush = base * vec3(0.8, 0.98, 0.78);
		vec3 dry = base * vec3(1.14, 1.07, 0.8);
		base = mix(base, mix(lush, dry, smoothstep(0.36, 0.64, broad)), grass);
		base *= 0.94 + 0.12 * broad * (1.0 - grass);
		// farmland: a patchwork of fields (Land.FIELD, turned by farm_angle)
		// of wheat, young crops, ploughed earth, rapeseed and hay, with
		// hedges round them; past the map's edge they run on to the horizon
		{
			float ca = cos(farm_angle);
			float sa = sin(farm_angle);
			vec2 fr = vec2(ca * p.x + sa * p.y, -sa * p.x + ca * p.y);
			vec2 q = fr / vec2(15.0, 10.0);
			vec2 cell = floor(q);
			vec2 mid = (cell + 0.5) * vec2(15.0, 10.0);
			vec2 cw = vec2(ca * mid.x - sa * mid.y, sa * mid.x + ca * mid.y);
			float half_map = grid_size * 0.5;
			float farm;
			if (abs(cw.x) < half_map && abs(cw.y) < half_map) {
				vec2 n = vec2(textureSize(farm_tex, 0));
				farm = step(0.5, texture(farm_tex, ((cw + half_map) / 4.0 + 0.5) / n).r);
			} else {
				// out in the country: by a broad noise, on gentle dry ground
				farm = step(0.5, g_noise(cw * 0.011 + 7.3)) * step(0.9, v_world.y) * step(v_world.y, 8.0);
			}
			farm *= grass * smoothstep(0.955, 0.98, v_wnorm.y);
			if (farm > 0.0) {
				float h = g_hash(cell + 11.0);
				vec3 crop;
				if (h < 0.28) crop = vec3(0.74, 0.55, 0.17);
				else if (h < 0.48) crop = vec3(0.25, 0.46, 0.09);
				else if (h < 0.64) crop = vec3(0.3, 0.19, 0.1);
				else if (h < 0.72) crop = vec3(0.86, 0.7, 0.08);
				else if (h < 0.86) crop = vec3(0.6, 0.6, 0.27);
				else crop = base * vec3(0.92, 1.0, 0.88);
				crop *= 0.92 + 0.16 * g_hash(cell + 3.0) + (broad - 0.5) * 0.1;
				// rows ploughed or sown along the field, fading before they shimmer
				vec2 f = fract(q);
				float along = g_hash(cell + 5.0) > 0.5 ? f.x * 15.0 : f.y * 10.0;
				float rw = fwidth(along * 2.2);
				float rows = sin(along * 2.2 * 6.2832) * (1.0 - smoothstep(0.2, 0.5, rw));
				crop *= 1.0 + rows * (h < 0.86 ? 0.07 : 0.0);
				// a hedge round the field
				float edge = min(min(f.x, 1.0 - f.x) * 15.0, min(f.y, 1.0 - f.y) * 10.0);
				float ew = fwidth(edge);
				float hedge = 1.0 - smoothstep(0.22 - ew, 0.22 + ew, edge);
				crop = mix(crop, vec3(0.1, 0.22, 0.06), hedge);
				base = mix(base, crop, farm);
				grass *= 1.0 - farm;
			}
		}
		// paving between the buildings of a dense town (Land.paved, in COLOR.a):
		// big stone slabs in staggered rows, each a slightly different tone
		float paved = 1.0 - COLOR.a;
		if (paved > 0.01) {
			vec2 q = p * vec2(1.4, 2.1);
			q.x += mod(floor(q.y), 2.0) * 0.5;
			vec2 sc = floor(q);
			vec2 sf = abs(fract(q) - 0.5);
			float saa = length(fwidth(q));
			float joint = smoothstep(0.46 - saa, 0.5, max(sf.x, sf.y)) * (1.0 - smoothstep(0.25, 0.6, saa));
			float tone = 0.93 + 0.12 * g_hash(sc + 19.0) + (broad - 0.5) * 0.06;
			base = mix(base, base * tone * mix(1.0, 0.8, joint), paved);
			grass *= 1.0 - paved;
		}
		// fine grain: blades, sand grains and grit, fading out before it can shimmer
		float fw = length(fwidth(p));
		float grain = g_noise(p * 5.3) * 0.6 + g_noise(p * 13.0) * 0.4;
		float close = 1.0 - smoothstep(0.05, 0.25, fw);
		base *= 1.0 + (grain - 0.5) * 0.12 * close;
		// tufts: darker and lighter clumps through the meadow
		if (grass > 0.0) {
			base *= 1.0 + (g_noise(p * 2.3 + 3.0) - 0.5) * 0.2 * grass;
		}
		// wind ripples in the dry sand
		float sand = smoothstep(0.06, 0.14, base.r - base.b) * (1.0 - grass);
		if (sand > 0.0) {
			float rip = sin(dot(p, vec2(0.8, 0.6)) * 9.0 + g_noise(p * 0.7) * 7.0);
			base *= 1.0 + rip * 0.035 * sand * close;
		}
		// tiny wildflowers and clover dotted through the grass
		vec2 fq = p * 5.0;
		vec2 fc = floor(fq);
		float fh = g_hash(fc + 41.0);
		if (fh > 0.93 && grass > 0.5) {
			vec2 off = vec2(g_hash(fc + 7.0), g_hash(fc + 13.0)) * 0.5 + 0.25;
			float dot_m = 1.0 - smoothstep(0.07, 0.11, length(fract(fq) - off));
			vec3 petals[4] = vec3[](vec3(1.0, 0.97, 0.9), vec3(1.0, 0.86, 0.3), vec3(0.95, 0.6, 0.75), vec3(0.7, 0.72, 1.0));
			vec3 pc = fh > 0.965 ? petals[int(fract(fh * 91.0) * 4.0)] : base * vec3(0.8, 1.08, 0.75);
			base = mix(base, pc, dot_m * close);
		}
	}
#endif
#ifndef GROUND
	{
		// fine surface grain (plaster, asphalt, paving), gone before it could shimmer
		vec2 gp = v_world.xz + v_world.yy * vec2(0.7, -1.3);
		float fw = length(fwidth(v_world));
		float gr = g_noise(gp * 9.0) * 0.6 + g_noise(gp * 23.0) * 0.4;
		base *= 1.0 + (gr - 0.5) * 0.07 * (1.0 - smoothstep(0.04, 0.18, fw));
		if (v_emit > 0.2 && v_emit < 0.3) {
			// roof tiles: rows down the slope with staggered joints
			float rows = v_world.y * 15.0;
			float row = floor(rows);
			float aa = fwidth(rows) * 1.5;
			float lip = smoothstep(0.0, 0.18 + aa, fract(rows));
			float along = (v_world.x + v_world.z) * 7.0 + mod(row, 2.0) * 0.5;
			float aj = fwidth(along) * 1.5;
			float joint = smoothstep(0.0, 0.06 + aj, fract(along)) * smoothstep(0.0, 0.06 + aj, 1.0 - fract(along));
			float fade = 1.0 - smoothstep(0.25, 0.6, aa);
			float tile_var = 0.94 + 0.12 * g_hash(vec2(row, floor(along)));
			base *= mix(1.0, mix(0.78, 1.0, lip) * mix(0.9, 1.0, joint) * tile_var, fade);
		} else if (v_emit > 0.31 && v_emit < 0.35) {
			// cobblestones: staggered rows of rounded setts with dark joints
			vec2 q = v_world.xz * 8.0;
			float row = floor(q.y);
			q.x += mod(row, 2.0) * 0.5;
			vec2 f = fract(q) - 0.5;
			float aa = length(fwidth(q));
			float stone = 1.0 - smoothstep(0.3, 0.46 + aa, max(abs(f.x), abs(f.y)) + 0.12 * dot(f, f));
			float tone = 0.88 + 0.2 * g_hash(floor(q) + row * 3.1);
			base *= mix(1.0, mix(0.62, tone, stone), 1.0 - smoothstep(0.3, 0.7, aa));
		} else if (v_emit > 0.35 && v_emit < 0.39) {
			// paving slabs: big squares in two tones with fine joints
			vec2 q = v_world.xz * 2.5;
			vec2 f = abs(fract(q) - 0.5);
			float aa = length(fwidth(q));
			float joint = smoothstep(0.47 - aa, 0.5, max(f.x, f.y));
			vec2 c = floor(q);
			float checker = mod(c.x + c.y, 2.0);
			base *= mix(mix(0.97, 1.05, checker) * (0.97 + 0.06 * g_hash(c)), 0.8, joint * (1.0 - smoothstep(0.2, 0.5, aa)));
		} else if (v_emit > 0.39 && v_emit < 0.43) {
			// painted timber siding: overlapping boards with a shadow under each lip
			float rows = v_world.y * 20.0;
			float aa = fwidth(rows) * 1.5;
			float lip = smoothstep(0.0, 0.25 + aa, fract(rows));
			base *= mix(1.0, mix(0.82, 1.02, lip), 1.0 - smoothstep(0.3, 0.6, aa));
		} else if (v_emit > 0.43 && v_emit < 0.47) {
			// brickwork: stretcher bond with pale mortar
			float rows = v_world.y * 26.0;
			float row = floor(rows);
			float along = (v_world.x + v_world.z) * 13.0 + mod(row, 2.0) * 0.5;
			float aa = fwidth(rows) + fwidth(along);
			float mortar = max(1.0 - smoothstep(0.0, 0.12 + aa, fract(rows)), 1.0 - smoothstep(0.0, 0.07 + aa, fract(along)));
			float tone = 0.9 + 0.18 * g_hash(vec2(row, floor(along)));
			base = mix(base, mix(base * tone, vec3(0.86, 0.82, 0.76), mortar), 1.0 - smoothstep(0.35, 0.8, aa));
		} else if (v_emit > 0.07 && v_emit < 0.13) {
			// asphalt: patched repairs, hairline cracks and fine aggregate
			vec2 p = v_world.xz;
			float aa = length(fwidth(p));
			float fade = 1.0 - smoothstep(0.08, 0.3, aa);
			vec2 cell = floor(p * 0.9);
			vec2 f = fract(p * 0.9);
			float patched = step(0.86, g_hash(cell + 3.7)) * step(0.15, f.x) * step(f.x, 0.8) * step(0.2, f.y) * step(f.y, 0.7);
			float crack = 1.0 - smoothstep(0.0, 0.006 + aa * 0.5, abs(g_noise(p * 3.6) - 0.5));
			crack *= smoothstep(0.62, 0.75, g_noise(p * 0.45 + 9.0));
			base *= mix(1.0, (1.0 - patched * 0.1) * (1.0 - crack * 0.25), fade);
			base *= 0.95 + 0.1 * g_noise(p * 0.35);
			if (v_emit > 0.122) {
				// one side of an avenue (1.2 m) or a highway (1.65 m): solid
				// lines along both edges, a dashed one between its two lanes
				// (COLOR.a runs across it, UV.y along)
				bool hwy = v_emit > 0.126;
				float width = hwy ? 1.65 : 1.2;
				float x = COLOR.a * width;
				float aw = fwidth(x);
				float edge = min(abs(x - 0.06), abs(x - (width - 0.06)));
				float solid = 1.0 - smoothstep(0.025 - aw, 0.025 + aw, edge);
				float mid = 1.0 - smoothstep(0.03 - aw, 0.03 + aw, abs(x - width * 0.5));
				float every = hwy ? 2.4 : 1.6;
				float d = fract(v_rand / every) * every;
				float al = fwidth(v_rand);
				float dash = smoothstep(-al, al, d) * (1.0 - smoothstep(every * 0.4 - al, every * 0.4 + al, d));
				base = mix(base, vec3(1.0, 0.97, 0.9), max(solid, mid * dash) * 0.92);
				// at night, a warm pool under each street light (StreetLights:
				// every 9 m from 2.6 m in, its head a quarter way out from the middle)
				float dl = (fract((v_rand - 2.6) / 9.0 + 0.5) - 0.5) * 9.0;
				float dx = (x - width * 0.75) * 1.3;
				EMISSION = vec3(1.0, 0.78, 0.5) * exp(-(dl * dl + dx * dx) * 1.1) * night * 0.45;
			} else if (v_emit > 0.115) {
				// a dashed white centre line: 0.5 m dashes every 1.4 m, 7 cm wide
				// on a 1.56 m carriageway (COLOR.a runs kerb to kerb, UV.y along)
				float across = (COLOR.a - 0.5) * 1.56;
				float aw = fwidth(across);
				float line = 1.0 - smoothstep(0.035 - aw, 0.035 + aw, abs(across));
				float d = fract(v_rand / 1.4) * 1.4;
				float al = fwidth(v_rand);
				float dash = smoothstep(-al, al, d) * (1.0 - smoothstep(0.5 - al, 0.5 + al, d));
				base = mix(base, vec3(1.0, 0.93, 0.79), line * dash * 0.95);
			}
		} else if (v_emit > 0.13 && v_emit < 0.19) {
			// pavement: small square slabs with fine joints and the odd odd-toned one
			vec2 q = v_world.xz * 3.0;
			vec2 f = abs(fract(q) - 0.5);
			float aa = length(fwidth(q));
			float joint = smoothstep(0.46 - aa, 0.5, max(f.x, f.y));
			float tone = 0.96 + 0.08 * g_hash(floor(q));
			base *= mix(tone, 0.84, joint * (1.0 - smoothstep(0.25, 0.6, aa)));
		} else if (v_emit > 0.47 && v_emit < 0.495) {
			// mown grass: wide light and dark stripes (along x below 0.485, along z above)
			float a = v_emit < 0.485 ? v_world.x : v_world.z;
			float st = smoothstep(0.42, 0.58, abs(fract(a * 1.25) - 0.5) * 2.0);
			base *= mix(0.93, 1.06, st);
		}
	}
#endif
#ifndef GROUND
	{
		// sides darken towards the ground they stand on (soft contact shadow), and
		// tall walls pick up faint rain streaks
		float h = texture(height_tex, v_world.xz / grid_size + 0.5).r * height_range.x - height_range.y;
		float above = v_world.y - h;
		float side = 1.0 - smoothstep(0.45, 0.85, abs(v_wnorm.y));
		base *= mix(1.0, mix(0.68, 1.0, smoothstep(0.0, 0.3, above)) * mix(0.92, 1.0, smoothstep(0.2, 2.2, above)), side);
		float fw = length(fwidth(v_world));
		float along = dot(v_world.xz, vec2(0.7071));
		if (side > 0.0 && above > 0.6) {
			float streak = g_noise(vec2(along * 5.0, v_world.y * 0.45));
			base *= 1.0 - side * (streak - 0.5) * 0.08 * (1.0 - smoothstep(0.05, 0.25, fw)) * smoothstep(0.6, 1.5, above);
		}
		// foliage: leafy clumps catching the light, darker underneath
		float leafy = smoothstep(0.04, 0.1, base.g - max(base.r, base.b)) * step(v_emit, 0.01);
		if (leafy > 0.0) {
			// (the fine layer is filtered out once it is smaller than a pixel, like a mipmap)
			float fine = mix(0.5, g_noise(v_world.xz * 11.0 - v_world.yy * 7.0), 1.0 - smoothstep(0.08, 0.3, fw));
			float clump = g_noise(v_world.xz * 4.5 + v_world.yy * vec2(3.1, -2.3)) * 0.65 + fine * 0.35;
			base *= mix(1.0, (0.84 + 0.32 * clump) * mix(0.82, 1.06, v_wnorm.y * 0.5 + 0.5), leafy);
		}
		// flat roofs: big membrane sheets with seams
		if (v_emit < 0.01 && v_wnorm.y > 0.95 && above > 0.9 && max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b)) < 0.25) {
			vec2 q = v_world.xz * vec2(1.4, 0.8);
			vec2 f = abs(fract(q) - 0.5);
			float aa = length(fwidth(q));
			float seam = smoothstep(0.47 - aa, 0.5, max(f.x, f.y)) * (1.0 - smoothstep(0.3, 0.7, aa));
			base *= (1.0 - seam * 0.1) * (0.96 + 0.08 * g_noise(v_world.xz * 0.8));
		}
	}
#endif
#ifdef GROUND
	if (show_zone) {
		vec2 side = vec2(textureSize(tint_tex, 0));
		vec4 tint = texture(tint_tex, ((v_world.xz / grid_size + 0.5) * (side - 1.0) + 0.5) / side);
		base = mix(base, tint.rgb, tint.a);
	}
#endif
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// soft toy-like rim and a gentle bottom-darkening ambient term
	base += rim * 0.05;
	ALBEDO = base;
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
#ifdef GROUND
	// grass and earth barely glint; a broad sheen would grey the land seen from high up
	SPECULAR = 0.12;
#endif
	float emit = v_emit;
	float rnd = v_rand;
	// pane coordinates of a window (u < 0: none) and what hangs behind its glass
	float wu = -1.0;
	float wv = 0.0;
	float pv = -1.0;
	float cover = 0.0;
	vec3 cover_col = vec3(1.0);
#ifdef WINDOW_ROWS
	if (emit > 299.5) {
		// trim lines round a block: y counts lines from the first, COLOR.a = half thickness
		if (abs(rnd - round(rnd)) > COLOR.a) {
			discard;
		}
		emit = 0.0;
	}
	if (emit > 199.5 && emit < 299.5) {
		// windows on several floors of a wall on one quad: x = 200 + count + u,
		// y = floors * 100 + seed + v, COLOR.a = how much of each window's cell
		// it fills; each floor's window sits where a single row's would
		float n = floor(emit) - 200.0;
		float cu = fract(emit) / 0.98 * n;
		float lu = (fract(cu) - 0.5) / max(COLOR.a, 0.01) + 0.5;
		float floors = floor(floor(rnd) / 100.0);
		float seed = mod(floor(rnd), 100.0);
		float cv = fract(rnd) / 0.98 * floors;
		float lv = (fract(cv) - 0.139) / 0.742;
		if (lu < 0.0 || lu > 1.0 || lv < 0.0 || lv > 1.0) {
			discard;
		}
		float r2 = fract(sin(seed * 12.9898 + floor(cu) * 78.233 + floor(cv) * 37.719) * 43758.5453);
		emit = 4.0 + lu * 0.98;
		rnd = floor(r2 * 100.0) + lv * 0.98;
	}
	if (emit > 19.5) {
		// a whole row of windows on one quad: x = 20 + count (+100 if frameless) + u,
		// y = seed + v, COLOR.a = how much of each window's cell it fills
		float code = floor(emit);
		float plain = step(119.5, code);
		float n = code - 20.0 - plain * 100.0;
		float cu = fract(emit) / 0.98 * n;
		float cell = fract(cu);
		float lu = (cell - 0.5) / max(COLOR.a, 0.01) + 0.5;
		if (lu < 0.0 || lu > 1.0) {
			discard;
		}
		float seed = floor(rnd);
		float idx = floor(cu);
		float v = fract(v_rand) / 0.98;
		rnd = fract(sin(seed * 12.9898 + idx * 78.233) * 43758.5453);
		if (plain > 0.5) {
			emit = 1.0;
			wu = lu;
			wv = v;
			pv = v;
		} else {
			emit = 4.0 + lu * 0.98;
			rnd = floor(rnd * 100.0) + v * 0.98;
		}
	}
#endif
	if (emit > 3.5) {
		// framed window on a single quad: x = 4 + u, y = random*100 + v
		float u = (emit - 4.0) / 0.98;
		float v = fract(rnd) / 0.98;
		rnd = floor(rnd) / 100.0;
		float aa = fwidth(u) + fwidth(v);
		float fx = smoothstep(0.14, 0.14 + aa, u) * (1.0 - smoothstep(0.86 - aa, 0.86, u));
		float fy = smoothstep(0.21, 0.21 + aa, v) * (1.0 - smoothstep(0.9 - aa, 0.9, v));
		float glass_m = fx * fy;
		// sill: a lighter ledge with a crisp shadow line beneath
		float sill = 1.0 - smoothstep(0.11 - aa, 0.11, v);
		vec3 fr = frame_col * mix(1.0, 1.08, sill) * mix(0.55, 1.0, smoothstep(0.0, 0.035 + aa, v));
		// the frame shades the top of the pane, like a recessed window
		pv = clamp((v - 0.21) / 0.69, 0.0, 1.0);
		vec3 gl = pane(base, (u - 0.14) / 0.72, pv, rnd, cover, cover_col) * mix(1.0, 0.72, smoothstep(0.65, 0.9, v));
		base = mix(fr, gl, glass_m);
		ALBEDO = base;
		emit = glass_m > 0.5 ? 1.0 : 0.0;
	}
	if (emit > 0.5) {
		ROUGHNESS = 0.18;
		SPECULAR = 0.7;
		float lit = 0.0;
		vec3 glow = warm_light;
		if (emit < 1.5) {
			// window: randomly lit, slightly varied tint, with a slow flicker of TV light in a few
			if (wu >= 0.0) {
				base = pane(base, wu, wv, rnd, cover, cover_col);
			}
			lit = step(rnd, lit_ratio) * night;
			glow = mix(warm_light, vec3(1.0, 0.9, 0.7), fract(rnd * 13.7));
			// light through a blind or curtain takes on its colour
			glow = mix(glow, glow * cover_col * 1.15, cover * 0.7);
			// a lit room: brightest under the ceiling lamp, dimmer behind blinds
			if (pv >= 0.0) {
				glow *= mix(0.78, 1.12, pv) * (1.0 - cover * 0.25);
			}
			if (fract(rnd * 31.0) > 0.93) {
				glow = mix(glow, vec3(0.55, 0.75, 1.0), 0.5 + 0.5 * sin(TIME * 3.0 + rnd * 40.0));
			}
		} else if (emit < 2.5) {
			lit = night;
			glow = vec3(1.0, 0.82, 0.55);
		} else if (emit > 2.6 && emit < 2.8) {
			// a coloured light, its own colour: floodlit crowns, and red
			// aircraft beacons that blink (2.75: floodlit, never blinking)
			lit = night;
			glow = base * 1.8;
			if (base.r > base.g * 3.0 && emit < 2.72) {
				lit *= step(0.4, fract(TIME * 0.6 + v_world.x * 0.037 + v_world.z * 0.051));
			}
		} else {
			lit = 0.0;
			ROUGHNESS = 0.05;
		}
		ALBEDO = mix(base, glow * 0.35, lit);
		EMISSION = glow * lit * 2.7;
#ifndef GROUND
		if (emit < 1.5 || emit > 2.8) {
			// glass mirrors the sky and the town around it, more so at a glancing
			// angle; a lit room shows through it at night
			vec3 vw = normalize(v_world - CAMERA_POSITION_WORLD);
			vec3 n = normalize(v_wnorm);
			float ndv = clamp(-dot(vw, n), 0.0, 1.0);
			float f = (0.24 + 0.6 * pow(1.0 - ndv, 2.0)) * (1.0 - lit * 0.85) * refl_amount;
			ALBEDO *= 1.0 - f;
			EMISSION += sky_reflect(reflect(vw, n)) * f;
			// the engine's own blurry sky reflection would double it
			SPECULAR = 0.3;
		}
#endif
	}
	if (beam_count > 0) {
		// a passing lighthouse beam lights whatever it sweeps over
		EMISSION += mix(ALBEDO, vec3(0.3), 0.5) * vec3(1.0, 0.9, 0.66) * beam_light(v_world) * 0.9;
	}
}
