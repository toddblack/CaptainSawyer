extends Node

## Tracks consumable voyage resources: food and water.
## Drains continuously in real time based on crew count and day length.
##
## Starting values: 20 food, 20 water.
## Drain: 1 unit per crew member per in-game day (day length from WorldClock).
## At 2 crew: 10 in-game days of range.

const FOOD_MAX: float  = 20.0
const WATER_MAX: float = 20.0

var food: float = FOOD_MAX
var water: float = WATER_MAX

## Number of crew aboard — drives drain rate.
## Update this when crew boards/leaves the vessel.
var crew_count: int = 2


func _process(delta: float) -> void:
	var drain: float = float(crew_count) * delta / WorldClock.DAY_LENGTH_SECONDS
	food  = maxf(0.0, food  - drain)
	water = maxf(0.0, water - drain)


func food_pct() -> float:
	return food / FOOD_MAX


func water_pct() -> float:
	return water / WATER_MAX
