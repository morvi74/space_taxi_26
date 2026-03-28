extends Node2D
## Represents the WaitingZone component.
class_name WaitingZone


## Cached node reference for waiting pos.
@onready var _waiting_pos: Marker2D = $WaitingPos
## Returns waiting position.
func get_waiting_position() -> Vector2:
	return _waiting_pos.global_position
## Cached node reference for leaving pos.
@onready var _leaving_pos: Marker2D = $LeavingPos
## Returns leaving position.
func get_leaving_position() -> Vector2:
	return _leaving_pos.global_position

## Internal state for direction to landing pad.
var _direction_to_landing_pad: Vector2 = Vector2.ZERO
## Returns direction to landing pad.
func get_direction_to_landing_pad() -> Vector2:
	return _direction_to_landing_pad


## Internal state for landing pad.
var _landing_pad: LandingPad = null
## Returns landing pad.
func get_landing_pad() -> LandingPad:
	return _landing_pad
## Updates landing pad.
func set_landing_pad(landing_pad: LandingPad) -> void:
	if landing_pad != null:
		_landing_pad = landing_pad

		if _landing_pad.global_position.x > global_position.x:
			_direction_to_landing_pad = Vector2.RIGHT
		else:
			_direction_to_landing_pad = Vector2.LEFT

## Internal state for passenger.
var _passenger: Passenger = null
## Returns passenger.
func get_passenger() -> Passenger:
	return _passenger

## Updates passenger.
func set_passenger(passenger: Passenger) -> void:
	_passenger = passenger
## Checks whether occupied.
func is_occupied() -> bool:
	return _passenger != null
## Handles clear passenger.
func clear_passenger() -> void:
	_passenger = null

## Handles send passenger to taxi.
func send_passenger_to_taxi(taxi_x_pos: float) -> void:
	if _passenger != null:
		_passenger.walk_to_taxi(taxi_x_pos)
