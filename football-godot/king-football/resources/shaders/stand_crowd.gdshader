// Stand crowd (UX phase 6): one camera-facing card per spectator, drawn as a simple silhouette
// (head + body) in the instance colour. The cards bob with a per-spectator phase; `excitement`
// (0..1, from the crowd model) makes them jump higher and faster, e.g. after a goal.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float excitement : hint_range(0.0, 1.0) = 0.0;
varying vec4 v_custom;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	float phase = INSTANCE_CUSTOM.a * 6.2831;
	float speed = 2.0 + excitement * 7.0;
	float height = 0.02 + excitement * 0.38;
	VERTEX.y += height * max(0.0, sin(TIME * speed + phase));
	// Upright billboard: face the camera around the world Y axis only.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], MODEL_MATRIX[1],
			vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, MODEL_MATRIX[1].xyz)), 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float head = length((uv - vec2(0.5, 0.2)) * vec2(1.0, 1.25)) - 0.17;
	float half_w = mix(0.22, 0.34, smoothstep(0.38, 0.6, uv.y));
	bool body = uv.y > 0.36 && abs(uv.x - 0.5) < half_w;
	if (head > 0.0 && !body) {
		discard;
	}
	vec3 skin = mix(vec3(0.95, 0.78, 0.62), vec3(0.42, 0.28, 0.2), fract(v_custom.a * 7.3));
	ALBEDO = head <= 0.0 ? skin : v_custom.rgb;
}
