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
