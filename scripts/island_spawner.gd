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

const ISLAND_COUNT_MIN  := 15
const ISLAND_COUNT_MAX  := 25
const SPAWN_MIN         := -475.0
const SPAWN_MAX         :=  475.0
const MIN_SPACING       := 80.0
const MIN_CENTER_DIST   := 50.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var count := rng.randi_range(ISLAND_COUNT_MIN, ISLAND_COUNT_MAX)
	var placed: Array[Vector2] = []

	var names := NAME_POOL.duplicate()
	names.shuffle()

	var attempts := 0
	while placed.size() < count and attempts < 1000:
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
		_spawn_island(candidate, names[placed.size() - 1], rng)

	if placed.size() < ISLAND_COUNT_MIN:
		push_warning("IslandSpawner: only placed %d/%d islands" % [placed.size(), count])


func _spawn_island(pos2d: Vector2, island_name: String, rng: RandomNumberGenerator) -> void:
	var island := IslandScript.new()
	island.island_name = island_name
	island.base_radius = rng.randf_range(6.0, 15.0)
	island.num_trees = rng.randi_range(4, 9)
	island.discovery_radius = 60.0
	island.position = Vector3(pos2d.x, 0.0, pos2d.y)
	add_child(island)

	# Connect discovery signal to HUD after the island is in the tree
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		island.island_discovered.connect(hud._on_island_discovered)
