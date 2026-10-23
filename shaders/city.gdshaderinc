
// 0 = day, 1 = deep night. Driven by the day/night cycle.
uniform float night : hint_range(0.0, 1.0) = 0.0;
// fraction of windows that are lit (varies through the night)
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.7;
uniform vec3 warm_light : source_color = vec3(1.0, 0.74, 0.42);
uniform vec3 frame_col : source_color = vec3(0.97, 0.97, 0.95);

varying float v_emit;
varying float v_rand;
varying vec3 v_world;

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
}
