extends CharacterBody3D

# Movement settings
@export var max_speed: float = 10.0
@export var max_reverse_speed: float = 3.0
@export var acceleration: float = 3.0
@export var turn_speed: float = 2.0
@export var drag: float = 0.95

# Bobbing settings
@export var bob_height: float = 0.15
@export var bob_speed: float = 1.5
@export var tilt_amount: float = 0.05

# Boundary settings (ocean is 200x200, so keep within -95 to 95)
@export var boundary_min: Vector2 = Vector2(-95, -95)
@export var boundary_max: Vector2 = Vector2(95, 95)

var current_speed: float = 0.0
var direction: Vector3 = Vector3.FORWARD
var bob_time: float = 0.0

# Touch steering — Option B: finger position projected to world XZ, boat sails toward it
var _has_touch_target: bool = false
var _touch_target: Vector3 = Vector3.ZERO

@onready var wake_particles: GPUParticles3D = $WakeParticles
@onready var _bow_left: GPUParticles3D = $BowWaveLeft
@onready var _bow_right: GPUParticles3D = $BowWaveRight

# Cached material references — set once in _ready() to avoid per-frame casting
var _wake_mat: ParticleProcessMaterial = null
var _bow_left_mat: ParticleProcessMaterial = null
var _bow_right_mat: ParticleProcessMaterial = null


func _ready() -> void:
	_wake_mat = wake_particles.process_material as ParticleProcessMaterial
	_bow_left_mat = _bow_left.process_material as ParticleProcessMaterial
	_bow_right_mat = _bow_right.process_material as ParticleProcessMaterial


# ------------------------------------------------------------------ #
#  Touch input — project screen point onto world XZ plane (Y = 0)    #
# ------------------------------------------------------------------ #

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_update_touch_target(touch.position)
		else:
			_has_touch_target = false
	elif event is InputEventScreenDrag:
		var drag_event: InputEventScreenDrag = event as InputEventScreenDrag
		_update_touch_target(drag_event.position)


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

	# ---- Water effects ------------------------------------------- #
	var spd: float = abs(current_speed)
	var speed_ratio: float = clamp(spd / max_speed, 0.0, 1.0)

	# Stern wake — any direction
	wake_particles.emitting = spd > 0.5
	if wake_particles.emitting:
		_wake_mat.initial_velocity_min = lerp(1.5, 2.5, speed_ratio)
		_wake_mat.initial_velocity_max = lerp(3.0, 5.5, speed_ratio)

	# Bow waves — forward only
	var going_forward: bool = current_speed > 0.5
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
