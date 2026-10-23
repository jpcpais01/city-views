shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// Round canopies and bushes as camera-facing sprites that are shaded and
// depth-tested as true spheres: 2 triangles instead of a mesh, and perfectly
// round. In the shadow pass the same sprite faces the sun, so shadows are round too.
// VERTEX = sphere centre, UV = corner (-1..1), UV2.x = radius.
// Poles (trunks, lamp posts) use the same trick as upright cylinders:
// VERTEX = base centre, UV = (-1..1 across, 0..1 up), UV2 = (radius, height).

varying vec3 v_centre;
varying float v_r;
varying float v_h;
varying vec3 v_seed;
varying vec3 v_side;
varying vec3 v_fwd;

void vertex() {
	vec3 c = COLOR.rgb;
	COLOR.rgb = mix(pow((c + vec3(0.055)) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
	// sizes are in model units: follow the node's (uniform) scale
	float sc = length(MODEL_MATRIX[0].xyz);
	v_r = UV2.x * sc;
	v_h = UV2.y * sc;
	v_seed = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 centre = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v_centre = centre.xyz;
	vec4 p;
	if (v_h > 0.0) {
		// turn the quad about the pole's own axis so it always shows its full width
		vec3 axis = normalize((MODELVIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		vec3 fwd = vec3(0.0, 0.0, 1.0) - axis * axis.z;
		fwd = length(fwd) > 0.001 ? normalize(fwd) : vec3(0.0, 1.0, 0.0);
		v_side = normalize(cross(axis, fwd));
		v_fwd = fwd;
		p = centre + vec4(v_side * UV.x * v_r + axis * UV.y * v_h, 0.0);
	} else {
		// a touch larger than the sphere so its edge is never clipped by the quad
		p = centre + vec4(UV * v_r * 1.08, 0.0, 0.0);
	}
	POSITION = PROJECTION_MATRIX * p;
}

void fragment() {
	if (v_h > 0.0) {
		float u = clamp(UV.x, -1.0, 1.0);
		float k = sqrt(1.0 - u * u);
		NORMAL = normalize(v_side * u + v_fwd * k);
		vec4 clip = PROJECTION_MATRIX * vec4(VERTEX + v_fwd * v_r * k, 1.0);
		DEPTH = clip.z / clip.w;
		ALBEDO = COLOR.rgb;
		ROUGHNESS = 0.85;
		SPECULAR = 0.3;
	} else {
		vec2 d = UV * 1.08;
		float l2 = dot(d, d);
		if (l2 > 1.0) {
			discard;
		}
		vec3 n = vec3(d, sqrt(1.0 - l2));
		// gentle leafy bumps, fixed to the world so they don't swim when the camera turns
		vec3 nw = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
		vec3 q = nw * 3.1 + v_seed * 1.7;
		vec3 bump = vec3(sin(q.y * 2.3 + q.z), sin(q.z * 2.1 + q.x), sin(q.x * 2.7 + q.y)) * 0.11;
		NORMAL = normalize(n + (VIEW_MATRIX * vec4(bump, 0.0)).xyz);
		vec3 pos = v_centre + n * v_r;
		vec4 clip = PROJECTION_MATRIX * vec4(pos, 1.0);
		DEPTH = clip.z / clip.w;
		// slightly darker underneath, like the mesh canopies were
		float shade = 0.88 + 0.12 * clamp(nw.y * 0.5 + 0.5, 0.0, 1.0);
		vec3 base = COLOR.rgb * shade;
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		ALBEDO = base + rim * 0.05;
		ROUGHNESS = 0.78;
		SPECULAR = 0.35;
	}
}
