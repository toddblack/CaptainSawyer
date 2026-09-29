shader_type spatial;
// Default back-face culling: island.gd winds triangles clockwise seen from
// above (Godot's front face), so only the top surface is rasterised.

// ── Layer textures ────────────────────────────────────────────────────────
// One seamless texture per material (see goals/add_shader.md → "Terrain
// textures").  repeat_enable lets the GPU wrap them — no atlas seam hacks.
// source_color: the PNGs are sRGB and must be linearised before lighting.
uniform sampler2D sand_tex  : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_tex : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_tex  : source_color, repeat_enable, filter_linear_mipmap_anisotropic;

// World units covered by one repeat of a texture.  ~4 puts a 256-px pixel-art
// tile close to 1 texel per screen pixel at the default zoom.
uniform float tile_world = 4.0;
// Large-scale brightness variation that breaks up uniform fields (0 = off).
uniform float variation  = 0.12;

uniform float blend_low      = 0.8;
uniform float blend_high     = 1.8;
uniform float rock_low       = 5.0;
uniform float rock_high      = 8.0;

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

// Anti-tiling sample (Inigo Quilez, "texture repetition" technique 3): a slow
// noise picks one of 8 random offsets per region and cross-fades between two
// of them, so the eye never finds the repeat.  Two taps per call.
// textureGrad keeps mip selection smooth across the offset jumps.  ddx/ddy are
// passed in: derivatives are undefined inside non-uniform branches, so they're
// computed once at the top of fragment() before any `if`.
vec3 sample_norep(sampler2D tex, vec2 uv, vec2 ddx, vec2 ddy) {
	float k  = value_noise(uv * 0.35) * 8.0;
	float ia = floor(k);
	float f  = fract(k);
	vec2 off_a = sin(vec2(3.0, 7.0) * ia);
	vec2 off_b = sin(vec2(3.0, 7.0) * (ia + 1.0));
	vec3 a = textureGrad(tex, uv + off_a, ddx, ddy).rgb;
	vec3 b = textureGrad(tex, uv + off_b, ddx, ddy).rgb;
	float contrast = dot(a - b, vec3(1.0 / 3.0));
	return mix(a, b, smoothstep(0.2, 0.8, f - 0.1 * contrast));
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

	vec2 uv  = v_world_pos.xz / tile_world;
	vec2 ddx = dFdx(uv);
	vec2 ddy = dFdy(uv);

	float t_grass = smoothstep(blend_low, blend_high, v_height);
	float t_rock  = smoothstep(rock_low,  rock_high,  v_height);

	// Only sample layers that actually contribute — most pixels are one layer,
	// which matters on mobile (each layer is two texture taps).
	vec3 sand_col = sample_norep(sand_tex, uv, ddx, ddy);
	vec3 col      = sand_col;
	if (t_grass > 0.001 && t_rock < 0.999) {
		col = mix(col, sample_norep(grass_tex, uv, ddx, ddy), t_grass);
	}
	if (t_rock > 0.001) {
		col = mix(col, sample_norep(rock_tex, uv, ddx, ddy), t_rock);
	}

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
		col *= tint_accum / w_sum;
	}

	if (has_river > 0.5) {
		float rm = river_mask(v_local_xz) * (1.0 - t_rock);
		col = mix(col, sand_col * 0.75, rm);
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
