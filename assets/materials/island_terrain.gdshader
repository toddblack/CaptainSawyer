shader_type spatial;
// Default back-face culling: island.gd winds triangles clockwise seen from
// above (Godot's front face), so only the top surface is rasterised.

// ── Tile atlas ────────────────────────────────────────────────────────────
// 4×4 grid of 256-px tiles (1024×1024 atlas).  Each tile_offset selects the
// tile's top-left corner in UV space; tile_scale covers one tile = (0.25,0.25).
// ─────────────────────────────────────────────────────────────────────────

uniform sampler2D terrain_atlas : filter_linear_mipmap, repeat_disable;

uniform vec2  beach_tile_offset = vec2(0.0,  0.25);
uniform vec2  beach_tile_scale  = vec2(0.25, 0.25);
uniform vec2  grass_tile_offset = vec2(0.0,  0.0);
uniform vec2  grass_tile_scale  = vec2(0.25, 0.25);
uniform vec2  rock_tile_offset  = vec2(0.5,  0.0);
uniform vec2  rock_tile_scale   = vec2(0.25, 0.25);

uniform float blend_low      = 0.8;
uniform float blend_high     = 1.8;
uniform float rock_low       = 5.0;
uniform float rock_high      = 8.0;
uniform float world_tile_size = 2.0;

// River — must match Island._river_valley() (island-local space).
uniform float has_river     = 0.0;
uniform float river_angle   = 0.0;
uniform float river_width   = 1.0;
uniform float river_meander = 0.05;   // 1 / meander wavelength
uniform float river_start   = 10.0;   // distance from centre where the river begins

// ── Zone-based biome tinting ──────────────────────────────────────────────
// Up to 4 spatial zones per island.  Each zone carries:
//   zone_data[i].xy  — local XZ centre (island-space, origin = island centre)
//   zone_data[i].z   — influence radius
// Gaussian weights — must match Island._zone_weight().
uniform int  zone_count = 1;
uniform vec4 zone_data[4];
uniform vec4 zone_grass_tint[4];
uniform vec4 zone_rock_tint[4];

// Below this the seabed is hidden by opaque deep water — skip the shading work.
const float HIDDEN_DEPTH = -12.0;

varying vec3  v_world_pos;
varying vec2  v_local_xz;    // island-local XZ — zones and river live here
varying float v_height;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_xz  = VERTEX.xz;   // mesh is centred on island origin → local == offset from centre
	v_height    = VERTEX.y;
}

// Dual-grid seamless tile: blend two half-phase samples so seam edges from
// one sample always fall at the centre of the other, eliminating visible
// tile-boundary lines from the atlas.
vec4 tile(vec2 wxz, vec2 offset, vec2 scale) {
	vec2 p  = wxz / world_tile_size;
	vec2 p2 = p + vec2(0.5);

	vec2 uv1 = fract(p)  * scale + offset;
	vec2 uv2 = fract(p2) * scale + offset;

	// Weight by proximity to each sample's own seam (0 at seam, 1 at centre)
	vec2 f1 = min(fract(p),  1.0 - fract(p))  * 2.0;
	vec2 f2 = min(fract(p2), 1.0 - fract(p2)) * 2.0;
	float w1 = f1.x * f1.y;
	float w2 = f2.x * f2.y;

	return (texture(terrain_atlas, uv1) * w1 + texture(terrain_atlas, uv2) * w2)
	       / max(w1 + w2, 0.0001);
}

float river_mask(vec2 p) {
	float c      = cos(river_angle);
	float s      = sin(river_angle);
	float along  = p.x * c + p.y * s;
	float perp   = -p.x * s + p.y * c;
	float across = abs(perp - sin(along * river_meander) * river_width * 1.5);
	// NOTE: smoothstep needs edge0 < edge1 — reversed edges are undefined in GLSL.
	return (1.0 - smoothstep(river_width * 0.45, river_width * 0.9, across))
	     * smoothstep(river_start * 0.5, river_start, along);
}

void fragment() {
	if (v_height < HIDDEN_DEPTH) {
		discard;
	}

	vec2 wxz = v_world_pos.xz;

	vec4 beach_col = tile(wxz, beach_tile_offset, beach_tile_scale);
	vec4 grass_col = tile(wxz, grass_tile_offset, grass_tile_scale);
	vec4 rock_col  = tile(wxz, rock_tile_offset,  rock_tile_scale);

	float t_grass = smoothstep(blend_low,  blend_high, v_height);
	float t_rock  = smoothstep(rock_low,   rock_high,  v_height);
	vec4  col     = mix(mix(beach_col, grass_col, t_grass), rock_col, t_rock);

	// Zone-based biome tint: Gaussian-weighted blend of grass/rock tints.
	vec3  tint_accum = vec3(0.0);
	float w_sum      = 0.0;
	for (int i = 0; i < zone_count; i++) {
		vec2  dd = v_local_xz - zone_data[i].xy;
		float r  = max(zone_data[i].z, 0.001);
		float w  = exp(-3.0 * dot(dd, dd) / (r * r));
		vec3  zt = mix(zone_grass_tint[i].rgb, zone_rock_tint[i].rgb, t_rock);
		tint_accum += zt * w;
		w_sum      += w;
	}
	if (w_sum > 1e-20) {
		col.rgb *= tint_accum / w_sum;
	}

	if (has_river > 0.5) {
		float rm = river_mask(v_local_xz) * (1.0 - t_rock);
		col = mix(col, beach_col * 0.75, rm);
	}

	// Wet sand just above the waterline ties land and sea together; the seabed
	// darkens with depth so shallows fade smoothly into the deep.
	float wet = 1.0 - smoothstep(0.0, 0.45, v_height);
	col.rgb  *= mix(1.0, 0.72, wet);
	col.rgb  *= mix(1.0, 0.55, smoothstep(0.0, 8.0, -v_height));

	ALBEDO    = col.rgb;
	ROUGHNESS = mix(0.95, 0.55, wet);
}
