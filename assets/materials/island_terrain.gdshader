shader_type spatial;
// cull_disabled is required: the rectangular grid mesh winds triangles
// counter-clockwise from the isometric camera's screen-space perspective,
// which Godot 4/Vulkan treats as back-faces.  Disabling culling lets both
// sides render; the waterline discard still hides the ocean-level underside.
render_mode unshaded, cull_disabled;

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

varying vec3  v_world_pos;
varying float v_height;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	// Hard waterline — discard below threshold so ocean shows through
	if (v_height < 0.05) {
		discard;
	}

	vec2 wxz = v_world_pos.xz;

	vec4 beach_col = tile(wxz, beach_tile_offset, beach_tile_scale);
	vec4 grass_col = tile(wxz, grass_tile_offset, grass_tile_scale);
	vec4 rock_col  = tile(wxz, rock_tile_offset,  rock_tile_scale);

	float t_grass = smoothstep(blend_low,  blend_high, v_height);
	float t_rock  = smoothstep(rock_low,   rock_high,  v_height);
	vec4  col     = mix(mix(beach_col, grass_col, t_grass), rock_col, t_rock);

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
