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

const ISLAND_COUNT_MIN: int   = 6
const ISLAND_COUNT_MAX: int   = 10
const WORLD_HALF:       float = 500.0
## Coastlines reach roughly this multiple of base_radius (see Island._sample_point).
const COAST_REACH:      float = 1.25
## Minimum open water between two coastlines, or between a coast and the boat's spawn.
const CHANNEL_WIDTH:    float = 40.0
const EDGE_MARGIN:      float = 15.0
const MIN_RADIUS:       float = 30.0
const HOME_POS:         Vector2 = Vector2(0.0, 160.0)
const HOME_RADIUS:      float = 80.0

## 0 = roll a new world on start.  Set it (e.g. from a save file) to regenerate
## exactly the same world — every island's shape is derived from this + its name.
@export var world_seed: int = 0


func _ready() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if world_seed == 0:
		rng.randomize()
		world_seed = maxi(1, rng.randi())
	rng.seed = world_seed
	print("IslandSpawner: world seed ", world_seed)

	var boat: Node3D = get_tree().get_first_node_in_group("boat") as Node3D
	var boat_xz: Vector2 = Vector2(0.0, 20.0)
	if boat != null:
		boat_xz = Vector2(boat.global_position.x, boat.global_position.z)

	# Home island builds synchronously so it's on screen from the first frame.
	_spawn_island(HOME_POS, "Sawyer's Rest", Island.IslandType.TROPICAL, HOME_RADIUS, 45, false)
	var placed_pos: Array[Vector2] = [HOME_POS]
	var placed_r:   Array[float]   = [HOME_RADIUS]

	var names: Array[String] = NAME_POOL.duplicate()
	for i: int in range(names.size() - 1, 0, -1):   # Fisher–Yates with the world RNG
		var j: int = rng.randi_range(0, i)
		var tmp: String = names[i]
		names[i] = names[j]
		names[j] = tmp

	# Roll every island first, then place the biggest first — big islands are
	# the hardest to fit, small ones fill the gaps.
	var count: int = rng.randi_range(ISLAND_COUNT_MIN, ISLAND_COUNT_MAX)
	var specs: Array[Vector2] = []   # x = type, y = radius
	for i: int in range(count):
		var itype: int = rng.randi_range(0, 3)
		specs.append(Vector2(float(itype), _roll_radius(itype, rng)))
	specs.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y > b.y)

	var spawned: int = 0
	for spec: Vector2 in specs:
		var itype:  int   = int(spec.x)
		var radius: float = spec.y
		var pos:    Vector2 = Vector2.INF
		# Shrink an island that won't fit rather than dropping it outright.
		while radius >= MIN_RADIUS:
			pos = _find_spot(radius, placed_pos, placed_r, boat_xz, rng)
			if pos.is_finite():
				break
			radius *= 0.85
		if not pos.is_finite():
			continue
		placed_pos.append(pos)
		placed_r.append(radius)
		_spawn_island(pos, names[spawned % names.size()], itype as Island.IslandType,
				radius, _roll_trees(itype, radius, rng), true)
		spawned += 1

	if spawned < ISLAND_COUNT_MIN:
		push_warning("IslandSpawner: only placed %d/%d islands" % [spawned, count])


func _roll_radius(itype: int, rng: RandomNumberGenerator) -> float:
	match itype:
		0: return rng.randf_range( 50.0, 180.0)  # TROPICAL  — big lush islands
		1: return rng.randf_range( 35.0, 120.0)  # VOLCANIC  — compact but tall
		2: return rng.randf_range( 80.0, 220.0)  # ATOLL     — wide and flat
		3: return rng.randf_range( 70.0, 180.0)  # HIGHLAND  — medium to large
	return rng.randf_range(50.0, 120.0)


# Tree count scales with island area; caps keep generation time bounded.
func _roll_trees(itype: int, radius: float, rng: RandomNumberGenerator) -> int:
	match itype:
		0: return mini(int(radius * rng.randf_range(1.4, 2.2)), 120)  # TROPICAL
		1: return mini(int(radius * rng.randf_range(0.3, 0.6)),  30)  # VOLCANIC
		2: return mini(int(radius * rng.randf_range(0.5, 0.9)),  60)  # ATOLL
		3: return mini(int(radius * rng.randf_range(1.8, 3.0)), 150)  # HIGHLAND
	return mini(int(radius * rng.randf_range(1.0, 1.5)), 100)


## Returns a centre whose coastline stays inside the world, clear of the boat's
## spawn point, and a full channel away from every other coastline — or
## Vector2.INF if no spot was found.
func _find_spot(radius: float, placed_pos: Array[Vector2], placed_r: Array[float],
		boat_xz: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var reach: float = radius * COAST_REACH
	var lim:   float = WORLD_HALF - EDGE_MARGIN - reach
	if lim <= 0.0:
		return Vector2.INF
	for attempt: int in range(200):
		var c: Vector2 = Vector2(rng.randf_range(-lim, lim), rng.randf_range(-lim, lim))
		if c.distance_to(boat_xz) < reach + CHANNEL_WIDTH:
			continue
		var clear: bool = true
		for j: int in range(placed_pos.size()):
			if c.distance_to(placed_pos[j]) < reach + placed_r[j] * COAST_REACH + CHANNEL_WIDTH:
				clear = false
				break
		if clear:
			return c
	return Vector2.INF


func _spawn_island(pos2d: Vector2, island_name: String, itype: Island.IslandType,
		radius: float, trees: int, async: bool) -> void:
	var island: Island = IslandScript.new() as Island
	island.island_name      = island_name
	island.world_seed       = world_seed
	island.position         = Vector3(pos2d.x, 0.0, pos2d.y)
	island.island_type      = itype
	island.base_radius      = radius
	island.discovery_radius = radius * 1.3
	island.num_trees        = trees
	island.build_async      = async
	add_child(island)

	var hud: Node = get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("_on_island_discovered"):
		island.island_discovered.connect(Callable(hud, "_on_island_discovered"))
