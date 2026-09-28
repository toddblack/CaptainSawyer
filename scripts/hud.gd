extends Control

# ------------------------------------------------------------------ #
#  Minimap constants                                                   #
# ------------------------------------------------------------------ #

const MAP_SIZE:       float = 160.0
const WORLD_HALF:     float = 500.0
const CELL_SIZE:      float = 50.0
const EXPLORE_RADIUS: int   = 2

const TOAST_W: float = 440.0
const TOAST_H: float = 220.0

const TOAST_SHADOW_LAYERS: Array[Vector3] = [
	Vector3(3.0,  4.0,  0.25),
	Vector3(6.0,  8.0,  0.18),
	Vector3(10.0, 13.0, 0.10),
]

# Fog cell grid: Vector2i -> true means explored
var _explored: Dictionary = {}

# Discovered island world positions
var _islands: Array[Vector2] = []

# Live boat reference
var _boat: Node3D = null

# Minimap rect — set each frame inside _draw_bottom_panel()
var _map_rect: Rect2

# Discovery toast — drawn entirely in _draw() to share the same coord space as the arc.
# No child Controls involved: position is guaranteed correct without layout fights.
var _parchment_tex:   Texture2D    = null
var _toast_alpha:     float        = 0.0   # tweened 0→1 on show, 1→0 on dismiss
var _toast_name_text: String       = ""
var _toast_res_icons: Array[String] = []   # up to 6 resource keys, sorted by amount desc
var _toast_tween:     Tween        = null

# ── Resource icon sheets ─────────────────────────────────────────────────────
# Sheet index: 0=tropical, 1=volcanic, 2=atoll, 3=highland, 4=forest(future),
#              5=desert(future), 6=plains(future).
# null entries are drawn as a grey placeholder rect.
var _icon_sheets: Array[Texture2D] = []
# Pre-built AtlasTexture per resource key — filter_clip=true prevents bleed at cell edges.
var _icon_atlas: Dictionary = {}   # String -> AtlasTexture

# resource_key → [sheet_idx: int, col: int, row: int]
# Matches _ZONE_RESOURCE_TABLE keys in island.gd.
# Column order is left→right, row 0 is top — maps directly to ICON_XX_01..08.
const _RESOURCE_ICON: Dictionary = {
	# Tropical (sheet 0) — islandResources_tropical.webp
	"coconut":          [0, 0, 0],
	"breadfruit":       [0, 1, 0],
	"sugarcane":        [0, 2, 0],
	"palm_fronds":      [0, 3, 0],
	"hardwood_teak":    [0, 0, 1],
	"quinine_bark":     [0, 1, 1],
	"bamboo_stalks":    [0, 2, 1],
	"volcanic_guano":   [0, 3, 1],
	# Volcanic (sheet 1) — islandResources_volcanic.webp
	"geothermal_water": [1, 0, 0],
	"taro_root":        [1, 1, 0],
	"basalt_rock":      [1, 2, 0],
	"obsidian":         [1, 3, 0],
	"sulfur":           [1, 0, 1],
	"lodestone":        [1, 1, 1],
	"pumice_stone":     [1, 2, 1],
	"native_copper":    [1, 3, 1],
	# Atoll (sheet 2) — islandResources_atoll.webp
	"seabird_eggs":     [2, 0, 0],
	"pelagic_fish":     [2, 1, 0],
	"pandanus_fruit":   [2, 2, 0],
	"driftwood":        [2, 3, 0],
	"clam_shell":       [2, 0, 1],
	"black_pearl":      [2, 1, 1],
	"coral_blocks":     [2, 2, 1],
	"seagrass_fibre":   [2, 3, 1],
	# Highland (sheet 3) — islandResources_highland.webp
	"wild_berries":     [3, 0, 0],
	"root_vegetable":   [3, 1, 0],
	"highland_wool":    [3, 2, 0],
	"stone_blocks":     [3, 3, 0],
	"hematite":         [3, 0, 1],
	"clay":             [3, 1, 1],
	"flax_stalks":      [3, 2, 1],
	"galena":           [3, 3, 1],
	# Plains (sheet 6 — placeholder until sheet ships)
	"wild_grains":      [6, 0, 0],
	"wild_game_bison":  [6, 1, 0],
	"thatch_grass":     [6, 2, 0],
	"hemp_fibre":       [6, 3, 0],
	"limestone_block":  [6, 0, 1],
	"coal_lump":        [6, 1, 1],
	"wild_flowers":     [6, 2, 1],
	"horses":           [6, 3, 1],
	# Desert (sheet 5 — placeholder until sheet ships)
	"prickly_pear":     [5, 0, 0],
	"reptile_meat":     [5, 1, 0],
	"sandstone_block":  [5, 2, 0],
	"silica_sand":      [5, 3, 0],
	"niter":            [5, 0, 1],
	"acacia_wood":      [5, 1, 1],
	"dried_aloe":       [5, 2, 1],
	"obsidian_shards":  [5, 3, 1],
}

# Arc panel clipping — bodies live in a child Control so clip_children masks them
var _arc_clip:   Control = null
var _arc_bodies: Control = null

# ------------------------------------------------------------------ #
#  Day/night arc constants                                             #
# ------------------------------------------------------------------ #

const ARC_RADIUS:  float = 52.0
const ARC_PANEL_W: float = 148.0
const ARC_PANEL_H: float = 72.0

var _star_offsets: Array[Vector2] = [
	Vector2(-38.0, -20.0), Vector2( 28.0, -32.0), Vector2(-18.0, -40.0),
	Vector2( 45.0, -12.0), Vector2(-50.0,  -8.0), Vector2( 10.0, -44.0),
	Vector2( 38.0, -38.0),
]

# ------------------------------------------------------------------ #
#  Bottom panel constants                                              #
# ------------------------------------------------------------------ #

const BOTTOM_PANEL_H:  float = 200.0
const CENTER_PANEL_H:  float = 100.0  # half-height centre console, bottom-locked
const PANEL_PAD:       float = 10.0

# Seamless wood texture (1024×1024). Tiling is done manually in _draw_wood_panel()
# so we control the display size precisely.
# Each displayed tile samples the full texture; adjust WOOD_TILE_DISPLAY to taste.
const WOOD_TILE_ORIGIN:    Vector2 = Vector2(256.0, 256.0)  # col 1, row 0 of the 4×4 atlas
const WOOD_TILE_SRC:       float   = 256.0  # one tile in the atlas (px)
const WOOD_TILE_DISPLAY_W: float   = 256.0  # display width per tile  (px)
const WOOD_TILE_DISPLAY_H: float   = 72.0   # display height per tile (px)

# Rope border — horizontal rope tile from rope_segments.png (1024×1024).
# ROPE_SRC samples the centre band of cell (0,0) — 128px wide, rope body only.
# Adjust ROPE_SRC.position.y / size.y if the rope body sits at a different offset.
const ROPE_BORDER_H:  float = 8.0
const ROPE_TILE_W:    float = 104                              # width of the horizontal rope tile
const ROPE_SRC:       Rect2 = Rect2(5, 130, 363, 45)          # horizontal rope band
const ROPE_CORNER_SRC: Rect2 = Rect2(255.0, 807.0, 66.0, 68.0) # └ corner (left-side-turn-up)

var _wood_tex: Texture2D = null
var _rope_tex: Texture2D = null


func _ready() -> void:
	_boat = get_tree().get_first_node_in_group("boat")

	_wood_tex = load("res://assets/textures/wood_nautical.png") as Texture2D
	_rope_tex = load("res://assets/textures/rope_segments.png") as Texture2D

	# Toast drawn entirely in _draw() — load texture here, no child nodes needed
	_parchment_tex = load("res://assets/textures/toastBG.webp") as Texture2D

	# Icon sheets: indices must match _RESOURCE_ICON sheet_idx values.
	# null = future biome, drawn as grey placeholder when needed.
	_icon_sheets.resize(7)
	var _sheet_paths: Array[String] = [
		"res://assets/textures/islandResources_tropical.webp",   # 0
		"res://assets/textures/islandResources_volcanic.webp",   # 1
		"res://assets/textures/islandResources_atoll.webp",      # 2
		"res://assets/textures/islandResources_highland.webp",   # 3
		"",  # 4 forest — future
		"",  # 5 desert — future
		"",  # 6 plains — future
	]
	for i: int in range(_sheet_paths.size()):
		if _sheet_paths[i] != "":
			_icon_sheets[i] = load(_sheet_paths[i]) as Texture2D

	# Build one AtlasTexture per resource key.
	# filter_clip=true clamps GPU sampling to the region, preventing bleed between cells.
	# Sheets are 128×68: 4 cols × 32px wide, 2 rows × 34px tall.
	const ICON_CELL_W: int = 32
	const ICON_CELL_H: int = 34
	for key: String in _RESOURCE_ICON.keys():
		var icon_data: Array  = _RESOURCE_ICON[key]
		var sheet_idx: int    = icon_data[0]
		if sheet_idx >= _icon_sheets.size() or _icon_sheets[sheet_idx] == null:
			continue
		var at: AtlasTexture  = AtlasTexture.new()
		at.atlas       = _icon_sheets[sheet_idx]
		at.region      = Rect2(icon_data[1] * ICON_CELL_W, icon_data[2] * ICON_CELL_H,
		                       ICON_CELL_W, ICON_CELL_H)
		at.filter_clip = true
		_icon_atlas[key] = at

	# Initialise _map_rect to a sane default before first _draw()
	var vp: Rect2 = get_viewport_rect()
	_map_rect = Rect2(PANEL_PAD, vp.size.y - BOTTOM_PANEL_H + PANEL_PAD, MAP_SIZE, MAP_SIZE)

	# Arc panel clip node — clip_children masks any child rendering to this rect,
	# giving the sun/moon a hard horizon clip without overdraw hacks.
	_arc_clip = Control.new()
	_arc_clip.position    = Vector2(vp.size.x * 0.5 - ARC_PANEL_W * 0.5, 0.0)
	_arc_clip.size        = Vector2(ARC_PANEL_W, ARC_PANEL_H)
	_arc_clip.clip_contents = true
	_arc_clip.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_arc_clip)

	_arc_bodies = Control.new()
	_arc_bodies.size         = Vector2(ARC_PANEL_W, ARC_PANEL_H)
	_arc_bodies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arc_clip.add_child(_arc_bodies)
	_arc_bodies.draw.connect(_on_arc_bodies_draw)


func _process(_delta: float) -> void:
	if _boat:
		_mark_explored(_boat.global_position)
	queue_redraw()
	_arc_bodies.queue_redraw()


# ------------------------------------------------------------------ #
#  Fog tracking                                                        #
# ------------------------------------------------------------------ #

func _mark_explored(world_pos: Vector3) -> void:
	var cx: int = int(floor((world_pos.x + WORLD_HALF) / CELL_SIZE))
	var cz: int = int(floor((world_pos.z + WORLD_HALF) / CELL_SIZE))
	for dx: int in range(-EXPLORE_RADIUS, EXPLORE_RADIUS + 1):
		for dz: int in range(-EXPLORE_RADIUS, EXPLORE_RADIUS + 1):
			_explored[Vector2i(cx + dx, cz + dz)] = true


# ------------------------------------------------------------------ #
#  Drawing — entry point                                               #
# ------------------------------------------------------------------ #

func _draw() -> void:
	var vp: Rect2 = get_viewport_rect()
	_draw_day_night_arc(vp)
	_draw_bottom_panel(vp)
	if _toast_alpha > 0.0:
		_draw_toast(vp)


# ------------------------------------------------------------------ #
#  Day / night arc (top-centre)                                        #
# ------------------------------------------------------------------ #

func _draw_day_night_arc(vp: Rect2) -> void:
	var cx: float = vp.size.x / 2.0
	var cy: float = ARC_RADIUS + 18.0

	var t:          float = WorldClock.time_of_day
	var body_angle: float = PI * 0.5 - t * TAU

	# Sky colour and star alpha driven continuously by sun elevation
	var sun_elev: float = clampf(-sin(body_angle), 0.0, 1.0)
	var sky_col:  Color = Color(0.04, 0.06, 0.18, 0.92).lerp(
		Color(0.22, 0.52, 0.82, 0.90), sun_elev)

	var panel_rect: Rect2 = Rect2(cx - ARC_PANEL_W / 2.0, 0.0, ARC_PANEL_W, ARC_PANEL_H)
	draw_rect(panel_rect, sky_col)

	# Stars fade out as the sun rises, in as it sets
	var star_a: float = clampf(1.0 - sun_elev * 3.0, 0.0, 1.0)
	if star_a > 0.0:
		for star: Vector2 in _star_offsets:
			draw_circle(Vector2(cx + star.x, cy + star.y), 1.2, Color(0.85, 0.88, 1.0, 0.7 * star_a))

	var arc_col: Color = Color(0.25, 0.30, 0.55, 0.50).lerp(Color(0.55, 0.65, 0.78, 0.50), sun_elev)
	draw_arc(Vector2(cx, cy), ARC_RADIUS, PI, TAU, 48, arc_col, 1.5)
	draw_line(
		Vector2(cx - ARC_RADIUS - 2.0, cy),
		Vector2(cx + ARC_RADIUS + 2.0, cy),
		Color(0.45, 0.55, 0.65, 0.45), 1.0
	)

	# Bodies are drawn by _arc_bodies child (clipped by _arc_clip.clip_children)
	draw_rect(panel_rect, Color(0.30, 0.40, 0.55, 0.55), false, 1.0)


# Draws sun and moon on _arc_bodies — called via its draw signal.
# _arc_clip.clip_children = CLIP_CHILDREN_ONLY ensures these are masked to the panel rect.
func _on_arc_bodies_draw() -> void:
	var cx: float = ARC_PANEL_W * 0.5
	var cy: float = ARC_RADIUS + 18.0

	var t:          float = WorldClock.time_of_day
	var body_angle: float = PI * 0.5 - t * TAU
	var moon_angle: float = body_angle + PI

	var sun_pos:  Vector2 = Vector2(cx + cos(body_angle) * ARC_RADIUS, cy + sin(body_angle) * ARC_RADIUS)
	_arc_bodies.draw_circle(sun_pos, 11.0, Color(1.0, 0.85, 0.30, 0.25))
	_arc_bodies.draw_circle(sun_pos,  7.0, Color(1.0, 0.88, 0.20))

	var moon_pos: Vector2 = Vector2(cx + cos(moon_angle) * ARC_RADIUS, cy + sin(moon_angle) * ARC_RADIUS)
	_arc_bodies.draw_circle(moon_pos, 9.0, Color(0.70, 0.78, 1.0, 0.20))
	_arc_bodies.draw_circle(moon_pos, 6.0, Color(0.86, 0.90, 1.0))


# ------------------------------------------------------------------ #
#  Bottom panel — wood console spanning full screen width              #
# ------------------------------------------------------------------ #

func _draw_bottom_panel(vp: Rect2) -> void:
	var full_y:   float = vp.size.y - BOTTOM_PANEL_H
	# side_w uses 3× PANEL_PAD so both minimap and resource bars have
	# generous right/left inner margins in addition to the outer edge pad.
	var side_w:   float = MAP_SIZE + PANEL_PAD * 3.0  # 190 px

	# Shared tile grid origin — all three sections align to this
	var tile_org: Vector2 = Vector2(0.0, full_y)

	# ── Left station (minimap) — full height ──────────────────────────
	var left_rect: Rect2 = Rect2(0.0, full_y, side_w, BOTTOM_PANEL_H)
	_draw_wood_panel(left_rect, tile_org)
	_draw_rope_border(0.0, full_y, side_w)

	# ── Right station (resources) — full height ───────────────────────
	var right_x:    float = vp.size.x - side_w
	var right_rect: Rect2 = Rect2(right_x, full_y, side_w, BOTTOM_PANEL_H)
	_draw_wood_panel(right_rect, tile_org)
	_draw_rope_border(right_x, full_y, side_w)

	# ── Centre console (cargo) — half height, locked to bottom ───────
	var ctr_x:    float = side_w
	var ctr_w:    float = vp.size.x - side_w * 2.0
	var ctr_y:    float = vp.size.y - CENTER_PANEL_H
	var ctr_rect: Rect2 = Rect2(ctr_x, ctr_y, ctr_w, CENTER_PANEL_H)
	_draw_wood_panel(ctr_rect, tile_org)
	_draw_rope_border(ctr_x, ctr_y, ctr_w)

	# Vertical rope borders at the inner edges of the side stations
	var gap_h: float = ctr_y - full_y
	_draw_rope_border_vert(side_w - ROPE_BORDER_H, full_y, gap_h)
	_draw_rope_border_vert(right_x,               full_y, gap_h)

	# Corner pieces — atlas piece is └; flip flags derive the other three orientations.
	# Bottom corners (vertical rope meets cargo horizontal rope)
	_draw_rope_corner(side_w - ROPE_BORDER_H, ctr_y,  false, false)  # └  bottom-left
	_draw_rope_corner(right_x,               ctr_y,  true,  false)  # ┘  bottom-right
	# Top corners (vertical rope meets side-station horizontal rope)
	_draw_rope_corner(side_w - ROPE_BORDER_H, full_y, true,  true)   # ┐  top-left
	_draw_rope_corner(right_x,               full_y, false, true)    # ┌  top-right

	# ── Station contents ──────────────────────────────────────────────
	# Content starts below the rope border with extra top breathing room.
	var content_top: float = full_y + ROPE_BORDER_H + PANEL_PAD + 4.0

	_map_rect = Rect2(PANEL_PAD, content_top, MAP_SIZE, MAP_SIZE)
	_draw_minimap()

	# Resources: PANEL_PAD * 2 from panel left edge for extra left margin
	_draw_resource_bars(right_x + PANEL_PAD * 2.0, content_top, MAP_SIZE, MAP_SIZE)

	_draw_cargo(ctr_rect)


# ------------------------------------------------------------------ #
#  Wood panel tiling                                                   #
# ------------------------------------------------------------------ #

# Tiles the chosen atlas tile across panel_rect in a staggered (brick) pattern.
# tile_origin anchors the shared grid so multiple adjacent panels stay aligned.
# Odd rows are offset by half a tile so vertical seams never line up.
func _draw_wood_panel(panel_rect: Rect2, tile_origin: Vector2 = Vector2.ZERO) -> void:
	if _wood_tex == null:
		draw_rect(panel_rect, Color(0.22, 0.15, 0.08, 0.92))
		return

	# Which rows of the shared grid are visible inside this panel?
	var first_row: int = int(floor((panel_rect.position.y - tile_origin.y) / WOOD_TILE_DISPLAY_H))
	var last_row:  int = int(ceil( (panel_rect.end.y      - tile_origin.y) / WOOD_TILE_DISPLAY_H))

	for row: int in range(first_row, last_row):
		var stagger: float   = (WOOD_TILE_DISPLAY_W * 0.5) if (row % 2 == 1) else 0.0
		var first_col: int   = int(floor((panel_rect.position.x - tile_origin.x + stagger) / WOOD_TILE_DISPLAY_W)) - 1
		var last_col:  int   = int(ceil( (panel_rect.end.x      - tile_origin.x + stagger) / WOOD_TILE_DISPLAY_W)) + 1

		for col: int in range(first_col, last_col):
			var dx: float = tile_origin.x + float(col) * WOOD_TILE_DISPLAY_W - stagger
			var dy: float = tile_origin.y + float(row) * WOOD_TILE_DISPLAY_H

			# Clamp both edges to stay inside the panel
			var dest_x1: float = maxf(dx,                       panel_rect.position.x)
			var dest_x2: float = minf(dx + WOOD_TILE_DISPLAY_W, panel_rect.end.x)
			var dest_y1: float = maxf(dy,                       panel_rect.position.y)
			var dest_y2: float = minf(dy + WOOD_TILE_DISPLAY_H, panel_rect.end.y)

			if dest_x2 <= dest_x1 or dest_y2 <= dest_y1:
				continue

			var dw: float = dest_x2 - dest_x1
			var dh: float = dest_y2 - dest_y1

			var src_ox: float = (dest_x1 - dx) * WOOD_TILE_SRC / WOOD_TILE_DISPLAY_W
			var src_oy: float = (dest_y1 - dy) * WOOD_TILE_SRC / WOOD_TILE_DISPLAY_H
			var sw: float     = dw * WOOD_TILE_SRC / WOOD_TILE_DISPLAY_W
			var sh: float     = dh * WOOD_TILE_SRC / WOOD_TILE_DISPLAY_H

			draw_texture_rect_region(
				_wood_tex,
				Rect2(dest_x1, dest_y1, dw, dh),
				Rect2(WOOD_TILE_ORIGIN.x + src_ox, WOOD_TILE_ORIGIN.y + src_oy, sw, sh)
			)

	# Uniform darkening so text stays readable
	draw_rect(panel_rect, Color(0.0, 0.0, 0.0, 0.40))


# ------------------------------------------------------------------ #
#  Minimap (drawn inside bottom panel)                                 #
# ------------------------------------------------------------------ #

func _draw_minimap() -> void:
	draw_rect(_map_rect, Color(0.05, 0.10, 0.18, 0.92))
	draw_rect(_map_rect.grow(-2), Color(0.08, 0.20, 0.40, 0.60))

	var total_cells: int = int(WORLD_HALF * 2.0 / CELL_SIZE)
	for cx: int in range(total_cells):
		for cz: int in range(total_cells):
			if not _explored.has(Vector2i(cx, cz)):
				var cell_world: Vector2 = Vector2(
					cx * CELL_SIZE - WORLD_HALF,
					cz * CELL_SIZE - WORLD_HALF
				)
				var cell_px:      Vector2 = _world_to_map(cell_world)
				var cell_size_px: float   = MAP_SIZE / total_cells
				draw_rect(
					Rect2(cell_px, Vector2(cell_size_px, cell_size_px)),
					Color(0.02, 0.04, 0.08, 0.88)
				)

	for island_pos: Vector2 in _islands:
		var mp: Vector2 = _world_to_map(island_pos)
		draw_circle(mp, 4.0, Color(0.25, 0.75, 0.30))
		draw_arc(mp, 4.0, 0.0, TAU, 12, Color(0.5, 1.0, 0.5), 1.0)

	if _boat:
		var bpx: Vector2 = _world_to_map(Vector2(_boat.global_position.x, _boat.global_position.z))
		draw_circle(bpx, 4.0, Color(1.0, 0.9, 0.2))

	_draw_inset_bevel(_map_rect)


func _world_to_map(world_xz: Vector2) -> Vector2:
	var t: Vector2 = (world_xz + Vector2(WORLD_HALF, WORLD_HALF)) / (WORLD_HALF * 2.0)
	return _map_rect.position + t * _map_rect.size


# ------------------------------------------------------------------ #
#  Resource bars (drawn inside bottom panel)                           #
# ------------------------------------------------------------------ #

func _draw_resource_bars(x: float, y: float, w: float, h: float) -> void:
	var gap:   float = 8.0
	var bar_h: float = (h - gap) / 2.0

	_draw_resource_bar(Rect2(x, y,              w, bar_h),
		"FOOD",  VoyageResources.food_pct(),  Color(0.82, 0.38, 0.08))
	_draw_resource_bar(Rect2(x, y + bar_h + gap, w, bar_h),
		"WATER", VoyageResources.water_pct(), Color(0.18, 0.52, 0.88))


func _draw_resource_bar(inset: Rect2, res_label: String, pct: float, fill_color: Color) -> void:
	var font:    Font = ThemeDB.fallback_font
	var font_sz: int  = 11

	# Carved inset
	draw_rect(inset, Color(0.06, 0.04, 0.03, 0.90))
	_draw_inset_bevel(inset)

	# Label
	draw_string(font,
		Vector2(inset.position.x + 6.0, inset.position.y + font_sz + 3.0),
		res_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz,
		Color(0.78, 0.68, 0.48))

	# Bar track
	var bm:       float = 5.0
	var bar_rect: Rect2 = Rect2(
		inset.position.x + bm,
		inset.position.y + font_sz + 9.0,
		inset.size.x - bm * 2.0,
		inset.size.y - font_sz - 15.0
	)
	draw_rect(bar_rect, Color(0.04, 0.03, 0.02, 0.90))

	# Fill — bleeds to red below 30 %
	if pct > 0.0:
		var col: Color = fill_color
		if pct < 0.30:
			col = fill_color.lerp(Color(0.90, 0.10, 0.05), (0.30 - pct) / 0.30)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * pct, bar_rect.size.y)), col)

	draw_rect(bar_rect, Color(0.30, 0.25, 0.15, 0.60), false, 1.0)


# ------------------------------------------------------------------ #
#  Rope border — horizontal rope tile along the top of a panel        #
# ------------------------------------------------------------------ #

func _draw_rope_border(x: float, y: float, w: float) -> void:
	if _rope_tex == null:
		# Fallback: warm line
		draw_line(Vector2(x, y + ROPE_BORDER_H * 0.5),
			Vector2(x + w, y + ROPE_BORDER_H * 0.5),
			Color(0.65, 0.50, 0.28, 0.80), ROPE_BORDER_H)
		return

	# Drop shadow — drawn behind the rope
	draw_rect(Rect2(x + 1.0, y + 2.0, w, ROPE_BORDER_H), Color(0.0, 0.0, 0.0, 0.35))

	var cols: int = int(ceil(w / ROPE_TILE_W)) + 1
	for col: int in range(cols):
		var dx: float     = x + float(col) * ROPE_TILE_W
		var dest_x1: float = maxf(dx, x)
		var dest_x2: float = minf(dx + ROPE_TILE_W, x + w)
		if dest_x2 <= dest_x1:
			continue
		var dw:    float = dest_x2 - dest_x1
		var src_ox: float = (dest_x1 - dx) / ROPE_TILE_W * ROPE_SRC.size.x
		var src_w:  float = dw / ROPE_TILE_W * ROPE_SRC.size.x
		draw_texture_rect_region(
			_rope_tex,
			Rect2(dest_x1, y, dw, ROPE_BORDER_H),
			Rect2(ROPE_SRC.position.x + src_ox, ROPE_SRC.position.y, src_w, ROPE_SRC.size.y)
		)


# Vertical variant — rotates the drawing context 90° so the same horizontal
# rope tile runs downward.  Math: with pivot (x, y_top) and rotation PI/2,
#   screen = (x - local.y,  y_top + local.x)
# Drawing Rect2(lx, -ROPE_BORDER_H, dw, ROPE_BORDER_H) in local space maps to
# a vertical stripe of width ROPE_BORDER_H at screen-x = x..x+ROPE_BORDER_H.
func _draw_rope_border_vert(x: float, y_top: float, h: float) -> void:
	if _rope_tex == null:
		draw_line(Vector2(x + ROPE_BORDER_H * 0.5, y_top),
			Vector2(x + ROPE_BORDER_H * 0.5, y_top + h),
			Color(0.65, 0.50, 0.28, 0.80), ROPE_BORDER_H)
		return

	# Drop shadow — drawn behind the rope (in screen space, before transform)
	draw_rect(Rect2(x + 0, y_top + 2.0, ROPE_BORDER_H, h), Color(0.0, 0.0, 0.0, 0.25))

	draw_set_transform(Vector2(x, y_top), PI / 2.0, Vector2.ONE)

	var cols: int = int(ceil(h / ROPE_TILE_W)) + 1
	for col: int in range(cols):
		var lx: float      = float(col) * ROPE_TILE_W
		var dest_x1: float = maxf(lx, 0.0)
		var dest_x2: float = minf(lx + ROPE_TILE_W, h)
		if dest_x2 <= dest_x1:
			continue
		var dw:     float = dest_x2 - dest_x1
		var src_ox: float = (dest_x1 - lx) / ROPE_TILE_W * ROPE_SRC.size.x
		var src_w:  float = dw / ROPE_TILE_W * ROPE_SRC.size.x
		draw_texture_rect_region(
			_rope_tex,
			Rect2(dest_x1, -ROPE_BORDER_H, dw, ROPE_BORDER_H),
			Rect2(ROPE_SRC.position.x + src_ox, ROPE_SRC.position.y, src_w, ROPE_SRC.size.y)
		)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Corner piece — atlas tile is └; flip_h mirrors it to ┘, flip_v to ┌, both to ┐.
# Display size matches ROPE_BORDER_H × ROPE_BORDER_H.
func _draw_rope_corner(x: float, y: float, flip_h: bool, flip_v: bool = false) -> void:
	if _rope_tex == null:
		return
	var s: float       = ROPE_BORDER_H
	# Drop shadow — in screen space before any transform
	draw_rect(Rect2(x + 0, y + 2.0, s, s), Color(0.0, 0.0, 0.0, 0.25))
	var pivot_x: float = x + s if flip_h else x
	var pivot_y: float = y + s if flip_v else y
	var scale_x: float = -1.0  if flip_h else 1.0
	var scale_y: float = -1.0  if flip_v else 1.0
	draw_set_transform(Vector2(pivot_x, pivot_y), 0.0, Vector2(scale_x, scale_y))
	draw_texture_rect_region(_rope_tex, Rect2(0.0, 0.0, s, s), ROPE_CORNER_SRC)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ #
#  Cargo console (centre, lower panel)                                #
# ------------------------------------------------------------------ #

func _draw_cargo(area: Rect2) -> void:
	var font:    Font = ThemeDB.fallback_font
	var font_sz: int  = 13

	# One solid inset — content starts below the rope border
	var inset: Rect2 = Rect2(
		area.position.x + PANEL_PAD,
		area.position.y + ROPE_BORDER_H + 8.0,
		area.size.x - PANEL_PAD * 2.0,
		area.size.y - ROPE_BORDER_H - PANEL_PAD - 4.0
	)
	draw_rect(inset, Color(0.06, 0.04, 0.03, 0.92))
	_draw_inset_bevel(inset)

	# "CARGO" label inside the inset
	draw_string(font,
		Vector2(inset.position.x + 8.0, inset.position.y + font_sz + 4.0),
		"CARGO", HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz,
		Color(0.78, 0.68, 0.48))

	# Empty slot row — square insets centred inside the inset
	var slot_h:   float = inset.size.y - float(font_sz) - 16.0
	var slot_w:   float = slot_h
	var slot_gap: float = 6.0
	var n:        int   = 8
	var total_w:  float = float(n) * slot_w + float(n - 1) * slot_gap
	var start_x:  float = inset.position.x + (inset.size.x - total_w) / 2.0
	var slot_y:   float = inset.position.y + float(font_sz) + 8.0

	for i: int in range(n):
		var sr: Rect2 = Rect2(start_x + float(i) * (slot_w + slot_gap), slot_y, slot_w, slot_h)
		draw_rect(sr, Color(0.04, 0.03, 0.02, 0.85))
		_draw_inset_bevel(sr)


# ------------------------------------------------------------------ #
#  Inset bevel — dark top/left shadow, warm bottom/right highlight    #
# ------------------------------------------------------------------ #

func _draw_inset_bevel(rect: Rect2) -> void:
	var shadow:    Color = Color(0.0,  0.0,  0.0,  0.70)
	var highlight: Color = Color(0.65, 0.50, 0.28, 0.45)
	var w: float = 2.0

	var tl: Vector2 = rect.position
	var tr: Vector2 = Vector2(rect.end.x,      rect.position.y)
	var bl: Vector2 = Vector2(rect.position.x, rect.end.y)
	var br: Vector2 = rect.end

	draw_line(tl, tr, shadow,    w)  # top    — in shadow
	draw_line(tl, bl, shadow,    w)  # left   — in shadow
	draw_line(bl, br, highlight, w)  # bottom — catches light
	draw_line(tr, br, highlight, w)  # right  — catches light


# ------------------------------------------------------------------ #
#  Discovery toast — drawn entirely in _draw(), no child Controls     #
# ------------------------------------------------------------------ #

func _draw_toast(vp: Rect2) -> void:
	var font:    Font = ThemeDB.fallback_font
	var tx: float = vp.size.x * 0.5 - TOAST_W * 0.5
	var ty: float = ARC_PANEL_H + 8.0

	# Soft drop shadow — 3 layers at increasing offsets and decreasing opacity
	if _parchment_tex != null:
		for layer: Vector3 in TOAST_SHADOW_LAYERS:
			var sa: float = layer.z * _toast_alpha
			draw_texture_rect(
				_parchment_tex,
				Rect2(tx + layer.x, ty + layer.y, TOAST_W, TOAST_H),
				false,
				Color(0.0, 0.0, 0.0, sa)
			)
		# Parchment background
		draw_texture_rect(
			_parchment_tex,
			Rect2(tx, ty, TOAST_W, TOAST_H),
			false,
			Color(1.0, 1.0, 1.0, _toast_alpha)
		)
	else:
		# Fallback if texture failed to load
		draw_rect(Rect2(tx, ty, TOAST_W, TOAST_H), Color(0.92, 0.84, 0.65, _toast_alpha))

	# Island name — large, centred on scroll
	var name_sz: int  = 22
	var name_y:  float = ty + TOAST_H * 0.26
	draw_string(font,
		Vector2(tx, name_y),
		_toast_name_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		TOAST_W,
		name_sz,
		Color(0.22, 0.12, 0.05, _toast_alpha)
	)

	# Resource icons — row of up to 6, centred on the scroll, below island name.
	const ICON_DISPLAY_W: float = 32.0   # matches sheet cell width
	const ICON_DISPLAY_H: float = 34.0   # matches sheet cell height
	const ICON_GAP:       float = 8.0
	if not _toast_res_icons.is_empty():
		var n: int       = _toast_res_icons.size()
		var row_w: float = float(n) * ICON_DISPLAY_W + float(n - 1) * ICON_GAP
		var ix: float    = tx + (TOAST_W - row_w) * 0.5
		var iy: float    = name_y + float(name_sz) + 14.0
		for key: String in _toast_res_icons:
			var dest: Rect2 = Rect2(ix, iy, ICON_DISPLAY_W, ICON_DISPLAY_H)
			var at: AtlasTexture = _icon_atlas.get(key, null) as AtlasTexture
			if at != null:
				draw_texture_rect(at, dest, false, Color(1.0, 1.0, 1.0, _toast_alpha))
			else:
				# Placeholder for future biome sheets
				draw_rect(dest, Color(0.55, 0.48, 0.38, _toast_alpha * 0.6))
				draw_rect(dest, Color(0.30, 0.22, 0.12, _toast_alpha * 0.5), false, 1.5)
			ix += ICON_DISPLAY_W + ICON_GAP

	# "tap to dismiss" hint — bottom of scroll
	var hint_sz: int   = 12
	var hint_y:  float = ty + TOAST_H - 38.0
	draw_string(font,
		Vector2(tx, hint_y),
		"Tap To Dismiss",
		HORIZONTAL_ALIGNMENT_CENTER,
		TOAST_W,
		hint_sz,
		Color(0.40, 0.28, 0.15, _toast_alpha * 0.70)
	)


func _set_toast_alpha(a: float) -> void:
	_toast_alpha = a


func _on_island_discovered(p_island_name: String, world_pos: Vector2, res: Dictionary) -> void:
	_islands.append(world_pos)
	_toast_name_text = p_island_name

	# Sort resources by amount descending, take top 6 by dominant-zone weighting.
	var pairs: Array = []
	for key: String in res.keys():
		pairs.append([key, res[key]])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	_toast_res_icons.clear()
	for i: int in range(mini(6, pairs.size())):
		_toast_res_icons.append(pairs[i][0])

	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_method(_set_toast_alpha, _toast_alpha, 1.0, 0.4).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(6.0)
	_toast_tween.tween_method(_set_toast_alpha, 1.0, 0.0, 0.5).set_ease(Tween.EASE_IN)


func _input(event: InputEvent) -> void:
	if _toast_alpha <= 0.0:
		return
	var pressed: bool = false
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		pressed = mb.pressed
	elif event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		pressed = touch.pressed
	if not pressed:
		return
	var vp: Rect2 = get_viewport_rect()
	var toast_rect: Rect2 = Rect2(
		vp.size.x * 0.5 - TOAST_W * 0.5,
		ARC_PANEL_H + 8.0,
		TOAST_W,
		TOAST_H
	)
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
	if toast_rect.has_point(pos):
		get_viewport().set_input_as_handled()
		_dismiss_toast()


func _dismiss_toast() -> void:
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_method(_set_toast_alpha, _toast_alpha, 0.0, 0.35).set_ease(Tween.EASE_IN)
