
// 0 = day, 1 = deep night. Driven by the day/night cycle.
uniform float night : hint_range(0.0, 1.0) = 0.0;
// fraction of windows that are lit (varies through the night)
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.7;
uniform vec3 warm_light : source_color = vec3(1.0, 0.74, 0.42);
uniform vec3 frame_col : source_color = vec3(0.97, 0.97, 0.95);

#include "res://shaders/beam.gdshaderinc"

varying float v_emit;
varying float v_rand;
varying vec3 v_world;

float g_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float g_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(g_hash(i), g_hash(i + vec2(1.0, 0.0)), f.x), mix(g_hash(i + vec2(0.0, 1.0)), g_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	// vertex colours are authored in sRGB
	vec3 c = COLOR.rgb;
	COLOR.rgb = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	v_emit = UV.x;
	v_rand = UV.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
		// fine grain: blades, sand grains and grit, fading out before it can shimmer
		float fw = length(fwidth(p));
		float grain = g_noise(p * 5.3) * 0.6 + g_noise(p * 13.0) * 0.4;
		base *= 1.0 + (grain - 0.5) * 0.12 * (1.0 - smoothstep(0.05, 0.25, fw));
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
		} else if (v_emit > 0.47 && v_emit < 0.495) {
			// mown grass: wide light and dark stripes (along x below 0.485, along z above)
			float a = v_emit < 0.485 ? v_world.x : v_world.z;
			float st = smoothstep(0.42, 0.58, abs(fract(a * 1.25) - 0.5) * 2.0);
			base *= mix(0.93, 1.06, st);
		}
	}
#endif
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// soft toy-like rim and a gentle bottom-darkening ambient term
	base += rim * 0.05;
	ALBEDO = base;
	ROUGHNESS = 0.78;
	SPECULAR = 0.35;
	float emit = v_emit;
	float rnd = v_rand;
#ifdef WINDOW_ROWS
	if (emit > 299.5) {
		// trim lines round a block: y counts lines from the first, COLOR.a = half thickness
		if (abs(rnd - round(rnd)) > COLOR.a) {
			discard;
		}
		emit = 0.0;
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
		vec3 gl = base * mix(1.0, 0.72, smoothstep(0.65, 0.9, v));
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
			lit = step(rnd, lit_ratio) * night;
			glow = mix(warm_light, vec3(1.0, 0.9, 0.7), fract(rnd * 13.7));
			if (fract(rnd * 31.0) > 0.93) {
				glow = mix(glow, vec3(0.55, 0.75, 1.0), 0.5 + 0.5 * sin(TIME * 3.0 + rnd * 40.0));
			}
		} else if (emit < 2.5) {
			lit = night;
			glow = vec3(1.0, 0.82, 0.55);
		} else {
			lit = 0.0;
			ROUGHNESS = 0.05;
		}
		ALBEDO = mix(base, glow * 0.35, lit);
		EMISSION = glow * lit * 2.4;
	}
	if (beam_count > 0) {
		// a passing lighthouse beam lights whatever it sweeps over
		EMISSION += mix(ALBEDO, vec3(0.3), 0.5) * vec3(1.0, 0.9, 0.66) * beam_light(v_world) * 0.9;
	}
}
