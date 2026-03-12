extends Node



signal taxi_health_changed(new_health)
signal gear_health_changed(new_health)


func emit_taxi_health_changed(new_health: float) -> void:
	taxi_health_changed.emit(new_health)

func emit_gear_health_changed(new_health: float) -> void:
	gear_health_changed.emit(new_health)