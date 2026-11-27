shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform sampler2D visibility_mask : filter_linear, repeat_disable;
uniform vec2 map_origin;
uniform vec2 map_size;
varying vec2 map_point;

void vertex() {
	map_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float state = texture(visibility_mask, (map_point - map_origin) / map_size).r * 255.0;
	ALBEDO = vec3(0.045, 0.065, 0.085);
	ALPHA = mix(1.0, 0.59, smoothstep(0.0, 1.0, state)) * (1.0 - smoothstep(1.0, 2.0, state));
}
