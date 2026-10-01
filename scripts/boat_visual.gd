class_name BoatVisual
extends Node3D

## The player's ship — a Claude Design GLB from assets/models/ships/.
## Each tier ships as two files that differ only in the sails (`_set` and
## `_furled`; Hull + Rigging are identical).  Hull + Rigging are baked into one
## mesh, each sail state into another (one surface per material), so even the
## ~300-piece galleon costs about a dozen draw calls.
## Attach to a Node3D child of the Boat CharacterBody3D.

const _SHIP_PATH: String = "res://assets/models/ships/sawyer_ship_%s_%s.glb"

## Dinghy 4 m, Sloop 11 m, Brigantine 22 m, Galleon 34 m (bow toward −Z).
@export_enum("dinghy", "sloop", "brigantine", "galleon") var tier: String = "dinghy"
## The GLBs are in metres. 0.6 keeps the dinghy about the size of the old
## placeholder boat (~2.6 units), which the collision box and wake are tuned for.
@export var model_scale: float = 0.6
## Canvas by default — dye the sails any colour.
@export var sail_color: Color = Color(0.91, 0.87, 0.76)
## Model origin is the waterline. The Boat body rides at y≈0.5, the ocean at y≈0.03.
@export var waterline_y: float = -0.47

var _sails_set: MeshInstance3D = null
var _sails_furled: MeshInstance3D = null


func _ready() -> void:
	position.y = waterline_y
	scale = Vector3.ONE * model_scale

	var set_root: Node = _instantiate("set")
	var furled_root: Node = _instantiate("furled")
	if set_root == null or furled_root == null:
		if set_root != null:
			set_root.free()
		if furled_root != null:
			furled_root.free()
		return

	var body_parts: Array[Node] = [
		set_root.find_child("Hull", true, false),
		set_root.find_child("Rigging", true, false),
	]
	var set_parts: Array[Node] = [set_root.find_child("SailsSet", true, false)]
	var furled_parts: Array[Node] = [furled_root.find_child("SailsFurled", true, false)]

	_add_mesh(MeshMerge.merge(set_root, body_parts))
	_sails_set = _add_mesh(MeshMerge.merge(set_root, set_parts))
	_sails_furled = _add_mesh(MeshMerge.merge(furled_root, furled_parts))
	var dye: StandardMaterial3D = _dye_sails(_sails_set.mesh as ArrayMesh, null)
	_dye_sails(_sails_furled.mesh as ArrayMesh, dye)

	set_root.free()
	furled_root.free()
	set_sails(false)  # the boat starts at rest


## Sails set (under way) or furled (at rest).  The only switch — whatever
## decides it (idle timer now; sail/anchor/dock controls later) calls this.
func set_sails(up: bool) -> void:
	if _sails_set == null:
		return
	_sails_set.visible = up
	_sails_furled.visible = not up


func _instantiate(state: String) -> Node:
	var path: String = _SHIP_PATH % [tier, state]
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("BoatVisual: failed to load ship GLB: %s" % path)
		return null
	return packed.instantiate()


func _add_mesh(mesh: ArrayMesh) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	return mi


## Swaps the GLB's `sail` material for one in `sail_color` (shared between both
## sail states).  Returns the dyed material so the next call can reuse it.
func _dye_sails(mesh: ArrayMesh, dye: StandardMaterial3D) -> StandardMaterial3D:
	for s: int in range(mesh.get_surface_count()):
		var mat: StandardMaterial3D = mesh.surface_get_material(s) as StandardMaterial3D
		if mat == null or mat.resource_name != "sail":
			continue
		if dye == null:
			dye = mat.duplicate() as StandardMaterial3D
			dye.albedo_color = sail_color
		mesh.surface_set_material(s, dye)
	return dye
