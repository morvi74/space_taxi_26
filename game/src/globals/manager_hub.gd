extends Node

## Internal state for level manager.
var _level_manager: LevelManager = null
## Returns level manager.
func get_level_manager() -> LevelManager:
	return _level_manager
## Updates level manager.
func set_level_manager(lm: LevelManager) -> void:
	_level_manager = lm

## Internal state for traffic manager.
var _traffic_manager: TrafficManager = null
## Returns traffic manager.
func get_traffic_manager() -> TrafficManager:
	return _traffic_manager
## Updates traffic manager.
func set_traffic_manager(tm: TrafficManager) -> void:
	_traffic_manager = tm
