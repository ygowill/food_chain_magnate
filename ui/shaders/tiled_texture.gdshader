shader_type canvas_item;

uniform sampler2D pattern_tex : repeat_enable, filter_linear;
uniform float tile_scale : hint_range(0.1, 10.0) = 1.0;
uniform vec4 tint_color : source_color = vec4(0.93, 0.88, 0.75, 1.0);

void fragment() {
	vec2 tiled_uv = UV * tile_scale;
	vec4 tex_color = texture(pattern_tex, tiled_uv);
	COLOR = tex_color * tint_color;
}
