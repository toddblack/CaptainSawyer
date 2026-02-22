shader_type spatial;
render_mode diffuse_lambert, shadows_disabled, blend_mix;

uniform sampler2D beach_atlas : hint_default_white, source_color;
uniform sampler2D grass_atlas  : hint_default_white, source_color;

uniform vec2 beach_tile_offset = vec2(0.0, 0.0);
uniform vec2 beach_tile_scale  = vec2(0.239, 0.239);
uniform vec2 grass_tile_offset = vec2(0.033, 0.033);
uniform vec2 grass_tile_scale  = vec2(0.210, 0.210);

uniform float world_tile_size : hint_range(0.5, 20.0) = 3.0;
// Height thresholds for sand-to-grass blend (world Y units)
uniform float blend_low  : hint_range(0.0, 2.0) = 0.15;
uniform float blend_high : hint_range(0.0, 4.0) = 0.80;
// Waterline fade: skirt blends to ocean color so it doesn't show as a dark wall
uniform vec3 ocean_color = vec3(0.14, 0.38, 0.68);
uniform float waterline  : hint_range(-1.0, 1.0) = 0.0;
uniform float waterline_fade : hint_range(0.05, 1.0) = 0.15;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_uv  = fract(world_pos.xz / world_tile_size);
	vec3 beach_col = texture(beach_atlas, beach_tile_offset + world_uv * beach_tile_scale).rgb;
	vec3 grass_col = texture(grass_atlas,  grass_tile_offset + world_uv * grass_tile_scale).rgb;
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
