extends CharacterBody3D

const _SHIP_DATA_PATH: String = "res://resources/ships/%s.tres"
const _SHIPS: Array[String] = ["dinghy", "sloop", "brigantine", "galleon"]

# Which ship to sail — model, size and handling come from resources/ships/<ship>.tres.
# Tab cycles ships while the game runs (testing).
@export_enum("dinghy", "sloop", "brigantine", "galleon") var ship: String = "dinghy"

var max_speed: float = 7.0
var max_reverse_speed: float = 2.0
var acceleration: float = 3.0
var turn_speed: float = 2.5
var drag: float = 0.95

# Bobbing settings
@export var bob_height: float = 0.15
@export var bob_speed: float = 1.5
@export var tilt_amount: float = 0.05

# Sails set the moment the boat gets under way, and furl only after it has sat
# still this long — a brief stop while steering doesn't touch them.
@export var furl_after_seconds: float = 5.0

# Boundary settings (ocean is 1000x1000, keep a small margin inside the edge)
@export var boundary_min: Vector2 = Vector2(-495, -495)
@export var boundary_max: Vector2 = Vector2(495, 495)

var current_speed: float = 0.0
var direction: Vector3 = Vector3.FORWARD
var bob_time: float = 0.0

# Touch steering — Option B: finger position projected to world XZ, boat sails toward it
var _has_touch_target: bool = false
var _touch_target: Vector3 = Vector3.ZERO
# Active finger indices — steering only follows a single finger, so a
# two-finger pinch-zoom never yanks the boat around.
var _touches: Dictionary = {}

var _still_time: float = 0.0
var _sails_up: bool = false

@onready var _visual: BoatVisual = $BoatVisual
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _wake_trail: WakeTrail = $WakeTrail
@onready var _bow_left: GPUParticles3D = $BowWaveLeft
@onready var _bow_right: GPUParticles3D = $BowWaveRight

# Cached material references — set once in _ready() to avoid per-frame casting
var _bow_left_mat: ParticleProcessMaterial = null
var _bow_right_mat: ParticleProcessMaterial = null


func _ready() -> void:
	_bow_left_mat = _bow_left.process_material as ParticleProcessMaterial
	_bow_right_mat = _bow_right.process_material as ParticleProcessMaterial
	_apply_ship(ship)


## Loads a ship tier: handling stats, model, and collision / wake / bow spray
## fitted to its hull.
func _apply_ship(id: String) -> void:
	var data: ShipData = load(_SHIP_DATA_PATH % id) as ShipData
	if data == null:
		push_warning("Boat: no ShipData for '%s'" % id)
		return
	ship = id
	max_speed         = data.max_speed
	max_reverse_speed = data.max_reverse_speed
	acceleration      = data.acceleration
	turn_speed        = data.turn_speed
	drag              = data.drag

	var hull: AABB = _visual.build(data.model, data.hull_length)
	if hull.size == Vector3.ZERO:
		return
	var box: BoxShape3D = _collision.shape as BoxShape3D
	box.size = Vector3(hull.size.x, 1.0, hull.size.z)
	_collision.position = Vector3(0.0, 0.0, hull.get_center().z)
	var bow_z: float = hull.position.z            # bow is toward −Z
	var half_beam: float = hull.size.x * 0.5
	_wake_trail.bow_offset = -bow_z
	_wake_trail.bow_half_width = half_beam
	_bow_left.position = Vector3(-half_beam, _bow_left.position.y, bow_z * 0.9)
	_bow_right.position = Vector3(half_beam, _bow_right.position.y, bow_z * 0.9)


# ------------------------------------------------------------------ #
#  Touch input — project screen point onto world XZ plane (Y = 0)    #
# ------------------------------------------------------------------ #

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = true
		else:
			_touches.erase(touch.index)
		if touch.pressed and _touches.size() == 1:
			_update_touch_target(touch.position)
		else:
			_has_touch_target = false
	elif event is InputEventScreenDrag:
		if _touches.size() == 1:
			var drag_event: InputEventScreenDrag = event as InputEventScreenDrag
			_update_touch_target(drag_event.position)
	elif event is InputEventKey:
		# Testing: Tab cycles through the ships.
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_TAB:
			var next: int = (_SHIPS.find(ship) + 1) % _SHIPS.size()
			_apply_ship(_SHIPS[next])
			get_viewport().set_input_as_handled()


func _update_touch_target(screen_pos: Vector2) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	# Avoid divide-by-zero if ray is nearly parallel to the water plane
	if abs(ray_dir.y) < 0.001:
		return
	# t = distance along ray to reach Y = 0
	var t: float = -ray_origin.y / ray_dir.y
	if t < 0.0:
		return  # intersection is behind the camera
	_touch_target = ray_origin + ray_dir * t
	_has_touch_target = true


# ------------------------------------------------------------------ #
#  Main update                                                         #
# ------------------------------------------------------------------ #

func _physics_process(delta: float) -> void:
	var forward_input: float = Input.get_axis("ui_down", "ui_up")
	var turn_input: float = Input.get_axis("ui_right", "ui_left")
	var using_keyboard: bool = forward_input != 0.0 or turn_input != 0.0

	if using_keyboard:
		# Keyboard takes priority and cancels any active touch target
		_has_touch_target = false

		if turn_input != 0.0:
			rotate_y(turn_input * turn_speed * delta)
			direction = -global_transform.basis.z

		if forward_input != 0.0:
			var target_speed: float = max_speed if forward_input > 0 else -max_reverse_speed
			current_speed = move_toward(current_speed, target_speed, acceleration * delta)
		else:
			current_speed *= drag  # coasting while turning only

	elif _has_touch_target:
		var to_target: Vector3 = _touch_target - global_position
		to_target.y = 0.0
		var dist: float = to_target.length()

		if dist > 0.8:
			# Rotate toward target using the same rotate_y mechanism as keyboard
			var target_dir: Vector3 = to_target / dist
			var angle_diff: float = (-global_transform.basis.z).signed_angle_to(target_dir, Vector3.UP)
			rotate_y(clamp(angle_diff, -turn_speed * delta, turn_speed * delta))
			direction = -global_transform.basis.z
			current_speed = move_toward(current_speed, max_speed, acceleration * delta)
		else:
			# Arrived — coast to stop. Keep _has_touch_target alive so a
			# drag update from a held finger resumes immediately.
			current_speed *= drag

	else:
		current_speed *= drag

	# Apply movement
	velocity = direction * current_speed

	# Bobbing
	bob_time += delta
	var bob_offset: float = sin(bob_time * bob_speed) * bob_height
	position.y = 0.5 + bob_offset

	# Gentle rocking
	var rock_z: float = sin(bob_time * bob_speed * 1.3) * tilt_amount
	var rock_x: float = cos(bob_time * bob_speed * 0.9) * tilt_amount * 0.5
	rotation.x = rock_x
	rotation.z = rock_z

	move_and_slide()

	# Grinding against a shore: bleed speed down to what we actually achieved
	# (sliding along the coast keeps the tangential part) so the wake and bow
	# spray don't keep running at full speed while we're stuck.
	if get_slide_collision_count() > 0:
		var real_speed: float = get_real_velocity().length()
		current_speed = signf(current_speed) * minf(absf(current_speed), real_speed)

	# ---- Water effects ------------------------------------------- #
	var spd: float = abs(current_speed)
	var speed_ratio: float = clamp(spd / max_speed, 0.0, 1.0)

	# Wake ribbon — laid from the bow when moving forward
	_wake_trail.strength = speed_ratio if current_speed > 0.5 else 0.0

	# Sails — set when under way, furled after sitting still a while
	var going_forward: bool = current_speed > 0.5
	if going_forward:
		_still_time = 0.0
		if not _sails_up:
			_sails_up = true
			_visual.set_sails(true)
	elif _sails_up and spd < 0.3:
		_still_time += delta
		if _still_time >= furl_after_seconds:
			_sails_up = false
			_visual.set_sails(false)

	# Bow waves — forward only
	_bow_left.emitting = going_forward
	_bow_right.emitting = going_forward
	if going_forward:
		var v_min: float = lerp(1.0, 1.8, speed_ratio)
		var v_max: float = lerp(2.5, 3.5, speed_ratio)
		_bow_left_mat.initial_velocity_min = v_min
		_bow_left_mat.initial_velocity_max = v_max
		_bow_right_mat.initial_velocity_min = v_min
		_bow_right_mat.initial_velocity_max = v_max

	# Boundaries
	position.x = clamp(position.x, boundary_min.x, boundary_max.x)
	position.z = clamp(position.z, boundary_min.y, boundary_max.y)
