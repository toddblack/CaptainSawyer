shader_type spatial;
render_mode unshaded, blend_mix, shadows_disabled, cull_disabled;

// Soft circular foam blob for wake/bow-wave particles.
// COLOR.a carries the particle's lifetime alpha from the ParticleProcessMaterial color_ramp.

void fragment() {
	vec2 c = UV - vec2(0.5);
	float dist = length(c) * 2.0;

	// Soft edge: fully opaque inside 0.35 radius, fades to transparent by 1.0
	float circle = 1.0 - smoothstep(0.35, 1.0, dist);

	ALBEDO = vec3(1.0);
	ALPHA  = circle * COLOR.a;
}
