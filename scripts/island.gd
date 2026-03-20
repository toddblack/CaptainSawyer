extends StaticBody3D
class_name Island

signal island_discovered(island_name: String, world_pos: Vector2)

enum IslandType { TROPICAL, VOLCANIC, ATOLL, HIGHLAND }

@export var island_name:      String     = "Unknown Isle"
@export var base_radius:      float      = 4.0
@export var num_trees:        int        = 3
@export var discovery_radius: float      = 18.0
@export var island_type:      IslandType = IslandType.TROPICAL

var discovered:   bool   = false
var _boat:        Node3D = null
var _has_river:   bool   = false
var _river_angle: float  = 0.0

# Terrain shader + single unified atlas
const _TERRAIN_SHADER = preload("res://assets/materials/island_terrain.gdshader")
const _TEX_ATLAS      = preload("res://assets/textures/dirt_sand_water_stone.png")

# Materials
var _terrain_mat: ShaderMaterial

# GLB tree pools keyed by IslandType int value.
# Singular-named files are individual trees; plural/group files excluded.
# Scale range 0.20–0.38 converts Quaternius meter-scale to game units (~1-3 u tall).
const _TREE_SCALE_MIN: float = 0.10
const _TREE_SCALE_MAX: float = 0.19

const _TREE_POOLS: Dictionary = {
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
}

# Noise
var _height_noise: FastNoiseLite
var _edge_noise:   FastNoiseLite   # used for domain warp — creates organic coastlines
var _forest_noise: FastNoiseLite

# Peaks — each Vector3 is (world_x, world_z, strength 0-1).
# Multi-peak layout drives shape: gaps between peaks become bays.
var _peaks: Array[Vector3] = []

# Grid resolution — computed per island in _ready() so cell size stays ~2 world units
# regardless of island radius.  Clamped to 64–128.
var _grid_n: int


func _ready() -> void:
	_grid_n = clampi(int(base_radius * 1.5), 64, 128)
	_setup_noise()
	_setup_type()
	_setup_peaks()
	_build_materials()
	_build_geometry()
	_boat = get_tree().get_first_node_in_group("boat")


# ------------------------------------------------------------------ #
#  Noise                                                               #
# ------------------------------------------------------------------ #

func _setup_noise() -> void:
	_height_noise = FastNoiseLite.new()
	_height_noise.seed       = island_name.hash()
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency  = 1.0  # we pass pre-scaled coords

	_edge_noise = FastNoiseLite.new()
	_edge_noise.seed       = island_name.hash() + 9999
	_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_edge_noise.frequency  = 1.0

	_forest_noise = FastNoiseLite.new()
	_forest_noise.seed       = island_name.hash() + 54321
	_forest_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_forest_noise.frequency  = 1.0


# ------------------------------------------------------------------ #
#  Island type                                                         #
# ------------------------------------------------------------------ #

func _setup_type() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash() + 77777
	match island_type:
		IslandType.TROPICAL, IslandType.HIGHLAND:
			_has_river   = rng.randf() < 0.60
			_river_angle = rng.randf() * TAU
		_:
			_has_river   = false
			_river_angle = 0.0


# ------------------------------------------------------------------ #
#  Peaks — multi-lobe shape generator                                  #
# ------------------------------------------------------------------ #

# Distributes 1-4 height peaks across the island.  Gaps between peaks
# become bays; peak overlap creates ridges.  ATOLLs skip this and use
# the ring profile directly in _height_at_xy.
func _setup_peaks() -> void:
	if island_type == IslandType.ATOLL:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash() + 22222

	var n: int
	match island_type:
		IslandType.TROPICAL: n = rng.randi_range(2, 3)
		IslandType.VOLCANIC:  n = rng.randi_range(1, 2)
		IslandType.HIGHLAND:  n = rng.randi_range(3, 4)
		_:                    n = rng.randi_range(1, 3)

	# How far peaks sit from island centre (as fraction of base_radius).
	# More spread → more elongated / more dramatic bays.
	var spread: float = rng.randf_range(0.28, 0.46)

	for i: int in range(n):
		var sector: float  = TAU / float(n)
		var jitter: float  = rng.randf_range(-sector * 0.35, sector * 0.35)
		var angle:  float  = float(i) * sector + jitter
		var dist:   float  = base_radius * (spread * rng.randf_range(0.70, 1.0) if n > 1 else rng.randf_range(0.0, 0.12))
		var strength: float = 1.0 if i == 0 else rng.randf_range(0.65, 1.0)
		_peaks.append(Vector3(cos(angle) * dist, sin(angle) * dist, strength))


func _get_max_height() -> float:
	var raw: float = base_radius * 0.55
	match island_type:
		IslandType.VOLCANIC: return min(raw, 80.0)   # dramatic cones — tallest type
		IslandType.ATOLL:    return min(raw, 10.0)   # flat ring stays at sea level
		IslandType.HIGHLAND: return min(raw, 70.0)   # mountain ranges with real scale
		_:                   return min(raw, 45.0)   # tropical — lush, moderate height


# ------------------------------------------------------------------ #
#  Height function — grid-based, domain-warped                        #
# ------------------------------------------------------------------ #

func _height_at_xy(x: float, z: float) -> float:
	var max_h: float = _get_max_height()

	# ── ATOLL: unchanged ring profile ──────────────────────────────────
	if island_type == IslandType.ATOLL:
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
		var res_a: float   = prof_a * max_h
		res_a = max(res_a, (1.0 - smoothstep(0.88, 1.0, r_norm_a)) * 0.80)
		return res_a

	# ── Multi-peak height for all other types ──────────────────────────
	var n: int = _peaks.size()
	if n == 0:
		return 0.0

	# Each peak's reach radius — slightly smaller with more peaks so that
	# gaps between distant peaks fall below sea level, forming bays.
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

		# Per-peak coast warp: direction-dependent radius variation.
		# Offsetting by peak world position gives each peak a unique coastline.
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

		# Peaked profile: tallest right at centre, smooth descent to edge.
		# smoothstep(0.05, 0.90) leaves only a tiny flat top so mountains
		# read as peaks rather than plateaux.
		var profile: float = 1.0 - smoothstep(0.05, 0.90, r_norm)
		total += profile * peak.z  # peak.z = strength

	# Clamp to [0,1].  Each peak can contribute up to 1.0, so single
	# isolated peaks reach full height.  Overlapping peaks saturate at
	# 1.0, forming ridges rather than stacking to unreachable values.
	total = clampf(total, 0.0, 1.0)

	# Hard outer clip — allows elongated tips up to 1.25× base_radius from centre
	var outer_r: float    = Vector2(x, z).length()
	var outer_mask: float = 1.0 - smoothstep(0.95, 1.25, outer_r / base_radius)
	total *= outer_mask

	if total <= 0.01:
		return 0.0

	var result: float = total * max_h
	# Narrow beach floor where the island meets the sea
	result = maxf(result, (1.0 - smoothstep(0.85, 1.05, outer_r / base_radius)) * 0.55)
	return result


# ------------------------------------------------------------------ #
#  Materials                                                           #
# ------------------------------------------------------------------ #

func _build_materials() -> void:
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = _TERRAIN_SHADER

	# Single 1024x1024 atlas — 4x4 grid of 256px tiles
	_terrain_mat.set_shader_parameter("terrain_atlas",     _TEX_ATLAS)
	_terrain_mat.set_shader_parameter("beach_tile_offset", Vector2(0.00, 0.25))
	_terrain_mat.set_shader_parameter("beach_tile_scale",  Vector2(0.25, 0.25))
	_terrain_mat.set_shader_parameter("grass_tile_offset", Vector2(0.00, 0.00))
	_terrain_mat.set_shader_parameter("grass_tile_scale",  Vector2(0.25, 0.25))

	# Fixed world-space tile size so grass/sand always looks the same scale
	# regardless of island size. Scaling with radius made large islands look bloated.
	_terrain_mat.set_shader_parameter("world_tile_size", 1.0)

	# Rock tile: lava for volcanic, mossy stone for everything else
	var rock_offset: Vector2
	match island_type:
		IslandType.VOLCANIC: rock_offset = Vector2(0.50, 0.50)
		_:                   rock_offset = Vector2(0.50, 0.00)
	_terrain_mat.set_shader_parameter("rock_tile_offset", rock_offset)
	_terrain_mat.set_shader_parameter("rock_tile_scale",  Vector2(0.25, 0.25))

	# Height-based blend: beach floor sits at 0.55 so blend_low matches it,
	# keeping the sandy strip narrow right at the coast edge.
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

	# Radial biome tints — coast vs interior colour zones.
	# island_center is always (0,0) since the mesh is centred on the island origin.
	_terrain_mat.set_shader_parameter("island_center", Vector2.ZERO)
	_terrain_mat.set_shader_parameter("island_radius", base_radius)
	match island_type:
		IslandType.TROPICAL:
			_terrain_mat.set_shader_parameter("coastal_tint",  Color(1.05, 0.98, 0.85))  # warm gold coast
			_terrain_mat.set_shader_parameter("interior_tint", Color(0.78, 1.00, 0.65))  # rich jungle green
		IslandType.VOLCANIC:
			_terrain_mat.set_shader_parameter("coastal_tint",  Color(0.75, 0.72, 0.68))  # dark ash coast
			_terrain_mat.set_shader_parameter("interior_tint", Color(1.00, 0.62, 0.42))  # fiery orange-red core
		IslandType.HIGHLAND:
			_terrain_mat.set_shader_parameter("coastal_tint",  Color(0.90, 0.98, 0.85))  # cool sea-green coast
			_terrain_mat.set_shader_parameter("interior_tint", Color(0.83, 0.88, 0.96))  # cool slate-blue peaks
		IslandType.ATOLL:
			_terrain_mat.set_shader_parameter("coastal_tint",  Color(1.02, 1.00, 0.94))  # barely-warm, flat
			_terrain_mat.set_shader_parameter("interior_tint", Color(1.00, 0.98, 0.90))  # slight warm center



# ------------------------------------------------------------------ #
#  Geometry                                                            #
# ------------------------------------------------------------------ #

func _build_geometry() -> void:
	# Compute the height grid once and share it with both the visual mesh
	# and the collision shape so they always match exactly.
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


func _build_terrain_mesh(heights: PackedFloat32Array, extent: float, cell_size: float, map_verts: int) -> void:
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
	return AABB(Vector3(-r, -0.2, -r), Vector3(r * 2.0, h + 0.2, r * 2.0))


func _build_collision(heights: PackedFloat32Array, extent: float, cell_size: float, map_verts: int) -> void:
	# Build a ConcavePolygonShape3D from the same height grid used for the
	# visual mesh.  Only land cells (max vertex height > 0.05) are added, so
	# the boat can sail freely through bays and right up to the true coastline.
	# Full resolution is used — stride subsampling caused cell sizes larger than
	# the boat hull, producing invisible ledges and missed collisions.
	var face_verts := PackedVector3Array()

	for iz: int in range(_grid_n):
		for ix: int in range(_grid_n):
			var h00: float = heights[ iz      * map_verts + ix    ]
			var h10: float = heights[ iz      * map_verts + ix + 1]
			var h01: float = heights[(iz + 1) * map_verts + ix    ]
			var h11: float = heights[(iz + 1) * map_verts + ix + 1]

			# Skip cells entirely below water
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
	shape.backface_collision = true  # collide from both sides — prevents getting trapped inside
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


# ------------------------------------------------------------------ #
#  Trees                                                               #
# ------------------------------------------------------------------ #

func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash()

	var density_threshold: float
	match island_type:
		IslandType.TROPICAL: density_threshold = 0.22
		IslandType.VOLCANIC: density_threshold = 0.52
		IslandType.ATOLL:    density_threshold = 0.28
		IslandType.HIGHLAND: density_threshold = 0.12
		_:                   density_threshold = 0.25

	var placed:   int = 0
	var attempts: int = 0
	while placed < num_trees and attempts < num_trees * 10:
		attempts += 1
		var angle:  float = rng.randf() * TAU
		var r:      float = rng.randf_range(0.0, base_radius * 0.92)
		var x:      float = cos(angle) * r
		var z:      float = sin(angle) * r
		var r_norm: float = r / base_radius

		# Atolls: only plant on the ring, not the central lagoon
		if island_type == IslandType.ATOLL and (r_norm < 0.35 or r_norm > 0.78):
			continue

		var y: float = _height_at_xy(x, z)
		if y < 0.20:
			continue

		# Forest clustering via noise
		var density: float = _forest_noise.get_noise_2d(x * 0.5, z * 0.5) * 0.5 + 0.5
		if density < density_threshold:
			continue

		_build_tree(rng, Vector3(x, y, z))
		placed += 1


func _build_tree(rng: RandomNumberGenerator, base_pos: Vector3) -> void:
	var pool: Array = _TREE_POOLS.get(int(island_type), [])
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
	tree.rotation.y = rng.randf() * TAU   # random facing for variety

	# Uniform scale with slight per-tree variation so the forest isn't uniform
	var s: float = rng.randf_range(_TREE_SCALE_MIN, _TREE_SCALE_MAX)
	tree.scale = Vector3(s, s * rng.randf_range(0.90, 1.15), s)

	# Tie every mesh inside the GLB to the island's AABB so the camera
	# frustum never culls individual trees while the island is in view.
	var aabb: AABB = _island_aabb()
	for m: Node in tree.find_children("*", "MeshInstance3D"):
		(m as MeshInstance3D).custom_aabb = aabb

	add_child(tree)


# ------------------------------------------------------------------ #
#  Discovery                                                           #
# ------------------------------------------------------------------ #

func _physics_process(_delta: float) -> void:
	if discovered or _boat == null:
		return
	var self_xz := Vector2(global_position.x, global_position.z)
	var boat_xz := Vector2(_boat.global_position.x, _boat.global_position.z)
	if self_xz.distance_to(boat_xz) <= discovery_radius:
		_discover()


func _discover() -> void:
	discovered = true
	island_discovered.emit(island_name, Vector2(global_position.x, global_position.z))
	# Punch a generous hole in the fog to expose the whole island including
	# the height-parallax shadow: a peak at height h has its Y=0 fog footprint
	# offset by ~h world units toward the camera, so we need extra radius.
	var fog: FogOfWar = get_tree().get_first_node_in_group("fog_of_war") as FogOfWar
	if fog != null:
		var island_xz: Vector2 = Vector2(global_position.x, global_position.z)
		fog.reveal_area(island_xz, base_radius * 1.5 + _get_max_height() * 2.0 + 15.0)
	print("Discovered: ", island_name)
