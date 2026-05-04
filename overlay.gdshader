shader_type canvas_item;

uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	COLOR.r *= 0.5;
	COLOR.g *= 0.5;
	COLOR.b *= 0.5;
	COLOR.a *= opacity;
}
