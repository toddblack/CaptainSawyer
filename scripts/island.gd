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
var _trunk_mat:   StandardMaterial3D
var _foliage_mat: StandardMaterial3D

var _trunk_meshes:   Array[MeshInstance3D] = []
var _foliage_meshes: Array[MeshInstance3D] = []

# Noise
var _height_noise: FastNoiseLite
var _edge_noise:   FastNoiseLite   # used for domain warp — creates organic coastlines
var _forest_noise: FastNoiseLite

# Grid resolution — 64x64 cells gives 65x65 = 4225 vertices per island
const GRID_N: int = 64


func _ready() -> void:
	_setup_noise()
	_setup_type()
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


func _get_max_height() -> float:
	var raw: float = base_radius * 0.38
	match island_type:
		IslandType.VOLCANIC: return min(raw, 14.0)
		IslandType.ATOLL:    return min(raw, 3.5)
		IslandType.HIGHLAND: return min(raw, 11.0)
		_:                   return min(raw, 8.0)


# ------------------------------------------------------------------ #
#  Height function — grid-based, domain-warped                        #
# ------------------------------------------------------------------ #

func _height_at_xy(x: float, z: float) -> float:
	var raw_r: float = Vector2(x, z).length()

	# Organic coastline: vary effective radius by direction (angle-based).
	# Using normalised direction as noise input keeps the island connected —
	# no interior holes possible, unlike displacement-based domain warp.
	var coast_n: float
	if raw_r < 0.001:
		coast_n = 0.0
	else:
		var nx: float = x / raw_r  # cos(angle)
		var nz: float = z / raw_r  # sin(angle)
		coast_n = _edge_noise.get_noise_2d(nx * 0.75, nz * 0.75)

	var eff_r: float  = base_radius * (1.0 + coast_n * 0.25)
	var r_norm: float = raw_r / eff_r
	if r_norm >= 1.0:
		return 0.0

	var max_h: float = _get_max_height()
	var hn: float    = _height_noise.get_noise_2d(x * 0.30, z * 0.30)

	if island_type == IslandType.ATOLL:
		# Ring of land around a central lagoon; lagoon (r_norm < 0.25) stays at 0 → ocean
		var profile: float = smoothstep(0.25, 0.50, r_norm) * (1.0 - smoothstep(0.65, 0.90, r_norm))
		profile = clamp(profile + hn * 0.12, 0.0, 1.0)
		var result_a: float = profile * max_h
		# Raised outer beach so the ring edge is clearly above water
		result_a = max(result_a, (1.0 - smoothstep(0.88, 1.0, r_norm)) * 0.80)
		return result_a

	# All other types: larger flat plateau + steeper coastal slope so the
	# low-height sandy zone stays narrow close to the waterline.
	var land_profile: float = 1.0 - smoothstep(0.55, 0.88, r_norm)
	land_profile = clamp(land_profile + hn * 0.15, 0.0, 1.0)
	var result: float  = land_profile * max_h
	# Beach floor — narrow ring at coast, height 0.55 = blend_low
	result = max(result, (1.0 - smoothstep(0.88, 1.0, r_norm)) * 0.55)
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

	# Tile size scales with island so large islands don't look over-tiled
	_terrain_mat.set_shader_parameter("world_tile_size", max(1.0, base_radius * 0.04))

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

	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_color = Color(0.40, 0.25, 0.10)
	_trunk_mat.roughness    = 1.0

	_foliage_mat = StandardMaterial3D.new()
	_foliage_mat.albedo_color = Color(0.13, 0.52, 0.15)
	_foliage_mat.roughness    = 0.95


# ------------------------------------------------------------------ #
#  Geometry                                                            #
# ------------------------------------------------------------------ #

func _build_geometry() -> void:
	_build_terrain_mesh()
	_build_trees()
	_build_collision()


func _build_terrain_mesh() -> void:
	var extent:    float = base_radius * 1.35
	var cell_size: float = (extent * 2.0) / GRID_N

	# Pre-compute height at every grid vertex
	var heights := PackedFloat32Array()
	heights.resize((GRID_N + 1) * (GRID_N + 1))
	for iz in range(GRID_N + 1):
		for ix in range(GRID_N + 1):
			var x: float = -extent + ix * cell_size
			var z: float = -extent + iz * cell_size
			heights[iz * (GRID_N + 1) + ix] = _height_at_xy(x, z)

	# Build quad grid mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for iz in range(GRID_N):
		for ix in range(GRID_N):
			var v00 := Vector3(-extent + ix       * cell_size, heights[ iz      * (GRID_N + 1) + ix],      -extent + iz       * cell_size)
			var v10 := Vector3(-extent + (ix + 1) * cell_size, heights[ iz      * (GRID_N + 1) + ix + 1], -extent + iz       * cell_size)
			var v01 := Vector3(-extent + ix       * cell_size, heights[(iz + 1) * (GRID_N + 1) + ix],      -extent + (iz + 1) * cell_size)
			var v11 := Vector3(-extent + (ix + 1) * cell_size, heights[(iz + 1) * (GRID_N + 1) + ix + 1], -extent + (iz + 1) * cell_size)
			st.add_vertex(v00); st.add_vertex(v11); st.add_vertex(v10)
			st.add_vertex(v00); st.add_vertex(v01); st.add_vertex(v11)

	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.custom_aabb = _island_aabb()
	add_child(mi)
	mi.set_surface_override_material(0, _terrain_mat)


func _island_aabb() -> AABB:
	var r: float = base_radius * 1.4
	var h: float = _get_max_height() + 4.0
	return AABB(Vector3(-r, -0.2, -r), Vector3(r * 2.0, h + 0.2, r * 2.0))


func _build_collision() -> void:
	# Sample outward at 64 angles to find the outermost land point at each angle,
	# then build a convex hull collision shape from those coast points.
	var points := PackedVector3Array()
	var scan_n: int = 64
	for i in range(scan_n):
		var angle: float = i / float(scan_n) * TAU
		var best_r: float = 2.0  # minimum non-zero fallback
		for step in range(24):
			var test_r: float = (step + 1.0) * base_radius * 1.35 / 24.0
			var tx: float = cos(angle) * test_r
			var tz: float = sin(angle) * test_r
			if _height_at_xy(tx, tz) > 0.05:
				best_r = test_r
		var cx: float = cos(angle) * best_r
		var cz: float = sin(angle) * best_r
		points.append(Vector3(cx, -0.5, cz))
		points.append(Vector3(cx,  4.0, cz))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
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
	var trunk_h:   float = rng.randf_range(1.2, 2.0)
	var trunk_r:   float = rng.randf_range(0.10, 0.18)
	var foliage_r: float = rng.randf_range(0.55, 0.90)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius      = trunk_r * 0.7
	trunk_mesh.bottom_radius   = trunk_r
	trunk_mesh.height          = trunk_h
	trunk_mesh.radial_segments = 6

	var trunk_mi := MeshInstance3D.new()
	trunk_mi.mesh        = trunk_mesh
	trunk_mi.position    = base_pos + Vector3(0.0, trunk_h * 0.5, 0.0)
	trunk_mi.custom_aabb = _island_aabb()
	add_child(trunk_mi)
	trunk_mi.set_surface_override_material(0, _trunk_mat)
	_trunk_meshes.append(trunk_mi)

	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius          = foliage_r
	foliage_mesh.height          = foliage_r * 2.0
	foliage_mesh.radial_segments = 8
	foliage_mesh.rings           = 5

	var foliage_mi := MeshInstance3D.new()
	foliage_mi.mesh        = foliage_mesh
	foliage_mi.position    = base_pos + Vector3(0.0, trunk_h + foliage_r * 0.75, 0.0)
	foliage_mi.custom_aabb = _island_aabb()
	add_child(foliage_mi)
	foliage_mi.set_surface_override_material(0, _foliage_mat)
	_foliage_meshes.append(foliage_mi)


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
	print("Discovered: ", island_name)
