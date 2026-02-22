shader_type spatial;

uniform sampler2D water_texture : source_color, repeat_enable, filter_linear;
uniform vec4 base_color : source_color = vec4(0.14, 0.38, 0.68, 1.0);
uniform float texture_strength : hint_range(0.0, 1.0) = 0.45;
uniform float tile_scale : hint_range(0.01, 1.0) = 0.3;
uniform float scroll_speed : hint_range(0.0, 1.0) = 0.025;
uniform float wave_height : hint_range(0.0, 0.5) = 0.08;
uniform float wave_speed : hint_range(0.0, 3.0) = 1.0;

// True world XZ passed from vertex to fragment so the texture is
// world-space locked — the pattern scrolls past as the boat moves
varying vec2 world_xz;

void vertex() {
	// Capture world position before displacement for stable UV mapping
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;

	// Gentle overlapping sine waves so the surface isn't perfectly flat
	float t = TIME * wave_speed;
	float w1 = sin(VERTEX.x * 0.5 + t * 1.2) * wave_height;
	float w2 = sin(VERTEX.z * 0.4 + t * 0.9) * wave_height * 0.8;
	float w3 = sin((VERTEX.x + VERTEX.z) * 0.3 + t * 0.7) * wave_height * 0.5;
	VERTEX.y += w1 + w2 + w3;

	// Recalculate normal so lighting reacts to the displaced surface
	float dx = cos(VERTEX.x * 0.5 + t * 1.2) * 0.5 * wave_height
			 + cos((VERTEX.x + VERTEX.z) * 0.3 + t * 0.7) * 0.3 * wave_height * 0.5;
	float dz = cos(VERTEX.z * 0.4 + t * 0.9) * 0.4 * wave_height * 0.8
			 + cos((VERTEX.x + VERTEX.z) * 0.3 + t * 0.7) * 0.3 * wave_height * 0.5;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	vec2 uv = world_xz * tile_scale;
	float t = TIME * scroll_speed;

	// Two offset samples to break up the repeat pattern
	vec3 s1 = texture(water_texture, uv + vec2(t, t * 0.6)).rgb;
	vec3 s2 = texture(water_texture, uv * 0.72 + vec2(-t * 0.4, t * 0.5) + vec2(0.4, 0.2)).rgb;
	vec3 water = mix(s1, s2, 0.5);

	ALBEDO = mix(base_color.rgb, water, texture_strength);
	ROUGHNESS = 0.7;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}
