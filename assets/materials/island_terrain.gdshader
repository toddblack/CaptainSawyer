shader_type spatial;
// Default back-face culling: island.gd winds triangles clockwise seen from
// above (Godot's front face), so only the top surface is rasterised.

// ── Layer textures ────────────────────────────────────────────────────────
// One seamless texture per material (see goals/add_shader.md → "Terrain
// textures").  repeat_enable lets the GPU wrap them — no atlas seam hacks.
// source_color: the PNGs are sRGB and must be linearised before lighting.
// Pixel art: nearest texels (crisp), mipmaps only to stop shimmer when zoomed out.
uniform sampler2D sand_tex  : source_color, repeat_enable, filter_nearest_mipmap;
uniform sampler2D grass_tex : source_color, repeat_enable, filter_nearest_mipmap;
uniform sampler2D rock_tex  : source_color, repeat_enable, filter_nearest_mipmap;
// Cliff faces: one texture per biome zone (cliff_tex_i belongs to zone i).
// Drawn side-on (strata, columns), so they're projected horizontally.
uniform sampler2D cliff_tex_0 : source_color, repeat_enable, filter_nearest_mipmap;
uniform sampler2D cliff_tex_1 : source_color, repeat_enable, filter_nearest_mipmap;
uniform sampler2D cliff_tex_2 : source_color, repeat_enable, filter_nearest_mipmap;
uniform sampler2D cliff_tex_3 : source_color, repeat_enable, filter_nearest_mipmap;

// World units covered by one repeat of a texture, and the tiles' pixel size.
// 32 px over 4 wu = 8 texels per world unit: chunky, readable retro pixels at
// the default zoom.  All layers must share the same texel density.
uniform float tile_world      = 4.0;
uniform float texels_per_tile = 32.0;
// Large-scale brightness variation that breaks up uniform fields (0 = off).
uniform float variation  = 0.12;

uniform float blend_low      = 0.8;
uniform float blend_high     = 1.8;
uniform float rock_low       = 5.0;
uniform float rock_high      = 8.0;

// Slope → cliff: world normal.y below cliff_ny_start begins dithering to cliff
// rock, fully cliff by cliff_ny_full.  0.72 ≈ 44°, 0.52 ≈ 59°.
uniform float cliff_ny_start = 0.72;
uniform float cliff_ny_full  = 0.52;

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
varying vec3  v_world_normal;   // NORMAL in fragment() is view space
varying vec2  v_local_xz;    // island-local XZ — zones and river live here
varying float v_height;

void vertex() {
	v_world_pos    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	v_local_xz     = VERTEX.xz;   // mesh is centred on island origin → local == offset from centre
	v_height       = VERTEX.y;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i),                   hash12(i + vec2(1.0, 0.0)), f.x),
	           mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Anti-tiling for pixel art (after Inigo Quilez, "texture repetition"): a slow
// noise picks one of 8 random offsets per region, and between two regions each
// texel is dithered to one offset or the other — never cross-faded, so pixels
// stay crisp.  Offsets snap to whole texels so the pixel grid never shears.
// One tap per call.  ddx/ddy are passed in: derivatives are undefined inside
// non-uniform branches, so they're computed at the top of fragment().
vec3 sample_norep(sampler2D tex, vec2 uv, vec2 ddx, vec2 ddy, float dither) {
	float k  = value_noise(uv * 0.35) * 8.0;
	float ia = floor(k);
	vec2 off_a = floor(sin(vec2(3.0, 7.0) * ia)         * texels_per_tile) / texels_per_tile;
	vec2 off_b = floor(sin(vec2(3.0, 7.0) * (ia + 1.0)) * texels_per_tile) / texels_per_tile;
	float use_b = step(dither, smoothstep(0.2, 0.8, fract(k)));
	return textureGrad(tex, uv + mix(off_a, off_b, use_b), ddx, ddy).rgb;
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

	// Three planar projections: top-down for ground, and two side-on ones for
	// cliff faces (so strata run horizontally instead of smearing downhill).
	vec2 uv    = v_world_pos.xz / tile_world;
	vec2 uv_sx = vec2(v_world_pos.z, -v_world_pos.y) / tile_world;   // faces looking along ±X
	vec2 uv_sz = vec2(v_world_pos.x, -v_world_pos.y) / tile_world;   // faces looking along ±Z
	vec2 ddx    = dFdx(uv);
	vec2 ddy    = dFdy(uv);
	vec2 ddx_sx = dFdx(uv_sx);
	vec2 ddy_sx = dFdy(uv_sx);
	vec2 ddx_sz = dFdx(uv_sz);
	vec2 ddy_sz = dFdy(uv_sz);

	vec3 n  = normalize(v_world_normal);
	vec3 an = abs(n);

	float t_grass = smoothstep(blend_low, blend_high, v_height);
	float t_rock  = smoothstep(rock_low,  rock_high,  v_height);
	float t_cliff = 1.0 - smoothstep(cliff_ny_full, cliff_ny_start, n.y);

	// Per-texel dither values (texel-aligned, so layer edges break up along the
	// pixel grid like hand-placed pixel art instead of a soft gradient).  The
	// texel grid comes from whichever projection faces the camera best, so
	// dither cells stay square on steep faces too.
	vec2 key_uv = uv;
	if (an.y < max(an.x, an.z)) {
		key_uv = an.x > an.z ? uv_sx : uv_sz;
	}
	vec2  texel   = floor(key_uv * texels_per_tile);
	float d_layer = hash12(texel);
	float d_tile  = hash12(texel + vec2(17.0, 53.0));
	float d_river = hash12(texel + vec2(91.0, 29.0));
	float d_cliff = hash12(texel + vec2(41.0, 7.0));
	float d_zone  = hash12(texel + vec2(63.0, 11.0));
	float d_proj  = hash12(texel + vec2(5.0, 71.0));

	// Zone weights: Gaussian — must match Island._zone_weight().
	float wts[4] = float[4](0.0, 0.0, 0.0, 0.0);
	float w_sum  = 0.0;
	float w_max  = 0.0;
	vec3  tint_accum = vec3(0.0);
	for (int i = 0; i < zone_count; i++) {
		vec2  dd = v_local_xz - zone_data[i].xy;
		float r  = max(zone_data[i].z, 0.001);
		float w  = exp(-3.0 * dot(dd, dd) / (r * r));
		wts[i]      = w;
		tint_accum += mix(zone_grass_tint[i].rgb, zone_rock_tint[i].rgb, t_rock) * w;
		w_sum      += w;
		w_max       = max(w_max, w);
	}

	// Dithered layer choice: each texel is exactly one material, so only one
	// texture is read per pixel.
	int layer = 0;                                   // 0 sand, 1 grass, 2 rock, 3 cliff
	if (d_layer < t_grass) { layer = 1; }
	if (d_layer < t_rock)  { layer = 2; }
	if (d_cliff < t_cliff) { layer = 3; }

	vec3 col;
	if (layer == 3) {
		// Which zone's cliff rock: dithered by sharpened zone weights, so
		// biome borders on a cliff are a narrow speckled seam, not a wide blend.
		float s_sum = 0.0;
		for (int i = 0; i < zone_count; i++) {
			wts[i] = pow(wts[i] / max(w_max, 1e-20), 8.0);
			s_sum += wts[i];
		}
		float pick = d_zone * s_sum;
		int   zi   = 0;
		float acc  = 0.0;
		for (int i = 0; i < zone_count; i++) {
			acc += wts[i];
			if (pick <= acc) { zi = i; break; }
		}
		// Side projection facing the surface best; dithered around 45°.
		bool use_x = d_proj < an.x / max(an.x + an.z, 1e-5);
		vec2 cuv = use_x ? uv_sx  : uv_sz;
		vec2 cdx = use_x ? ddx_sx : ddx_sz;
		vec2 cdy = use_x ? ddy_sx : ddy_sz;
		if (zi == 0) {
			col = sample_norep(cliff_tex_0, cuv, cdx, cdy, d_tile);
		} else if (zi == 1) {
			col = sample_norep(cliff_tex_1, cuv, cdx, cdy, d_tile);
		} else if (zi == 2) {
			col = sample_norep(cliff_tex_2, cuv, cdx, cdy, d_tile);
		} else {
			col = sample_norep(cliff_tex_3, cuv, cdx, cdy, d_tile);
		}
	} else if (layer == 2) {
		col = sample_norep(rock_tex, uv, ddx, ddy, d_tile);
	} else if (layer == 1) {
		col = sample_norep(grass_tex, uv, ddx, ddy, d_tile);
	} else {
		col = sample_norep(sand_tex, uv, ddx, ddy, d_tile);
	}

	// Zone-based biome tint on ground layers.  Cliff textures are already
	// chosen per biome, so they're left untinted.
	if (layer != 3 && w_sum > 1e-20) {
		col *= tint_accum / w_sum;
	}

	if (has_river > 0.5 && layer != 3) {
		float rm = river_mask(v_local_xz) * (1.0 - t_rock);
		if (d_river < rm) {
			col = sample_norep(sand_tex, uv, ddx, ddy, d_tile) * 0.75;
		}
	}

	// Broad light/dark patches (~30-unit scale) so big fields aren't flat.
	col *= 1.0 + (value_noise(v_world_pos.xz * 0.033) - 0.5) * 2.0 * variation;

	// Wet sand just above the waterline ties land and sea together; the seabed
	// darkens with depth so shallows fade smoothly into the deep.
	float wet = 1.0 - smoothstep(0.0, 0.45, v_height);
	col *= mix(1.0, 0.72, wet);
	col *= mix(1.0, 0.55, smoothstep(0.0, 8.0, -v_height));

	ALBEDO    = col;
	ROUGHNESS = mix(0.95, 0.55, wet);
}
