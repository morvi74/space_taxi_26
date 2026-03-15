extends StaticBody2D
class_name LandingPad



@export var _id: int = 0
func get_id() -> int:
	return _id

var _is_occupied: bool = false
func is_occupied() -> bool:
	return _waiting_zone.is_occupied()

@onready var _left_ray: RayCast2D = $LeftRay
@onready var _right_ray: RayCast2D = $RightRay
@onready var _label_id: Label = $IdLabel

var _waiting_zone: WaitingZone
func get_waiting_zone() -> WaitingZone:
	return _waiting_zone

func _ready() -> void:
	EventHub.taxi_landed.connect(_on_taxi_landed)

func setup(id: int) -> void:
	_id = id
	name = "LandingPad" + str(_id).pad_zeros(2)
	_label_id.text = str(_id).pad_zeros(2)
	_left_ray.force_raycast_update()
	_right_ray.force_raycast_update()
	if _left_ray.is_colliding():
		_waiting_zone = _left_ray.get_collider() as WaitingZone

	elif _right_ray.is_colliding():
		_waiting_zone = _right_ray.get_collider() as WaitingZone
	else:
		printerr("Error: LandingPad ", _id, " has no waiting zone detected by rays. This should not happen if the level is set up correctly.")
	_waiting_zone.set_landing_pad(self)

func assign_passenger(passenger: Passenger) -> void:
	_waiting_zone.set_passenger(passenger)

func clear_passenger() -> void:
	_waiting_zone.clear_passenger()


func _on_taxi_landed(landing_pad: LandingPad, taxi_pos_x: float) -> void:
	if landing_pad == self:
		print("Taxi landed event received by LandingPad ", _id, " for landing pad: ", landing_pad.get_id())
		var passengers_in_taxi: Array[Passenger] = GameData.get_taxi().get_passengers_aboard()
		var passengers_to_remove_from_taxi: Array[int] = []
		for i in range(passengers_in_taxi.size()):
			if passengers_in_taxi[i].get_destination_landing_pad() == landing_pad:
				passengers_to_remove_from_taxi.append(i)
				passengers_in_taxi[i].exit_taxi()
		for i in range(passengers_to_remove_from_taxi.size()):
				GameData.get_taxi().erase_passenger_at(passengers_to_remove_from_taxi[i])
			
		if not GameData.get_taxi().is_full():
			print("Taxi has landed on LandingPad ", _id)
			_waiting_zone.send_passenger_to_taxi(taxi_pos_x)
