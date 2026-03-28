extends Node

## Internal state for taxi.
var _taxi: Taxi
## Updates taxi.
func set_taxi(taxi_instance: Taxi) -> void:
	_taxi = taxi_instance
## Returns taxi.
func get_taxi() -> Taxi:
	return _taxi
