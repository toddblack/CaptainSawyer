extends Node

## Tracks in-game time of day and day of year.
## 0.0 = midnight | 0.25 = dawn | 0.5 = noon | 0.75 = dusk | 1.0 = midnight
##
## One full cycle = DAY_LENGTH_SECONDS real seconds (default 30 min).

const DAY_LENGTH_SECONDS: float = 1800.0  # 30 real minutes

## Current time within a single day, range [0.0, 1.0).
var time_of_day: float = 0.28  # start just after dawn

## Day of the year, 1–365.  Day 80 ≈ spring equinox (March 21).
var day_of_year: int = 80

signal day_started
signal night_started

var _is_night: bool = false


func _process(delta: float) -> void:
	var prev: float = time_of_day
	time_of_day = fmod(time_of_day + delta / DAY_LENGTH_SECONDS, 1.0)
	# Detect day rollover (time_of_day wraps from ~1.0 back to ~0.0).
	if time_of_day < prev:
		day_of_year = (day_of_year % 365) + 1
	var now_night: bool = is_night()
	if now_night and not _is_night:
		_is_night = true
		night_started.emit()
	elif not now_night and _is_night:
		_is_night = false
		day_started.emit()


## Returns true when the sun is below the horizon (time < 0.25 or time > 0.75).
func is_night() -> bool:
	return time_of_day < 0.25 or time_of_day > 0.75
