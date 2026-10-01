# Captain Sawyer — Claude Instructions

## GDScript Coding Standards

**Performance is a top priority.** Always write typed GDScript — never leave variables as untyped Variant.

- Use explicit type annotations on all variable declarations: `var x: float = 0.0`
- Use explicit types when assigning cast results — `:=` with `as` infers Variant and is a parse error in strict mode:
  ```gdscript
  # WRONG
  var mat := node.material as StandardMaterial3D
  # RIGHT
  var mat: StandardMaterial3D = node.material as StandardMaterial3D
  ```
- Annotate all function parameters and return types: `func foo(x: float) -> void:`
- Prefer typed arrays: `var items: Array[Node] = []`

Typed GDScript runs meaningfully faster (engine skips Variant boxing) and catches bugs at parse time rather than at runtime.

## Start Here

**Read `goals/status.md` first** — current branch state, what needs verifying, next steps,
and working agreements. Update it at the end of each session.

## Game Design

Before building any significant new system, read `goals/game_design.md`.
It defines the vision, open questions, and build priority. Update it when decisions are made.

For anything narrative — crew, dialogue, island lore, naming, discovery text — read
`goals/storyline.md` first. It's the story source of truth (premise, the 13 crew, world).

## Architecture Notes

- **Islands** (`scripts/island.gd`): a signed land field `s(x,z)` (domain-warped fractal
  noise, `s = 0` is the coast) places the coastline; heights on both sides are built from
  true grid distance to that coast (chamfer pass), so every shore has the same slope. Terrain is
  built on a `WorkerThreadPool` task, split into 32-cell chunks (waterline cells are split
  4×4 with Catmull-Rom heights for curved coasts; edges shared with coarse cells stay linear
  so there are no cracks), with `HeightMapShape3D`
  collision and MultiMesh trees. Trees are Claude Design low-poly clusters
  (`assets/models/trees/sawyer/`, mapped per zone in `_ZONE_TREE_CLUSTERS`); each GLB is
  merged into one mesh per material at load — they ship as 18–67 pieces each. Keep `_river_valley()` / `_zone_weight()` in sync with
  `island_terrain.gdshader`.
- **Cliffs**: height code *makes* steep ground (`_cliff_params()` per zone via `_ZONE_CLIFFS`:
  cliff coasts, terraced hillsides, gorges where rivers cut high ground); the shader *paints*
  anything steep (world `normal.y` < `cliff_ny_start`) with the zone's cliff texture,
  projected side-on. Cliff texture slot `cliff_tex_i` belongs to zone `i`.
- **Ship** (`scripts/boat_visual.gd`): Claude Design GLBs in `assets/models/ships/`, one
  `_set` + one `_furled` file per tier. Hull, Rigging and each sail state are merged per material
  (`MeshMerge`, shared with trees). `Boat.ship` picks `resources/ships/<tier>.tres` (stats,
  model, `hull_length`); `_apply_ship()` fits collision and the wake to the hull bounds
  that `BoatVisual.build()` returns. Sails only change via `BoatVisual.set_sails()`; the rule
  that calls it lives in `boat.gd`.
- **World seed** (`IslandSpawner.world_seed`): every island derives from
  `hash(world_seed, island_name)`. A save file only needs the seed to rebuild the world.
- **Fog of war** is a full-screen spatial quad using the depth buffer (true world XZ per
  pixel). The minimap draws the same fog texture. Don't reintroduce parallax hacks.
- **Day length** lives only in `WorldClock.DAY_LENGTH_SECONDS`; everything else reads it.

## Task Playbooks

Before starting any of these tasks, read the corresponding goal file first:

| Task | Goal file |
|---|---|
| Add a particle effect (GPUParticles3D) | `goals/add_particle_effect.md` |
| Add a HUD element (minimap, toast, panel) | `goals/add_hud_element.md` |
| Add a shader (.gdshader) | `goals/add_shader.md` |

Goals define the established pattern, known gotchas, and correct assembly order for each task type. Follow them. Update them when a new gotcha is discovered.
