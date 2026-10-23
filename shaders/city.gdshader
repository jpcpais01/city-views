shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// 0 = day, 1 = deep night. Driven by the day/night cycle.
uniform float night : hint_range(0.0, 1.0) = 0.0;
// fraction of windows that are lit (varies through the night)
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.7;
uniform vec3 warm_light : source_color = vec3(1.0, 0.74, 0.42);

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
	if (v_emit > 0.5) {
		ROUGHNESS = 0.18;
		SPECULAR = 0.7;
		float lit = 0.0;
		vec3 glow = warm_light;
		if (v_emit < 1.5) {
			// window: randomly lit, slightly varied tint, with a slow flicker of TV light in a few
			lit = step(v_rand, lit_ratio) * night;
			glow = mix(warm_light, vec3(1.0, 0.9, 0.7), fract(v_rand * 13.7));
			if (fract(v_rand * 31.0) > 0.93) {
				glow = mix(glow, vec3(0.55, 0.75, 1.0), 0.5 + 0.5 * sin(TIME * 3.0 + v_rand * 40.0));
			}
		} else if (v_emit < 2.5) {
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
