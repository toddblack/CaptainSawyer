# Captain Sawyer — Session Status & Handoff

> Read this first when picking the project back up. Update it at the end of every session.
> *Last updated: 2026-09-29 (end of session)*

---

## Where things stand

### Git
| Branch | State |
|---|---|
| `main` | ✅ Verified in Godot by Todd (2026-09-29). Working tree clean. **6 commits ahead of the remote — not pushed** (ask Todd before pushing). |
| `island-overhaul` | Stale — fully contained in `main`. Safe to delete (ask first). |

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
  `churn_alpha` in `wake_trail.gdshader`; `_LIFETIME`, `_KELVIN_SPREAD`, `_BOW_HALF_WIDTH` in `wake_trail.gd`.

### Open questions for Todd (ask at the start)
1. **Bow spray particles** (`BowWaveLeft/Right` in `main.tscn`) are still the old tiny-dot style.
   Remove them (wake arms now start at the bow) or restyle as dithered splashes?
2. **`.gitattributes` with `* text=auto eol=lf`** (Godot's recommended default)? Stops the
   phantom "modified" `.import` files and LF→CRLF warnings caused by `core.autocrlf=true`.
   If `.import` files show as modified with no real diff: `git add -u -- '*.import'` clears them.
3. Push `main` to the remote? Delete `island-overhaul`?
4. Older housekeeping: unused tree GLBs in `assets/models/trees/{tropical,volcanic,atoll,highland}/`
   and unused `assets/textures/sawyer_atlas_32px_day.png` — delete?

### Tech debt noted
- **World size is duplicated**: `WORLD_HALF` in `island_spawner.gd`, `fog_of_war.gd`, `hud.gd`,
  `world_half` on the camera, `boundary_min/max` on the boat. Centralise when world expansion is built.
- Wake ribbon and water shader share the wave sum — keep `wake_trail.gdshader` in sync with
  `water_shader.gdshader` if waves change.

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
