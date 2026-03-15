extends StaticBody2D
class_name WaitingZone


@onready var _waiting_pos: Marker2D = $WaitingPos
func get_waiting_position() -> Vector2:
	return _waiting_pos.global_position
@onready var _leaving_pos: Marker2D = $LeavingPos
func get_leaving_position() -> Vector2:
	return _leaving_pos.global_position

var _direction_to_landing_pad: Vector2 = Vector2.ZERO
func get_direction_to_landing_pad() -> Vector2:
	return _direction_to_landing_pad


var _landing_pad: LandingPad = null
func get_landing_pad() -> LandingPad:
	return _landing_pad
func set_landing_pad(landing_pad: LandingPad) -> void:
	if landing_pad != null:
		_landing_pad = landing_pad

		if _landing_pad.global_position.x > global_position.x:
			_direction_to_landing_pad = Vector2.RIGHT
		else:
			_direction_to_landing_pad = Vector2.LEFT

var _passenger: Passenger = null
func get_passenger() -> Passenger:
	return _passenger

func set_passenger(passenger: Passenger) -> void:
	_passenger = passenger
func is_occupied() -> bool:
	return _passenger != null
func clear_passenger() -> void:
	_passenger = null

func send_passenger_to_taxi(taxi_x_pos: float) -> void:
	if _passenger != null:
		_passenger.walk_to_taxi(taxi_x_pos)
