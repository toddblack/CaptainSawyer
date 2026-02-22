# Goal: Add a HUD Element

Use this playbook any time a new UI element is added to the player's screen.

---

## A — Architect

Answer before touching any file:

- **What type of element?**
  - **Minimap addition** (dot, icon, overlay drawn on the map) → modify `_draw()` in hud.gd
  - **Transient overlay** (toast, popup, notification) → create a Control/Label in `_ready()`, animate with Tween
  - **Persistent panel** (log, inventory, stat bar) → consider a separate Control node with its own script
- **When is it visible?** (always, on event, toggled by input)
- **Does it need world→screen coordinate mapping?** (use `_world_to_map()` for minimap elements)

---

## T — Trace

**HUD structure:**
```
HUD (CanvasLayer, layer=0)
└── MinimapControl (Control, anchors fill screen)
    └── script: scripts/hud.gd
        └── _toast_label (Label, created in _ready)
```

**Key hud.gd entry points:**
| Method | Purpose |
|---|---|
| `_ready()` | Create child Controls (labels, panels) and store as `var _thing` |
| `_process()` | Call `queue_redraw()` each frame to keep minimap live |
| `_draw()` | All 2D canvas drawing (minimap bg, fog, dots, boat, border) |
| `_world_to_map(world_xz: Vector2) -> Vector2` | Converts world XZ → minimap pixel position |
| `_on_island_discovered(name, pos)` | Signal handler; appends to `_islands`, triggers toast |

**Files touched:**
- `scripts/hud.gd` — primary file for all HUD logic
- `scenes/main.tscn` — only if adding a new top-level CanvasLayer or Control node (rare)

---

## L — Link

Before writing:
- [ ] Identify which entry point handles this (draw vs ready vs signal)
- [ ] If the element needs a world position, confirm `_world_to_map()` is the right converter
- [ ] If it's a new signal, confirm the emitter (island.gd, boat.gd, etc.) already emits it or plan to add it

---

## A — Assemble

### Pattern A: Minimap dot / icon (drawn element)

Add to `_draw()` inside the `# Discovered islands` or boat section:

```gdscript
# Example: a new icon type at a world position
var px: Vector2 = _world_to_map(Vector2(world_x, world_z))
draw_circle(px, radius, color)
draw_arc(px, radius, 0, TAU, 12, outline_color, 1.0)
```

Store world positions in a typed array declared at the top of the script:
```gdscript
var _things: Array[Vector2] = []
```

### Pattern B: Transient overlay (toast/notification)

Create in `_ready()`:
```gdscript
var _my_label: Label

func _ready() -> void:
    _my_label = Label.new()
    _my_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
    _my_label.position.y = 60
    _my_label.add_theme_font_size_override("font_size", 20)
    _my_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
    _my_label.modulate.a = 0.0  # start invisible
    add_child(_my_label)
```

Trigger with Tween (follow existing toast pattern):
```gdscript
var _my_tween: Tween

func show_message(text: String) -> void:
    _my_label.text = text
    if _my_tween:
        _my_tween.kill()
    _my_tween = create_tween()
    _my_tween.tween_property(_my_label, "modulate:a", 1.0, 0.3)
    _my_tween.tween_interval(2.5)
    _my_tween.tween_property(_my_label, "modulate:a", 0.0, 0.8)
```

### Pattern C: Persistent panel (log, stat bar)

Create a new script file `scripts/my_panel.gd`, extend Control. Add the node in main.tscn as a child of HUD (CanvasLayer). Wire signals from game nodes to panel methods via the scene or via `get_tree().get_first_node_in_group()`.

---

## S — Stress-test

- [ ] Run the scene — no parse errors
- [ ] Trigger the condition — element appears/updates correctly
- [ ] Resize the viewport (if applicable) — element stays anchored correctly
- [ ] Check minimap rect is recalculated in `_draw()` (not just `_ready()`) — it already is for existing elements; new draw elements inherit this
- [ ] Toast/overlay: trigger twice in quick succession — old tween is killed, new one starts cleanly

---

## Gotchas

- **`_draw()` runs every frame via `queue_redraw()`** — keep draw calls cheap; don't allocate Arrays or Dictionaries inside `_draw()`.
- **`_map_rect` is recalculated inside `_draw()`** — safe to use it there directly.
- **`_world_to_map()` takes `Vector2` (XZ), not `Vector3`** — strip the Y: `Vector2(pos.x, pos.z)`.
- **Tweens must be killed before restarting** — if `_tween` exists, call `.kill()` before `create_tween()`, or the old and new tweens fight each other.
- **`add_child()` in `_ready()` vs scene** — for dynamic/conditional elements, creating in `_ready()` is fine. For always-visible structure, prefer the .tscn.
- **CanvasLayer layer order** — HUD is layer=0. If a new overlay needs to appear above the fog-of-war or other CanvasLayers, check/set the layer value explicitly.
