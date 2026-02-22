extends StaticBody3D

signal island_discovered(island_name: String, world_pos: Vector2)

@export var island_name: String = "Unknown Isle"
@export var base_radius: float = 4.0
@export var num_trees: int = 3
@export var discovery_radius: float = 18.0

var discovered: bool = false
var _boat: Node3D = null

# Texture atlases and terrain shader
const _TERRAIN_SHADER = preload("res://assets/materials/island_terrain.gdshader")
const _TEX_BEACH      = preload("res://assets/textures/beach_watersEdge_rocks.png")
const _TEX_GRASSES    = preload("res://assets/textures/grasses_dirt.png")

# Materials
var _terrain_mat: ShaderMaterial
var _trunk_mat:   StandardMaterial3D
var _foliage_mat: StandardMaterial3D

var _trunk_meshes:   Array[MeshInstance3D] = []
var _foliage_meshes: Array[MeshInstance3D] = []

# Noise (members so tree placement can reuse them)
var _height_noise: FastNoiseLite
var _edge_noise:   FastNoiseLite

# Mesh resolution
const ANGULAR_STEPS := 64
const RADIAL_STEPS  := 18
const SKIRT_DEPTH   := -0.50


func _ready() -> void:
	_setup_noise()
	_build_materials()
	_build_geometry()
	_boat = get_tree().get_first_node_in_group("boat")


# ------------------------------------------------------------------ #
#  Noise                                                               #
# ------------------------------------------------------------------ #

func _setup_noise() -> void:
	_height_noise = FastNoiseLite.new()
	_height_noise.seed        = island_name.hash()
	_height_noise.noise_type  = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency   = 0.35

	_edge_noise = FastNoiseLite.new()
	_edge_noise.seed        = island_name.hash() + 9999
	_edge_noise.noise_type  = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_edge_noise.frequency   = 0.40


func _perturbed_radius(angle: float) -> float:
	var en := _edge_noise.get_noise_2d(cos(angle) * 1.5, sin(angle) * 1.5)
	return base_radius * (1.0 + en * 0.28)


func _height_at(x: float, z: float, r_norm: float) -> float:
	var max_h := base_radius * 0.38
	var hn    := _height_noise.get_noise_2d(x * 0.28, z * 0.28)
	# Plateau profile: inner 25% stays high, steeper slope 25%-95%, wide beach 95%-100%
	var profile := (1.0 - smoothstep(0.20, 0.95, r_norm)) * max_h
	# Noise adds bumps inland, fades out at shore so the beach stays flat
	var bump    := hn * max_h * 0.35 * (1.0 - r_norm * r_norm)
	var result  := profile + bump
	# Sloped beach minimum: tapers from ~0.30 where terrain ends (r_norm=0.95) to 0 at the rim
	# so the beach slopes naturally down to the waterline instead of being a flat platform
	var beach_floor := (1.0 - smoothstep(0.95, 1.0, r_norm)) * 0.30
	return max(result, beach_floor)


# ------------------------------------------------------------------ #
#  Materials                                                           #
# ------------------------------------------------------------------ #

func _build_materials() -> void:
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = _TERRAIN_SHADER
	_terrain_mat.set_shader_parameter("beach_atlas", _TEX_BEACH)
	_terrain_mat.set_shader_parameter("grass_atlas",  _TEX_GRASSES)
	# Beach tile: col 1, row 3 in beach sheet (245 px tiles, 4 px margin, 10 px gutter)
	var bs := 245 + 10
	_terrain_mat.set_shader_parameter("beach_tile_offset",
			Vector2((4 + 1 * bs) / 1024.0, (4 + 3 * bs) / 1024.0))
	_terrain_mat.set_shader_parameter("beach_tile_scale",
			Vector2(245.0 / 1024.0, 245.0 / 1024.0))
	# Grass tile: col 0, row 0 in grasses sheet (215 px tiles, 34 px margin, 34 px gutter)
	_terrain_mat.set_shader_parameter("grass_tile_offset",
			Vector2(34.0 / 1024.0, 34.0 / 1024.0))
	_terrain_mat.set_shader_parameter("grass_tile_scale",
			Vector2(215.0 / 1024.0, 215.0 / 1024.0))
	_terrain_mat.set_shader_parameter("world_tile_size", 1.0)
	# Blend heights: beach at low elevation, grass on the slopes and plateau
	# max_h ≈ base_radius * 0.38, so these sit at ~20% and ~60% of peak
	_terrain_mat.set_shader_parameter("blend_low",  base_radius * 0.07)
	_terrain_mat.set_shader_parameter("blend_high", base_radius * 0.22)
	# Tight fade at waterline only — just hides the skirt edge, doesn't tint the beach
	_terrain_mat.set_shader_parameter("waterline_fade", 0.12)

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
	# Pre-compute perturbed edge radius for every angular step
	var angle_radii := PackedFloat32Array()
	angle_radii.resize(ANGULAR_STEPS)
	for s in ANGULAR_STEPS:
		angle_radii[s] = _perturbed_radius(s / float(ANGULAR_STEPS) * TAU)

	# Build vertex grid for rings 1..RADIAL_STEPS (terrain) + skirt ring
	# grid[(ring-1) * (ANGULAR_STEPS+1) + s]  — ring index starts at 1
	var grid: Array[Vector3] = []
	grid.resize((RADIAL_STEPS + 1) * (ANGULAR_STEPS + 1))

	for ring in range(1, RADIAL_STEPS + 2):
		var gi := ring - 1
		for s in range(ANGULAR_STEPS + 1):
			var seg    := s % ANGULAR_STEPS
			var angle  := s / float(ANGULAR_STEPS) * TAU
			var max_r  := angle_radii[seg]
			var x: float
			var z: float
			var y: float

			if ring <= RADIAL_STEPS:
				var r_norm := ring / float(RADIAL_STEPS)
				var r      := r_norm * max_r
				x = cos(angle) * r
				z = sin(angle) * r
				y = _height_at(x, z, r_norm)
			elif ring == RADIAL_STEPS:
				# Waterline ring — always at sea level
				x = cos(angle) * max_r
				z = sin(angle) * max_r
				y = 0.0
			else:
				# Skirt ring — slightly narrowed, below waterline
				var skirt_r := max_r * 0.85
				x = cos(angle) * skirt_r
				z = sin(angle) * skirt_r
				y = SKIRT_DEPTH

			grid[gi * (ANGULAR_STEPS + 1) + s] = Vector3(x, y, z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Center vertex (peak)
	var center_v := Vector3(0.0, _height_at(0.0, 0.0, 0.0), 0.0)

	# Center fan: center → ring 1 (grid row 0)
	# Winding: CW in XZ from above = upward normal in Godot's right-hand coords
	for s in ANGULAR_STEPS:
		var v_cw  := grid[s]
		var v_ccw := grid[s + 1]
		st.add_vertex(center_v)
		st.add_vertex(v_cw)
		st.add_vertex(v_ccw)

	# Ring bands — reversed winding for upward normals
	for k in range(RADIAL_STEPS):
		for s in ANGULAR_STEPS:
			var v0 := grid[k       * (ANGULAR_STEPS + 1) + s]
			var v1 := grid[k       * (ANGULAR_STEPS + 1) + s + 1]
			var v2 := grid[(k + 1) * (ANGULAR_STEPS + 1) + s + 1]
			var v3 := grid[(k + 1) * (ANGULAR_STEPS + 1) + s]
			st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v1)
			st.add_vertex(v0); st.add_vertex(v3); st.add_vertex(v2)

	st.generate_normals()

	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.custom_aabb = _island_aabb()
	add_child(mi)
	mi.set_surface_override_material(0, _terrain_mat)


func _island_aabb() -> AABB:
	# Generous bounds covering perturbed coastline + tallest possible tree.
	# Used as custom_aabb on every mesh so Godot never frustum-culls individual
	# pieces (trees, terrain) while the rest of the island is still on screen.
	var r := base_radius * 1.5
	var h := base_radius * 0.38 + 3.5
	return AABB(Vector3(-r, SKIRT_DEPTH - 0.1, -r), Vector3(r * 2.0, h - SKIRT_DEPTH + 0.1, r * 2.0))


func _build_collision() -> void:
	# Build a ConvexPolygonShape3D from the actual perturbed coastline.
	# Extruded vertically so the boat always hits a wall normal (horizontal push),
	# not a sloped beach normal (which would bounce it upward).
	var points := PackedVector3Array()
	for s in ANGULAR_STEPS:
		var angle := s / float(ANGULAR_STEPS) * TAU
		var r     := _perturbed_radius(angle)
		var x     := cos(angle) * r
		var z     := sin(angle) * r
		points.append(Vector3(x, -0.5, z))
		points.append(Vector3(x,  4.0, z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = island_name.hash()

	for i in num_trees:
		var r_norm := rng.randf_range(0.08, 0.50)  # keep trees on the elevated plateau
		var angle  := rng.randf() * TAU
		var max_r  := _perturbed_radius(angle)
		var r      := r_norm * max_r
		var x      := cos(angle) * r
		var z      := sin(angle) * r
		var y      := _height_at(x, z, r_norm)
		_build_tree(rng, Vector3(x, y, z))


func _build_tree(rng: RandomNumberGenerator, base_pos: Vector3) -> void:
	var trunk_h   := rng.randf_range(1.2, 2.0)
	var trunk_r   := rng.randf_range(0.10, 0.18)
	var foliage_r := rng.randf_range(0.55, 0.90)

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
