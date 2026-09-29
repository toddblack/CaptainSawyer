# Captain Sawyer — Session Status & Handoff

> Read this first when picking the project back up. Update it at the end of every session.
> *Last updated: 2026-09-28 (end of day)*

---

## Where things stand

### Branches
| Branch | State |
|---|---|
| `main` @ `3ffb240` | ✅ Verified in Godot by Todd. Natural islands, depth-based shores, world-space fog, seamless terrain textures. |
| `claude-design-assets` @ `38eb770` | ⚠️ **Not yet run in Godot.** Smooth coastlines + Claude Design tiles + 3D tree clusters. Merge to `main` (fast-forward) once verified. |

### Verify on `claude-design-assets` (Todd runs Godot — don't launch it for him)
1. **Coastline corners rounded** — waterline cells are split 4×4 with Catmull-Rom heights.
   Look for any thin **cracks** along the waterline (would mean the linear-edge rule failed).
2. **Foam** varies in width along the shore (not an even outline).
3. **Terrain tiles** — crisp 32-px pixel art, dithered transitions sand→grass→rock.
   If too chunky: `tile_world` 4 → 2 in `island_terrain.gdshader`.
4. **Trees** — Claude Design low-poly clusters per biome. Check **scale**
   (`_TREE_SCALE_MIN/MAX` = 0.9–1.3 in `island.gd`) and **density** (tree counts in
   `island_spawner.gd` `_roll_trees`). Volcanic `ember` material should glow at night.
5. First open imports 60 GLBs — may take a moment.

### Open housekeeping (ask Todd)
- `incoming/claude_design/` is **untracked** (~6 MB, duplicates the GLBs). Add to `.gitignore`? Undecided.
- Old tree GLBs in `assets/models/trees/{tropical,volcanic,atoll,highland}/` are now unused — delete?
- `assets/textures/sawyer_atlas_32px_day.png` (Claude Design atlas) is unused; per-tile files are used instead.
- Todd's "happy accident" 32-px sand was replaced by Claude Design's sand; old one is in `3ffb240` if wanted.

---

## Next up (in order)
1. Verify + merge `claude-design-assets`.
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
