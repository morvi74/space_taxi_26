extends Node

var _level_manager: LevelManager = null
func get_level_manager() -> LevelManager:
	return _level_manager
func set_level_manager(lm: LevelManager) -> void:
	_level_manager = lm

var _traffic_manager: TrafficManager = null
func get_traffic_manager() -> TrafficManager:
	return _traffic_manager
func set_traffic_manager(tm: TrafficManager) -> void:
	_traffic_manager = tm