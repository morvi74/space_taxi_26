extends StaticBody2D
## Represents the ParkikngLot component.
class_name ParkikngLot



## Inspector setting for id.
@export var _id: int = 0
## Returns id.
func get_id() -> int:
	return _id

## Internal state for is occupied.
var _is_occupied: bool = false
## Checks whether occupied.
func is_occupied() -> bool:
	return _is_occupied

## Internal state for traffic node.
var _traffic_node: TrafficNode = null
## Returns traffic node.
func get_traffic_node() -> TrafficNode:
	return _traffic_node
## Updates traffic node.
func set_traffic_node(traffic_node: TrafficNode) -> void:
	_traffic_node = traffic_node

## Cached node reference for label id.
@onready var _label_id: Label = $IdLabel

## Internal state for my waiting zone.
var _my_waiting_zone: WaitingZone


## Handles setup.
func setup(id: int) -> void:
	_id = id
	_label_id.text = str(_id).pad_zeros(2)
