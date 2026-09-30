# Captain Sawyer — Session Status & Handoff

> Read this first when picking the project back up. Update it at the end of every session.
> *Last updated: 2026-09-29*

---

## Where things stand

### Branches
| Branch | State |
|---|---|
| `wake-trail` | ⚠️ **Not yet run.** Stern wake particles → foam ribbon (V arms at the Kelvin angle, churned centre, dithered world-grid pixels). Bow spray particles unchanged. |
| `main` | ✅ Verified in Godot by Todd (2026-09-29). Smooth coastlines, Claude Design tiles + 3D tree clusters, terrain cliffs, and camera clamped inside the world (ocean edge never shows). Merged side branches deleted. |

- **World size is duplicated**: `WORLD_HALF` in `island_spawner.gd`, `fog_of_war.gd`, `hud.gd`,
  plus `world_half` on the camera and `boundary_min/max` on the boat. Centralise when the
  world-expansion feature is built.

### Cliffs — tuning knobs if Todd wants changes
- Per-biome cliff height / how much coast is cliff / terrace step & strength: `_ZONE_CLIFFS` in `island.gd`.
- How steep counts as cliff: `cliff_ny_start` / `cliff_ny_full` in `island_terrain.gdshader`.
- Biome → cliff texture: `_ZONE_CLIFF_TEX` in `island.gd`. `cliffIce` is unused (for a future polar biome).

### Open housekeeping (ask Todd)
- ~~`incoming/` untracked~~ → now in `.gitignore` + `.gdignore` (2026-09-29).
- Old tree GLBs in `assets/models/trees/{tropical,volcanic,atoll,highland}/` are now unused — delete?
- `assets/textures/sawyer_atlas_32px_day.png` (Claude Design atlas) is unused; per-tile files are used instead.
- Todd's "happy accident" 32-px sand was replaced by Claude Design's sand; old one is in `3ffb240` if wanted.

---

## Next up (in order)
1. ~~Verify + merge `claude-design-assets`~~ ✅ done, along with terrain cliffs.
2. **Save system** — build priority #5. World = `IslandSpawner.world_seed`; also persist fog texture
   (`FogOfWar._fog_data`), discovered islands, `WorldClock` time/day, `VoyageResources`,
   boat transform. Mobile expects auto-save. Decide death/carry-over rules (see game_design.md §2).
3. **Capsule sites** — first storyline feature: wreckage + stranded crewmate on a discovered
   island (see storyline.md crew table; C-2 engineers are "findable mid-early game").
4. Later polish: tree shadows at low sun, more terrain layers (wetsand, jungle, meadow, ash,
   snow, cliffs, `_b/_c` variations are all in the Claude Design export), minimap island shapes,
   HUD static/dynamic split.

## Decisions made this session
- **Premise:** stranded crew (storyline.md) is canonical. ✅
- **Day length:** 30 real minutes. ✅
- Atolls always have 1–3 guaranteed passes into the lagoon. ✅
- Terrain art = one seamless texture per layer (spec in `goals/add_shader.md`). ✅
- Handoff from Claude Design: export into `incoming/claude_design/`, then tell Claude.
  (Claude Code can't connect to Claude Design projects directly.)

## Working agreements with Todd
- Todd verifies visually in Godot and sends screenshots; Claude doesn't hunt for / launch the editor.
- Commit to a side branch when work is unverified; merge to `main` after Todd confirms.
- Audience: Todd is the solo dev; keep explanations plain, lead with what changed and what to check.
