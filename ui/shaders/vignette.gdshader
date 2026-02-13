shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.45;
uniform float smoothness : hint_range(0.01, 1.0) = 0.5;

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 1.414;
	float vignette = smoothstep(1.0 - smoothness, 1.0, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vignette * intensity);
}
