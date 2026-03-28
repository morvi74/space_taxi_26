extends Control
## Represents the TaxiUI component.
class_name TaxiUI



## Cached node reference for taxi health label.
@onready var _taxi_health_label: Label = $VBoxContainer/TaxiHealthHBox/ValueLabel
## Cached node reference for gear health label.
@onready var _gear_health_label: Label = $VBoxContainer/GearHealthHBox/ValueLabel
## Cached node reference for dest label.
@onready var _dest_label: Label = $VBoxContainer/DestinationHBox/ValueLabel
## Cached node reference for pay value label.
@onready var _pay_value_label: Label = $VBoxContainer/PaymentHBox/ValueLabel


## Initializes runtime references and startup state.
func _ready() -> void:
	EventHub.taxi_health_changed.connect(_on_taxi_health_changed)
	EventHub.gear_health_changed.connect(_on_gear_health_changed)
	EventHub.passenger_entered_taxi.connect(_on_passenger_entered_taxi)
	EventHub.passenger_exited_taxi.connect(_on_passenger_exited_taxi)
	

## Handles the taxi health changed callback.
func _on_taxi_health_changed(new_health: int) -> void:
	_taxi_health_label.text = str(round(new_health))

## Handles the gear health changed callback.
func _on_gear_health_changed(new_health: int) -> void:
	_gear_health_label.text = str(round(new_health))

## Handles the passenger entered taxi callback.
func _on_passenger_entered_taxi(passenger: Passenger) -> void:
	_dest_label.text = str(passenger.get_destination_landing_pad().get_id())
	_pay_value_label.text = "$" + str(passenger.get_transport_distance() * 0.1)
## Handles the passenger exited taxi callback.
func _on_passenger_exited_taxi(passenger: Passenger) -> void:
	_dest_label.text = "None"
	_pay_value_label.text = "$0"
