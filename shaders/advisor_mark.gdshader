shader_type spatial;
// Pip's highlight on the map: a soft disc lying on the ground with a bright
// rim and ripples running out from the middle, drawn over everything so it
// shows through trees and houses. UV.x is how far out from the middle (0..1).
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, blend_mix, fog_disabled;

uniform vec4 tint : source_color = vec4(0.3, 0.8, 0.4, 1.0);
// 0 hidden .. 1 shown (it grows in)
uniform float appear = 1.0;
// 1 for the tip being looked at: brighter, quicker ripples
uniform float lit = 0.0;
uniform float phase = 0.0;

varying float r;

void vertex() {
	r = UV.x;
}

void fragment() {
	float edge = appear;
	float rr = r / max(edge, 0.001);
	if (rr > 1.0) {
		discard;
	}
	float t = TIME * (0.45 + lit * 0.35) + phase;
	float rim = smoothstep(0.84, 0.93, rr) * (1.0 - smoothstep(0.96, 1.0, rr));
	float fill = 0.16 + 0.08 * lit - rr * 0.06;
	float wave = fract(t);
	float ripple = exp(-pow((rr - wave) * 11.0, 2.0)) * (1.0 - wave) * (0.45 + lit * 0.3);
	// a dashed inner ring turning slowly
	float dash = step(0.5, fract(UV.y * 12.0 + TIME * 0.15)) * exp(-pow((rr - 0.72) * 30.0, 2.0)) * 0.35;
	ALBEDO = mix(tint.rgb, vec3(1.0), rim * 0.35 + ripple * 0.4);
	ALPHA = clamp(fill + rim * 0.85 + ripple + dash, 0.0, 1.0) * clamp(appear * 1.5, 0.0, 1.0);
}
