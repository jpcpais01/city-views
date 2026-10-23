shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Lighthouse beam: an additive cone that is brightest along its core, fades to
// nothing at its tip and never reaches under the sea surface.

uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float sea_y = 0.0;

varying float wy;

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// looking through the middle of the cone crosses more lit air than its rim
	float core = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float a = COLOR.a * strength * smoothstep(sea_y - 0.1, sea_y + 0.6, wy) * mix(0.15, 1.0, core);
	ALBEDO = COLOR.rgb * a;
}
