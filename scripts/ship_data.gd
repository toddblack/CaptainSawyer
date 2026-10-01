extends Resource
class_name ShipData

## Defines a single ship tier: its model, size and handling.
## One .tres file per ship type in resources/ships/ (named after `model`).

@export var ship_name: String = ""
## Model in assets/models/ships/ (sawyer_ship_<model>_<set|furled>.glb).
@export_enum("dinghy", "sloop", "brigantine", "galleon") var model: String = "dinghy"
## In-game hull length in world units.  The GLBs are true-scale metres
## (dinghy 4 m … galleon 34 m); this squashes the range so islands still feel big.
@export var hull_length: float = 2.6
## Lifts the model in the water (world units).  The open dinghy's floor sits
## below the GLB waterline, so the ocean would show inside the hull without it.
@export var ride_height: float = 0.0
@export var max_speed: float = 7.0
@export var max_reverse_speed: float = 2.0
@export var acceleration: float = 3.0
@export var turn_speed: float = 2.5
@export var drag: float = 0.95
