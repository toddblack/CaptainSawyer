extends Node3D
class_name FogOfWar

# ------------------------------------------------------------------ #
#  Fog of War — 2D CanvasLayer overlay                                #
#                                                                      #
#  A horizontal 3D plane breaks at high orthographic zoom: rays from  #
#  the bottom of the screen start below the plane and miss it.        #
#  Instead we render a full-screen ColorRect on a CanvasLayer and     #
#  project screen UV → world XZ at Y=0 analytically inside the        #
#  shader. This covers 100 % of the screen at any zoom level.         #
# ------------------------------------------------------------------ #

const FOG_TEX_SIZE   := 256
const WORLD_HALF     := 500.0
const MOVE_THRESHOLD := 0.5

# Base reveal radius for Tier 1 (Dinghy). Each subsequent ship tier adds ~12%.
# Tier 1: 20  |  Tier 2: 23  |  Tier 3: 26  |  Tier 4: 30
const REVEAL_RADIUS_BASE: float = 20.0

var _reveal_radius: float = REVEAL_RADIUS_BASE  # updated by set_ship_tier()

var _fog_image: Image
var _fog_tex:   ImageTexture
var _fog_mat:   ShaderMaterial
var _camera:    Camera3D
var _boat:      Node3D
var _last_boat_xz := Vector2(9999.0, 9999.0)

var _startup_frames: int = 0
var _startup_pos:    Vector2 = Vector2.ZERO


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
	// 9-tap Gaussian blur on the fog texture.
	// s = 3 texels at 256px resolution → ±12 world units, same as before.
	float s = 3.0 / 256.0;
	float fog_sample =
		texture(fog_tex, clamp(fog_uv_safe,                     0.0, 1.0)).r * 0.36
		+ texture(fog_tex, clamp(fog_uv_safe + vec2( s,  0.0), 0.0, 1.0)).r * 0.12
		+ texture(fog_tex, clamp(fog_uv_safe + vec2(-s,  0.0), 0.0, 1.0)).r * 0.12
		+ texture(fog_tex, clamp(fog_uv_safe + vec2( 0.0,  s), 0.0, 1.0)).r * 0.12
		+ texture(fog_tex, clamp(fog_uv_safe + vec2( 0.0, -s), 0.0, 1.0)).r * 0.12
		+ texture(fog_tex, clamp(fog_uv_safe + vec2( s,   s),  0.0, 1.0)).r * 0.04
		+ texture(fog_tex, clamp(fog_uv_safe + vec2(-s,   s),  0.0, 1.0)).r * 0.04
		+ texture(fog_tex, clamp(fog_uv_safe + vec2( s,  -s),  0.0, 1.0)).r * 0.04
		+ texture(fog_tex, clamp(fog_uv_safe + vec2(-s,  -s),  0.0, 1.0)).r * 0.04;
	// edge_fade=1 inside map, 0 outside → outside blends to opaque cloud.
	float fog_mask = mix(1.0, fog_sample, edge_fade);

	if (fog_mask < 0.02) discard;

	COLOR = vec4(cloud_color.rgb, fog_mask * 0.85);
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
		_last_boat_xz  = start
		_startup_pos   = start
		_startup_frames = 3
		_reveal(start, _reveal_radius)
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

	if _startup_frames > 0:
		_startup_frames -= 1
		_reveal(_startup_pos, _reveal_radius)
		return

	var boat_xz := Vector2(_boat.global_position.x, _boat.global_position.z)
	if boat_xz.distance_to(_last_boat_xz) >= MOVE_THRESHOLD:
		_last_boat_xz = boat_xz
		_reveal(boat_xz, _reveal_radius)


## Call when the player's ship tier changes (1–4).
## Each tier adds ~12 % visibility over the previous one.
func set_ship_tier(tier: int) -> void:
	_reveal_radius = REVEAL_RADIUS_BASE * pow(1.12, float(tier - 1))


## Clear a world-space circle at world_xz with the given radius.
## Called by Island on discovery to expose tall terrain's height-parallax
## shadow — the Y=0 footprint of a peak at height h is offset by –h world
## units in the camera direction, so islands need a larger reveal than the
## boat's normal travelling radius.
func reveal_area(world_xz: Vector2, world_radius: float) -> void:
	_reveal(world_xz, world_radius)


func _reveal(world_xz: Vector2, world_radius: float) -> void:
	var cx: int = int((world_xz.x + WORLD_HALF) / (WORLD_HALF * 2.0) * FOG_TEX_SIZE)
	var cy: int = int((world_xz.y + WORLD_HALF) / (WORLD_HALF * 2.0) * FOG_TEX_SIZE)
	var r_px: int = int(world_radius / (WORLD_HALF * 2.0) * FOG_TEX_SIZE)
	# Search to 3× r_px to capture the full Gaussian tail (exp(-9) ≈ 0.0001).
	var r_search: int = r_px * 3
	var r_search_sq: int = r_search * r_search
	var size: int = FOG_TEX_SIZE

	# Multiplicative Gaussian clearance via PackedByteArray (one get_data / set_data pair).
	# Each call multiplies remaining fog by (1 - gaussian(t)), where t = dist / r_px.
	# Overlapping circles compound: a point hit by N passes is cleared to (1-g)^N → 0.
	# Corridor walls (t≈1 from every passing circle) are hit many times and fully clear,
	# eliminating the straight-tangent seam that plagued the old smoothstep+min approach.
	var data: PackedByteArray = _fog_image.get_data()
	var changed := false

	for dy: int in range(-r_search, r_search + 1):
		for dx: int in range(-r_search, r_search + 1):
			if dx * dx + dy * dy > r_search_sq:
				continue
			var px: int = cx + dx
			var py: int = cy + dy
			if px < 0 or px >= size or py < 0 or py >= size:
				continue
			var dist: float = sqrt(float(dx * dx + dy * dy))
			var t: float = dist / float(r_px)
			# exp(-1.5·t²): 1.0 at center (full clear), ~0.22 at t=1, ~0.002 at t=2
			# Sigma=1.5 keeps the halo tighter — accumulated passes clear less far out.
			var contribution: float = exp(-t * t * 1.5)
			var idx: int = (py * size + px) * 4
			var current_byte: int = int(data[idx])
			var target_byte: int = int(float(current_byte) * (1.0 - contribution))
			if target_byte < current_byte:
				data[idx + 0] = target_byte
				data[idx + 1] = target_byte
				data[idx + 2] = target_byte
				changed = true

	if changed:
		_fog_image.set_data(size, size, false, Image.FORMAT_RGBA8, data)
		_fog_tex = ImageTexture.create_from_image(_fog_image)
		_fog_mat.set_shader_parameter("fog_tex", _fog_tex)
