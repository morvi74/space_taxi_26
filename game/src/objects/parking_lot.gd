extends StaticBody2D
class_name ParkikngLot



@export var _id: int = 0
func get_id() -> int:
	return _id

var _is_occupied: bool = false
func is_occupied() -> bool:
	return _is_occupied

var _traffic_node: TrafficNode = null
func get_traffic_node() -> TrafficNode:
	return _traffic_node
func set_traffic_node(traffic_node: TrafficNode) -> void:
	_traffic_node = traffic_node

@onready var _label_id: Label = $IdLabel

var _my_waiting_zone: WaitingZone


func setup(id: int) -> void:
	_id = id
	_label_id.text = str(_id).pad_zeros(2)