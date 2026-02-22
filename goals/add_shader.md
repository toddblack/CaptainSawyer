# Goal: Add a Shader

Use this playbook any time a new `.gdshader` file is written for a material.

---

## A — Architect

Answer before touching any file:

- **What type of shader?**
  - `spatial` — 3D world geometry (water, terrain, boat, islands)
  - `canvas_item` — 2D overlay (fog of war, HUD effects)
- **What does it need from the CPU?** (shader parameters → exported `uniform` values, set in ShaderMaterial)
- **Does it need world-space UV?** (almost always yes for 3D — requires a `varying`)
- **Does it need transparency?** (requires `blend_mix` in render_mode + ALPHA output)

---

## T — Trace

**Files touched:**
- `assets/materials/<name>.gdshader` — new shader file
- `scenes/main.tscn` — new `ShaderMaterial` sub-resource referencing the shader; applied to mesh node

**Existing shaders for reference:**
| Shader | Purpose | Key technique |
|---|---|---|
| `water_shader.gdshader` | Ocean surface | World-space UV via varying, vertex wave displacement |
| `island_terrain.gdshader` | Island mesh | Height-based blend, ALPHA fade at waterline |
| Fog of war (inline in fog_of_war.gd) | Screen overlay | canvas_item, screen UV → world XZ projection |

---

## L — Link

Before writing:
- [ ] Confirm shader type (`spatial` vs `canvas_item`)
- [ ] If world-space UV is needed, plan the `varying vec2 world_uv` pattern
- [ ] If transparency is needed, confirm `blend_mix` is in render_mode
- [ ] If textures are needed, confirm the `.png` exists in `assets/textures/`
- [ ] List all `uniform` parameters that will need to be set from main.tscn

---

## A — Assemble

### Spatial shader template (3D geometry)

```glsl
shader_type spatial;
render_mode diffuse_lambert, shadows_disabled;
// Add blend_mix if transparency (ALPHA) is needed

// Uniforms set from ShaderMaterial in main.tscn
uniform sampler2D my_texture : source_color;
uniform float my_param : hint_range(0.0, 1.0) = 0.5;

// REQUIRED for world-space UV — VERTEX in fragment() is VIEW space, not world
varying vec2 world_uv;

void vertex() {
    // Pass world XZ to fragment before the view transform
    world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    vec2 uv = world_uv / my_tile_size;
    vec4 tex = texture(my_texture, uv);
    ALBEDO = tex.rgb;
    // ALPHA = ...; // only if blend_mix is in render_mode
}
```

### Canvas item shader template (2D overlay)

```glsl
shader_type canvas_item;

uniform vec2 world_min = vec2(-100.0, -100.0);
uniform vec2 world_max = vec2(100.0, 100.0);

void fragment() {
    // UV is 0..1 across the canvas item (screen if on a full-screen ColorRect)
    vec2 world_xz = mix(world_min, world_max, UV);
    // ... use world_xz to look up data or drive effects
    COLOR = vec4(result, alpha);
}
```

### Wiring in main.tscn

```
[sub_resource type="ShaderMaterial" id="ShaderMaterial_myshader"]
shader = ExtResource("N_myshader")
shader_parameter/my_param = 0.5
shader_parameter/my_texture = ExtResource("N_mytexture")

[node name="MyMesh" type="MeshInstance3D" parent="."]
surface_material_override/0 = SubResource("ShaderMaterial_myshader")
```

Add the shader as an `ext_resource` at the top of main.tscn:
```
[ext_resource type="Shader" path="res://assets/materials/my_shader.gdshader" id="N_myshader"]
```

---

## S — Stress-test

- [ ] Run the scene — no shader compile errors in Output
- [ ] Verify the effect looks correct at default camera zoom
- [ ] Zoom in/out — no UV discontinuities or tiling breaks
- [ ] If transparent: verify ALPHA fades correctly and no z-fighting with adjacent geometry
- [ ] If world-space UV: confirm texture doesn't "swim" when the camera moves (common sign that VERTEX was used in fragment without a varying)

---

## Gotchas

- **`VERTEX` in `fragment()` is VIEW space, not world space** — always use a `varying vec2 world_uv` populated in `vertex()` using `MODEL_MATRIX * vec4(VERTEX, 1.0)`.
- **Transparency requires TWO things**: `blend_mix` in `render_mode` AND setting `ALPHA` in `fragment()`. Missing either → no transparency.
- **`shadows_disabled` in render_mode** — prevents the mesh *receiving* cast shadows. Does NOT affect geometry shape or wave displacement. Use it for terrain/water to avoid shadow artifacts.
- **`render_priority`** — if a transparent object draws behind opaque geometry incorrectly, set `render_priority = 1` (or higher) on the ShaderMaterial.
- **Avoid pixel-snapping in UV calculations** — causes visible grid lines. Use smooth world-space UV math; don't `floor()` or `round()` UV before sampling.
- **Value noise grid seams** — if using noise, rotate each UV sample by a different irrational angle (22°, 55°) to break up grid alignment, especially on isometric 45° screen axes.
- **`ext_resource` uid=** — not strictly required in .tscn; Godot adds it on next editor save. Safe to omit when writing by hand.
