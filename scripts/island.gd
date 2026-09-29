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
## World seed from IslandSpawner. Mixed with island_name so the same name gives
## a different island in every world, but the same island when a world reloads.
@export var world_seed:       int        = 0
## Build terrain on a worker thread. The home island builds synchronously so it
## is on screen from the first frame.
@export var build_async:      bool       = true

var discovered:   bool       = false
var resources:    Dictionary = {}
var _boat:        Node3D     = null
var _seed:        int        = 0
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

# ── Terrain shader + textures ──────────────────────────────────────────────── #
const _TERRAIN_SHADER = preload("res://assets/materials/island_terrain.gdshader")
# One seamless texture per layer — see goals/add_shader.md "Terrain textures"
# for the spec.  Swap files in place to restyle every island.
const _TEX_SAND:      String = "res://assets/textures/terrain/sand.png"
const _TEX_GRASS:     String = "res://assets/textures/terrain/grass.png"
const _TEX_ROCK:      String = "res://assets/textures/terrain/rock.png"
const _TEX_LAVA_ROCK: String = "res://assets/textures/terrain/lava_rock.png"

# Cliff-face texture per zone type (painted by slope in the shader).
const _ZONE_CLIFF_TEX: Dictionary = {
	0: "res://assets/textures/terrain/cliff_earth.png",       # TROPICAL
	1: "res://assets/textures/terrain/cliff_basalt.png",      # VOLCANIC
	2: "res://assets/textures/terrain/cliff_sandstone.png",   # ATOLL (never steep)
	3: "res://assets/textures/terrain/cliff_granite.png",     # HIGHLAND
	4: "res://assets/textures/terrain/cliff_earth.png",       # PLAINS
	5: "res://assets/textures/terrain/cliff_sandstone.png",   # DESERT
}

var _terrain_mat: ShaderMaterial

# ── Terrain shape ──────────────────────────────────────────────────────────── #
# The island is a signed "land field" s(x, z): s > 0 is land, s < 0 is sea, and
# s = 0 is the coastline.  Heights on both sides are built from the true
# distance to that coastline (see _coast_distance), so they meet exactly at
# Y = 0 and every shore has the same beach and seabed slope.
const _SEABED_SLOPE:    float = 0.40    # depth gained per world unit offshore
const _SEABED_FLOOR:    float = -14.0   # water is fully opaque well before this
const _LAGOON_FLOOR:    float = -2.2    # atoll lagoons stay shallow and turquoise
const _BEACH_SLOPE:     float = 0.22    # height gained per world unit inland
const _BEACH_CAP:       float = 1.2     # beach ramp tops out here; hills take over
const _MESH_EXTENT:     float = 1.50    # mesh half-size as a multiple of base_radius
const _TARGET_CELL:     float = 1.6     # desired grid spacing (world units)
const _MAX_GRID:        int   = 320
const _CHUNK_CELLS:     int   = 32      # terrain split into chunks for frustum culling
const _MESH_SKIP_DEPTH: float = -11.0   # cells entirely below this are never visible
const _COAST_SUBDIV:    int   = 4       # waterline cells split k×k with smooth heights
const _COAST_BAND:      float = 0.35    # a cell is "waterline" if its heights straddle ±this
										# (covers the ±0.19 wave swing)

# ── Cliffs ─────────────────────────────────────────────────────────────────── #
# Steep ground is made here; the shader paints anything steep as cliff rock.
# Per zone type: x = coastal cliff height (world units), y = cliff coast bias
# (added to the cliff noise — higher = more of the coast is cliff), z = terrace
# step height, w = terrace strength (0 = smooth slopes, 1 = flat benches).
const _ZONE_CLIFFS: Dictionary = {
	0: Vector4(5.0,  0.00, 5.0, 0.35),   # TROPICAL
	1: Vector4(8.0,  0.08, 7.0, 0.50),   # VOLCANIC
	2: Vector4(0.0, -1.00, 0.0, 0.00),   # ATOLL — no cliffs
	3: Vector4(9.0,  0.10, 6.0, 0.70),   # HIGHLAND
	4: Vector4(3.5, -0.12, 3.0, 0.30),   # PLAINS
	5: Vector4(7.0,  0.08, 4.0, 0.85),   # DESERT — mesas
}
const _CLIFF_RUN:          float = 1.25   # cliff face width, in grid cells
const _CLIFF_SEABED_SLOPE: float = 1.0    # deep water right under a cliff
const _TERRACE_RISER:      float = 0.3    # fraction of each terrace step that is the steep riser
const _TREE_MAX_SLOPE:     float = 0.8    # rise/run; keeps trees off cliff faces

# ── Trees ──────────────────────────────────────────────────────────────────── #
# Claude Design low-poly clusters: ~4–6 wu footprint, 2–4 wu tall, base at y=0,
# flat-shaded named materials, no textures.  Each cluster has variants a–e.
const _TREE_SCALE_MIN:  float = 0.9
const _TREE_SCALE_MAX:  float = 1.3
const _TREE_MIN_HEIGHT: float = 0.8     # keep trees off the wet sand
const _TREE_DIR:        String = "res://assets/models/trees/sawyer/sawyer_%s_%s.glb"
const _TREE_VARIANTS:   Array[String] = ["a", "b", "c", "d", "e"]

# Clusters per zone type.  Unused for now: snowy_stand (no polar biome yet),
# orchard (settlements).
const _ZONE_TREE_CLUSTERS: Dictionary = {
	0: ["coastal_palms", "jungle_thicket", "fern_gully"],   # TROPICAL
	1: ["ash_forest", "dead_snags"],                         # VOLCANIC
	2: ["coastal_palms", "mangrove"],                        # ATOLL
	3: ["pine_stand", "spruce_ridge", "birch_copse"],        # HIGHLAND
	4: ["temperate_grove", "birch_copse"],                   # PLAINS
	5: ["dead_snags"],                                       # DESERT
}

# One merged mesh per tree GLB (one surface per material), shared by every island.
static var _tree_mesh_cache: Dictionary = {}

# ── Noise ──────────────────────────────────────────────────────────────────── #
var _warp_noise:   FastNoiseLite   # bends the whole island so nothing is circular
var _coast_noise:  FastNoiseLite   # fractal coastline detail, in world units
var _ridge_noise:  FastNoiseLite   # ridged texture on mountains
var _hill_noise:   FastNoiseLite   # gentle rolling ground
var _forest_noise: FastNoiseLite   # tree clumping
var _cliff_noise:  FastNoiseLite   # which stretches of coast / hillside get cliffs
var _warp_amp:     float = 0.0

# ── Peaks — each Vector3 is (local_x, local_z, strength 0–1) ──────────────── #
var _peaks:      Array[Vector3] = []
var _peak_reach: float = 1.0

# ── Atoll passes — guaranteed boat channels through the reef ring ────────── #
var _pass_angles:     PackedFloat32Array = PackedFloat32Array()
var _pass_half_angle: float = 0.0   # angular half-width of each channel (radians)

# ── Grid ───────────────────────────────────────────────────────────────────── #
var _grid_n: int     = 64
var _extent: float   = 0.0
var _cell:   float   = 1.0

# Filled by the build task (worker thread), consumed on the main thread.
var _build_task:     int                 = -1
var _heights:        PackedFloat32Array
var _collision_data: PackedFloat32Array
var _chunk_arrays:   Array[Array]        = []
var _tree_xforms:    Dictionary          = {}   # GLB path -> Array of Transform3D

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

var _zones: Array[BiomeZone] = []


# ── Lifecycle ──────────────────────────────────────────────────────────────── #

func _ready() -> void:
	_seed   = ("%d:%s" % [world_seed, island_name]).hash()
	_extent = base_radius * _MESH_EXTENT
	_grid_n = clampi(int(ceil(_extent * 2.0 / _TARGET_CELL)), 64, _MAX_GRID)
	_cell   = _extent * 2.0 / float(_grid_n)

	_setup_noise()
	_setup_zones()
	_setup_type()
	_assign_resources()
	_setup_peaks()
	_build_materials()
	_boat = get_tree().get_first_node_in_group("boat") as Node3D

	if build_async:
		_build_task = WorkerThreadPool.add_task(_generate_terrain_data, false, "Island " + island_name)
	else:
		_generate_terrain_data()
		_finish_build()
		set_process(false)


func _process(_delta: float) -> void:
	if _build_task >= 0 and WorkerThreadPool.is_task_completed(_build_task):
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1
		_finish_build()
	if _build_task < 0:
		set_process(false)


func _exit_tree() -> void:
	if _build_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1


# ── Noise ──────────────────────────────────────────────────────────────────── #

func _setup_noise() -> void:
	var r: float = maxf(base_radius, 1.0)

	_warp_noise = _make_noise(_seed + 9999, 1.0 / (r * 0.8), FastNoiseLite.FRACTAL_FBM, 3)
	_warp_amp   = r * 0.18

	# Enough octaves that the finest coastline wiggle is ~5 world units, whatever
	# the island's size — big islands get more detail, not bigger blobs.
	var octaves: int = clampi(1 + int(ceil(log(r * 0.6 / 5.0) / log(2.0))), 3, 7)
	_coast_noise = _make_noise(_seed + 4242, 1.0 / (r * 0.6), FastNoiseLite.FRACTAL_FBM, octaves)
	_coast_noise.fractal_gain = 0.55

	_ridge_noise  = _make_noise(_seed + 777,   1.0 / (r * 0.25), FastNoiseLite.FRACTAL_RIDGED, 3)
	_hill_noise   = _make_noise(_seed + 1313,  1.0 / (r * 0.35), FastNoiseLite.FRACTAL_FBM, 3)
	_forest_noise = _make_noise(_seed + 54321, 0.06,             FastNoiseLite.FRACTAL_FBM, 2)
	_cliff_noise  = _make_noise(_seed + 2468,  1.0 / (r * 0.3),  FastNoiseLite.FRACTAL_FBM, 2)


func _make_noise(noise_seed: int, freq: float, fractal: FastNoiseLite.FractalType,
		octaves: int) -> FastNoiseLite:
	var n: FastNoiseLite = FastNoiseLite.new()
	n.seed            = noise_seed
	n.noise_type      = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency       = freq
	n.fractal_type    = fractal
	n.fractal_octaves = octaves
	return n


# ── Biome zone setup ───────────────────────────────────────────────────────── #

# Populates _zones with 1–4 spatial biome zones.
# ATOLLs get a single covering ATOLL zone; all others get 1–4 typed zones
# whose positions drive the height, tinting, resources, and tree variety.
func _setup_zones() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + 88888

	# ATOLLs stay as a single covering zone — ring land field handles shape.
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
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + 77777
	# Rivers occur on lush/highland zones; volcanic and desert terrain is too rough.
	var has_lush_zone: bool = false
	for zone: BiomeZone in _zones:
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
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + 11111

	for zone: BiomeZone in _zones:
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
# ATOLL skips this entirely — its ring land field handles the shape.

func _setup_peaks() -> void:
	if island_type == IslandType.ATOLL:
		_setup_passes()
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + 22222

	for zone: BiomeZone in _zones:
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

	# Peak reach shrinks with more peaks so valleys form between them.
	match _peaks.size():
		1: _peak_reach = base_radius * 0.90
		2: _peak_reach = base_radius * 0.78
		3: _peak_reach = base_radius * 0.73
		_: _peak_reach = base_radius * 0.68


# Every atoll gets 1–3 channels through the reef so the lagoon is always
# reachable by boat.  Spread apart so two passes never merge into one gap.
func _setup_passes() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed + 33333

	var count: int = 1
	var roll: float = rng.randf()
	if roll < 0.15:
		count = 3
	elif roll < 0.55:
		count = 2

	var start: float = rng.randf() * TAU
	for i: int in range(count):
		var spread: float = TAU / float(count)
		_pass_angles.append(start + float(i) * spread + rng.randf_range(-0.25, 0.25) * spread)

	# Channel half-width 7–11 world units, measured along the ring (radius 0.72 r).
	var half_width: float = rng.randf_range(7.0, 11.0)
	_pass_half_angle = half_width / maxf(base_radius * 0.72, 1.0)


## 0–1 mask: 1 in the middle of an atoll pass, 0 away from every pass.
## Uses the warped position so channels bend with the ring.
func _pass_mask(qx: float, qz: float) -> float:
	var ang: float = atan2(qz, qx)
	var best: float = 0.0
	for pass_angle: float in _pass_angles:
		var diff: float = absf(wrapf(ang - pass_angle, -PI, PI))
		best = maxf(best, 1.0 - smoothstep(_pass_half_angle * 0.6, _pass_half_angle, diff))
	return best


# ── Height helpers ─────────────────────────────────────────────────────────── #

## Global max height — used for rock blending thresholds.
func _get_max_height() -> float:
	var mh: float = 0.0
	for zone: BiomeZone in _zones:
		mh = maxf(mh, zone.max_height)
	return mh


## Gaussian zone influence.  Never reaches zero, so every point on the island
## has a well-defined blend (no gaps where heights or tints snap).  Must match
## the weighting in island_terrain.gdshader.
func _zone_weight(zone: BiomeZone, x: float, z: float) -> float:
	var dx: float = x - zone.pos.x
	var dz: float = z - zone.pos.y
	var t2: float = (dx * dx + dz * dz) / maxf(zone.radius * zone.radius, 0.001)
	return exp(-3.0 * t2)


## Zone-weighted height cap at a given local XZ position.
func _zone_weighted_max_height(x: float, z: float) -> float:
	var total_w:  float = 0.0
	var weighted: float = 0.0
	for zone: BiomeZone in _zones:
		var w: float = _zone_weight(zone, x, z)
		weighted += zone.max_height * w
		total_w  += w
	if total_w < 1e-12:
		return _get_max_height()
	return weighted / total_w


## Returns the ZoneType int of the zone with the highest influence at (x, z).
## Used to select tree pools and density thresholds per placement point.
func _dominant_zone_at(x: float, z: float) -> int:
	var best_w:  float = -1.0
	var best_zt: int   = ZoneType.TROPICAL
	for zone: BiomeZone in _zones:
		var w: float = _zone_weight(zone, x, z)
		if w > best_w:
			best_w  = w
			best_zt = zone.zone_type
	return best_zt


# ── Height function ────────────────────────────────────────────────────────── #
# Two stages, both on the build thread:
#   1. _sample_point() evaluates the noise at every grid vertex: the land field s
#      (where the coast is), relief (how high mountains/hills want to be there),
#      and the atoll radius / river mask.
#   2. _coast_distance() measures true world-unit distance to the s = 0 coastline
#      across the grid, and _compose_height() builds beach and seabed slopes from
#      that distance.  Using real distance (not s itself) means every shore gets
#      the same beach width and foam lip — no broad sea-level flats where the
#      noise happens to flatten s out.

## Height at an island-local position, bilinear from the built grid.
## Returns the seabed floor before the terrain has finished building.
func get_height_at(local_x: float, local_z: float) -> float:
	return _grid_height(_heights, local_x, local_z)


func _grid_height(heights: PackedFloat32Array, x: float, z: float) -> float:
	var nv: int = _grid_n + 1
	if heights.size() != nv * nv:
		return _SEABED_FLOOR
	var fx: float = clampf((x + _extent) / _cell, 0.0, float(_grid_n) - 0.001)
	var fz: float = clampf((z + _extent) / _cell, 0.0, float(_grid_n) - 0.001)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var i: int = iz * nv + ix
	var top:    float = lerpf(heights[i],      heights[i + 1],      tx)
	var bottom: float = lerpf(heights[i + nv], heights[i + nv + 1], tx)
	return lerpf(top, bottom, tz)


## Ground steepness (rise over run) at an island-local position.
func _grid_slope(heights: PackedFloat32Array, x: float, z: float) -> float:
	var gx: float = _grid_height(heights, x + _cell, z) - _grid_height(heights, x - _cell, z)
	var gz: float = _grid_height(heights, x, z + _cell) - _grid_height(heights, x, z - _cell)
	return sqrt(gx * gx + gz * gz) / (2.0 * _cell)


## Noise inputs at one point: x = land field s (> 0 land), y = relief height
## (mountains + hills, world units), z = warped normalised radius, w = river mask.
func _sample_point(x: float, z: float) -> Vector4:
	var r: float = base_radius
	if sqrt(x * x + z * z) / r > 1.8:
		return Vector4(-10.0, 0.0, 2.0, 0.0)   # beyond any possible coast

	# Domain warp: bend the sample position so coast, peaks and bays all distort
	# together and nothing follows a circle.
	var qx: float = x + _warp_noise.get_noise_2d(x, z) * _warp_amp
	var qz: float = z + _warp_noise.get_noise_2d(x + 173.1, z - 91.7) * _warp_amp
	var d:  float = sqrt(qx * qx + qz * qz) / r
	var n:  float = _coast_noise.get_noise_2d(qx, qz)

	var s: float
	if island_type == IslandType.ATOLL:
		s = 0.07 - absf(d - 0.72) + n * 0.12      # reef ring; low noise opens extra gaps
		# Guaranteed passes: the ring peaks at s ≈ 0.19, so -0.35 always opens a
		# channel whose centre sits well below the boat's keel.
		s -= _pass_mask(qx, qz) * 0.35
	else:
		s = (0.95 - d) + n * 0.55
	s -= smoothstep(1.15, 1.40, d) * 1.5          # land can never reach the mesh edge

	var relief: float = 0.0
	if s > -0.02:
		relief = _relief(x, z, qx, qz)
	var v: float = _river_valley(x, z) if _has_river else 0.0
	return Vector4(s, relief, d, v)


## Height the ground wants to reach inland of the beach (world units).
func _relief(x: float, z: float, qx: float, qz: float) -> float:
	var max_h: float = _zone_weighted_max_height(x, z)
	var hills: float = _hill_noise.get_noise_2d(qx, qz) * 0.5 + 0.5

	if island_type == IslandType.ATOLL:
		return hills * max_h * 0.35

	var mount: float = 0.0
	for peak: Vector3 in _peaks:
		var dx: float = qx - peak.x
		var dz: float = qz - peak.y
		var rn: float = sqrt(dx * dx + dz * dz) / _peak_reach
		if rn < 1.0:
			var p: float = 1.0 - rn
			# Half rounded dome, half sharp cone.
			mount += lerpf(p * p, p * p * (3.0 - 2.0 * p), 0.5) * peak.z
	mount = clampf(mount, 0.0, 1.0)
	var ridge: float = _ridge_noise.get_noise_2d(qx, qz) * 0.5 + 0.5
	mount *= 0.65 + 0.35 * ridge

	return (mount + hills * 0.10) * max_h


## Cliff inputs at an island-local position: x = coastal cliff height (0 on
## beach coasts), y = coastal cliff mask 0–1, z = terrace step height,
## w = terrace strength 0–1.  Zone-weighted, so biome borders blend smoothly.
func _cliff_params(x: float, z: float) -> Vector4:
	if island_type == IslandType.ATOLL:
		return Vector4.ZERO
	var total_w: float   = 0.0
	var zc:      Vector4 = Vector4.ZERO
	for zone: BiomeZone in _zones:
		var w:  float   = _zone_weight(zone, x, z)
		var zp: Vector4 = _ZONE_CLIFFS.get(zone.zone_type, Vector4.ZERO)
		zc      += zp * w
		total_w += w
	if total_w < 1e-12:
		return Vector4.ZERO
	zc /= total_w
	# One noise, two decorrelated samples: stretches of cliff coast, and patches
	# of terraced hillside.
	var coast: float = smoothstep(0.05, 0.22, _cliff_noise.get_noise_2d(x, z) + zc.y)
	var terr:  float = smoothstep(-0.10, 0.25, _cliff_noise.get_noise_2d(x + 517.3, z - 229.1))
	return Vector4(zc.x * coast, coast, zc.z, zc.w * terr)


## Stair-steps a height: flat benches with a steep riser at the top of each
## step.  Where the ground was already rising fast, the risers become cliffs.
func _terrace(h: float, step: float) -> float:
	var f: float = h / step
	var i: float = floor(f)
	return (i + smoothstep(1.0 - _TERRACE_RISER, 1.0, f - i)) * step


## Final height from a sample, its distance (world units) to the coastline, and
## its island-local position.
func _compose_height(sp: Vector4, dist: float, x: float, z: float) -> float:
	# Deep seabed never needs cliff inputs (it's at the floor either way).
	var cl: Vector4 = Vector4.ZERO
	if sp.x > 0.0 or dist < 36.0:
		cl = _cliff_params(x, z)

	var h: float
	if sp.x > 0.0:
		var ramp:   float = maxf(8.0, base_radius * 0.15)
		var relief: float = smoothstep(0.0, ramp, dist) * sp.y
		if cl.w > 0.0 and cl.z > 0.5:
			relief = lerpf(relief, _terrace(relief, cl.z), cl.w)
		# Cliff coasts: the land rises to the cliff top within ~one grid cell
		# instead of the gentle beach ramp.
		var beach: float = minf(dist * _BEACH_SLOPE, _BEACH_CAP)
		var cliff: float = cl.x * smoothstep(0.0, _cell * _CLIFF_RUN, dist)
		h = maxf(beach, cliff) + relief
	else:
		var slope: float = lerpf(_SEABED_SLOPE, _CLIFF_SEABED_SLOPE, cl.y)
		h = maxf(-dist * slope, _SEABED_FLOOR)
		if island_type == IslandType.ATOLL:
			var lagoon: float = maxf(-dist * 0.3, _LAGOON_FLOOR)
			h = lerpf(h, lagoon, 1.0 - smoothstep(0.62, 0.74, sp.z))

	if sp.w > 0.0:
		# Carve a valley.  Lower reaches drop below sea level and fill with real
		# ocean water; upper reaches are a dry valley with a painted river bed.
		# Through high ground the valley's edge sharpens into a steep gorge.
		var v: float = lerpf(sp.w, smoothstep(0.35, 0.65, sp.w), smoothstep(4.0, 14.0, h))
		h -= v * (0.85 * maxf(h, 0.0) + 0.6)
	return h


## Unsigned distance (world units) from every grid vertex to the s = 0 coastline.
## Seeds vertices beside a sign change with the exact sub-cell crossing, then
## spreads outward with a two-pass 8-neighbour chamfer (within a few % of true
## Euclidean distance — plenty for slopes).
func _coast_distance(samples: PackedVector4Array, nv: int) -> PackedFloat32Array:
	var dist: PackedFloat32Array = PackedFloat32Array()
	dist.resize(nv * nv)
	dist.fill(1.0e9)

	for iz: int in range(nv):
		for ix: int in range(nv):
			var i: int = iz * nv + ix
			var a: float = samples[i].x
			if ix + 1 < nv:
				var b: float = samples[i + 1].x
				if (a > 0.0) != (b > 0.0):
					var t: float = a / (a - b)
					dist[i]     = minf(dist[i],     t * _cell)
					dist[i + 1] = minf(dist[i + 1], (1.0 - t) * _cell)
			if iz + 1 < nv:
				var b2: float = samples[i + nv].x
				if (a > 0.0) != (b2 > 0.0):
					var t2: float = a / (a - b2)
					dist[i]      = minf(dist[i],      t2 * _cell)
					dist[i + nv] = minf(dist[i + nv], (1.0 - t2) * _cell)

	var c:    float = _cell
	var diag: float = _cell * 1.41421356
	# Forward pass: neighbours above and to the left.
	for iz: int in range(nv):
		for ix: int in range(nv):
			var i: int = iz * nv + ix
			var best: float = dist[i]
			if ix > 0:
				best = minf(best, dist[i - 1] + c)
			if iz > 0:
				best = minf(best, dist[i - nv] + c)
				if ix > 0:
					best = minf(best, dist[i - nv - 1] + diag)
				if ix + 1 < nv:
					best = minf(best, dist[i - nv + 1] + diag)
			dist[i] = best
	# Backward pass: neighbours below and to the right.
	for iz: int in range(nv - 1, -1, -1):
		for ix: int in range(nv - 1, -1, -1):
			var i: int = iz * nv + ix
			var best: float = dist[i]
			if ix + 1 < nv:
				best = minf(best, dist[i + 1] + c)
			if iz + 1 < nv:
				best = minf(best, dist[i + nv] + c)
				if ix + 1 < nv:
					best = minf(best, dist[i + nv + 1] + diag)
				if ix > 0:
					best = minf(best, dist[i + nv - 1] + diag)
			dist[i] = best
	return dist


## 0–1 river valley mask in island-local space.  Must match river_mask() in
## island_terrain.gdshader (same angle, width, meander and start).
func _river_valley(x: float, z: float) -> float:
	var c:      float = cos(_river_angle)
	var sn:     float = sin(_river_angle)
	var along:  float = x * c + z * sn
	var perp:   float = -x * sn + z * c
	var w:      float = base_radius * 0.07
	var across: float = absf(perp - sin(along / (base_radius * 0.15)) * w * 1.5)
	var start:  float = base_radius * 0.25
	return (1.0 - smoothstep(w * 0.5, w * 3.0, across)) * smoothstep(start * 0.5, start, along)


# ── Materials ─────────────────────────────────────────────────────────────────#

func _build_materials() -> void:
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = _TERRAIN_SHADER

	# Rock layer: lava if any zone is VOLCANIC, mossy stone otherwise.
	var has_volcanic: bool = false
	for zone: BiomeZone in _zones:
		if zone.zone_type == ZoneType.VOLCANIC:
			has_volcanic = true
			break
	var rock_path: String = _TEX_LAVA_ROCK if has_volcanic else _TEX_ROCK
	_terrain_mat.set_shader_parameter("sand_tex",  load(_TEX_SAND) as Texture2D)
	_terrain_mat.set_shader_parameter("grass_tex", load(_TEX_GRASS) as Texture2D)
	_terrain_mat.set_shader_parameter("rock_tex",  load(rock_path) as Texture2D)

	# Cliff texture slot i belongs to zone i; unused slots repeat zone 0's.
	for i: int in range(4):
		var zt: int = _zones[mini(i, _zones.size() - 1)].zone_type
		var cliff_path: String = _ZONE_CLIFF_TEX.get(zt, _ZONE_CLIFF_TEX[3])
		_terrain_mat.set_shader_parameter("cliff_tex_%d" % i, load(cliff_path) as Texture2D)

	var max_h: float = _get_max_height()
	if island_type == IslandType.ATOLL:
		# Atolls are mostly sand with a little scrub on the high spots.
		_terrain_mat.set_shader_parameter("blend_low",  1.6)
		_terrain_mat.set_shader_parameter("blend_high", 3.0)
		_terrain_mat.set_shader_parameter("rock_low",  999.0)
		_terrain_mat.set_shader_parameter("rock_high", 1000.0)
	else:
		# The beach ramp tops out at _BEACH_CAP, so sand gives way to grass there.
		_terrain_mat.set_shader_parameter("blend_low",  0.8)
		_terrain_mat.set_shader_parameter("blend_high", 1.8)
		_terrain_mat.set_shader_parameter("rock_low",  max_h * 0.55)
		_terrain_mat.set_shader_parameter("rock_high", max_h * 0.82)

	_terrain_mat.set_shader_parameter("has_river",     1.0 if _has_river else 0.0)
	_terrain_mat.set_shader_parameter("river_angle",   _river_angle)
	_terrain_mat.set_shader_parameter("river_width",   base_radius * 0.07)
	_terrain_mat.set_shader_parameter("river_meander", 1.0 / (base_radius * 0.15))
	_terrain_mat.set_shader_parameter("river_start",   base_radius * 0.25)

	# Zone arrays drive spatial tinting in the shader.  Uniform arrays must be
	# set whole — "name[i]" parameter paths are not supported.
	# zone_data[i]       — xy = local XZ centre, z = influence radius, w = unused
	# zone_grass_tint[i] — colour multiplied onto the grass/vegetation layer
	# zone_rock_tint[i]  — colour multiplied onto the rock layer
	var zone_count: int = mini(_zones.size(), 4)
	var zone_data:  PackedVector4Array = PackedVector4Array()
	var grass_tint: PackedVector4Array = PackedVector4Array()
	var rock_tint:  PackedVector4Array = PackedVector4Array()
	zone_data.resize(4)
	grass_tint.resize(4)
	rock_tint.resize(4)
	for i: int in range(zone_count):
		var zone: BiomeZone = _zones[i]
		var g: Color = _ZONE_GRASS_TINT.get(zone.zone_type, Color.WHITE)
		var k: Color = _ZONE_ROCK_TINT.get(zone.zone_type, Color.WHITE)
		zone_data[i]  = Vector4(zone.pos.x, zone.pos.y, zone.radius, 0.0)
		grass_tint[i] = Vector4(g.r, g.g, g.b, g.a)
		rock_tint[i]  = Vector4(k.r, k.g, k.b, k.a)
	_terrain_mat.set_shader_parameter("zone_count",      zone_count)
	_terrain_mat.set_shader_parameter("zone_data",       zone_data)
	_terrain_mat.set_shader_parameter("zone_grass_tint", grass_tint)
	_terrain_mat.set_shader_parameter("zone_rock_tint",  rock_tint)


# ── Terrain data (runs on a worker thread when build_async) ───────────────── #
# Only pure math here — no scene tree access.  Results land in member arrays
# that _finish_build() turns into nodes on the main thread.

func _generate_terrain_data() -> void:
	var nv: int = _grid_n + 1
	var samples: PackedVector4Array = PackedVector4Array()
	samples.resize(nv * nv)
	for iz: int in range(nv):
		var wz: float = -_extent + float(iz) * _cell
		for ix: int in range(nv):
			samples[iz * nv + ix] = _sample_point(-_extent + float(ix) * _cell, wz)

	var dist: PackedFloat32Array = _coast_distance(samples, nv)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(nv * nv)
	for iz: int in range(nv):
		var wz: float = -_extent + float(iz) * _cell
		for ix: int in range(nv):
			var i: int = iz * nv + ix
			heights[i] = _compose_height(samples[i], dist[i], -_extent + float(ix) * _cell, wz)

	# Collision heightmap: uniform scale by _cell, so heights are stored in cell
	# units.  Seabed clamped — the boat only ever touches the shallows.
	var col: PackedFloat32Array = PackedFloat32Array()
	col.resize(nv * nv)
	for i: int in range(nv * nv):
		col[i] = maxf(heights[i], -2.0) / _cell

	_heights        = heights
	_collision_data = col
	_chunk_arrays   = _build_chunk_arrays(heights, nv)
	_tree_xforms    = _place_trees(heights)


func _build_chunk_arrays(heights: PackedFloat32Array, nv: int) -> Array[Array]:
	var out: Array[Array] = []
	var n: int = _grid_n
	var chunks: int = int(ceil(float(n) / float(_CHUNK_CELLS)))

	# Cells the waterline passes through get subdivided (see _append_coast_cell).
	var refine: PackedByteArray = PackedByteArray()
	refine.resize(n * n)
	for iz: int in range(n):
		for ix: int in range(n):
			var i: int = iz * nv + ix
			var mn: float = minf(minf(heights[i], heights[i + 1]), minf(heights[i + nv], heights[i + nv + 1]))
			var mx: float = maxf(maxf(heights[i], heights[i + 1]), maxf(heights[i + nv], heights[i + nv + 1]))
			refine[iz * n + ix] = 1 if (mn < _COAST_BAND and mx > -_COAST_BAND) else 0

	for cz: int in range(chunks):
		for cx: int in range(chunks):
			var x0: int = cx * _CHUNK_CELLS
			var z0: int = cz * _CHUNK_CELLS
			var x1: int = mini(x0 + _CHUNK_CELLS, n)
			var z1: int = mini(z0 + _CHUNK_CELLS, n)
			var w:  int = x1 - x0 + 1

			# Base vertex grid for the chunk (coarse cells index into it).
			var verts:   PackedVector3Array = PackedVector3Array()
			var normals: PackedVector3Array = PackedVector3Array()
			verts.resize(w * (z1 - z0 + 1))
			normals.resize(w * (z1 - z0 + 1))
			for iz: int in range(z0, z1 + 1):
				var row:  int = iz * nv
				var up:   int = maxi(iz - 1, 0) * nv
				var down: int = mini(iz + 1, n) * nv
				for ix: int in range(x0, x1 + 1):
					var li: int = (iz - z0) * w + (ix - x0)
					verts[li] = Vector3(-_extent + float(ix) * _cell, heights[row + ix],
							-_extent + float(iz) * _cell)
					# Central-difference normal straight from the height grid.
					var hl: float = heights[row + maxi(ix - 1, 0)]
					var hr: float = heights[row + mini(ix + 1, n)]
					var hu: float = heights[up + ix]
					var hd: float = heights[down + ix]
					normals[li] = Vector3(hl - hr, 2.0 * _cell, hu - hd).normalized()

			var indices: PackedInt32Array = PackedInt32Array()
			for iz: int in range(z0, z1):
				for ix: int in range(x0, x1):
					if refine[iz * n + ix] == 1:
						_append_coast_cell(heights, refine, ix, iz, verts, normals, indices)
						continue
					var h00: float = heights[iz * nv + ix]
					var h10: float = heights[iz * nv + ix + 1]
					var h01: float = heights[(iz + 1) * nv + ix]
					var h11: float = heights[(iz + 1) * nv + ix + 1]
					if maxf(maxf(h00, h10), maxf(h01, h11)) < _MESH_SKIP_DEPTH:
						continue
					var i00: int = (iz - z0) * w + (ix - x0)
					var i10: int = i00 + 1
					var i01: int = i00 + w
					var i11: int = i01 + 1
					# Clockwise seen from above = Godot front face, so back-face
					# culling works and normals point up.
					indices.append(i00); indices.append(i10); indices.append(i11)
					indices.append(i00); indices.append(i11); indices.append(i01)
			if indices.is_empty():
				continue

			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_INDEX]  = indices
			out.append(arrays)
	return out


## Splits one coastal grid cell into _COAST_SUBDIV² sub-cells with Catmull-Rom
## (smooth, C1) heights, so the waterline is a curve instead of a chain of
## straight segments with hard corners.
## Crack-free: on any edge shared with an unrefined cell (or the grid border),
## sub-vertices use plain linear interpolation — exactly the coarse neighbour's
## straight triangle edge.  Refined↔refined edges evaluate the same bicubic, so
## they match too.  Corners are the original grid heights in both cases.
func _append_coast_cell(heights: PackedFloat32Array, refine: PackedByteArray, ix: int, iz: int,
		verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var n:    int   = _grid_n
	var nv:   int   = n + 1
	var k:    int   = _COAST_SUBDIV
	var step: float = 1.0 / float(k)

	# Bicubic heights on a padded (k+3)² sub-grid: the extra ring gives
	# central-difference normals that agree with neighbouring refined cells.
	var pw: int = k + 3
	var hs: PackedFloat32Array = PackedFloat32Array()
	hs.resize(pw * pw)
	for sj: int in range(pw):
		for si: int in range(pw):
			hs[sj * pw + si] = _bicubic(heights, float(ix) + float(si - 1) * step,
					float(iz) + float(sj - 1) * step)

	var lin_w: bool = ix == 0     or refine[iz * n + ix - 1] == 0
	var lin_e: bool = ix == n - 1 or refine[iz * n + ix + 1] == 0
	var lin_n: bool = iz == 0     or refine[(iz - 1) * n + ix] == 0
	var lin_s: bool = iz == n - 1 or refine[(iz + 1) * n + ix] == 0
	var h00: float = heights[iz * nv + ix]
	var h10: float = heights[iz * nv + ix + 1]
	var h01: float = heights[(iz + 1) * nv + ix]
	var h11: float = heights[(iz + 1) * nv + ix + 1]

	var base: int = verts.size()
	var sub_step: float = step * _cell
	for sj: int in range(k + 1):
		for si: int in range(k + 1):
			var h: float = hs[(sj + 1) * pw + si + 1]
			if (si == 0 and lin_w) or (si == k and lin_e) or (sj == 0 and lin_n) or (sj == k and lin_s):
				var tx: float = float(si) * step
				var tz: float = float(sj) * step
				h = lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
			verts.append(Vector3(-_extent + (float(ix) + float(si) * step) * _cell, h,
					-_extent + (float(iz) + float(sj) * step) * _cell))
			var hl: float = hs[(sj + 1) * pw + si]
			var hr: float = hs[(sj + 1) * pw + si + 2]
			var hu: float = hs[sj * pw + si + 1]
			var hd: float = hs[(sj + 2) * pw + si + 1]
			normals.append(Vector3(hl - hr, 2.0 * sub_step, hu - hd).normalized())

	var row: int = k + 1
	for sj: int in range(k):
		for si: int in range(k):
			var i00: int = base + sj * row + si
			var i10: int = i00 + 1
			var i01: int = i00 + row
			var i11: int = i01 + 1
			indices.append(i00); indices.append(i10); indices.append(i11)
			indices.append(i00); indices.append(i11); indices.append(i01)


## Catmull-Rom bicubic sample of the height grid at fractional grid coords.
## Passes exactly through every grid height, with a continuous slope between.
func _bicubic(heights: PackedFloat32Array, fx: float, fz: float) -> float:
	var n:  int   = _grid_n
	var nv: int   = n + 1
	var ix: int   = clampi(int(floor(fx)), 0, n - 1)
	var iz: int   = clampi(int(floor(fz)), 0, n - 1)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var c0: int = clampi(ix - 1, 0, n)
	var c1: int = ix
	var c2: int = ix + 1
	var c3: int = clampi(ix + 2, 0, n)
	var r0: int = clampi(iz - 1, 0, n) * nv
	var r1: int = iz * nv
	var r2: int = (iz + 1) * nv
	var r3: int = clampi(iz + 2, 0, n) * nv
	return _catmull_rom(
		_catmull_rom(heights[r0 + c0], heights[r0 + c1], heights[r0 + c2], heights[r0 + c3], tx),
		_catmull_rom(heights[r1 + c0], heights[r1 + c1], heights[r1 + c2], heights[r1 + c3], tx),
		_catmull_rom(heights[r2 + c0], heights[r2 + c1], heights[r2 + c2], heights[r2 + c3], tx),
		_catmull_rom(heights[r3 + c0], heights[r3 + c1], heights[r3 + c2], heights[r3 + c3], tx),
		tz)


func _catmull_rom(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	return p1 + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3
			+ t * (3.0 * (p1 - p2) + p3 - p0)))


func _place_trees(heights: PackedFloat32Array) -> Dictionary:
	var out: Dictionary = {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed

	var placed:   int = 0
	var attempts: int = 0
	while placed < num_trees and attempts < num_trees * 10:
		attempts += 1
		# sqrt → uniform over the disc area instead of bunching at the centre.
		var angle: float = rng.randf() * TAU
		var r:     float = sqrt(rng.randf()) * base_radius * 1.25
		var x:     float = cos(angle) * r
		var z:     float = sin(angle) * r

		var y: float = _grid_height(heights, x, z)
		if y < _TREE_MIN_HEIGHT:
			continue
		if _grid_slope(heights, x, z) > _TREE_MAX_SLOPE:
			continue

		var zt: int = _dominant_zone_at(x, z)
		var density_threshold: float = _ZONE_DENSITY_THRESHOLD.get(zt, 0.25)
		var density: float = _forest_noise.get_noise_2d(x, z) * 0.5 + 0.5
		if density < density_threshold:
			continue

		var clusters: Array = _ZONE_TREE_CLUSTERS.get(zt, [])
		if clusters.is_empty():
			continue
		var cluster: String = clusters[rng.randi() % clusters.size()]
		var variant: String = _TREE_VARIANTS[rng.randi() % _TREE_VARIANTS.size()]
		var path: String = _TREE_DIR % [cluster, variant]

		var s: float = rng.randf_range(_TREE_SCALE_MIN, _TREE_SCALE_MAX)
		var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3(s, s * rng.randf_range(0.90, 1.15), s))
		if not out.has(path):
			out[path] = []
		(out[path] as Array).append(Transform3D(basis, Vector3(x, y - 0.1, z)))
		placed += 1
	return out


# ── Node building (main thread) ───────────────────────────────────────────── #

func _finish_build() -> void:
	for arrays: Array in _chunk_arrays:
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _terrain_mat)
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
	_chunk_arrays.clear()

	_build_collision()
	_build_trees()


func _build_collision() -> void:
	var nv: int = _grid_n + 1
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = nv
	shape.map_depth = nv
	shape.map_data  = _collision_data
	var col: CollisionShape3D = CollisionShape3D.new()
	col.shape = shape
	# HeightMapShape3D is centred with 1-unit spacing; uniform scale maps it onto
	# the render grid (heights were pre-divided by _cell to match).
	col.scale = Vector3(_cell, _cell, _cell)
	add_child(col)
	_collision_data = PackedFloat32Array()


# One MultiMeshInstance3D per tree model: every copy of that model on this
# island draws in one call per material, instead of one node per tree.
func _build_trees() -> void:
	for path: String in _tree_xforms.keys():
		var mesh: ArrayMesh = _tree_mesh(path)
		if mesh == null:
			continue
		var xforms: Array = _tree_xforms[path]
		var mm: MultiMesh = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i: int in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i] as Transform3D)
		var mmi: MultiMeshInstance3D = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
	_tree_xforms.clear()


## Loads a tree GLB and bakes all its MeshInstance3D pieces (with their node
## transforms) into ONE ArrayMesh with one surface per material.  The Claude
## Design clusters have 18–67 pieces each; merged they're ~5 surfaces, i.e.
## ~5 draw calls per model per island.  Cached across all islands.
static func _tree_mesh(path: String) -> ArrayMesh:
	if _tree_mesh_cache.has(path):
		return _tree_mesh_cache[path]
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("Island: failed to load tree GLB: %s" % path)
		_tree_mesh_cache[path] = null
		return null

	var root: Node = packed.instantiate()
	# Material -> SurfaceTool collecting every piece that uses it.
	var by_mat: Dictionary = {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf: Transform3D = Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		if root is Node3D:
			xf = (root as Node3D).transform * xf
		for s: int in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.get_active_material(s)
			if not by_mat.has(mat):
				var st_new: SurfaceTool = SurfaceTool.new()
				st_new.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st_new
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, s, xf)
	root.free()

	var merged: ArrayMesh = ArrayMesh.new()
	for mat: Variant in by_mat.keys():
		var st: SurfaceTool = by_mat[mat] as SurfaceTool
		if mat != null:
			st.set_material(mat as Material)
		st.commit(merged)
	_tree_mesh_cache[path] = merged
	return merged


# ── Discovery ──────────────────────────────────────────────────────────────── #

func _physics_process(_delta: float) -> void:
	if _boat == null:
		return
	var self_xz: Vector2 = Vector2(global_position.x, global_position.z)
	var boat_xz: Vector2 = Vector2(_boat.global_position.x, _boat.global_position.z)
	if self_xz.distance_to(boat_xz) <= discovery_radius:
		_discover()


func _discover() -> void:
	discovered = true
	set_physics_process(false)
	island_discovered.emit(island_name, Vector2(global_position.x, global_position.z), resources)
	var fog: FogOfWar = get_tree().get_first_node_in_group("fog_of_war") as FogOfWar
	if fog != null:
		# Fog is sampled at true world positions now, so the reveal only needs
		# to cover the island's footprint (coasts reach ~1.25 × base_radius).
		fog.reveal_area(Vector2(global_position.x, global_position.z), base_radius * 1.35 + 12.0)
	print("Discovered: ", island_name)
