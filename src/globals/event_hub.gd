extends Node


# taxi related signals
signal taxi_health_changed(new_health)
signal gear_health_changed(new_health)

# junction graph related signals
signal mouse_over_junction_point(point: JunctionPoint2D)
signal mouse_exit_junction_point(point: JunctionPoint2D)


func emit_taxi_health_changed(new_health: float) -> void:
	taxi_health_changed.emit(new_health)

func emit_gear_health_changed(new_health: float) -> void:
	gear_health_changed.emit(new_health)

func emit_mouse_over_junction_point(point: JunctionPoint2D) -> void:
	mouse_over_junction_point.emit(point)

func emit_mouse_exit_junction_point(point: JunctionPoint2D) -> void:
	mouse_exit_junction_point.emit(point)
