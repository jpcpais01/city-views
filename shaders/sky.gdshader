shader_type sky;
// The sky: a blue that deepens overhead and pales into a bright band of haze
// at the horizon (as the air it is seen through thickens), the sun's glow and
// aureole, a low sun warming its side of the sky while the pink Belt of Venus
// rises opposite, and two layers of cloud far overhead: a field of fair
// weather cumulus, lit from the sun's side with grey bellies and silver edges,
// and thin streaks of cirrus above them, both melting into the haze towards
// the horizon. At night stars, the moon and the town's warm glow low down.

uniform vec3 top_col : source_color = vec3(0.35, 0.62, 0.92);
uniform vec3 hor_col : source_color = vec3(0.78, 0.9, 0.98);
uniform vec3 bottom_col : source_color = vec3(0.6, 0.75, 0.85);
uniform vec3 sun_col : source_color = vec3(1.0, 0.9, 0.7);
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D cloud_tex : filter_linear_mipmap, repeat_enable;
// how much of the sky the far cumulus covers
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Henyey-Greenstein: how much light the air scatters at an angle to the sun
float hg(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (12.566 * pow(1.0 + g2 - 2.0 * g * c, 1.5));
}

float cumulus(vec2 uv, vec2 w) {
	return texture(cloud_tex, uv + w).r * 0.58
		+ texture(cloud_tex, uv * 2.31 - w * 1.6 + 0.31).r * 0.29
		+ texture(cloud_tex, uv * 5.17 + w * 2.4 + 0.67).r * 0.13;
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	float yu = max(y, 0.0);
	float day = 1.0 - night;
	vec3 L = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	float c = dot(dir, L);
	// a low sun (0 when it stands high, 1 on the horizon)
	float low = 1.0 - smoothstep(0.0, 0.4, L.y);

	// how much air the eye looks through: little straight up, a great deal
	// along the horizon, where the sky pales into haze
	float air = 1.0 / (yu * 1.7 + 0.115);
	float haze = 1.0 - exp(-air * 0.27);
	vec3 col = mix(top_col, hor_col, haze);
	col = mix(col, hor_col * 1.07 + vec3(0.025), exp(-yu * 26.0) * 0.42 * day);

	// the sun's glow: a wide halo and a bright aureole round the disc, both
	// stronger and warmer as it sinks
	col += sun_col * (hg(c, 0.76) * 0.1 + pow(max(c, 0.0), 7.0) * 0.12) * day * (1.0 + low * 1.4);
	// a low sun sets its whole side of the sky aglow along the horizon
	col += sun_col * pow(c * 0.5 + 0.5, 3.0) * exp(-yu * 4.5) * 0.42 * low * day;
	// and opposite it the pink Belt of Venus over the blue-grey shadow of the earth
	float belt = smoothstep(0.0, 0.06, y) * (1.0 - smoothstep(0.08, 0.26, y));
	float anti = smoothstep(0.1, 1.0, -c) * low * smoothstep(-0.12, 0.02, L.y);
	col = mix(col, vec3(0.93, 0.66, 0.68) * (hor_col * 0.4 + 0.65), belt * anti * 0.32);
	col = mix(col, top_col * 0.75 + hor_col * 0.25, (1.0 - smoothstep(0.0, 0.05, y)) * anti * 0.25);

	// the town's warm glow low on the horizon at night
	col += vec3(1.0, 0.56, 0.28) * exp(-yu * 11.0) * 0.07 * night;

	if (night > 0.01 && y > 0.0) {
		vec3 p = dir * 160.0;
		vec3 cell = floor(p);
		float h = hash3(cell);
		float star = step(0.986, h) * smoothstep(0.45, 0.05, length(fract(p) - 0.5));
		float tw = 0.6 + 0.4 * sin(h * 900.0 + TIME * (1.0 + h * 3.0));
		col += vec3(star * tw) * night * smoothstep(0.02, 0.3, y) * 1.6;
	}

	// the sun by day, the moon by night (drawn before the clouds pass over them)
	float sun_disc = smoothstep(0.9994, 0.9997, c);
	// darker at its rim, as the real sun is
	float limb = 0.75 + 0.25 * smoothstep(0.9994, 0.99995, c);
	vec3 discs = sun_col * sun_disc * limb * 7.0 * day * (1.0 - smoothstep(-0.01, -0.03, L.y));
	float moon = smoothstep(0.9990, 0.9993, c);
	vec2 mp = (dir - L * c).xy * 900.0;
	float maria = texture(cloud_tex, mp * 0.02 + 0.5).r;
	discs += vec3(0.95, 0.97, 1.0) * moon * (1.15 - maria * 0.45) * 1.4 * night;

	if (y > 0.0) {
		float t = TIME;
		// far fair weather cumulus, seen on a sheet high overhead
		vec2 uv = dir.xz / (y + 0.055) * 0.09;
		vec2 w = vec2(t * 0.0022, t * 0.0011);
		float n = cumulus(uv, w);
		float cov = cloud_cover;
		float dens = smoothstep(1.0 - cov - 0.02, 1.0 - cov + 0.24, n);
		// lit from the sun's side: one step towards the sun shows which side faces it
		vec2 toward = normalize(L.xz + vec2(0.0001)) * 0.035;
		float n2 = cumulus(uv + toward, w);
		float lit = clamp(0.55 + (n - n2) * 6.0, 0.0, 1.0);
		vec3 shade = (top_col * 0.45 + hor_col * 0.55) * vec3(0.78, 0.8, 0.86);
		vec3 sunny = sun_col * 1.12 + vec3(0.12);
		vec3 cl = mix(shade, sunny, lit * (1.0 - dens * 0.35));
		// a low sun fires up the clouds on its side of the sky from below
		cl += sun_col * low * day * pow(c * 0.5 + 0.5, 2.5) * (0.25 + 0.35 * (1.0 - lit));
		// thin edges glow round the sun
		cl += sun_col * pow(max(c, 0.0), 10.0) * (1.0 - dens) * 0.9 * day;
		cl = mix(cl, hor_col * 0.32 + vec3(0.02, 0.025, 0.05), night * night * 0.9);
		// towards the horizon they melt into the haze
		float fade = smoothstep(0.0, 0.04, y);
		cl = mix(cl, mix(col, hor_col, 0.4), haze * 0.55);
		float a = dens * fade * 0.94;

		// cirrus: long, thin, high streaks, under the cumulus in the picture
		vec2 cu = dir.xz / (y + 0.03) * 0.028;
		cu = vec2(cu.x * 0.8 + cu.y * 0.6, -cu.x * 0.6 + cu.y * 0.8) * vec2(0.35, 2.2);
		float ci = texture(cloud_tex, cu + vec2(t * 0.0012, 0.0)).r * 0.7 + texture(cloud_tex, cu * 3.1 + 0.4).r * 0.3;
		float streak = smoothstep(0.56, 0.86, ci) * 0.42 * smoothstep(0.03, 0.3, y);
		vec3 ccol = mix(vec3(0.97, 0.98, 1.0), sun_col * 1.1, 0.4 + low * 0.5);
		ccol = mix(ccol, hor_col * 0.4, night * 0.8);
		col = mix(col, ccol, streak * (1.0 - a));
		col += discs * (1.0 - a) * (1.0 - streak * 0.6);
		col = mix(col, cl, a);
	} else {
		col += discs;
		// below the horizon (barely seen past the sea) the haze darkens a little
		col = mix(col, bottom_col, smoothstep(0.0, -0.25, y));
	}
	COLOR = col;
}
