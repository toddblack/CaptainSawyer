shader_type spatial;
// cull_disabled is required: the rectangular grid mesh winds triangles
// counter-clockwise from the isometric camera's screen-space perspective,
// which Godot 4/Vulkan treats as back-faces.  Disabling culling lets both
// sides render; the waterline discard still hides the ocean-level underside.
render_mode cull_disabled;  // unshaded removed — terrain now receives shadows

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

uniform float blend_low      = 0.55;
uniform float blend_high     = 1.20;
uniform float rock_low       = 5.0;
uniform float rock_high      = 8.0;
uniform float world_tile_size = 2.0;

uniform float has_river   = 0.0;
uniform float river_angle = 0.0;
uniform float river_width = 1.0;

// ── Zone-based biome tinting ──────────────────────────────────────────────
// Up to 4 spatial zones per island.  Each zone carries:
//   zone_data[i].xy  — local XZ centre (island-space, origin = island centre)
//   zone_data[i].z   — influence radius
//   zone_data[i].w   — unused
// Tints are blended by inverse-distance weights, squared for sharper borders.
uniform int  zone_count = 1;
uniform vec4 zone_data[4];
uniform vec4 zone_grass_tint[4];
uniform vec4 zone_rock_tint[4];

varying vec3  v_world_pos;
varying vec2  v_local_xz;    // island-local XZ — used for zone distance
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

void fragment() {
	// Discard terrain that is too deep to be visible through the water.
	// The coast dips to ~-2wu; keeping geometry down to -20.0 lets the
	// depth-based water shader show the underwater slope in shallow areas.
	if (v_height < -20.0) {
		discard;
	}

	vec2 wxz = v_world_pos.xz;

	vec4 beach_col = tile(wxz, beach_tile_offset, beach_tile_scale);
	vec4 grass_col = tile(wxz, grass_tile_offset, grass_tile_scale);
	vec4 rock_col  = tile(wxz, rock_tile_offset,  rock_tile_scale);

	float t_grass = smoothstep(blend_low,  blend_high, v_height);
	float t_rock  = smoothstep(rock_low,   rock_high,  v_height);
	vec4  col     = mix(mix(beach_col, grass_col, t_grass), rock_col, t_rock);

	// Zone-based biome tint: inverse-distance-weighted blend of grass/rock tints.
	// v_local_xz is in island-local space (zone positions are local offsets too).
	vec3  tint_accum = vec3(0.0);
	float w_sum      = 0.0;
	for (int i = 0; i < zone_count; i++) {
		vec2  zpos = zone_data[i].xy;
		float zrad = zone_data[i].z;
		float d    = length(v_local_xz - zpos);
		float w    = max(0.0, 1.0 - d / max(zrad, 0.001));
		w = w * w;   // squared: sharper zone borders, less muddy middle-ground
		// Blend grass/rock tint by the same t_rock that drives atlas blending
		vec3 zt = mix(zone_grass_tint[i].rgb, zone_rock_tint[i].rgb, t_rock);
		tint_accum += zt * w;
		w_sum      += w;
	}
	if (w_sum > 0.001) {
		col.rgb *= tint_accum / w_sum;
	}

	if (has_river > 0.5) {
		float cos_r  = cos(river_angle);
		float sin_r  = sin(river_angle);
		float along  =  wxz.x * cos_r + wxz.y * sin_r;
		float across = abs(-wxz.x * sin_r + wxz.y * cos_r);
		float rmask  = smoothstep(river_width, river_width * 0.5, across)
		             * smoothstep(-river_width * 0.5, river_width * 0.5, along);
		col = mix(col, beach_col * 0.75, rmask);
	}

	ALBEDO = col.rgb;
}
