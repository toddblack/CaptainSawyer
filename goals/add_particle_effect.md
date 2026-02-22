# Goal: Add a Particle Effect

Use this playbook any time a new `GPUParticles3D` effect is added to the scene.

---

## A — Architect

Answer before touching any file:

- **What emits?** (which node is the parent — Boat, Island, etc.)
- **What does it look like?** (foam, sparks, smoke, splash — affects mesh choice and color)
- **When does it emit?** (always, speed-gated, event-triggered)
- **Does it follow the parent or stay in world space?** (almost always world space — `local_coords = false` default)

---

## T — Trace

**Files touched:**
- `scenes/main.tscn` — new sub-resources + node
- `scripts/<parent>.gd` — emission control (if speed/event gated)

**Sub-resources needed in main.tscn (in order):**
1. `Gradient` — color over lifetime
2. `GradientTexture1D` — wraps the Gradient
3. `ShaderMaterial` pointing at a `.gdshader` — **preferred over StandardMaterial3D** for soft shapes (see Gotchas)
4. `PlaneMesh` or `SphereMesh` — particle shape; PlaneMesh lies flat (XZ), good for water-surface effects
5. `ParticleProcessMaterial` — behavior (direction, spread, velocity, damping, color_ramp)

**Key ParticleProcessMaterial parameters:**
| Param | Notes |
|---|---|
| `direction` | In emitter's **local** space. `(0,0,1)` = backward when emitter is child of Boat |
| `spread` | Degrees of cone spread. 25–35° gives a V-wake shape |
| `flatness` | 0 = full 3D cone, 0.9 = mostly flat (reduces vertical scatter) |
| `gravity` | Set to `Vector3(0,0,0)` for water-surface particles |
| `damping_min/max` | Slows particles over time — use 1–3 for foam |
| `color_ramp` | Assign the GradientTexture1D for fade-out |

**Direction behavior with `local_coords = false` (default):**
When the emitter is a child of a rotating node (e.g. Boat), direction is transformed to world space at the moment each particle emits. Particles trail correctly behind a turning boat with no code changes needed.

---

## L — Link

Before writing:
- [ ] Confirm parent node name matches `$NodeName` reference in the script
- [ ] Confirm `position.y` of the emitter puts it at the right world height (Boat center is y≈0.5, water is y=0; local y=-0.4 on Boat ≈ world y=0.1)
- [ ] Confirm sub-resource IDs don't collide with existing IDs in main.tscn

---

## A — Assemble

**Order of operations:**
1. Add sub-resources to main.tscn **before** the first `[node]` block
2. Add the `[node type="GPUParticles3D"]` as a child of the correct parent node
3. Set `emitting = false` if emission is controlled by script
4. Add `@onready` reference in the parent script
5. Add emission control logic in `_physics_process` or `_process`

**Script emission pattern:**
```gdscript
@onready var _fx: GPUParticles3D = $FXNodeName

# In _physics_process or _process:
_fx.emitting = <condition>

# For variable intensity, cast and set velocity (avoid := with as):
if _fx.emitting:
    var mat: ParticleProcessMaterial = _fx.process_material as ParticleProcessMaterial
    mat.initial_velocity_min = lerp(min_slow, min_fast, speed_ratio)
    mat.initial_velocity_max = lerp(max_slow, max_fast, speed_ratio)
```

**TSCN node block:**
```
[node name="FXName" type="GPUParticles3D" parent="ParentName"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, <x>, <y>, <z>)
amount = 24
lifetime = 2.0
fixed_fps = 20
emitting = false
process_material = SubResource("ParticleProcessMaterial_fx")
draw_pass_1 = SubResource("PlaneMesh_fx")
```

---

## S — Stress-test

- [ ] Run the scene — no parse errors in Output
- [ ] Trigger the condition — particles appear
- [ ] Stop the condition — particles stop emitting; existing ones fade out over `lifetime`
- [ ] Turn the boat while emitting — trail follows the correct direction
- [ ] Zoom camera to extremes — particles not clipped or culled prematurely

---

## Gotchas

- **Never use `:=` with an `as` cast** — infers Variant, parse error in strict mode. Use `var x: Type = expr as Type`.
- **PlaneMesh is already flat (XZ plane)** — no rotation needed for water-surface particles.
- **`local_coords = false` (default) is correct for trails** — particles simulate in world space, emit direction is local-to-world at emit time.
- **`flatness = 1.0` spreads in the wrong axis** — use 0.8–0.9 to reduce vertical scatter without fully inverting the spread shape.
- **Set `gravity = Vector3(0,0,0)`** — otherwise particles arc down through the water mesh.
- **Prefer `ShaderMaterial` over `StandardMaterial3D` for particle meshes** — a simple shader using `COLOR.a` and UV distance gives soft circular foam blobs with zero texture files. See `assets/materials/wake_foam.gdshader` as the reference. `StandardMaterial3D` requires `vertex_color_use_as_albedo = true` to connect `color_ramp`, and produces hard square edges.
- **Cache material references in `_ready()`** — don't cast `.process_material as ParticleProcessMaterial` every frame. Store as typed `var _mat: ParticleProcessMaterial = null` and assign once in `_ready()`.
