extends StaticBody2D
class_name WaitingZone


@onready var _waiting_pos: Marker2D = $WaitingPos
func get_waiting_position() -> Vector2:
	return _waiting_pos.get_marker_position("WaitingPos").to_global()
@onready var _leaving_pos: Marker2D = $LeavingPos
func get_leaving_position() -> Vector2:
	return _leaving_pos.get_marker_position("LeavingPos").to_global()


