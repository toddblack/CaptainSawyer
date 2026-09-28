shader_type spatial;
// blend_mix     — transparent water; opaque fragments still write depth
// depth_draw_opaque — write depth only for fully-opaque pixels (deep water)
// cull_disabled — ocean plane may be viewed from below at steep angles
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ── Water surface texture ─────────────────────────────────────────────────────
uniform sampler2D water_texture : source_color, repeat_enable, filter_linear;
uniform float texture_strength : hint_range(0.0, 1.0) = 0.30;
uniform float tile_scale       : hint_range(0.01, 1.0) = 0.3;
uniform float scroll_speed     : hint_range(0.0, 1.0) = 0.025;
uniform float wave_height      : hint_range(0.0, 0.5) = 0.08;
uniform float wave_speed       : hint_range(0.0, 3.0) = 1.0;

// ── Shore proximity map (256×256, world-space, painted by IslandSpawner) ──────
// R=1.0 at land, R≈0.0–0.65 in the near-shore gradient ring, R=0 in open ocean.
uniform sampler2D shore_tex : repeat_disable, filter_linear;

// ── Depth buffer — lets us see through water to the seafloor ─────────────────
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

// ── Colour & transparency ─────────────────────────────────────────────────────
// Shallow: tropical teal (seafloor visible).  Deep: dark oceanic blue (opaque).
uniform vec4  shallow_color : source_color = vec4(0.18, 0.76, 0.65, 1.0);
uniform vec4  deep_color    : source_color = vec4(0.06, 0.18, 0.52, 1.0);
// max_depth — water depth (world units) at which colour/alpha reach the deep extreme.
uniform float max_depth     : hint_range(1.0, 40.0) = 10.0;
uniform float shallow_alpha : hint_range(0.0, 1.0)  = 0.40;
uniform float deep_alpha    : hint_range(0.0, 1.0)  = 0.8;

// True world XZ — world-space locked so the surface texture scrolls past the boat.
varying vec2 world_xz;

void vertex() {
	// Capture world position before displacement for stable UV / shore lookup.
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;

	// Gentle overlapping sine waves so the surface is never perfectly flat.
	float t  = TIME * wave_speed;
	float w1 = sin(VERTEX.x * 0.5 + t * 1.2) * wave_height;
	float w2 = sin(VERTEX.z * 0.4 + t * 0.9) * wave_height * 0.8;
	float w3 = sin((VERTEX.x + VERTEX.z) * 0.3 + t * 0.7) * wave_height * 0.5;
	VERTEX.y += w1 + w2 + w3;

	// Recalculate normal so lighting responds to the displaced surface.
	float dx = cos(VERTEX.x * 0.5 + t * 1.2) * 0.5 * wave_height
	         + cos((VERTEX.x + VERTEX.z) * 0.3 + t * 0.7) * 0.3 * wave_height * 0.5;
	float dz = cos(VERTEX.z * 0.4 + t * 0.9) * 0.4 * wave_height * 0.8
	         + cos((VERTEX.x + VERTEX.z) * 0.3 + t * 0.7) * 0.3 * wave_height * 0.5;
	NORMAL = normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	// ── Depth reconstruction ──────────────────────────────────────────────────
	// Reconstruct the view-space depth of the geometry behind the water surface.
	// VERTEX in fragment() is already in view space; -VERTEX.z is its depth.
	// The difference tells us how thick the water column is at this pixel.
	float raw_depth  = texture(depth_texture, SCREEN_UV).r;
	vec4  ndc        = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4  view_pos   = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz    /= view_pos.w;
	float scene_z    = -view_pos.z;          // depth of the terrain behind the water
	float water_z    = -VERTEX.z;            // depth of the water surface itself
	float depth_diff = max(0.0, scene_z - water_z);   // water column thickness
	float depth_t    = clamp(depth_diff / max_depth, 0.0, 1.0);

	// ── Surface texture ───────────────────────────────────────────────────────
	vec2  uv = world_xz * tile_scale;
	float ts = TIME * scroll_speed;
	vec3  s1 = texture(water_texture, uv + vec2(ts, ts * 0.6)).rgb;
	vec3  s2 = texture(water_texture, uv * 0.72 + vec2(-ts * 0.4, ts * 0.5) + vec2(0.4, 0.2)).rgb;
	vec3  water_tex = mix(s1, s2, 0.5);

	// ── Shore foam ────────────────────────────────────────────────────────────
	// shore_tex encodes island proximity over the full 1000×1000 world.
	// Values ≈ 0.40–0.62 mark the outer sand ring just seaward of the shore —
	// that is where wave foam appears.
	vec2  shore_uv   = (world_xz + vec2(500.0)) / 1000.0;
	float shore_prox = texture(shore_tex, shore_uv).r;
	float foam_band  = smoothstep(0.35, 0.52, shore_prox)
	                 * (1.0 - smoothstep(0.62, 0.76, shore_prox));
	float foam_anim  = sin(shore_prox * 12.0 + TIME * 2.5) * 0.5 + 0.5;
	float foam       = foam_band * foam_anim * 0.50;

	// ── Colour ────────────────────────────────────────────────────────────────
	// Shallow: teal; deep: dark blue.  Texture overlaid more strongly in deep water
	// (in shallows the seafloor colour dominates through the transparent surface).
	vec3 base = mix(shallow_color.rgb, deep_color.rgb, depth_t);
	base = mix(base, water_tex, texture_strength * mix(0.15, 0.90, depth_t));
	base = mix(base, vec3(1.0), foam);

	ALBEDO    = base;
	ALPHA     = clamp(mix(shallow_alpha, deep_alpha, depth_t) + foam * 0.35, 0.0, 1.0);
	ROUGHNESS = mix(0.35, 0.72, depth_t);
	METALLIC  = 0.0;
	SPECULAR  = mix(0.45, 0.22, depth_t);   // wet shallows catch more light
}
