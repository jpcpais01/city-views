// Lighthouse beams sweeping the island and the sea at night: each beam is a lamp
// position (xyz) and the yaw it points along (w, both ways), set by the world.
uniform vec4 beams[4];
uniform int beam_count = 0;

// how strongly the beams light the point p (0 by day and away from the sweep)
float beam_light(vec3 p) {
	float acc = 0.0;
	for (int i = 0; i < beam_count; i++) {
		vec2 d = p.xz - beams[i].xz;
		float r = length(d);
		vec2 dir = vec2(cos(beams[i].w), sin(beams[i].w));
		float c = abs(dot(d, dir)) / max(r, 0.001);
		// a narrow fan that widens a little with distance, fading in past the tower
		float cone = smoothstep(0.988, 0.9985, c);
		float fall = smoothstep(2.0, 6.0, r) * (1.0 - smoothstep(10.0, 19.0, r));
		acc += cone * fall;
	}
	return acc;
}
