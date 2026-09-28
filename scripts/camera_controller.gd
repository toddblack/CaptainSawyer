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
var touch_points: Dictionary = {}   # finger index -> Vector2
var last_pinch_distance: float = 0.0

var target_node: Node3D = null


func _ready() -> void:
	current_size = size
	target_size = size
	# The camera is moved every rendered frame in _process, so it must not be
	# physics-interpolated itself; it follows the boat's *interpolated* transform.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	if not follow_target.is_empty():
		target_node = get_node(follow_target) as Node3D


func _input(event: InputEvent) -> void:
	# Mouse wheel zoom (desktop)
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()

	# Touch handling for mobile pinch-to-zoom
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			touch_points[touch.index] = touch.position
		else:
			touch_points.erase(touch.index)
			last_pinch_distance = 0.0

	if event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		touch_points[drag.index] = drag.position

		# Pinch zoom with 2 fingers
		if touch_points.size() == 2:
			var points: Array = touch_points.values()
			var p1: Vector2 = points[0]
			var p2: Vector2 = points[1]
			var current_distance: float = p1.distance_to(p2)

			if last_pinch_distance > 0.0:
				var pinch_delta: float = current_distance - last_pinch_distance
				# Pinch in = zoom out, pinch out = zoom in
				target_size = clampf(target_size - pinch_delta * 0.01, min_zoom, max_zoom)

			last_pinch_distance = current_distance
		else:
			last_pinch_distance = 0.0


func _process(delta: float) -> void:
	# Smooth zoom transition
	current_size = lerpf(current_size, target_size, zoom_smoothing * delta)
	size = current_size

	# Follow the boat's interpolated position (smooth at any refresh rate, e.g.
	# 90/120 Hz phones) — lock Y to 0 so bobbing doesn't shift the scene.
	if target_node != null:
		var boat_pos: Vector3 = target_node.get_global_transform_interpolated().origin
		var target_pos: Vector3 = Vector3(boat_pos.x, 0.0, boat_pos.z) + camera_offset
		global_position = global_position.lerp(target_pos, minf(follow_smoothing * delta, 1.0))


func zoom_in() -> void:
	target_size = clampf(target_size - zoom_speed, min_zoom, max_zoom)


func zoom_out() -> void:
	target_size = clampf(target_size + zoom_speed, min_zoom, max_zoom)
