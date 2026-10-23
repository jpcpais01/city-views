shader_type sky;

uniform vec3 top_col : source_color = vec3(0.35, 0.62, 0.92);
uniform vec3 hor_col : source_color = vec3(0.78, 0.9, 0.98);
uniform vec3 bottom_col : source_color = vec3(0.6, 0.75, 0.85);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9, 0.7);
uniform float night : hint_range(0.0, 1.0) = 0.0;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void sky() {
	float y = EYEDIR.y;
	vec3 col = mix(hor_col, top_col, smoothstep(-0.02, 0.6, y));
	col = mix(col, bottom_col, smoothstep(0.0, -0.25, y));
	if (LIGHT0_ENABLED) {
		float d = max(dot(EYEDIR, LIGHT0_DIRECTION), 0.0);
		// sun by day, moon by night
		float sun_disc = smoothstep(0.9994, 0.9997, d);
		float moon_disc = smoothstep(0.9990, 0.9993, d);
		col += sun_col * sun_disc * 6.0 * (1.0 - night);
		col += vec3(0.95, 0.97, 1.0) * moon_disc * 1.4 * night;
		col += sun_col * pow(d, 9.0) * 0.28 * (1.0 - night * 0.6);
		col += sun_col * pow(d, 2.5) * 0.08 * (1.0 - night);
	}
	if (night > 0.01 && y > 0.0) {
		vec3 p = EYEDIR * 160.0;
		vec3 cell = floor(p);
		float h = hash3(cell);
		float star = step(0.986, h) * smoothstep(0.45, 0.05, length(fract(p) - 0.5));
		float tw = 0.6 + 0.4 * sin(h * 900.0);
		col += vec3(star * tw) * night * smoothstep(0.02, 0.3, y) * 1.6;
	}
	COLOR = col;
}
