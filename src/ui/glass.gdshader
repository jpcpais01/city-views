shader_type canvas_item;
// Frosted glass for HUD panels: blurs and brightens whatever the 3D view shows
// behind the element. The element's own colour (its StyleBox) is the tint and
// its alpha is the shape mask, so rounded corners and borders come for free.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 2.6;
uniform float tint = 0.5;
uniform float vibrance = 1.35;
uniform float lift = 0.06;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE * exp2(blur) * 0.9;
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur).rgb * 0.2;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(px.x, 0.0), blur).rgb * 0.1;
	bg += textureLod(screen_tex, SCREEN_UV - vec2(px.x, 0.0), blur).rgb * 0.1;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(0.0, px.y), blur).rgb * 0.1;
	bg += textureLod(screen_tex, SCREEN_UV - vec2(0.0, px.y), blur).rgb * 0.1;
	bg += textureLod(screen_tex, SCREEN_UV + px * 0.7, blur).rgb * 0.1;
	bg += textureLod(screen_tex, SCREEN_UV - px * 0.7, blur).rgb * 0.1;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y) * 0.7, blur).rgb * 0.1;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y) * 0.7, blur).rgb * 0.1;
	float l = dot(bg, vec3(0.299, 0.587, 0.114));
	bg = mix(vec3(l), bg, vibrance) + lift;
	COLOR = vec4(mix(bg, COLOR.rgb, tint), COLOR.a);
}
