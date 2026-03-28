extends Node


# taxi related signals
## Emitted when taxi health changed.
signal taxi_health_changed(new_health)
## Emitted when gear health changed.
signal gear_health_changed(new_health)
## Emitted when taxi landed.
signal taxi_landed(landing_pad: LandingPad, taxi_x_pos: float)

# junction graph related signals
## Emitted when mouse over junction point.
signal mouse_over_junction_point(point: JunctionPoint2D)
## Emitted when mouse exit junction point.
signal mouse_exit_junction_point(point: JunctionPoint2D)

# passenger related signals
## Emitted when passenger request taxi.
signal passenger_request_taxi(passenger: Passenger, landing_pad: LandingPad)
## Emitted when passenger entered taxi.
signal passenger_entered_taxi(passenger: Passenger)
## Emitted when passenger exited taxi.
signal passenger_exited_taxi(passenger: Passenger)
## Emitted when passenger died.
signal passenger_died(passenger: Passenger)
## Emitted when passenger despawned.
signal passenger_despawned(passenger: Passenger)

# region Taxi related emitters
## Handles emit taxi health changed.
func emit_taxi_health_changed(new_health: float) -> void:
	taxi_health_changed.emit(new_health)

## Handles emit gear health changed.
func emit_gear_health_changed(new_health: float) -> void:
	gear_health_changed.emit(new_health)

## Handles emit taxi landed.
func emit_taxi_landed(landing_pad: LandingPad, taxi_x_pos: float) -> void:
	taxi_landed.emit(landing_pad, taxi_x_pos)
# endregion

# region Junction graph related emitters
## Handles emit mouse over junction point.
func emit_mouse_over_junction_point(point: JunctionPoint2D) -> void:
	mouse_over_junction_point.emit(point)

## Handles emit mouse exit junction point.
func emit_mouse_exit_junction_point(point: JunctionPoint2D) -> void:
	mouse_exit_junction_point.emit(point)
# endregion

# region Passenger related emitters
## Handles emit passenger request taxi.
func emit_passenger_request_taxi(passenger: Passenger, landing_pad: LandingPad) -> void:
	passenger_request_taxi.emit(passenger, landing_pad)

## Handles emit passenger entered taxi.
func emit_passenger_entered_taxi(passenger: Passenger) -> void:
	passenger_entered_taxi.emit(passenger)

## Handles emit passenger exited taxi.
func emit_passenger_exited_taxi(passenger: Passenger) -> void:
	passenger_exited_taxi.emit(passenger)

## Handles emit passenger died.
func emit_passenger_died(passenger: Passenger) -> void:
	passenger_died.emit(passenger)

## Handles emit passenger despawned.
func emit_passenger_despawned(passenger: Passenger) -> void:
	passenger_despawned.emit(passenger)
# endregion
