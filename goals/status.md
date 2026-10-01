# Captain Sawyer — Session Status & Handoff

> Read this first when picking the project back up. Update it at the end of every session.
> *Last updated: 2026-09-30 (ship models verified & merged)*

---

## Where things stand

### Git
| Branch | State |
|---|---|
| `main` | ✅ Verified in Godot by Todd (2026-09-30). **Not pushed** — ask Todd before pushing. |
| `island-overhaul` | Stale — fully contained in `main`. Safe to delete (ask first). |

### Done on 2026-09-30 (verified by Todd, merged to `main`) — 3D ships ("omg it looks fantastic")
- 8 Claude Design ship GLBs (4 tiers × sails set/furled) in `assets/models/ships/`, replacing
  the hand-built dinghy.
- All 4 ships sailable. **Boat → Ship** dropdown in the Inspector, or **Tab** in-game to cycle.
  Each tier = `resources/ships/<tier>.tres` (stats from game_design.md §9, model, `hull_length`:
  2.6 / 5 / 8 / 11). Collision box and wake fit the hull automatically.
- `boat_visual.gd` builds the GLB ship, merged per material. `sail_color` on BoatVisual dyes
  the sails (the GLBs only have canvas).
- Todd: all 4 ships "look great". Dinghy showed water on its deck (open boat — floor is below
  the GLB waterline; the old ±0.15 bob ran out of step with the waves). Fix: every ship now
  rides the ocean's actual swell (`Boat._swell()`), and `ride_height` in the .tres lifts a
  model (dinghy 0.12, others 0). ✅
- Wake starts as a point at the bow tip, flares along the hull (first 30% of its length), then
  spreads at the Kelvin angle — fixed a hard line across the bow. ✅
- Sails set when moving; furl after 5 s still (`furl_after_seconds` on Boat). Interim rule —
  sail/anchor/dock controls logged as an open question in game_design.md.
- Tree GLB merge moved into shared `scripts/mesh_merge.gd`.
- Old bow spray particles (`BowWaveLeft/Right`) removed — the wake arms start at the bow now.
  `assets/materials/wake_foam.gdshader` is unused, kept only as the particle playbook's example.
- Galleon reverse speed set to 2.0 (Todd: big ship, slow). Per-tier sizes (`hull_length`)
  are still a first guess.

### Done on 2026-09-29 (all verified by Todd, all on `main`)
- **Claude Design tiles + 3D tree clusters + smooth coastlines** (the previously unverified branch).
- **Terrain cliffs** — cliff coasts, terraced hillsides, river gorges; the shader paints anything
  steep with a per-biome cliff texture projected side-on. ("looking incredible")
- **Camera clamped inside the world** — the ocean edge / grey void never shows (`camera_controller.gd`).
- **Boat wake** — stern particles replaced by a foam ribbon (`scripts/wake_trail.gd` +
  `assets/materials/wake_trail.gdshader`): V arms at the Kelvin angle from the bow, churned
  centre behind the stern, world-grid pixels + Bayer dithering, rides the swell. ("can I faint now")
- `incoming/` is git-ignored and Godot-ignored (`.gdignore`).

### Todd's visual taste (learned this session)
"Retro but polished": real shapes (geometry, slopes, ribbons) given a retro feel with
world-grid pixels and ordered/per-texel dithering. Tiny particles read as "cheap 8-bit".

### Tuning knobs (if Todd wants tweaks)
- **Cliffs:** `_ZONE_CLIFFS` (height, coast bias, terrace step/strength per biome) and
  `_ZONE_CLIFF_TEX` in `island.gd`; `cliff_ny_start` / `cliff_ny_full` in `island_terrain.gdshader`.
  `cliffIce` texture unused (future polar biome).
- **Wake:** `texels_per_unit` (16; 8 = terrain pixel size), `foam_color`, `churn_color`,
  `churn_alpha` in `wake_trail.gdshader`; `_LIFETIME`, `_KELVIN_SPREAD` in `wake_trail.gd`;
  bow flare = `hull_length * 0.3` in `WakeTrail.fit_hull()`.

### Open questions for Todd (ask at the start)
1. **`.gitattributes` with `* text=auto eol=lf`** (Godot's recommended default)? Stops the
   phantom "modified" `.import` files and LF→CRLF warnings caused by `core.autocrlf=true`.
   If `.import` files show as modified with no real diff: `git add -u -- '*.import'` clears them.
2. Delete `island-overhaul`?
3. Older housekeeping: unused tree GLBs in `assets/models/trees/{tropical,volcanic,atoll,highland}/`
   and unused `assets/textures/sawyer_atlas_32px_day.png` — delete?

### Tech debt noted
- **World size is duplicated**: `WORLD_HALF` in `island_spawner.gd`, `fog_of_war.gd`, `hud.gd`,
  `world_half` on the camera, `boundary_min/max` on the boat. Centralise when world expansion is built.
- Wake ribbon, boat and water shader share the wave sum — keep `wake_trail.gdshader` and
  `Boat._wave_at()` in sync with `water_shader.gdshader` if waves change.

---

## Next up (in order)
1. **Save system** — build priority #5. World = `IslandSpawner.world_seed`; also persist fog texture
   (`FogOfWar._fog_data`), discovered islands, `WorldClock` time/day, `VoyageResources`,
   boat transform. Mobile expects auto-save. Decide death/carry-over rules (see game_design.md §2).
2. **Capsule sites** — first storyline feature: wreckage + stranded crewmate on a discovered
   island (see storyline.md crew table; C-2 engineers are "findable mid-early game").
   Todd says the story is being made up as we go — confirm details with him, update storyline.md.
3. **World edge as story** (idea, not decided): the boat currently stops at an invisible wall;
   later this could be "the charts end here" / rough water until more ocean is unlocked
   (see memory: world expansion).
4. Later polish: tree shadows at low sun, more terrain layers (wetsand, jungle, meadow, ash,
   snow, `_b/_c` variations are in the Claude Design export), minimap island shapes,
   HUD static/dynamic split.

## Decisions made so far
- **Premise:** stranded crew (storyline.md) is canonical. ✅
- **Day length:** 30 real minutes. ✅
- Atolls always have 1–3 guaranteed passes into the lagoon. ✅
- Terrain art = one seamless texture per layer (spec in `goals/add_shader.md`); cliff textures
  are the side-on exception. ✅
- Camera never shows past the world edge. ✅
- Handoff from Claude Design: export into `incoming/claude_design/`, then tell Claude.
  (Claude Code can't connect to Claude Design projects directly.)

## Working agreements with Todd
- Todd verifies visually in Godot and sends screenshots; Claude doesn't hunt for / launch the editor.
- Commit to a side branch when work is unverified; merge to `main` (fast-forward) after Todd
  confirms — an enthusiastic "it works" counts. Delete the side branch after merging.
- Audience: Todd is the solo dev; keep explanations plain, lead with what changed and what to check.
