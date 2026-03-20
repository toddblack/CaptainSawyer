extends DirectionalLight3D

## Dynamic day/night cycle with seasonal sun elevation.
## Attach to DirectionalLight3D in main.tscn.
##
## Reads WorldClock.time_of_day (0–1) and WorldClock.day_of_year (1–365)
## each frame and drives:
##   • light rotation  (east → noon → west arc)
##   • light colour / energy  (warm sun ↔ cool moon)
##   • ProceduralSkyMaterial colours  (night navy → dawn orange → day blue)
##   • WorldEnvironment ambient_light_energy  (softens shadow darkness)

## Tropical northern hemisphere, ~15° N — no GPS needed, purely game-world.
const GAME_LATITUDE_DEG: float = 15.0

# ── Sky palette ───────────────────────────────────────────────────────────
const _DAY_SKY_TOP:    Color = Color(0.13, 0.32, 0.80, 1)
const _DAY_SKY_HORIZ:  Color = Color(0.58, 0.76, 0.95, 1)
const _DUSK_SKY_HORIZ: Color = Color(0.95, 0.52, 0.18, 1)
const _DUSK_SKY_TOP:   Color = Color(0.22, 0.10, 0.38, 1)
const _NIGHT_SKY_TOP:  Color = Color(0.01, 0.02, 0.07, 1)
const _NIGHT_SKY_HORIZ: Color = Color(0.03, 0.05, 0.12, 1)

# ── Light palette ─────────────────────────────────────────────────────────
const _SUN_NOON_COLOR:  Color = Color(1.00, 0.97, 0.86, 1)
const _SUN_DAWN_COLOR:  Color = Color(1.00, 0.70, 0.38, 1)
const _MOON_COLOR:      Color = Color(0.50, 0.55, 0.78, 1)

var _sky_mat: ProceduralSkyMaterial = null
var _env:     Environment           = null


func _ready() -> void:
	var we: WorldEnvironment = _find_world_environment()
	if we == null:
		push_warning("WorldLighting: no WorldEnvironment node found in scene")
		return
	_env = we.environment
	if _env == null:
		push_warning("WorldLighting: WorldEnvironment has no Environment resource")
		return
	var sky: Sky = _env.sky
	if sky == null:
		push_warning("WorldLighting: Environment has no Sky assigned")
		return
	_sky_mat = sky.sky_material as ProceduralSkyMaterial
	if _sky_mat == null:
		push_warning("WorldLighting: Sky material is not ProceduralSkyMaterial")


## Walk direct children of the root scene to find a WorldEnvironment node.
func _find_world_environment() -> WorldEnvironment:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	for child: Node in root.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
	return null


func _process(_delta: float) -> void:
	_update_sun(WorldClock.time_of_day, WorldClock.day_of_year)


func _update_sun(t: float, doy: int) -> void:
	# arc = 0 at dawn (t=0.25), π/2 at noon (t=0.5), π at dusk (t=0.75).
	# Full TAU * (t - 0.25) maps the whole day to a semicircle in +Y space.
	var arc: float      = (t - 0.25) * TAU
	var sin_arc: float  = sin(arc)   # < 0 when sun is below horizon
	var cos_arc: float  = cos(arc)   # +1=east(dawn), –1=west(dusk)

	# Seasonal noon elevation from solar declination (±23.5° over the year).
	# doy 80 ≈ spring equinox;  doy 172 ≈ summer solstice.
	var decl: float      = sin(float(doy) / 365.0 * TAU - PI * 0.5) * deg_to_rad(23.5)
	var noon_elev: float = clampf(
		PI * 0.5 - deg_to_rad(GAME_LATITUDE_DEG) + decl,
		deg_to_rad(12.0), PI * 0.5
	)

	# Sun direction: unit vector from scene toward sun (east at dawn, up at noon).
	var sun_dir: Vector3 = Vector3(
		cos_arc,
		sin_arc * sin(noon_elev),
		-sin_arc * cos(noon_elev) * 0.18
	).normalized()

	# Day when sun is above horizon (small twilight buffer for smooth transition).
	var is_day: bool        = sin_arc >= -0.06
	# Day: light rays travel from sun toward scene (–sun_dir).
	# Night: moon is antipodal, its rays travel in +sun_dir.
	var light_dir: Vector3  = -sun_dir if is_day else sun_dir
	# Singularity guard: avoid collinear with UP at zenith / nadir.
	var up: Vector3 = Vector3.UP if absf(light_dir.dot(Vector3.UP)) < 0.97 else Vector3.FORWARD
	global_transform.basis  = Basis.looking_at(light_dir, up)

	# ── Light energy / colour ─────────────────────────────────────────────
	# day_t: 0 at the horizon, 1 at peak noon brightness.
	var day_t: float     = clampf(sin_arc / 0.25, 0.0, 1.0)
	# horizon_t: 1 at sunrise/sunset, 0 at noon and midnight.
	var horizon_t: float = clampf(1.0 - absf(sin_arc) * 4.5, 0.0, 1.0)

	if is_day:
		light_energy = lerp(0.05, 1.40, day_t * day_t)
		light_color  = _SUN_NOON_COLOR.lerp(_SUN_DAWN_COLOR, horizon_t)
	else:
		light_energy = 0.16
		light_color  = _MOON_COLOR

	# ── Sky colours ───────────────────────────────────────────────────────
	if _sky_mat != null:
		var top:   Color = _NIGHT_SKY_TOP.lerp(_DAY_SKY_TOP,   day_t)
		var horiz: Color = _NIGHT_SKY_HORIZ.lerp(_DAY_SKY_HORIZ, day_t)
		# Warm dawn/dusk tint on top of the base blend.
		horiz = horiz.lerp(_DUSK_SKY_HORIZ, horizon_t * 0.75)
		top   = top.lerp(_DUSK_SKY_TOP,    horizon_t * 0.45)
		_sky_mat.sky_top_color       = top
		_sky_mat.sky_horizon_color   = horiz
		_sky_mat.ground_horizon_color = horiz.darkened(0.25)
		_sky_mat.ground_bottom_color  = _NIGHT_SKY_TOP

	# ── Ambient ───────────────────────────────────────────────────────────
	# Lifts shadow darkness so back-facing terrain faces stay visible at night.
	if _env != null:
		_env.ambient_light_energy = lerp(0.05, 0.45, day_t)
