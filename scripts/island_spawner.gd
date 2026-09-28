extends Node3D

const IslandScript = preload("res://scripts/island.gd")

const NAME_POOL: Array[String] = [
	"Torchwood Bay",
	"Crow's Landing",
	"Serpent Cove",
	"Dead Man's Spit",
	"Pelican Rock",
	"The Emerald Bank",
	"Storm's Rest",
	"Amber Key",
	"Whistler's Reef",
	"Black Coral Cay",
	"Devil's Anvil",
	"Mariner's Folly",
	"Cape Solitude",
	"Ironwood Shoal",
	"The Shattered Crown",
	"Galleon's Grave",
	"Saltmere Isle",
	"Fog Witch Point",
	"Starfall Atoll",
	"Crimson Ledge",
	"Old Bones Harbour",
	"Windlass Cay",
	"The Lonely Pinnacle",
	"Driftwood Passage",
	"Brine Witch Rock",
]

const ISLAND_COUNT_MIN  := 6
const ISLAND_COUNT_MAX  := 10
const SPAWN_MIN         := -460.0
const SPAWN_MAX         :=  460.0
const MIN_SPACING       := 280.0
const MIN_CENTER_DIST   := 80.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Home island — far enough that the boat spawns in open water (~60 units from shore)
	var home_pos := Vector2(0.0, 160.0)
	_spawn_home_island(home_pos)
	var placed: Array[Vector2] = [home_pos]

	var count := rng.randi_range(ISLAND_COUNT_MIN, ISLAND_COUNT_MAX)
	var names := NAME_POOL.duplicate()
	names.shuffle()

	var attempts := 0
	while placed.size() <= count and attempts < 1000:
		attempts += 1
		var candidate := Vector2(
			rng.randf_range(SPAWN_MIN, SPAWN_MAX),
			rng.randf_range(SPAWN_MIN, SPAWN_MAX)
		)

		if candidate.length() < MIN_CENTER_DIST:
			continue

		var too_close := false
		for p in placed:
			if candidate.distance_to(p) < MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue

		placed.append(candidate)
		_spawn_island(candidate, names[(placed.size() - 2) % names.size()], rng)

	if placed.size() - 1 < ISLAND_COUNT_MIN:
		push_warning("IslandSpawner: only placed %d/%d islands" % [placed.size() - 1, count])

	call_deferred("_build_shore_map")


# ── Shore proximity map ────────────────────────────────────────────────────── #
# Paints a 256×256 texture that the water shader and beach skirt shader sample
# to know how close each ocean fragment is to an island shore.
#
# Each island is sampled in two zones:
#   • Inside the island — the actual height function determines the land boundary.
#     This makes the painted shoreline follow the real organic coastline rather
#     than the nominal circular radius.
#   • Outside the island — a smooth circular gradient falls from 0.65 at the
#     nominal radius to 0.0 at (radius + BEACH_WIDTH_WU).
#     Capped at 0.65 so the water shader's foam band (threshold 0.68) only
#     fires at the organic inner coastline, not this circular gradient ring.

const _SHORE_TEX_SIZE:   int   = 256
const _SHORE_WORLD_HALF: float = 500.0
# Width of the shallow-water gradient in world units measured outward from the
# island's nominal radius.  Kept at 6wu so turquoise extends nicely; the beach
# skirt shader uses its own thresholds to show only the inner ~3wu as sand.
const _BEACH_WIDTH_WU:   float = 6.0


func _build_shore_map() -> void:
	var ocean: MeshInstance3D = get_node_or_null("../Ocean") as MeshInstance3D
	if ocean == null:
		push_warning("IslandSpawner: Ocean node not found — shore map skipped")
		return
	var water_mat: ShaderMaterial = ocean.get_active_material(0) as ShaderMaterial
	if water_mat == null:
		push_warning("IslandSpawner: water ShaderMaterial not found")
		return

	var img: Image = Image.create(_SHORE_TEX_SIZE, _SHORE_TEX_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var data: PackedByteArray = img.get_data()

	for child: Node in get_children():
		var island: Island = child as Island
		if island == null:
			continue
		_paint_island_shore(data, island)

	img.set_data(_SHORE_TEX_SIZE, _SHORE_TEX_SIZE, false, Image.FORMAT_RGBA8, data)
	var tex: ImageTexture = ImageTexture.create_from_image(img)

	# Water shader — shallow colour and foam
	water_mat.set_shader_parameter("shore_tex", tex)


func _paint_island_shore(data: PackedByteArray, island: Island) -> void:
	var size:       int   = _SHORE_TEX_SIZE
	var world_half: float = _SHORE_WORLD_HALF
	# World units per texel
	var wu_per_px:  float = (world_half * 2.0) / float(size)

	var world_xz := Vector2(island.global_position.x, island.global_position.z)
	var radius:     float = island.base_radius
	var r_px:       float = radius / wu_per_px
	var beach_px:   float = _BEACH_WIDTH_WU / wu_per_px
	var search:     int   = int(r_px + beach_px) + 2

	var cx: int = int((world_xz.x + world_half) / (world_half * 2.0) * float(size))
	var cy: int = int((world_xz.y + world_half) / (world_half * 2.0) * float(size))

	for dy: int in range(-search, search + 1):
		for dx: int in range(-search, search + 1):
			var px: int = cx + dx
			var py: int = cy + dy
			if px < 0 or px >= size or py < 0 or py >= size:
				continue

			var dist: float = sqrt(float(dx * dx + dy * dy))
			var proximity: float

			if dist <= r_px:
				# Inside the nominal radius: query the actual height function so the
				# painted boundary follows the real organic coastline.
				var wx: float = (float(px) / float(size)) * (world_half * 2.0) - world_half
				var wz: float = (float(py) / float(size)) * (world_half * 2.0) - world_half
				var h: float = island.get_height_at(wx - world_xz.x, wz - world_xz.y)
				proximity = 1.0 if h > 0.05 else 0.0
			else:
				# Outside the nominal radius: smooth circular falloff into open ocean.
				# Capped at 0.65 so the water shader's foam band (threshold 0.68)
				# only fires at the organic inner coastline, not this circular ring.
				proximity = maxf(0.0, 1.0 - (dist - r_px) / beach_px) * 0.65

			if proximity <= 0.0:
				continue

			var val: int = int(proximity * 255.0)
			var idx: int = (py * size + px) * 4
			# Max-blend: keep highest proximity where islands overlap
			if val > int(data[idx]):
				data[idx + 0] = val
				data[idx + 1] = val
				data[idx + 2] = val
				data[idx + 3] = 255


func _spawn_home_island(pos2d: Vector2) -> void:
	var island := IslandScript.new()
	island.island_name      = "Sawyer's Rest"
	island.position         = Vector3(pos2d.x, 0.0, pos2d.y)
	island.island_type      = Island.IslandType.TROPICAL
	island.base_radius      = 80.0
	island.discovery_radius = island.base_radius * 1.3  # shore reaches ~base_radius from centre
	island.num_trees        = 45
	add_child(island)
	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud:
		island.island_discovered.connect(hud._on_island_discovered)


func _spawn_island(pos2d: Vector2, island_name: String, rng: RandomNumberGenerator) -> void:
	var island := IslandScript.new()
	island.island_name = island_name
	island.position    = Vector3(pos2d.x, 0.0, pos2d.y)

	# Type first — radius and tree count vary by type
	var itype: int = rng.randi_range(0, 3)
	island.island_type = itype as Island.IslandType

	var radius: float
	match itype:
		0: radius = rng.randf_range( 50.0, 180.0)  # TROPICAL  — big lush islands
		1: radius = rng.randf_range( 35.0, 120.0)  # VOLCANIC  — compact but tall
		2: radius = rng.randf_range( 80.0, 220.0)  # ATOLL     — wide and flat
		3: radius = rng.randf_range( 70.0, 180.0)  # HIGHLAND  — medium to large
		_: radius = rng.randf_range( 50.0, 120.0)
	island.base_radius      = radius
	island.discovery_radius = radius * 1.3  # shore reaches ~base_radius from centre

	# Tree count scales with island area; caps prevent load() stalls on giant islands
	match itype:
		0: island.num_trees = min(int(radius * rng.randf_range(1.4, 2.2)), 120)  # TROPICAL
		1: island.num_trees = min(int(radius * rng.randf_range(0.3, 0.6)),  30)  # VOLCANIC
		2: island.num_trees = min(int(radius * rng.randf_range(0.5, 0.9)),  60)  # ATOLL
		3: island.num_trees = min(int(radius * rng.randf_range(1.8, 3.0)), 150)  # HIGHLAND
		_: island.num_trees = min(int(radius * rng.randf_range(1.0, 1.5)), 100)

	add_child(island)

	# Connect discovery signal to HUD after the island is in the tree
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		island.island_discovered.connect(hud._on_island_discovered)
