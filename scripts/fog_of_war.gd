extends Node3D

# ------------------------------------------------------------------ #
#  Fog of War — 2D CanvasLayer overlay                                #
#                                                                      #
#  A horizontal 3D plane breaks at high orthographic zoom: rays from  #
#  the bottom of the screen start below the plane and miss it.        #
#  Instead we render a full-screen ColorRect on a CanvasLayer and     #
#  project screen UV → world XZ at Y=0 analytically inside the        #
#  shader. This covers 100 % of the screen at any zoom level.         #
# ------------------------------------------------------------------ #

const FOG_TEX_SIZE   := 128
const WORLD_HALF     := 100.0
const REVEAL_RADIUS  := 22.0
const MOVE_THRESHOLD := 0.5

var _fog_image: Image
var _fog_tex:   ImageTexture
var _fog_mat:   ShaderMaterial
var _camera:    Camera3D
var _boat:      Node3D
var _last_boat_xz := Vector2(9999.0, 9999.0)


const SHADER_CODE := """
shader_type canvas_item;

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec4  cloud_color : source_color = vec4(0.92, 0.93, 0.96, 1.0);
uniform float world_half  = 100.0;

// Orthographic camera parameters — updated every frame from GDScript.
uniform vec3  cam_pos;
uniform vec3  cam_right;
uniform vec3  cam_up;
uniform vec3  cam_fwd;
uniform float cam_size;    // full viewport height in world units (Camera3D.size)
uniform float cam_aspect;  // viewport width / height

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	// Convert screen UV → world-space ray origin (orthographic: all rays parallel).
	float ndc_x =  UV.x * 2.0 - 1.0;
	float ndc_y = (1.0 - UV.y) * 2.0 - 1.0;   // flip Y (screen Y-down → world Y-up)
	vec3 ray_origin = cam_pos
	                + cam_right * (ndc_x * cam_size * cam_aspect * 0.5)
	                + cam_up    * (ndc_y * cam_size * 0.5);

	// Intersect ray with the Y=0 ocean plane.
	// cam_fwd.y is always negative for our downward-looking camera.
	float t = -ray_origin.y / cam_fwd.y;
	vec2 world_xz = (ray_origin + cam_fwd * t).xz;

	// Map world XZ to fog texture UV [0..1].
	vec2 fog_uv = (world_xz + vec2(world_half)) / (world_half * 2.0);

	// Smooth fade to fully opaque near and beyond world edges.
	// Transition zone ≈ 8 world units (0.04 × 200) — no hard white bar.
	float e = 0.04;
	float edge_fade = smoothstep(0.0, e, fog_uv.x)
	                * smoothstep(1.0, 1.0 - e, fog_uv.x)
	                * smoothstep(0.0, e, fog_uv.y)
	                * smoothstep(1.0, 1.0 - e, fog_uv.y);

	vec2 fog_uv_safe = clamp(fog_uv, 0.0, 1.0);
	float fog_sample = texture(fog_tex, fog_uv_safe).r;
	// edge_fade=1 inside map, 0 outside → outside blends to opaque cloud.
	float fog_mask = mix(1.0, fog_sample, edge_fade);

	if (fog_mask < 0.02) discard;

	vec2 uv1 = fog_uv_safe * 7.0  + vec2( TIME * 0.010,  TIME * 0.006);
	vec2 uv2 = fog_uv_safe * 13.0 + vec2(-TIME * 0.007,  TIME * 0.009);
	// Rotate each sample by a different irrational angle so the value-noise grid
	// never aligns with world or screen axes (eliminates visible grid seams).
	// uv1r ≈ 22°, uv2r ≈ 55° — neither aligns with the isometric 45° screen axes.
	vec2 uv1r = vec2(uv1.x * 0.927 - uv1.y * 0.374, uv1.x * 0.374 + uv1.y * 0.927);
	vec2 uv2r = vec2(uv2.x * 0.574 - uv2.y * 0.819, uv2.x * 0.819 + uv2.y * 0.574);
	float n = smooth_noise(uv1r) * 0.6 + smooth_noise(uv2r) * 0.4;

	COLOR = vec4(cloud_color.rgb * (0.90 + n * 0.10), fog_mask * (0.72 + n * 0.22));
}
"""


func _ready() -> void:
	_build_fog_overlay()
	call_deferred("_find_nodes")


func _find_nodes() -> void:
	_boat   = get_node_or_null("../Boat")
	_camera = get_node_or_null("../Camera3D")

	if not _boat:
		_boat = get_tree().get_first_node_in_group("boat")
	if not _camera:
		_camera = get_viewport().get_camera_3d()

	if _boat:
		print("FogOfWar: found boat at ", _boat.global_position)
		var start := Vector2(_boat.global_position.x, _boat.global_position.z)
		_last_boat_xz = start
		_reveal(start)
	else:
		print("FogOfWar: boat NOT found")

	if not _camera:
		print("FogOfWar: camera NOT found")


func _build_fog_overlay() -> void:
	_fog_image = Image.create(FOG_TEX_SIZE, FOG_TEX_SIZE, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color.WHITE)
	_fog_tex = ImageTexture.create_from_image(_fog_image)

	var shader := Shader.new()
	shader.code = SHADER_CODE
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = shader
	_fog_mat.set_shader_parameter("world_half",  WORLD_HALF)
	_fog_mat.set_shader_parameter("fog_tex",     _fog_tex)
	_fog_mat.set_shader_parameter("cloud_color", Color(0.92, 0.93, 0.96, 1.0))

	# CanvasLayer 0 → renders above the 3D scene, below the HUD (which is at layer 1).
	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 0

	var color_rect := ColorRect.new()
	color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.material = _fog_mat

	canvas_layer.add_child(color_rect)
	add_child(canvas_layer)


func _process(_delta: float) -> void:
	# Push fresh camera parameters to the shader every frame.
	if _camera:
		var vp_size := get_viewport().get_visible_rect().size
		var aspect  := vp_size.x / vp_size.y if vp_size.y > 0.0 else 1.0
		_fog_mat.set_shader_parameter("cam_pos",    _camera.global_position)
		_fog_mat.set_shader_parameter("cam_right",  _camera.global_transform.basis.x)
		_fog_mat.set_shader_parameter("cam_up",     _camera.global_transform.basis.y)
		_fog_mat.set_shader_parameter("cam_fwd",   -_camera.global_transform.basis.z)
		_fog_mat.set_shader_parameter("cam_size",   _camera.size)
		_fog_mat.set_shader_parameter("cam_aspect", aspect)

	if not _boat:
		_find_nodes()
		return

	var boat_xz := Vector2(_boat.global_position.x, _boat.global_position.z)
	if boat_xz.distance_to(_last_boat_xz) >= MOVE_THRESHOLD:
		_last_boat_xz = boat_xz
		_reveal(boat_xz)


func _reveal(world_xz: Vector2) -> void:
	var cx := int((world_xz.x + WORLD_HALF) / (WORLD_HALF * 2.0) * FOG_TEX_SIZE)
	var cy := int((world_xz.y + WORLD_HALF) / (WORLD_HALF * 2.0) * FOG_TEX_SIZE)
	var r   := int(REVEAL_RADIUS / (WORLD_HALF * 2.0) * FOG_TEX_SIZE)

	var changed := false
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var dist := sqrt(float(dx * dx + dy * dy))
			if dist > r:
				continue
			var px := cx + dx
			var py := cy + dy
			if px < 0 or px >= FOG_TEX_SIZE or py < 0 or py >= FOG_TEX_SIZE:
				continue
			var t      := dist / float(r)
			var target := smoothstep(0.0, 1.0, t * 1.15 - 0.15)
			var current := _fog_image.get_pixel(px, py).r
			if target < current:
				_fog_image.set_pixel(px, py, Color(target, target, target, 1.0))
				changed = true

	if changed:
		_fog_tex = ImageTexture.create_from_image(_fog_image)
		_fog_mat.set_shader_parameter("fog_tex", _fog_tex)
