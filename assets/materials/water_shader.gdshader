shader_type spatial;
// blend_mix     — transparent in the shallows so the seabed shows through
// depth_draw_opaque — transparent pass: water never occludes the seabed in the depth buffer
// cull_disabled — ocean plane may be viewed from below at steep angles
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ── Water surface texture ─────────────────────────────────────────────────────
uniform sampler2D water_texture : source_color, repeat_enable, filter_linear;
uniform float texture_strength : hint_range(0.0, 1.0) = 0.30;
uniform float tile_scale       : hint_range(0.01, 1.0) = 0.3;
uniform float scroll_speed     : hint_range(0.0, 1.0) = 0.025;
uniform float wave_height      : hint_range(0.0, 0.5) = 0.08;
uniform float wave_speed       : hint_range(0.0, 3.0) = 1.0;

// ── Depth buffer — lets us see through water to the seafloor ─────────────────
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

// ── Colour & transparency ─────────────────────────────────────────────────────
// Shallow: tropical teal (seafloor visible).  Deep: dark oceanic blue (opaque).
uniform vec4  shallow_color : source_color = vec4(0.18, 0.76, 0.65, 1.0);
uniform vec4  deep_color    : source_color = vec4(0.06, 0.18, 0.52, 1.0);
// max_depth — water column (view-ray units) at which colour/alpha reach the deep extreme.
uniform float max_depth     : hint_range(1.0, 40.0) = 10.0;
uniform float shallow_alpha : hint_range(0.0, 1.0)  = 0.40;
// Fully opaque when deep, so the edge of an island's seabed mesh is never visible.
uniform float deep_alpha    : hint_range(0.0, 1.0)  = 1.0;

// ── Shore foam ────────────────────────────────────────────────────────────────
// Driven by the water column thickness, so it hugs the real coastline (and the
// boat's hull) at per-pixel precision — no baked shore map needed.
uniform float foam_width    : hint_range(0.1, 4.0)  = 0.9;
uniform float foam_strength : hint_range(0.0, 1.0)  = 0.85;

// True world XZ — world-space locked so the surface texture scrolls past the boat.
varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;

	// Gentle overlapping sine waves so the surface is never perfectly flat.
	float t  = TIME * wave_speed;
	float w1 = sin(world_xz.x * 0.5 + t * 1.2) * wave_height;
	float w2 = sin(world_xz.y * 0.4 + t * 0.9) * wave_height * 0.8;
	float w3 = sin((world_xz.x + world_xz.y) * 0.3 + t * 0.7) * wave_height * 0.5;
	VERTEX.y += w1 + w2 + w3;
}

void fragment() {
	float t = TIME * wave_speed;

	// ── Per-pixel wave normal ─────────────────────────────────────────────────
	// The ocean mesh is only one vertex every 10 units — far too coarse to carry
	// these waves' normals — so derive them here from the same sine sum.
	float dx = cos(world_xz.x * 0.5 + t * 1.2) * 0.5 * wave_height
	         + cos((world_xz.x + world_xz.y) * 0.3 + t * 0.7) * 0.3 * wave_height * 0.5;
	float dz = cos(world_xz.y * 0.4 + t * 0.9) * 0.4 * wave_height * 0.8
	         + cos((world_xz.x + world_xz.y) * 0.3 + t * 0.7) * 0.3 * wave_height * 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(-dx, 1.0, -dz, 0.0)).xyz);

	// ── Depth reconstruction ──────────────────────────────────────────────────
	// View-space depth of the geometry behind the water surface.  The difference
	// is the water column thickness along the view ray.
	float raw_depth  = texture(depth_texture, SCREEN_UV).r;
	vec4  ndc        = vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	vec4  view_pos   = INV_PROJECTION_MATRIX * ndc;
	view_pos.xyz    /= view_pos.w;
	float scene_z    = -view_pos.z;
	float water_z    = -VERTEX.z;
	float depth_diff = max(0.0, scene_z - water_z);
	float depth_t    = clamp(depth_diff / max_depth, 0.0, 1.0);

	// ── Surface texture ───────────────────────────────────────────────────────
	vec2  uv = world_xz * tile_scale;
	float ts = TIME * scroll_speed;
	vec3  s1 = texture(water_texture, uv + vec2(ts, ts * 0.6)).rgb;
	vec3  s2 = texture(water_texture, uv * 0.72 + vec2(-ts * 0.4, ts * 0.5) + vec2(0.4, 0.2)).rgb;
	vec3  water_tex = mix(s1, s2, 0.5);

	// ── Shore foam ────────────────────────────────────────────────────────────
	// edge: solid lip right at the waterline.  wash: bands that roll in toward
	// the shore, broken up by the surface texture so they never look like rings.
	// Width swells and thins along the shore (slow, large-scale texture sample)
	// so the lip reads as surf rather than an even outline tracing the coast.
	float swell = texture(water_texture, world_xz * 0.07 + vec2(ts * 0.3, ts * 0.2)).r;
	float fw    = foam_width * mix(0.35, 1.6, swell);
	float edge  = 1.0 - smoothstep(0.0, fw, depth_diff);
	float brk   = texture(water_texture, world_xz * 0.9 + vec2(ts * 1.6, -ts * 1.2)).r;
	float wash  = sin(depth_diff / fw * 9.0 + TIME * 2.2 + brk * 5.0) * 0.5 + 0.5;
	float foam  = edge * edge * 0.9 + edge * smoothstep(0.55, 0.9, wash) * 0.6;
	foam        = clamp(foam * smoothstep(0.15, 0.6, brk + edge * 0.5), 0.0, 1.0) * foam_strength;

	// ── Colour ────────────────────────────────────────────────────────────────
	vec3 base = mix(shallow_color.rgb, deep_color.rgb, depth_t);
	base = mix(base, water_tex, texture_strength * mix(0.15, 0.90, depth_t));
	base = mix(base, vec3(1.0), foam);

	ALBEDO    = base;
	ALPHA     = clamp(mix(shallow_alpha, deep_alpha, depth_t) + foam * 0.5, 0.0, 1.0);
	ROUGHNESS = mix(0.35, 0.72, depth_t);
	METALLIC  = 0.0;
	SPECULAR  = mix(0.45, 0.22, depth_t);   // wet shallows catch more light
}
