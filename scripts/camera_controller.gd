extends Camera3D

# Zoom settings
@export var min_zoom: float = 6.0
@export var max_zoom: float = 60.0
@export var zoom_speed: float = 1.0
@export var zoom_smoothing: float = 10.0

# Camera follow settings
@export var follow_target: NodePath
@export var follow_smoothing: float = 5.0
@export var camera_offset: Vector3 = Vector3(0, 30, 30)

# Current zoom level
var target_size: float = 12.0
var current_size: float = 12.0

# For pinch-to-zoom on mobile
var touch_points: Dictionary = {}
var last_pinch_distance: float = 0.0

var target_node: Node3D = null

func _ready() -> void:
	current_size = size
	target_size = size

	# Get the target to follow
	if follow_target:
		target_node = get_node(follow_target)

func _input(event: InputEvent) -> void:
	# Mouse wheel zoom (desktop)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_out()

	# Touch handling for mobile pinch-to-zoom
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
		else:
			touch_points.erase(event.index)
			last_pinch_distance = 0.0

	if event is InputEventScreenDrag:
		touch_points[event.index] = event.position

		# Pinch zoom with 2 fingers
		if touch_points.size() == 2:
			var touch_indices = touch_points.keys()
			var touch1_pos = touch_points[touch_indices[0]]
			var touch2_pos = touch_points[touch_indices[1]]
			var current_distance = touch1_pos.distance_to(touch2_pos)

			if last_pinch_distance > 0:
				var delta = current_distance - last_pinch_distance
				# Pinch in = zoom out, pinch out = zoom in
				target_size -= delta * 0.01
				target_size = clamp(target_size, min_zoom, max_zoom)

			last_pinch_distance = current_distance
		else:
			last_pinch_distance = 0.0

func _process(delta: float) -> void:
	# Smooth zoom transition
	current_size = lerp(current_size, target_size, zoom_smoothing * delta)
	size = current_size

	# Follow the target (boat) — lock Y to 0 so boat bobbing doesn't shift the scene
	if target_node:
		var target_pos = Vector3(target_node.global_position.x, 0.0, target_node.global_position.z) + camera_offset
		global_position = global_position.lerp(target_pos, follow_smoothing * delta)

func zoom_in() -> void:
	target_size -= zoom_speed
	target_size = clamp(target_size, min_zoom, max_zoom)

func zoom_out() -> void:
	target_size += zoom_speed
	target_size = clamp(target_size, min_zoom, max_zoom)
