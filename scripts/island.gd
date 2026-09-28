extends StaticBody3D
class_name Island

signal island_discovered(island_name: String, world_pos: Vector2, resources: Dictionary)

enum IslandType { TROPICAL, VOLCANIC, ATOLL, HIGHLAND }
enum ZoneType    { TROPICAL = 0, VOLCANIC = 1, ATOLL = 2, HIGHLAND = 3, PLAINS = 4, DESERT = 5 }

@export var island_name:      String     = "Unknown Isle"
@export var base_radius:      float      = 4.0
@export var num_trees:        int        = 3
@export var discovery_radius: float      = 18.0
@export var island_type:      IslandType = IslandType.TROPICAL

var discovered:   bool       = false
var resources:    Dictionary = {}
var _boat:        Node3D     = null
var _has_river:   bool       = false
var _river_angle: float      = 0.0

# ── Zone constants ─────────────────────────────────────────────────────────── #
# Integer keys match ZoneType enum values (0–5).

# Height cap per zone type (world units).  Scaled further by base_radius at setup.
const _ZONE_MAX_HEIGHT: Dictionary = {
	0: 45.0,   # TROPICAL
	1: 80.0,   # VOLCANIC
	2: 10.0,   # ATOLL
	3: 70.0,   # HIGHLAND
	4: 12.0,   # PLAINS
	5: 22.0,   # DESERT
}

# Tint applied to the grass/vegetation layer in the shader.
const _ZONE_GRASS_TINT: Dictionary = {
	0: Color(0.78, 1.00, 0.65, 1.0),   # TROPICAL  — rich jungle green
	1: Color(1.00, 0.62, 0.42, 1.0),   # VOLCANIC  — fiery orange
	2: Color(1.02, 1.00, 0.94, 1.0),   # ATOLL     — warm sand
	3: Color(0.83, 0.88, 0.96, 1.0),   # HIGHLAND  — cool slate-blue
	4: Color(0.90, 0.98, 0.76, 1.0),   # PLAINS    — pale meadow green
	5: Color(1.05, 0.90, 0.68, 1.0),   # DESERT    — warm tan
}

# Tint applied to the rock layer in the shader.
const _ZONE_ROCK_TINT: Dictionary = {
	0: Color(0.72, 0.80, 0.65, 1.0),   # TROPICAL  — mossy
	1: Color(0.55, 0.48, 0.42, 1.0),   # VOLCANIC  — dark ash
	2: Color(0.90, 0.88, 0.82, 1.0),   # ATOLL     — pale limestone
	3: Color(0.75, 0.78, 0.82, 1.0),   # HIGHLAND  — grey slate
	4: Color(0.85, 0.82, 0.72, 1.0),   # PLAINS    — earthy brown
	5: Color(0.88, 0.76, 0.58, 1.0),   # DESERT    — sandstone
}

# Resources available from each zone type.
# Keys match ICON_XX_YY entries in hud.gd's _RESOURCE_ICON lookup (sheet, col, row).
const _ZONE_RESOURCE_TABLE: Dictionary = {
	0: ["coconut", "breadfruit", "sugarcane", "palm_fronds",
		"hardwood_teak", "quinine_bark", "bamboo_stalks", "volcanic_guano"],    # TROPICAL
	1: ["geothermal_water", "taro_root", "basalt_rock", "obsidian",
		"sulfur", "lodestone", "pumice_stone", "native_copper"],                # VOLCANIC
	2: ["seabird_eggs", "pelagic_fish", "pandanus_fruit", "driftwood",
		"clam_shell", "black_pearl", "coral_blocks", "seagrass_fibre"],         # ATOLL
	3: ["wild_berries", "root_vegetable", "highland_wool", "stone_blocks",
		"hematite", "clay", "flax_stalks", "galena"],                           # HIGHLAND
	4: ["wild_grains", "wild_game_bison", "thatch_grass", "hemp_fibre",
		"limestone_block", "coal_lump", "wild_flowers", "horses"],              # PLAINS
	5: ["prickly_pear", "reptile_meat", "sandstone_block", "silica_sand",
		"niter", "acacia_wood", "dried_aloe", "obsidian_shards"],               # DESERT
}

# Forest density noise threshold per zone.  Higher = fewer trees.
const _ZONE_DENSITY_THRESHOLD: Dictionary = {
	0: 0.22,   # TROPICAL
	1: 0.52,   # VOLCANIC
	2: 0.28,   # ATOLL
	3: 0.12,   # HIGHLAND
	4: 0.30,   # PLAINS
	5: 0.65,   # DESERT
}

# ── Terrain shader + atlas ─────────────────────────────────────────────────── #
const _TERRAIN_SHADER = preload("res://assets/materials/island_terrain.gdshader")
const _TEX_ATLAS      = preload("res://assets/textures/dirt_sand_water_stone.png")

var _terrain_mat: ShaderMaterial

# ── Tree pools keyed by ZoneType int value ─────────────────────────────────── #
const _TREE_SCALE_MIN: float = 0.10
const _TREE_SCALE_MAX: float = 0.19

const _ZONE_TREE_POOLS: Dictionary = {
	0: [  # TROPICAL
		"res://assets/models/trees/tropical/Palm Tree.glb",
		"res://assets/models/trees/tropical/Ivory cane palm tree.glb",
		"res://assets/models/trees/tropical/Triangle palm.glb",
		"res://assets/models/trees/tropical/Everglades palm tree.glb",
		"res://assets/models/trees/tropical/Thatch palm tree.glb",
	],
	1: [  # VOLCANIC
		"res://assets/models/trees/volcanic/Dead Tree.glb",
		"res://assets/models/trees/volcanic/Dead Tree_2.glb",
		"res://assets/models/trees/volcanic/Dead Tree_3.glb",
	],
	2: [  # ATOLL
		"res://assets/models/trees/atoll/Tree.glb",
		"res://assets/models/trees/atoll/Bush with Flowers.glb",
	],
	3: [  # HIGHLAND
		"res://assets/models/trees/highland/Pine.glb",
		"res://assets/models/trees/highland/Tree.glb",
		"res://assets/models/trees/highland/Birch Trees.glb",
	],
	4: [  # PLAINS — sparse, mostly low scrub
		"res://assets/models/trees/tropical/Thatch palm tree.glb",
		"res://assets/models/trees/highland/Tree.glb",
	],
	5: [  # DESERT — dead wood / sparse
		"res://assets/models/trees/volcanic/Dead Tree.glb",
		"res://assets/models/trees/volcanic/Dead Tree_3.glb",
	],
}

# ── Noise ──────────────────────────────────────────────────────────────────── #
var _height_noise: FastNoiseLite
var _edge_noise:   FastNoiseLite
var _forest_noise: FastNoiseLite

# ── Peaks — each Vector3 is (local_x, local_z, strength 0–1) ──────────────── #
var _peaks: Array[Vector3] = []

# Grid resolution — clamped to 64–128 cells
var _grid_n: int

# ── Biome zones ────────────────────────────────────────────────────────────── #
class BiomeZone:
	var pos:        Vector2   # local XZ offset from island centre
	var radius:     float     # influence radius (world units)
	var zone_type:  int       # ZoneType enum value
	var max_height: float     # height cap for this zone

	func _init(p: Vector2, r: float, zt: int, mh: float) -> void:
		pos        = p
		radius     = r
		zone_type  = zt
		max_height = mh

var _zones: Array = []   # Array[BiomeZone]


# ── Lifecycle ──────────────────────────────────────────────────────────────── #

func _ready() -> void:
	_grid_n = clampi(int(base_radius * 1.5), 64, 128)
	_setup_noise()
	_setup_zones()
	_setup_type()
	_assign_resources()
	_setup_peaks()
	_build_materials()
	_build_geometry()
	_boat = get_tree().get_first_node_in_group("boat")


# ── Noise ──────────────────────────────────────────────────────────────────── #

func _setup_noise() -> void:
	_height_noise = FastNoiseLite.new()
	_height_noise.seed       = island_name.hash()
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency  = 1.0

	_edge_noise = FastNoiseLite.new()
	_edge_noise.seed       = island_name.hash() + 9999
	_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_edge_noise.frequency  = 1.0

	_forest_noise = FastNoiseLite.new()
	_forest_noise.seed       = island_name.hash() + 54321
	_forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest_noise.frequency  = 1.0


# ── Biome zone setup ───────────────────────────────────────────────────────── #

# Populates _zones with 1–4 spatial biome zones.
# ATOLLs get a single covering ATOLL zone; all others get 1–4 typed zones
# whose positions drive the height, tinting, resources, and tree variety.
func _setup_zones() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash() + 88888

	# ATOLLs stay as a single covering zone — ring height profile handles shape.
	if island_type == IslandType.ATOLL:
		var mh: float = minf(base_radius * 0.55, 10.0)
		_zones.append(BiomeZone.new(Vector2.ZERO, base_radius, ZoneType.ATOLL, mh))
		return

	# Zone count: weighted toward single-biome with a chance of 2–4.
	# HIGHLAND islands lean multi-zone; VOLCANIC lean single.
	var num_zones: int
	match island_type:
		IslandType.TROPICAL: num_zones = _weighted_zone_count(rng, 40, 35, 18, 7)
		IslandType.VOLCANIC:  num_zones = _weighted_zone_count(rng, 55, 30, 15, 0)
		IslandType.HIGHLAND:  num_zones = _weighted_zone_count(rng, 25, 35, 28, 12)
		_:                    num_zones = _weighted_zone_count(rng, 38, 34, 20, 8)

	# Zone type pools biased by island_type.
	# Primary type appears 3–4× more often than secondary types.
	var pool: Array[int]
	match island_type:
		IslandType.TROPICAL:
			pool = [ZoneType.TROPICAL, ZoneType.TROPICAL, ZoneType.TROPICAL,
					ZoneType.PLAINS, ZoneType.DESERT]
		IslandType.VOLCANIC:
			pool = [ZoneType.VOLCANIC, ZoneType.VOLCANIC, ZoneType.VOLCANIC,
					ZoneType.HIGHLAND, ZoneType.PLAINS]
		IslandType.HIGHLAND:
			pool = [ZoneType.HIGHLAND, ZoneType.HIGHLAND,
					ZoneType.TROPICAL, ZoneType.PLAINS, ZoneType.VOLCANIC]
		_:
			pool = [ZoneType.TROPICAL, ZoneType.TROPICAL, ZoneType.HIGHLAND,
					ZoneType.PLAINS, ZoneType.DESERT]

	# For single-zone islands place the primary type at centre.
	if num_zones == 1:
		var zt: int = pool[0]
		var mh: float = minf(base_radius * 0.55, _ZONE_MAX_HEIGHT.get(zt, 45.0))
		_zones.append(BiomeZone.new(Vector2.ZERO, base_radius * 0.90, zt, mh))
		return

	# Multi-zone: evenly distribute around the island with angular jitter.
	for i: int in range(num_zones):
		var sector: float = TAU / float(num_zones)
		var jitter: float = rng.randf_range(-sector * 0.30, sector * 0.30)
		var angle:  float = float(i) * sector + jitter
		# Zones sit 20–55 % of base_radius from centre so they can overlap
		# at the island's heart while still creating distinct edge biomes.
		var dist: float   = base_radius * rng.randf_range(0.20, 0.55)
		var zpos: Vector2 = Vector2(cos(angle) * dist, sin(angle) * dist)
		# Radius large enough that zones cover the full island together.
		var zrad: float   = base_radius * rng.randf_range(0.55, 0.90)
		var zt:   int     = pool[rng.randi() % pool.size()]
		var mh:   float   = minf(base_radius * 0.55, _ZONE_MAX_HEIGHT.get(zt, 45.0))
		_zones.append(BiomeZone.new(zpos, zrad, zt, mh))


## Returns a zone count (1–4) driven by the four percentage weights.
func _weighted_zone_count(rng: RandomNumberGenerator,
		w1: int, w2: int, w3: int, w4: int) -> int:
	var roll: int = rng.randi_range(0, w1 + w2 + w3 + w4 - 1)
	if roll < w1:        return 1
	elif roll < w1 + w2: return 2
	elif roll < w1 + w2 + w3: return 3
	return 4


# ── Island type (river chance) ─────────────────────────────────────────────── #

func _setup_type() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash() + 77777
	# Rivers occur on lush/highland zones; volcanic and desert terrain is too rough.
	var has_lush_zone: bool = false
	for z: Object in _zones:
		var zone: BiomeZone = z as BiomeZone
		if zone.zone_type == ZoneType.TROPICAL or zone.zone_type == ZoneType.HIGHLAND \
				or zone.zone_type == ZoneType.PLAINS:
			has_lush_zone = true
			break
	if has_lush_zone and island_type != IslandType.ATOLL:
		_has_river   = rng.randf() < 0.55
		_river_angle = rng.randf() * TAU
	else:
		_has_river   = false
		_river_angle = 0.0


# ── Resources ─────────────────────────────────────────────────────────────────#
# Each zone independently rolls a 70 % per-resource gate, then contributes
# an amount scaled by that zone's radius relative to the island.
# Same resource type from multiple zones stacks — a tropical + highland island
# can have both jungle spices AND highland flax.

func _assign_resources() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash() + 11111

	for z: Object in _zones:
		var zone: BiomeZone = z as BiomeZone
		var pool: Array = _ZONE_RESOURCE_TABLE.get(zone.zone_type, ["food"])
		# Larger zones contribute proportionally more resources.
		var zone_scale: float = clampf(zone.radius / maxf(base_radius, 1.0), 0.4, 1.2)
		for res: String in pool:
			if rng.randf() < 0.70:
				var amount: int = clampi(
					int(base_radius * zone_scale * rng.randf_range(0.4, 1.1)), 5, 150)
				resources[res] = resources.get(res, 0) + amount


# ── Peaks ─────────────────────────────────────────────────────────────────────#
# One peak is placed near each zone that isn't a flat biome (PLAINS).
# VOLCANIC and HIGHLAND zones get strong peaks; TROPICAL moderate; DESERT gentle.
# ATOLL skips this entirely — ring profile in _height_at_xy handles its shape.

func _setup_peaks() -> void:
	if island_type == IslandType.ATOLL:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash() + 22222

	for z: Object in _zones:
		var zone: BiomeZone = z as BiomeZone
		if zone.zone_type == ZoneType.PLAINS:
			continue   # Plains zones stay flat — no peak

		# Place the peak near the zone's centre with a small random offset.
		var peak_angle: float = rng.randf() * TAU
		var peak_dist:  float = zone.radius * rng.randf_range(0.0, 0.30)
		var px: float = zone.pos.x + cos(peak_angle) * peak_dist
		var pz: float = zone.pos.y + sin(peak_angle) * peak_dist

		var strength: float
		match zone.zone_type:
			ZoneType.VOLCANIC: strength = rng.randf_range(0.85, 1.00)
			ZoneType.HIGHLAND: strength = rng.randf_range(0.80, 1.00)
			ZoneType.DESERT:   strength = rng.randf_range(0.45, 0.70)
			ZoneType.TROPICAL: strength = rng.randf_range(0.60, 0.88)
			_:                 strength = rng.randf_range(0.50, 0.80)

		_peaks.append(Vector3(px, pz, strength))

	# Safety net: if all zones were PLAINS, add a gentle central dome.
	if _peaks.is_empty():
		_peaks.append(Vector3(0.0, 0.0, 0.30))


# ── Height helpers ─────────────────────────────────────────────────────────── #

## Global max height — used for AABB and fog reveal sizing.
func _get_max_height() -> float:
	if not _zones.is_empty():
		var mh: float = 0.0
		for z: Object in _zones:
			mh = maxf(mh, (z as BiomeZone).max_height)
		return mh
	# ATOLL fallback (should not reach here — ATOLL always has a zone)
	return minf(base_radius * 0.55, 10.0)


## Zone-weighted height cap at a given local XZ position.
## Smoothly blends zone max_height values so zones transition gradually.
func _zone_weighted_max_height(x: float, z: float) -> float:
	var total_w: float = 0.0
	var weighted: float = 0.0
	for obj: Object in _zones:
		var zone: BiomeZone = obj as BiomeZone
		var d: float  = Vector2(x, z).distance_to(zone.pos)
		var w: float  = maxf(0.0, 1.0 - d / maxf(zone.radius, 0.001))
		w = w * w   # squared weight: sharper transitions between zones
		weighted += zone.max_height * w
		total_w  += w
	if total_w < 0.001:
		return _get_max_height()
	return weighted / total_w


## Returns the ZoneType int of the zone with the highest influence at (x, z).
## Used to select tree pools and density thresholds per placement point.
func _dominant_zone_at(x: float, z: float) -> int:
	var best_w:  float = -1.0
	var best_zt: int   = ZoneType.TROPICAL
	for obj: Object in _zones:
		var zone: BiomeZone = obj as BiomeZone
		var d: float = Vector2(x, z).distance_to(zone.pos)
		var w: float = maxf(0.0, 1.0 - d / maxf(zone.radius, 0.001))
		if w > best_w:
			best_w  = w
			best_zt = zone.zone_type
	return best_zt


# ── Height function — grid-based, domain-warped ───────────────────────────── #

# Public accessor used by IslandSpawner to paint the shore proximity map.
func get_height_at(local_x: float, local_z: float) -> float:
	return _height_at_xy(local_x, local_z)


func _height_at_xy(x: float, z: float) -> float:
	# ── ATOLL: ring profile (unchanged) ────────────────────────────────────
	if island_type == IslandType.ATOLL:
		var max_h_a: float  = _get_max_height()
		var raw_r_a: float  = Vector2(x, z).length()
		var coast_n_a: float = 0.0
		if raw_r_a > 0.001:
			coast_n_a = _edge_noise.get_noise_2d(x / raw_r_a * 0.75, z / raw_r_a * 0.75)
		var eff_r_a: float  = base_radius * (1.0 + coast_n_a * 0.25)
		var r_norm_a: float = raw_r_a / eff_r_a
		if r_norm_a >= 1.0:
			return 0.0
		var hn_a: float    = _height_noise.get_noise_2d(x * 0.30, z * 0.30)
		var prof_a: float  = smoothstep(0.25, 0.50, r_norm_a) * (1.0 - smoothstep(0.65, 0.90, r_norm_a))
		prof_a = clamp(prof_a + hn_a * 0.12, 0.0, 1.0)
		var res_a: float = prof_a * max_h_a
		# Outer ring edge dips below Y=0 so the water always covers the terrain edge.
		# Lagoon centre also dips so the interior stays navigable open ocean.
		var outer_dip: float = smoothstep(0.65, 1.05, r_norm_a) * 2.0
		var inner_dip: float = (1.0 - smoothstep(0.0, 0.25, r_norm_a)) * 2.0
		res_a -= outer_dip + inner_dip
		return res_a

	# ── Multi-peak height (all other types) ────────────────────────────────
	var n: int = _peaks.size()
	if n == 0:
		return 0.0

	# Peak reach radius shrinks with more peaks so gaps form between them.
	var peak_r: float
	match n:
		1: peak_r = base_radius * 0.90
		2: peak_r = base_radius * 0.78
		3: peak_r = base_radius * 0.73
		_: peak_r = base_radius * 0.68

	var total: float = 0.0
	for peak: Vector3 in _peaks:
		var dx: float    = x - peak.x
		var dz: float    = z - peak.y
		var raw_r: float = Vector2(dx, dz).length()

		var coast_n: float = 0.0
		if raw_r > 0.001:
			var dir_x: float = dx / raw_r
			var dir_z: float = dz / raw_r
			coast_n  = _edge_noise.get_noise_2d(
				dir_x * 1.2 + peak.x * 0.04,
				dir_z * 1.2 + peak.y * 0.04) * 0.52
			coast_n += _height_noise.get_noise_2d(
				dir_x * 5.0, dir_z * 5.0) * 0.15

		var eff_r: float  = maxf(peak_r * (1.0 + coast_n), peak_r * 0.30)
		var r_norm: float = raw_r / eff_r
		if r_norm >= 1.0:
			continue

		var profile: float = 1.0 - smoothstep(0.05, 0.90, r_norm)
		total += profile * peak.z   # peak.z = strength

	total = clampf(total, 0.0, 1.0)

	var outer_r: float    = Vector2(x, z).length()
	var r_norm_outer: float = outer_r / base_radius
	var outer_mask: float = 1.0 - smoothstep(0.95, 1.25, r_norm_outer)
	total *= outer_mask

	# Coast dip: applied even when total≈0 so the shoreline goes below Y=0.
	# The opaque water surface then always covers the terrain edge.
	var coast_dip: float = smoothstep(0.70, 1.25, r_norm_outer) * 2.0

	# Skip the expensive zone lookup only when far from the coast and no peaks reach here.
	if total <= 0.01 and r_norm_outer < 0.70:
		return 0.0

	# Zone-weighted height cap: PLAINS zones stay flat, VOLCANIC soar.
	var max_h: float = _zone_weighted_max_height(x, z)
	var result: float = total * max_h
	result -= coast_dip
	return result


# ── Materials ─────────────────────────────────────────────────────────────────#

func _build_materials() -> void:
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = _TERRAIN_SHADER

	_terrain_mat.set_shader_parameter("terrain_atlas",     _TEX_ATLAS)
	_terrain_mat.set_shader_parameter("beach_tile_offset", Vector2(0.00, 0.25))
	_terrain_mat.set_shader_parameter("beach_tile_scale",  Vector2(0.25, 0.25))
	_terrain_mat.set_shader_parameter("grass_tile_offset", Vector2(0.00, 0.00))
	_terrain_mat.set_shader_parameter("grass_tile_scale",  Vector2(0.25, 0.25))
	_terrain_mat.set_shader_parameter("world_tile_size",   1.0)

	# Rock tile: lava if any zone is VOLCANIC, mossy stone otherwise.
	var has_volcanic: bool = false
	for obj: Object in _zones:
		if (obj as BiomeZone).zone_type == ZoneType.VOLCANIC:
			has_volcanic = true
			break
	var rock_offset: Vector2 = Vector2(0.50, 0.50) if has_volcanic else Vector2(0.50, 0.00)
	_terrain_mat.set_shader_parameter("rock_tile_offset", rock_offset)
	_terrain_mat.set_shader_parameter("rock_tile_scale",  Vector2(0.25, 0.25))

	var max_h: float = _get_max_height()
	_terrain_mat.set_shader_parameter("blend_low",  max(0.55, max_h * 0.05))
	_terrain_mat.set_shader_parameter("blend_high", max(1.20, max_h * 0.15))

	if island_type == IslandType.ATOLL:
		_terrain_mat.set_shader_parameter("rock_low",  999.0)
		_terrain_mat.set_shader_parameter("rock_high", 1000.0)
	else:
		_terrain_mat.set_shader_parameter("rock_low",  max_h * 0.55)
		_terrain_mat.set_shader_parameter("rock_high", max_h * 0.82)

	_terrain_mat.set_shader_parameter("has_river",   1.0 if _has_river else 0.0)
	_terrain_mat.set_shader_parameter("river_angle", _river_angle)
	_terrain_mat.set_shader_parameter("river_width", base_radius * 0.07)

	# Upload zone array uniforms to drive spatial tinting in the shader.
	# zone_data[i]       — vec4: xy = local XZ centre, z = influence radius, w = unused
	# zone_grass_tint[i] — vec4: RGBA colour multiplied onto the grass/vegetation layer
	# zone_rock_tint[i]  — vec4: RGBA colour multiplied onto the rock layer
	var zone_count: int = mini(_zones.size(), 4)
	_terrain_mat.set_shader_parameter("zone_count", zone_count)
	for i: int in range(zone_count):
		var zone: BiomeZone = _zones[i] as BiomeZone
		_terrain_mat.set_shader_parameter(
			"zone_data[%d]" % i,
			Vector4(zone.pos.x, zone.pos.y, zone.radius, 0.0))
		_terrain_mat.set_shader_parameter(
			"zone_grass_tint[%d]" % i,
			_ZONE_GRASS_TINT.get(zone.zone_type, Color.WHITE))
		_terrain_mat.set_shader_parameter(
			"zone_rock_tint[%d]" % i,
			_ZONE_ROCK_TINT.get(zone.zone_type, Color.WHITE))




# ── Geometry ───────────────────────────────────────────────────────────────── #

func _build_geometry() -> void:
	var extent:    float = base_radius * 1.50
	var cell_size: float = (extent * 2.0) / _grid_n
	var map_verts: int   = _grid_n + 1

	var heights := PackedFloat32Array()
	heights.resize(map_verts * map_verts)
	for iz: int in range(map_verts):
		for ix: int in range(map_verts):
			var wx: float = -extent + ix * cell_size
			var wz: float = -extent + iz * cell_size
			heights[iz * map_verts + ix] = _height_at_xy(wx, wz)

	_build_terrain_mesh(heights, extent, cell_size, map_verts)
	_build_trees()
	call_deferred("_build_collision", heights, extent, cell_size, map_verts)


func _build_terrain_mesh(heights: PackedFloat32Array, extent: float,
		cell_size: float, map_verts: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for iz: int in range(_grid_n):
		for ix: int in range(_grid_n):
			var v00 := Vector3(-extent + ix       * cell_size, heights[ iz      * map_verts + ix    ], -extent + iz       * cell_size)
			var v10 := Vector3(-extent + (ix + 1) * cell_size, heights[ iz      * map_verts + ix + 1], -extent + iz       * cell_size)
			var v01 := Vector3(-extent + ix       * cell_size, heights[(iz + 1) * map_verts + ix    ], -extent + (iz + 1) * cell_size)
			var v11 := Vector3(-extent + (ix + 1) * cell_size, heights[(iz + 1) * map_verts + ix + 1], -extent + (iz + 1) * cell_size)
			st.add_vertex(v00); st.add_vertex(v11); st.add_vertex(v10)
			st.add_vertex(v00); st.add_vertex(v01); st.add_vertex(v11)

	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.custom_aabb = _island_aabb()
	add_child(mi)
	mi.set_surface_override_material(0, _terrain_mat)


func _island_aabb() -> AABB:
	var r: float = base_radius * 1.55
	var h: float = _get_max_height() + 4.0
	# Lower bound extended to -20 so the underwater coastal slope isn't culled.
	return AABB(Vector3(-r, -20.0, -r), Vector3(r * 2.0, h + 20.0, r * 2.0))


func _build_collision(heights: PackedFloat32Array, extent: float,
		cell_size: float, map_verts: int) -> void:
	var face_verts := PackedVector3Array()

	for iz: int in range(_grid_n):
		for ix: int in range(_grid_n):
			var h00: float = heights[ iz      * map_verts + ix    ]
			var h10: float = heights[ iz      * map_verts + ix + 1]
			var h01: float = heights[(iz + 1) * map_verts + ix    ]
			var h11: float = heights[(iz + 1) * map_verts + ix + 1]

			if maxf(maxf(h00, h10), maxf(h01, h11)) < 0.05:
				continue

			var v00 := Vector3(-extent + ix       * cell_size, h00, -extent + iz       * cell_size)
			var v10 := Vector3(-extent + (ix + 1) * cell_size, h10, -extent + iz       * cell_size)
			var v01 := Vector3(-extent + ix       * cell_size, h01, -extent + (iz + 1) * cell_size)
			var v11 := Vector3(-extent + (ix + 1) * cell_size, h11, -extent + (iz + 1) * cell_size)
			face_verts.append(v00); face_verts.append(v11); face_verts.append(v10)
			face_verts.append(v00); face_verts.append(v01); face_verts.append(v11)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(face_verts)
	shape.backface_collision = true
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


# ── Trees ─────────────────────────────────────────────────────────────────── #

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash()

	var placed:   int = 0
	var attempts: int = 0
	while placed < num_trees and attempts < num_trees * 10:
		attempts += 1
		var angle: float = rng.randf() * TAU
		var r:     float = rng.randf_range(0.0, base_radius * 0.92)
		var x:     float = cos(angle) * r
		var z:     float = sin(angle) * r
		var r_norm: float = r / base_radius

		# ATOLLs only plant on the ring, not the central lagoon.
		if island_type == IslandType.ATOLL and (r_norm < 0.35 or r_norm > 0.78):
			continue

		var y: float = _height_at_xy(x, z)
		if y < 0.20:
			continue

		# Use zone-local density threshold and tree pool.
		var zt: int = _dominant_zone_at(x, z)
		var density_threshold: float = _ZONE_DENSITY_THRESHOLD.get(zt, 0.25)
		var density: float = _forest_noise.get_noise_2d(x * 0.5, z * 0.5) * 0.5 + 0.5
		if density < density_threshold:
			continue

		_build_tree(rng, Vector3(x, y, z), zt)
		placed += 1


func _build_tree(rng: RandomNumberGenerator, base_pos: Vector3, zone_type: int) -> void:
	var pool: Array = _ZONE_TREE_POOLS.get(zone_type, [])
	if pool.is_empty():
		return

	var path: String = pool[rng.randi() % pool.size()]
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("Island: failed to load tree GLB: %s" % path)
		return

	var tree: Node3D = packed.instantiate() as Node3D
	if tree == null:
		return

	tree.position   = base_pos
	tree.rotation.y = rng.randf() * TAU

	var s: float = rng.randf_range(_TREE_SCALE_MIN, _TREE_SCALE_MAX)
	tree.scale = Vector3(s, s * rng.randf_range(0.90, 1.15), s)

	var aabb: AABB = _island_aabb()
	for m: Node in tree.find_children("*", "MeshInstance3D"):
		(m as MeshInstance3D).custom_aabb = aabb

	add_child(tree)


# ── Discovery ──────────────────────────────────────────────────────────────── #

func _physics_process(_delta: float) -> void:
	if discovered or _boat == null:
		return
	var self_xz := Vector2(global_position.x, global_position.z)
	var boat_xz := Vector2(_boat.global_position.x, _boat.global_position.z)
	if self_xz.distance_to(boat_xz) <= discovery_radius:
		_discover()


func _discover() -> void:
	discovered = true
	island_discovered.emit(island_name, Vector2(global_position.x, global_position.z), resources)
	var fog: FogOfWar = get_tree().get_first_node_in_group("fog_of_war") as FogOfWar
	if fog != null:
		var island_xz: Vector2 = Vector2(global_position.x, global_position.z)
		fog.reveal_area(island_xz, base_radius * 1.5 + _get_max_height() * 2.0 + 15.0)
	print("Discovered: ", island_name)
