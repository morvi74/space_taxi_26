extends Node

var _taxi: Taxi
func set_taxi(taxi_instance: Taxi) -> void:
	_taxi = taxi_instance
func get_taxi() -> Taxi:
	return _taxi