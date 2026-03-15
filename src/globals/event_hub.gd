extends Node


# taxi related signals
signal taxi_health_changed(new_health)
signal gear_health_changed(new_health)
signal taxi_landed(landing_pad: LandingPad, taxi_x_pos: float)

# junction graph related signals
signal mouse_over_junction_point(point: JunctionPoint2D)
signal mouse_exit_junction_point(point: JunctionPoint2D)

# passenger related signals
signal passenger_request_taxi(passenger: Passenger, landing_pad: LandingPad)
signal passenger_entered_taxi(passenger: Passenger)
signal passenger_exited_taxi(passenger: Passenger)
signal passenger_died(passenger: Passenger)
signal passenger_despawned(passenger: Passenger)

# region Taxi related emitters
func emit_taxi_health_changed(new_health: float) -> void:
	taxi_health_changed.emit(new_health)

func emit_gear_health_changed(new_health: float) -> void:
	gear_health_changed.emit(new_health)

func emit_taxi_landed(landing_pad: LandingPad, taxi_x_pos: float) -> void:
	taxi_landed.emit(landing_pad, taxi_x_pos)
# endregion

# region Junction graph related emitters
func emit_mouse_over_junction_point(point: JunctionPoint2D) -> void:
	mouse_over_junction_point.emit(point)

func emit_mouse_exit_junction_point(point: JunctionPoint2D) -> void:
	mouse_exit_junction_point.emit(point)
# endregion

# region Passenger related emitters
func emit_passenger_request_taxi(passenger: Passenger, landing_pad: LandingPad) -> void:
	passenger_request_taxi.emit(passenger, landing_pad)

func emit_passenger_entered_taxi(passenger: Passenger) -> void:
	passenger_entered_taxi.emit(passenger)

func emit_passenger_exited_taxi(passenger: Passenger) -> void:
	passenger_exited_taxi.emit(passenger)

func emit_passenger_died(passenger: Passenger) -> void:
	passenger_died.emit(passenger)

func emit_passenger_despawned(passenger: Passenger) -> void:
	passenger_despawned.emit(passenger)
# endregion