shader_type spatial;
render_mode diffuse_lambert, shadows_disabled, blend_mix;

uniform sampler2D terrain_atlas : hint_default_white, source_color;

uniform vec2 beach_tile_offset = vec2(0.0, 0.25);
uniform vec2 beach_tile_scale  = vec2(0.25, 0.25);
uniform vec2 grass_tile_offset = vec2(0.0, 0.0);
uniform vec2 grass_tile_scale  = vec2(0.25, 0.25);

uniform float world_tile_size : hint_range(0.5, 20.0) = 1.0;
// Height thresholds for sand-to-grass blend (world Y units)
uniform float blend_low  : hint_range(0.0, 2.0) = 0.15;
uniform float blend_high : hint_range(0.0, 4.0) = 0.80;
// Waterline fade: skirt blends to transparent so actual water shows through
uniform float waterline      : hint_range(-1.0, 1.0) = 0.0;
uniform float waterline_fade : hint_range(0.05, 1.0) = 0.15;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_uv  = fract(world_pos.xz / world_tile_size);
	vec3 beach_col = texture(terrain_atlas, beach_tile_offset + world_uv * beach_tile_scale).rgb;
	vec3 grass_col = texture(terrain_atlas, grass_tile_offset + world_uv * grass_tile_scale).rgb;
	float t = smoothstep(blend_low, blend_high, world_pos.y);
	vec3 terrain_col = mix(beach_col, grass_col, t);
	// Fade to transparent at/below the waterline so actual water shows through
	float water_blend = 1.0 - smoothstep(waterline, waterline + waterline_fade, world_pos.y);
	ALBEDO    = terrain_col;
	ALPHA     = 1.0 - water_blend;
	// Subtle self-illumination to lift the shadow-facing slopes slightly
	EMISSION  = terrain_col * 0.08;
	ROUGHNESS = 0.92;
}
