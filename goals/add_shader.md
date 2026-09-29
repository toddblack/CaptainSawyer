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
| `water_shader.gdshader` | Ocean surface | World-space UV via varying, depth-buffer water column → colour, alpha and shore foam |
| `island_terrain.gdshader` | Island mesh | Height-based atlas blend, Gaussian zone tints, wet sand / seabed darkening |
| Fog of war (inline in fog_of_war.gd) | Full-screen 3D quad | spatial + depth buffer → true world XZ per pixel |

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

## Terrain textures (supplying art)

Island terrain uses **one seamless texture per layer**, not an atlas:
`assets/textures/terrain/{sand,grass,rock,lava_rock}.png`. Replace a file in place to
restyle every island. Each texture must be:

- **Seamless on all four edges** — the GPU wraps it (`repeat_enable`). Test by tiling 2×2.
- **Square, 256–1024 px**, top-down, **flat lighting** (no baked shadow direction).
- **No borders, grid lines, labels or watermarks.**
- **No directional features** — no drawn shorelines, paths or wave edges. The terrain
  and water shaders make coastlines. Small scattered details (pebbles, flowers) are fine.
- Not too high-contrast at large scale — big dark/light blobs make repetition obvious.

Current set: Claude Design's 32-px pixel-art tiles (`incoming/claude_design/…/tiles/`:
sand, grass, rock, basalt→lava_rock). More ids are available there (wetsand, jungle,
meadow, ash, snow, cliff*, _b/_c variations) for future layers.

Scale: `tile_world` (4 wu per repeat) and `texels_per_tile` (32) — **all layers must share
the same texel density**. 32 px / 4 wu = 8 texels per world unit.

Pixel-art rules (the shader already follows them):
- Sampler `filter_nearest_mipmap` — crisp texels; mipmaps only for zoomed-out shimmer.
- **Never cross-fade** layers or anti-tiling offsets — dither per texel (`hash12(floor(uv * texels_per_tile))`)
  and snap offsets to whole texels. One texture read per pixel as a bonus.

**Import settings** (in each `.png.import`): `compress/mode=0` (lossless),
`mipmaps/generate=true`, **`detect_3d/compress_to=0`** — the default `1` silently
re-imports as VRAM-compressed the first time the texture is used in 3D, which smears
pixel art.

Atlas sheets drawn as 2D-tilemap pieces (`beach_watersEdge_rocks.png`,
`grasses_dirt.png`) don't fit a 3D heightfield blend — use them only as reference.

---

## Gotchas

- **Texture atlases + `fract()` tiling = seams and mip bleed.** Use separate textures with
  `repeat_enable` instead.
- **Colour textures need `source_color`** on the sampler hint, or sRGB PNGs are read as
  linear (washed-out / wrong-looking colours).
- **`dFdx`/`dFdy` inside an `if` are undefined** (neighbouring pixels may take the other
  branch). Compute derivatives at the top of `fragment()` and pass them to `textureGrad`.

- **`VERTEX` in `fragment()` is VIEW space, not world space** — always use a `varying vec2 world_uv` populated in `vertex()` using `MODEL_MATRIX * vec4(VERTEX, 1.0)`.
- **Transparency requires TWO things**: `blend_mix` in `render_mode` AND setting `ALPHA` in `fragment()`. Missing either → no transparency.
- **`shadows_disabled` in render_mode** — prevents the mesh *receiving* cast shadows. Does NOT affect geometry shape or wave displacement. Use it for terrain/water to avoid shadow artifacts.
- **`render_priority`** — if a transparent object draws behind opaque geometry incorrectly, set `render_priority = 1` (or higher) on the ShaderMaterial.
- **Avoid pixel-snapping in UV calculations** — causes visible grid lines. Use smooth world-space UV math; don't `floor()` or `round()` UV before sampling.
- **Value noise grid seams** — if using noise, rotate each UV sample by a different irrational angle (22°, 55°) to break up grid alignment, especially on isometric 45° screen axes.
- **`ext_resource` uid=** — not strictly required in .tscn; Godot adds it on next editor save. Safe to omit when writing by hand.
- **Uniform arrays must be set whole** — `set_shader_parameter("zone_data[0]", ...)` silently does nothing. Build a `PackedVector4Array` (padded to the declared size) and set `"zone_data"`.
- **`smoothstep(a, b, x)` needs `a < b`** — reversed edges are undefined in GLSL (works on some GPUs, garbage on others). Write `1.0 - smoothstep(lo, hi, x)` instead.
- **Procedural meshes: wind triangles clockwise seen from the front** (Godot's front face). Wrong winding forces `cull_disabled` as a workaround and flips generated normals. Island terrain uses `i00, i10, i11 / i00, i11, i01` on an X-right, Z-down grid.
- **Shoreline effects: use the depth buffer, not a baked map.** The water column thickness (`depth_texture` → view depth − `-VERTEX.z`) follows the real coastline per pixel; a low-res baked shore texture drifts into circles and rings.
- **Full-screen spatial quad** (fog): `QuadMesh` 2×2, `POSITION = vec4(VERTEX.xy, 1.0, 1.0)` in `vertex()`, huge `custom_aabb` so it's never culled, `render_priority` high so it draws after the transparent ocean. The ocean isn't in the depth buffer — project below-sea-level points back up to Y=0 along the view ray.
