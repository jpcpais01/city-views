shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled, shadows_disabled;
// Soft cumulus clouds: each puff is one camera-facing quad that the shader
// turns into a billowy, translucent ball of vapour. Its edge is eaten away by
// two layers of drifting world-fixed noise, so the outline is wispy and keeps
// slowly changing; its base is cut flat like a real cumulus, and it lights as
// a sphere with soft wrap-around shading and a silver lining against the sun.
// Where a tower pokes into a cloud the vapour thins around it instead of
// being cut by a hard line.
// VERTEX = puff centre, UV = corner (-1..1), UV2 = (radius, height of the centre
// above the cloud's flat base), COLOR.r = how far up the cloud the puff sits,
// COLOR.a = seed.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// clouds wrap round at this x, and fade in and out over the last stretch
uniform float wrap = 300.0;

varying vec3 v_centre;
varying vec3 v_wc;
varying float v_r;
varying float v_base;
varying float v_up;
varying float v_seed;

void vertex() {
	float sc = length(MODEL_MATRIX[0].xyz);
	v_r = UV2.x * sc;
	v_wc = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_base = v_wc.y - UV2.y * sc;
	v_up = COLOR.r;
	v_seed = COLOR.a * 23.0;
	vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_centre = c.xyz;
	vec3 p = c.xyz + vec3(UV * v_r, 0.0);
	// slide the quad along the view ray to the front of the ball, so whatever
	// stands inside the puff is faded softly by depth instead of clipped by the quad
	if (c.z < -0.6) {
		float s = min(v_r, -c.z - 0.5);
		p *= (-c.z - s) / -c.z;
	}
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
}

void fragment() {
	vec2 d = UV;
	float l2 = dot(d, d);
	if (l2 > 1.0) {
		discard;
	}
	vec3 n = vec3(d, sqrt(1.0 - l2));
	vec3 nw = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
	vec3 wp = v_wc + nw * v_r;
	// two octaves of vapour fixed to the world, each drifting its own way
	vec3 np = mix(v_wc, wp, 0.55);
	vec2 q = np.xz * 0.021 + vec2(np.y * 0.031, -np.y * 0.017) + vec2(v_seed, v_seed * 0.61);
	float n1 = texture(noise_tex, q + vec2(TIME * 0.0021, TIME * 0.0013)).r;
	float n2 = texture(noise_tex, q * 2.7 + vec2(-TIME * 0.0047, TIME * 0.0031) + 0.37).r;
	float nz = n1 * 0.62 + n2 * 0.38;
	// and a fine cauliflower texture for the light to pick out
	float n3 = texture(noise_tex, q * 6.3 + vec2(TIME * 0.006, -TIME * 0.004) + 0.71).r;
	// a solid core with billowy, eroded edges
	float body = 1.0 - sqrt(l2);
	float shape = body * 1.25 - (nz - 0.5) * 1.1 - 0.05;
	// never let the quad's round edge show
	float a = smoothstep(0.0, 0.5, shape) * (1.0 - smoothstep(0.72, 1.0, l2));
	// cumulus bases are flat
	a *= smoothstep(v_base - 0.6, v_base + 1.8, wp.y);
	// fade in and out where the wind wraps the clouds round the world
	a *= 1.0 - smoothstep(wrap - 55.0, wrap, abs(v_wc.x));
	// thin out around anything standing inside the vapour, and round the camera
	float sd = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, sd, 1.0);
	float scene_z = -sv.z / sv.w;
	float surf_z = -(v_centre.z + n.z * v_r);
	a *= clamp((scene_z - surf_z) / (v_r * 0.6 + 1.0), 0.0, 1.0);
	a *= clamp((-v_centre.z - 1.0) / (v_r + 2.0), 0.0, 1.0);
	if (a < 0.004) {
		discard;
	}
	// lumpy surface: the noise bends the normal so the light picks out billows
	vec3 bump = vec3(n1 - 0.5, (n2 - 0.5) * 0.6, n2 - n1) * 1.2 + vec3(n3 - 0.5, 0.0, 0.5 - n3) * 0.9;
	NORMAL = normalize(n + (VIEW_MATRIX * vec4(bump, 0.0)).xyz);
	// darker underneath and in the folds, brightest on the sunlit crowns
	float h = clamp((wp.y - v_base) / (v_r * 2.4), 0.0, 1.0);
	float shade = mix(0.74, 1.0, smoothstep(0.0, 1.0, h * 0.7 + v_up * 0.3));
	shade *= mix(0.84, 1.04, smoothstep(0.25, 0.75, nz * 0.6 + n3 * 0.4));
	// the shaded side and the belly take a cool tint from the sky
	ALBEDO = mix(vec3(0.82, 0.87, 0.96), vec3(1.0), shade) * shade;
	ROUGHNESS = 1.0;
	// thin edges let the light through (silver lining when the sun is behind)
	BACKLIGHT = vec3(1.0 - smoothstep(0.1, 0.6, shape));
	ALPHA = a * 0.97;
}

// vapour scatters light: a very soft wrap-around diffuse that never goes
// fully dark on the far side, plus a glow through the thin edges towards the sun
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float soft = clamp((ndl + 0.7) / 1.7, 0.0, 1.0);
	float through = pow(clamp(dot(-VIEW, LIGHT), 0.0, 1.0), 5.0) * BACKLIGHT.r;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (0.3 + 0.85 * soft + 1.2 * through) / PI;
}
