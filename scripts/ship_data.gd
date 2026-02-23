extends Resource
class_name ShipData

## Defines the stats for a single ship tier.
## Create one .tres file per ship type in resources/ships/.

@export var ship_name: String = ""
@export var max_speed: float = 7.0
@export var max_reverse_speed: float = 2.0
@export var acceleration: float = 3.0
@export var turn_speed: float = 2.5
@export var drag: float = 0.95
