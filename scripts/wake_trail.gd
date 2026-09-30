extends MeshInstance3D
class_name WakeTrail

## Boat wake: a foam ribbon laid on the water.  The bow's path is sampled into
## world-space points; every frame they're rebuilt into a strip that widens at
## the Kelvin wake angle and fades with age.  The look (foam arms, churned
## centre, dithered pixels) lives in wake_trail.gdshader.
## Child of the Boat; boat.gd sets `strength` from its speed each physics tick.

const _SHADER = preload("res://assets/materials/wake_trail.gdshader")

const _LIFETIME:       float = 3.0     # seconds a stretch of wake survives
const _SAMPLE_SPACING: float = 0.35    # world units between recorded points
const _BOW_OFFSET:     float = 1.15    # bow, ahead of the boat's centre
const _BOW_HALF_WIDTH: float = 0.5     # ribbon half-width at the bow (hull beam)
const _KELVIN_SPREAD:  float = 0.36    # tan(19.5°): half-width gained per unit behind the bow
const _WATER_Y:        float = 0.1     # just above the ocean surface (ocean sits at y≈0.03)
const _TELEPORT_DIST:  float = 5.0     # bow jumped this far → start a fresh wake
# Across-ribbon vertex positions (UV.x).  Five columns keep the wide tail
# following the swell; the arms sit at ±1, the extra 0.2 lets them fade out.
const _ACROSS: Array[float] = [-1.2, -0.6, 0.0, 0.6, 1.2]

## 0 = no new wake (stopped / reversing slowly), 1 = full speed.
var strength: float = 0.0

var _boat:  Node3D
var _mesh:  ArrayMesh = ArrayMesh.new()
var _time:  float = 0.0
# Recorded bow points, oldest first.
var _pts:      PackedVector3Array = PackedVector3Array()
var _born:     PackedFloat32Array = PackedFloat32Array()
var _strength: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_boat = get_parent() as Node3D
	# Vertices are written in world space, so this node must not inherit the
	# boat's transform (or its rocking).
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mesh = _mesh
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _SHADER
	mat.render_priority = 1   # after the ocean (0), before the fog quad
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_time += delta
	if _boat == null:
		return

	# Follow the boat's interpolated transform so the ribbon is smooth at any
	# refresh rate; flatten out the rocking.
	var xf:  Transform3D = _boat.get_global_transform_interpolated()
	var fwd: Vector3 = -xf.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return
	fwd = fwd.normalized()
	var bow: Vector3 = xf.origin + fwd * _BOW_OFFSET
	bow.y = _WATER_Y

	# Drop expired points (oldest are at the front).
	var expired: int = 0
	while expired < _born.size() and _time - _born[expired] > _LIFETIME:
		expired += 1
	if expired > 0:
		_pts      = _pts.slice(expired)
		_born     = _born.slice(expired)
		_strength = _strength.slice(expired)

	if not _pts.is_empty() and _pts[_pts.size() - 1].distance_to(bow) > _TELEPORT_DIST:
		_pts.clear()
		_born.clear()
		_strength.clear()

	if strength > 0.0 and (_pts.is_empty() or _pts[_pts.size() - 1].distance_to(bow) >= _SAMPLE_SPACING):
		_pts.append(bow)
		_born.append(_time)
		_strength.append(strength)

	_rebuild(bow)


## Rebuilds the ribbon: the live bow position, then recorded points newest → oldest.
func _rebuild(bow: Vector3) -> void:
	_mesh.clear_surfaces()
	var n_rec: int = _pts.size()
	if n_rec == 0:
		return
	var n:    int = n_rec + 1          # points along the ribbon, index 0 = bow
	var cols: int = _ACROSS.size()

	var pts: PackedVector3Array = PackedVector3Array()
	var age: PackedFloat32Array = PackedFloat32Array()
	var stg: PackedFloat32Array = PackedFloat32Array()
	pts.resize(n)
	age.resize(n)
	stg.resize(n)
	pts[0] = bow
	age[0] = 0.0
	stg[0] = maxf(strength, _strength[n_rec - 1])
	for i: int in range(1, n):
		var r: int = n_rec - i         # newest recorded first
		pts[i] = _pts[r]
		age[i] = clampf((_time - _born[r]) / _LIFETIME, 0.0, 1.0)
		stg[i] = _strength[r]

	var verts:   PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uv:      PackedVector2Array = PackedVector2Array()
	var uv2:     PackedVector2Array = PackedVector2Array()
	verts.resize(n * cols)
	normals.resize(n * cols)
	uv.resize(n * cols)
	uv2.resize(n * cols)

	var dist: float = 0.0
	for i: int in range(n):
		if i > 0:
			dist += pts[i].distance_to(pts[i - 1])
		# Direction along the path from the neighbours; perpendicular is "across".
		var ahead:  Vector3 = pts[maxi(i - 1, 0)]
		var behind: Vector3 = pts[mini(i + 1, n - 1)]
		var along:  Vector3 = ahead - behind
		along.y = 0.0
		if along.length_squared() < 1e-8:
			along = Vector3.FORWARD
		var side:  Vector3 = Vector3(-along.z, 0.0, along.x).normalized()
		var half:  float   = _BOW_HALF_WIDTH + _KELVIN_SPREAD * dist
		for c: int in range(cols):
			var k: int = i * cols + c
			verts[k]   = pts[i] + side * (_ACROSS[c] * half)
			normals[k] = Vector3.UP
			uv[k]      = Vector2(_ACROSS[c], age[i])
			uv2[k]     = Vector2(dist, stg[i])

	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize((n - 1) * (cols - 1) * 6)
	var w: int = 0
	for i: int in range(n - 1):
		for c: int in range(cols - 1):
			# Clockwise seen from above = Godot front face.  Wound the other way,
			# cull_disabled flips the normal down and the foam renders black.
			var a: int = i * cols + c
			var b: int = a + cols
			indices[w]     = a
			indices[w + 1] = b + 1
			indices[w + 2] = b
			indices[w + 3] = a
			indices[w + 4] = a + 1
			indices[w + 5] = b + 1
			w += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]  = verts
	arrays[Mesh.ARRAY_NORMAL]  = normals
	arrays[Mesh.ARRAY_TEX_UV]  = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX]   = indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
