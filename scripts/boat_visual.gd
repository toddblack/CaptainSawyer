extends Node3D

## Tier-1 Dinghy — all visual geometry built in _ready() via mesh primitives
## and ArrayMesh triangles.  No external model files required.
## Attach this script to a Node3D child of the Boat CharacterBody3D.

const _HULL_COLOR: Color = Color(0.50, 0.31, 0.15)
const _DECK_COLOR: Color = Color(0.68, 0.50, 0.27)
const _SPAR_COLOR: Color = Color(0.36, 0.22, 0.10)
const _SAIL_COLOR: Color = Color(0.93, 0.89, 0.78)
const _FLAG_COLOR: Color = Color(0.82, 0.18, 0.18)


func _ready() -> void:
	_hull()
	_deck()
	_spar(Vector3(0.0,  0.03, -0.22), Vector3(0.0,  2.50, -0.22), 0.045)  # mast
	_spar(Vector3(0.0,  2.00, -0.22), Vector3(0.18, 2.72,  0.45), 0.028)  # gaff
	_spar(Vector3(0.0,  0.40, -0.22), Vector3(0.10, 0.38,  1.05), 0.028)  # boom
	_spar(Vector3(0.0,  2.40, -0.22), Vector3(0.0,  0.04, -1.10), 0.012)  # forestay
	_mainsail()
	_foresail()
	_flag()


# ---------- material / mesh-instance helpers ----------------------------------

func _mat(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _add_mi(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	add_child(node)


# ---------- hull & deck -------------------------------------------------------

func _hull() -> void:
	var m: BoxMesh = BoxMesh.new()
	m.size = Vector3(1.02, 0.75,  2.42)
	_add_mi(m, _mat(_HULL_COLOR), Vector3(0.0, -0.34, 0.0))


func _deck() -> void:
	var m: BoxMesh = BoxMesh.new()
	m.size = Vector3(0.80, 0.05, 2.10)
	_add_mi(m, _mat(_DECK_COLOR), Vector3(0.0, 0.025, 0.0))


# ---------- spars -------------------------------------------------------------
# Builds a CylinderMesh oriented from point a to point b.

func _spar(a: Vector3, b: Vector3, radius: float) -> void:
	var length: float = a.distance_to(b)
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length

	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _mat(_SPAR_COLOR)
	node.position = (a + b) * 0.5

	# Rotate local Y-axis to point along (b - a)
	var dir: Vector3 = (b - a).normalized()
	var up_dot: float = dir.dot(Vector3.UP)
	if up_dot < 0.9999 and up_dot > -0.9999:
		var axis: Vector3 = Vector3.UP.cross(dir).normalized()
		node.rotate(axis, acos(up_dot))
	elif up_dot <= -0.9999:
		node.rotate(Vector3.RIGHT, PI)

	add_child(node)


# ---------- sails -------------------------------------------------------------
# Builds a double-sided flat mesh from 3 (triangle) or 4 (quad) vertices.
# Uses explicit per-face normals so lighting is correct on both sides.

func _sail(verts: PackedVector3Array) -> void:
	var n: int = verts.size()
	var edge1: Vector3 = verts[1] - verts[0]
	var edge2: Vector3 = verts[2] - verts[0]
	var fn: Vector3 = edge1.cross(edge2).normalized()  # front normal
	var bn: Vector3 = -fn                               # back normal

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Front face
	st.set_normal(fn)
	st.add_vertex(verts[0])
	st.set_normal(fn)
	st.add_vertex(verts[1])
	st.set_normal(fn)
	st.add_vertex(verts[2])
	if n == 4:
		st.set_normal(fn)
		st.add_vertex(verts[0])
		st.set_normal(fn)
		st.add_vertex(verts[2])
		st.set_normal(fn)
		st.add_vertex(verts[3])

	# Back face (reverse winding, flipped normal)
	st.set_normal(bn)
	st.add_vertex(verts[2])
	st.set_normal(bn)
	st.add_vertex(verts[1])
	st.set_normal(bn)
	st.add_vertex(verts[0])
	if n == 4:
		st.set_normal(bn)
		st.add_vertex(verts[3])
		st.set_normal(bn)
		st.add_vertex(verts[2])
		st.set_normal(bn)
		st.add_vertex(verts[0])

	var sail_mesh: ArrayMesh = st.commit()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = sail_mesh
	node.material_override = _mat(_SAIL_COLOR)
	add_child(node)


func _mainsail() -> void:
	# Gaff-rigged quadrilateral mainsail.
	# jaw  = gaff-at-mast  (upper forward)
	# peak = gaff tip       (upper aft, slightly starboard)
	# clew = boom tip       (lower aft)
	# tack = boom-at-mast  (lower forward)
	_sail(PackedVector3Array([
		Vector3(0.00, 2.00, -0.22),  # jaw
		Vector3(0.18, 2.72,  0.45),  # peak
		Vector3(0.10, 0.38,  1.05),  # clew
		Vector3(0.00, 0.40, -0.22),  # tack
	]))


func _foresail() -> void:
	# Triangular staysail forward of mast.
	# head = high on mast, tack = at bow, clew = port mid-height
	_sail(PackedVector3Array([
		Vector3( 0.00, 2.20, -0.22),  # head
		Vector3( 0.00, 0.04, -1.10),  # tack (bow)
		Vector3(-0.35, 0.70, -0.45),  # clew (port)
	]))


func _flag() -> void:
	var m: BoxMesh = BoxMesh.new()
	m.size = Vector3(0.28, 0.12, 0.04)
	_add_mi(m, _mat(_FLAG_COLOR), Vector3(0.14, 2.58, -0.22))
