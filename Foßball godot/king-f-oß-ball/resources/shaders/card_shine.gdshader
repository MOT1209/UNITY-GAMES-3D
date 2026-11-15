// Card gloss (round 3, C4): a soft diagonal light band sweeping across the card frame. Used only by the
// upper card classes (CardCategory theme "shader_shine") and never in low-performance mode (CardFrame).
shader_type canvas_item;

uniform vec2 card_size = vec2(200.0, 280.0);
uniform float strength = 0.22;
uniform float speed = 0.11;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 uv = local_pos / max(card_size, vec2(1.0));
	float t = fract(TIME * speed);
	float diag = uv.x + uv.y * 0.45;
	float center = mix(-0.5, 1.95, t);
	float band = 1.0 - smoothstep(0.0, 0.11, abs(diag - center));
	COLOR.rgb += band * strength * COLOR.a;
}
