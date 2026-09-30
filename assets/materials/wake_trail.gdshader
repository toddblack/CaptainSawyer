shader_type spatial;
// Boat wake ribbon (built by scripts/wake_trail.gd).  Lit, so it dims at night
// like the water.  Transparent pass; render_priority 1 on the material keeps it
// drawing after the ocean.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

// Mesh attributes (set per vertex by wake_trail.gd):
//   UV.x  — across the ribbon: 0 = centre, ±1 = the wake arms (mesh reaches ±1.2)
//   UV.y  — age 0 (just made) → 1 (about to vanish)
//   UV2.x — distance behind the bow along the boat's path (world units)
//   UV2.y — strength 0–1 (boat speed when that bit of wake was made)

// Foam pixel grid in world space.  8 = the terrain's texel density; 16 is finer.
uniform float texels_per_unit = 16.0;
uniform vec3  foam_color  : source_color = vec3(0.95, 0.98, 1.0);
uniform vec3  churn_color : source_color = vec3(0.62, 0.88, 0.95);
uniform float churn_alpha = 0.28;
// The centre churn starts behind the stern (the hull covers it before that).
uniform float hull_length = 2.2;

// Must match water_shader.gdshader + ShaderMaterial_water in main.tscn, so the
// ribbon rides the same swell instead of clipping under it.
uniform float wave_height = 0.08;
uniform float wave_speed  = 1.0;

varying vec2 v_world_xz;

// 4×4 ordered (Bayer) dither thresholds — the classic retro fade.
const float BAYER[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0);

float bayer4(vec2 texel) {
	vec2 m = mod(texel, 4.0);
	return (BAYER[int(m.x) + int(m.y) * 4] + 0.5) / 16.0;
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

void vertex() {
	// The mesh is built in world space (top_level node, identity transform).
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = wp.xz;
	float t = TIME * wave_speed;
	VERTEX.y += sin(wp.x * 0.5 + t * 1.2) * wave_height
	          + sin(wp.z * 0.4 + t * 0.9) * wave_height * 0.8
	          + sin((wp.x + wp.z) * 0.3 + t * 0.7) * wave_height * 0.5;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float s        = abs(UV.x);
	float life     = 1.0 - UV.y;
	float dist     = UV2.x;
	float strength = UV2.y;

	vec2  texel  = floor(v_world_xz * texels_per_unit);
	float dither = bayer4(texel);
	float grit   = hash12(texel);                       // per-pixel sparkle
	float clumps = value_noise(v_world_xz * 0.9);       // ~1-unit foam patches, fixed in the water

	// Wake arms: a crest line at |s| = 1, feathered into short diagonal
	// ripples (steady relative to the boat, like a real Kelvin wake).
	float ad      = (1.0 - s) / 0.16;     // squared directly: pow() of a negative is undefined
	float arm     = exp(-ad * ad);
	float feather = 0.6 + 0.4 * sin(dist * 3.2 - s * 5.0);
	arm *= feather * life * life;

	// Churned water down the middle, behind the stern; dies away quickly.
	float churn = (1.0 - smoothstep(0.0, 0.55, s))
	            * smoothstep(hull_length * 0.8, hull_length * 1.2, dist)
	            * life * life * life;

	float foam = max(arm, churn) * strength * (0.45 + 1.1 * clumps) * (0.8 + 0.4 * grit);

	// Foam pixels: ordered dither, so a fading wake thins out into a retro
	// pixel pattern instead of going see-through.
	if (foam > 0.25 + dither * 0.6) {
		ALBEDO = foam_color;
		ALPHA  = 0.92;
	} else {
		// Faint lighter water under the whole ribbon — smooth, so the foam
		// pixels sit on disturbed water rather than floating on flat blue.
		float body = (1.0 - smoothstep(0.55, 1.05, s)) * life * strength;
		ALPHA = body * churn_alpha;
		if (ALPHA < 0.01) {
			discard;
		}
		ALBEDO = churn_color;
	}
	ROUGHNESS = 0.9;
}
