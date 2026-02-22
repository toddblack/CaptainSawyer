extends Control

# ------------------------------------------------------------------ #
#  Minimap constants                                                   #
# ------------------------------------------------------------------ #

const MAP_SIZE      := 160.0       # px
const MAP_MARGIN    := 12.0        # px from screen edge
const WORLD_HALF    := 100.0       # world coords run -100..100
const CELL_SIZE     := 10.0        # world units per fog cell
const EXPLORE_RADIUS := 2          # cells cleared around the boat each frame

# Fog cell grid: Vector2i -> true means explored
var _explored: Dictionary = {}

# Discovered island world positions
var _islands: Array[Vector2] = []

# Live boat reference
var _boat: Node3D = null

# Cached minimap rect (top-right corner)
var _map_rect: Rect2

# Discovery toast
var _toast_label: Label
var _toast_tween: Tween


func _ready() -> void:
	_boat = get_tree().get_first_node_in_group("boat")

	# Build the minimap rect (top-right corner)
	var vp := get_viewport_rect()
	_map_rect = Rect2(
		MAP_MARGIN,
		vp.size.y - MAP_SIZE - MAP_MARGIN,
		MAP_SIZE,
		MAP_SIZE
	)

	# Toast label — starts invisible, centered near top
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 20)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_toast_label.add_theme_constant_override("shadow_offset_x", 1)
	_toast_label.add_theme_constant_override("shadow_offset_y", 1)
	_toast_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_toast_label.position.y = 60
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)


func _process(_delta: float) -> void:
	if _boat:
		_mark_explored(_boat.global_position)
	queue_redraw()


# ------------------------------------------------------------------ #
#  Fog tracking                                                        #
# ------------------------------------------------------------------ #

func _mark_explored(world_pos: Vector3) -> void:
	var cx := int(floor((world_pos.x + WORLD_HALF) / CELL_SIZE))
	var cz := int(floor((world_pos.z + WORLD_HALF) / CELL_SIZE))
	for dx in range(-EXPLORE_RADIUS, EXPLORE_RADIUS + 1):
		for dz in range(-EXPLORE_RADIUS, EXPLORE_RADIUS + 1):
			_explored[Vector2i(cx + dx, cz + dz)] = true


# ------------------------------------------------------------------ #
#  Drawing                                                             #
# ------------------------------------------------------------------ #

func _draw() -> void:
	# Update map rect each draw in case viewport resized
	var vp := get_viewport_rect()
	_map_rect = Rect2(
		MAP_MARGIN,
		vp.size.y - MAP_SIZE - MAP_MARGIN,
		MAP_SIZE,
		MAP_SIZE
	)

	# Background
	draw_rect(_map_rect, Color(0.05, 0.10, 0.18, 0.92))

	# Ocean tint (slightly lighter than background)
	draw_rect(_map_rect.grow(-2), Color(0.08, 0.20, 0.40, 0.6))

	# Fog of war — draw dark cells over unexplored areas
	var total_cells := int(WORLD_HALF * 2.0 / CELL_SIZE)
	for cx in range(total_cells):
		for cz in range(total_cells):
			if not _explored.has(Vector2i(cx, cz)):
				var cell_world := Vector2(
					cx * CELL_SIZE - WORLD_HALF,
					cz * CELL_SIZE - WORLD_HALF
				)
				var cell_px := _world_to_map(cell_world)
				var cell_size_px := MAP_SIZE / total_cells
				draw_rect(
					Rect2(cell_px, Vector2(cell_size_px, cell_size_px)),
					Color(0.02, 0.04, 0.08, 0.88)
				)

	# Discovered islands — green dots
	for island_pos in _islands:
		var px := _world_to_map(island_pos)
		draw_circle(px, 4.0, Color(0.25, 0.75, 0.30))
		draw_arc(px, 4.0, 0, TAU, 12, Color(0.5, 1.0, 0.5), 1.0)

	# Boat — small yellow dot with direction indicator
	if _boat:
		var bpx := _world_to_map(Vector2(_boat.global_position.x, _boat.global_position.z))
		draw_circle(bpx, 4.0, Color(1.0, 0.9, 0.2))

	# Border
	draw_rect(_map_rect, Color(0.6, 0.7, 0.8, 0.8), false, 1.5)


func _world_to_map(world_xz: Vector2) -> Vector2:
	var t := (world_xz + Vector2(WORLD_HALF, WORLD_HALF)) / (WORLD_HALF * 2.0)
	return _map_rect.position + t * _map_rect.size


# ------------------------------------------------------------------ #
#  Discovery toast                                                     #
# ------------------------------------------------------------------ #

func _on_island_discovered(p_island_name: String, world_pos: Vector2) -> void:
	_islands.append(world_pos)

	_toast_label.text = "Discovered: " + p_island_name

	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_label, "modulate:a", 1.0, 0.3)
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.8)
