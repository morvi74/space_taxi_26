extends StaticBody2D
class_name LandingPad



@export var _id: int = 0
func get_id() -> int:
	return _id

var _is_occupied: bool = false
func is_occupied() -> bool:
	return _is_occupied

@onready var _left_ray: RayCast2D = $LeftRay
@onready var _right_ray: RayCast2D = $RightRay
@onready var _label_id: Label = $IdLabel

var _my_waiting_zone: WaitingZone


func setup(id: int) -> void:
	_id = id
	_label_id.text = str(_id).pad_zeros(2)
	_left_ray.force_raycast_update()
	_right_ray.force_raycast_update()
	if _left_ray.is_colliding():
		_my_waiting_zone = _left_ray.get_collider() as WaitingZone

	elif _right_ray.is_colliding():
		_my_waiting_zone = _right_ray.get_collider() as WaitingZone
	else:
		printerr("Error: LandingPad ", _id, " has no waiting zone detected by rays. This should not happen if the level is set up correctly.")
	print("My waiting zone is: ", _my_waiting_zone.name)
