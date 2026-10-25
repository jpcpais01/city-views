// Shared by cloud.gdshader and cloud_shadow.gdshader: the shape of one
// cumulus inside its box. The box is the unit box x, z in -1..1, y in 0..1
// (the node's scale makes it the cloud's size). The vapour is a low dome with a
// flat base, its outline and billows carved by world-fixed 3D noise that
// drifts slowly, so each cloud is its own shape and keeps changing.

uniform sampler3D noise3 : filter_linear, repeat_enable;
// clouds wrap round at this x, and fade in and out over the last stretch
uniform float wrap = 560.0;

// density (0..1) at q in the box, wp the same point in the world, `fine` adds
// the small billows (left out where only the broad shape matters)
float cloud_density(vec3 q, vec3 wp, float seed, bool fine) {
	// a dome sitting low in the box: wide at the base, rounded on top
	vec3 e = vec3(q.x, (q.y - 0.18) * 1.55, q.z);
	float dome = 1.0 - length(e);
	if (dome < -0.42) {
		return 0.0;
	}
	vec3 drift = vec3(TIME * 0.35, 0.0, TIME * 0.12);
	vec3 np = (wp + drift) * 0.016 + vec3(seed);
	float big = texture(noise3, np).r;
	float shape = dome + (big - 0.5) * 1.15;
	if (fine) {
		// billows: cauliflower lumps on the outside, wisps at the edge
		float n2 = texture(noise3, np * 3.1 + vec3(0.37, 0.11, 0.73) + vec3(0.0, TIME * 0.004, 0.0)).r;
		float billow = 1.0 - abs(n2 * 2.0 - 1.0);
		shape -= (1.0 - billow) * 0.42 * (1.0 - smoothstep(0.0, 0.5, shape));
	}
	// flat, slightly ragged base; thinning towards the top
	float base = smoothstep(0.0, 0.09, q.y + (big - 0.5) * 0.05);
	float d = smoothstep(0.0, 0.13, shape) * base;
	return d * (1.0 - smoothstep(wrap - 70.0, wrap, abs(wp.x)));
}
