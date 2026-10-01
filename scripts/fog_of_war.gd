extends Node3D
class_name FogOfWar

# ------------------------------------------------------------------ #
#  Fog of War — world-space overlay                                    #
#                                                                      #
#  A full-screen quad reads the depth buffer, rebuilds each pixel's   #
#  true world position, and looks up the fog texture there.  Tall     #
#  terrain and trees are fogged at their own XZ, so there is no       #
#  height-parallax to compensate for.  Pixels below sea level (seabed #
#  seen through the transparent ocean, or empty background) are       #
#  projected back up to the Y=0 water surface along the view ray.     #
# ------------------------------------------------------------------ #

const FOG_TEX_SIZE:   int   = 256
const WORLD_HALF:     float = 500.0
const MOVE_THRESHOLD: float = 0.5

# Base reveal radius for Tier 1 (Dinghy). Each subsequent ship tier adds ~12%.
# Tier 1: 20  |  Tier 2: 23  |  Tier 3: 26  |  Tier 4: 30
const REVEAL_RADIUS_BASE: float = 20.0

var _reveal_radius: float = REVEAL_RADIUS_BASE  # updated by set_ship_tier()

# LA8: L drives the 3D overlay, A lets the minimap draw the same texture as a mask.
var _fog_data:  PackedByteArray
var _fog_image: Image
var _fog_tex:   ImageTexture
var _fog_mat:   ShaderMaterial
var _boat:      Node3D
var _dirty:     bool    = false
var _last_boat_xz: Vector2 = Vector2(9999.0, 9999.0)

var _startup_frames: int     = 0
var _startup_pos:    Vector2 = Vector2.ZERO


const SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4  cloud_color : source_color = vec4(0.92, 0.93, 0.96, 1.0);
uniform float world_half  = 500.0;
uniform float blur_texels = 3.0;
uniform float tex_size    = 256.0;

void vertex() {
	// Full-screen quad: QuadMesh 2×2 maps straight to clip space.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4  view  = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	view.xyz   /= view.w;
	vec3  world = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;

	// The ocean is transparent, so it isn't in the depth buffer.  Anything below
	// sea level is seen through the water — fog it where the ray meets Y=0.
	vec3 fwd = -INV_VIEW_MATRIX[2].xyz;
	if (world.y < 0.0 && fwd.y < -0.0001) {
		world -= fwd * (world.y / fwd.y);
	}

	vec2 fog_uv = (world.xz + vec2(world_half)) / (world_half * 2.0);

	// Smooth fade to fully opaque near and beyond world edges.
	float e = 0.04;
	float edge_fade = smoothstep(0.0, e, fog_uv.x)
					* smoothstep(0.0, e, 1.0 - fog_uv.x)
					* smoothstep(0.0, e, fog_uv.y)
					* smoothstep(0.0, e, 1.0 - fog_uv.y);

	// 9-tap blur softens the texel grid into cloud-like edges.
	vec2  c = clamp(fog_uv, 0.0, 1.0);
	float s = blur_texels / tex_size;
	float fog_sample =
		  texture(fog_tex, c).r * 0.36
		+ texture(fog_tex, clamp(c + vec2( s,  0.0), 0.0, 1.0)).r * 0.12
		+ texture(fog_tex, clamp(c + vec2(-s,  0.0), 0.0, 1.0)).r * 0.12
		+ texture(fog_tex, clamp(c + vec2( 0.0,  s), 0.0, 1.0)).r * 0.12
		+ texture(fog_tex, clamp(c + vec2( 0.0, -s), 0.0, 1.0)).r * 0.12
		+ texture(fog_tex, clamp(c + vec2( s,   s),  0.0, 1.0)).r * 0.04
		+ texture(fog_tex, clamp(c + vec2(-s,   s),  0.0, 1.0)).r * 0.04
		+ texture(fog_tex, clamp(c + vec2( s,  -s),  0.0, 1.0)).r * 0.04
		+ texture(fog_tex, clamp(c + vec2(-s,  -s),  0.0, 1.0)).r * 0.04;
	float fog_mask = mix(1.0, fog_sample, edge_fade);

	if (fog_mask < 0.02) discard;

	ALBEDO = cloud_color.rgb;
	ALPHA  = fog_mask * 0.85;
}
"""


func _ready() -> void:
	_build_fog_overlay()
	call_deferred("_find_boat")


func _find_boat() -> void:
	_boat = get_tree().get_first_node_in_group("boat") as Node3D
	if _boat == null:
		push_warning("FogOfWar: boat not found")
		return
	var start: Vector2 = Vector2(_boat.global_position.x, _boat.global_position.z)
	_last_boat_xz   = start
	_startup_pos    = start
	_startup_frames = 3
	_reveal(start, _reveal_radius, false)


func _build_fog_overlay() -> void:
	_fog_data = PackedByteArray()
	_fog_data.resize(FOG_TEX_SIZE * FOG_TEX_SIZE * 2)
	_fog_data.fill(255)
	_fog_image = Image.create_from_data(FOG_TEX_SIZE, FOG_TEX_SIZE, false, Image.FORMAT_LA8, _fog_data)
	_fog_tex   = ImageTexture.create_from_image(_fog_image)

	var shader: Shader = Shader.new()
	shader.code = SHADER_CODE
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = shader
	# Transparent objects sort by priority first — draw after the ocean.
	_fog_mat.render_priority = 100
	_fog_mat.set_shader_parameter("world_half",  WORLD_HALF)
	_fog_mat.set_shader_parameter("tex_size",    float(FOG_TEX_SIZE))
	_fog_mat.set_shader_parameter("fog_tex",     _fog_tex)
	_fog_mat.set_shader_parameter("cloud_color", Color(0.92, 0.93, 0.96, 1.0))

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _fog_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader ignores the node's position; a huge AABB keeps it from
	# ever being frustum-culled.
	mi.custom_aabb = AABB(Vector3(-100000.0, -100000.0, -100000.0), Vector3(200000.0, 200000.0, 200000.0))
	add_child(mi)


func _process(_delta: float) -> void:
	if _boat != null:
		if _startup_frames > 0:
			_startup_frames -= 1
			_reveal(_startup_pos, _reveal_radius, false)
		else:
			var boat_xz: Vector2 = Vector2(_boat.global_position.x, _boat.global_position.z)
			if boat_xz.distance_to(_last_boat_xz) >= MOVE_THRESHOLD:
				_last_boat_xz = boat_xz
				_reveal(boat_xz, _reveal_radius, false)

	# At most one upload per frame, into the existing GPU texture.
	if _dirty:
		_dirty = false
		_fog_image.set_data(FOG_TEX_SIZE, FOG_TEX_SIZE, false, Image.FORMAT_LA8, _fog_data)
		_fog_tex.update(_fog_image)


## Fog texture (LA8, 1 = fogged) covering the whole world — the minimap draws it.
func get_fog_texture() -> Texture2D:
	return _fog_tex


## Call when the player's ship tier changes (1–4).
## Each tier adds ~12 % visibility over the previous one.
func set_ship_tier(tier: int) -> void:
	_reveal_radius = REVEAL_RADIUS_BASE * pow(1.12, float(tier - 1))


## Fully clear a world-space circle (soft rim) — used when an island is discovered.
func reveal_area(world_xz: Vector2, world_radius: float) -> void:
	_reveal(world_xz, world_radius, true)


# solid = false: multiplicative Gaussian (the boat's trail).  Each pass multiplies
#   remaining fog by (1 - gaussian(t)); overlapping passes compound, so corridor
#   walls clear fully with no straight-tangent seams.
# solid = true: clear everything inside the radius with a short soft rim.
func _reveal(world_xz: Vector2, world_radius: float, solid: bool) -> void:
	var size:  int   = FOG_TEX_SIZE
	var px_per_wu: float = float(size) / (WORLD_HALF * 2.0)
	var r_px:  float = world_radius * px_per_wu
	if r_px < 0.5:
		return
	var cx:    float = (world_xz.x + WORLD_HALF) * px_per_wu
	var cy:    float = (world_xz.y + WORLD_HALF) * px_per_wu
	# Gaussian tail is negligible past t=3 (exp(-13.5)).
	var reach: float = r_px * (1.1 if solid else 3.0)

	var x0: int = maxi(int(floor(cx - reach)), 0)
	var x1: int = mini(int(ceil(cx + reach)), size - 1)
	var y0: int = maxi(int(floor(cy - reach)), 0)
	var y1: int = mini(int(ceil(cy + reach)), size - 1)

	for py: int in range(y0, y1 + 1):
		var dy: float = float(py) + 0.5 - cy
		for px: int in range(x0, x1 + 1):
			var dx: float = float(px) + 0.5 - cx
			var t:  float = sqrt(dx * dx + dy * dy) / r_px
			var clear: float
			if solid:
				clear = 1.0 - smoothstep(0.85, 1.1, t)
			else:
				if t > 3.0:
					continue
				clear = exp(-t * t * 1.5)
			if clear <= 0.0:
				continue
			var idx: int = (py * size + px) * 2
			var cur: int = _fog_data[idx]
			var nxt: int = int(float(cur) * (1.0 - clear))
			if nxt < cur:
				_fog_data[idx]     = nxt
				_fog_data[idx + 1] = nxt
				_dirty = true
