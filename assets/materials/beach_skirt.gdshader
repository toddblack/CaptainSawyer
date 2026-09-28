shader_type spatial;
// blend_mix     — alpha fade at the ocean edge
// depth_draw_opaque — write depth only for opaque pixels
// cull_disabled — flat mesh may be seen from below at steep camera angles
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// ── Per-island beach proximity texture ───────────────────────────────────────
// 128×128 image baked from _height_at_xy() at island startup.
// R=1.0 land, R≈0.78 inner beach (1px from land), R≈0.47 outer beach (2px from land), R=0 ocean.
uniform sampler2D beach_tex        : repeat_disable, filter_linear;
uniform vec2      island_center;            // world XZ position of this island
uniform float     beach_tex_half_size;      // half the texture coverage in world units

// ── Beach sand tile from the shared terrain atlas ────────────────────────────
uniform sampler2D terrain_atlas : filter_linear_mipmap, repeat_disable;
uniform vec2  beach_tile_offset = vec2(0.0,  0.25);
uniform vec2  beach_tile_scale  = vec2(0.25, 0.25);
uniform float world_tile_size   = 1.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// ── Noise helpers (identical to water / terrain shaders) ─────────────────────
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float smooth_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i),                 hash(i + vec2(1.0, 0.0)), f.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// ── Dual-grid seamless tile (matches island_terrain.gdshader) ────────────────
vec4 tile(vec2 wxz, vec2 offset, vec2 scale) {
	vec2 p  = wxz / world_tile_size;
	vec2 p2 = p + vec2(0.5);
	vec2 uv1 = fract(p)  * scale + offset;
	vec2 uv2 = fract(p2) * scale + offset;
	vec2 f1 = min(fract(p),  1.0 - fract(p))  * 2.0;
	vec2 f2 = min(fract(p2), 1.0 - fract(p2)) * 2.0;
	float w1 = f1.x * f1.y;
	float w2 = f2.x * f2.y;
	return (texture(terrain_atlas, uv1) * w1 + texture(terrain_atlas, uv2) * w2)
	       / max(w1 + w2, 0.0001);
}

void fragment() {
	vec2 world_xz = v_world_pos.xz;

	// ── Island-local UV ───────────────────────────────────────────────────────
	// Map world XZ → [0,1] UV centred on this island.
	vec2 local_uv = (world_xz - island_center) / (beach_tex_half_size * 2.0) + 0.5;

	// Discard anything outside the texture footprint (outer mesh fringe).
	if (any(lessThan(local_uv, vec2(0.0))) || any(greaterThan(local_uv, vec2(1.0)))) {
		discard;
	}

	float beach_s = texture(beach_tex, local_uv).r;

	// Noise to break the pixel-grid staircase into an organic, irregular edge.
	float noise_edge = smooth_noise(world_xz * 0.85 + vec2(5.3, 11.7)) * 0.18 - 0.09;
	float beach_n    = clamp(beach_s + noise_edge, 0.0, 1.0);

	// ── Beach alpha ───────────────────────────────────────────────────────────
	// beach_n ≈ 0.47 → outer sand edge (2px from land boundary)
	// beach_n ≈ 0.78 → inner sand (1px from land boundary)
	// beach_n ≈ 1.00 → solid land — fade out; terrain renders on top
	float beach_alpha = smoothstep(0.28, 0.50, beach_n)
	                  * (1.0 - smoothstep(0.85, 1.0, beach_n));

	if (beach_alpha < 0.01) {
		discard;
	}

	// ── Beach texture ─────────────────────────────────────────────────────────
	vec4 beach_col = tile(world_xz, beach_tile_offset, beach_tile_scale);

	// Wet-sand darkening at the outer (ocean) edge where waves wash in.
	float wetness = 1.0 - smoothstep(0.28, 0.60, beach_n);
	beach_col.rgb *= mix(1.0, 0.72, wetness);

	// ── Output ────────────────────────────────────────────────────────────────
	ALBEDO    = beach_col.rgb;
	ALPHA     = beach_alpha;
	ROUGHNESS = mix(0.65, 0.92, smoothstep(0.28, 0.60, beach_n)); // wet=smooth, dry=rough
	METALLIC  = 0.0;
	SPECULAR  = mix(0.25, 0.05, smoothstep(0.28, 0.60, beach_n)); // wet sand catches light
}
