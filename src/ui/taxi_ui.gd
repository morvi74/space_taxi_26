extends Control
class_name TaxiUI



@onready var _taxi_health_label: Label = $VBoxContainer/TaxiHealthHBox/ValueLabel
@onready var _gear_health_label: Label = $VBoxContainer/GearHealthHBox/ValueLabel
@onready var _dest_label: Label = $VBoxContainer/DestinationHBox/ValueLabel

func _ready() -> void:
	EventHub.taxi_health_changed.connect(_on_taxi_health_changed)
	EventHub.gear_health_changed.connect(_on_gear_health_changed)
	EventHub.passenger_entered_taxi.connect(_on_passenger_entered_taxi)
	EventHub.passenger_exited_taxi.connect(_on_passenger_exited_taxi)

func _on_taxi_health_changed(new_health: int) -> void:
	_taxi_health_label.text = str(round(new_health))

func _on_gear_health_changed(new_health: int) -> void:
	_gear_health_label.text = str(round(new_health))

func _on_passenger_entered_taxi(passenger: Passenger) -> void:
	_dest_label.text = str(passenger.get_destination_landing_pad().get_id())

func _on_passenger_exited_taxi(passenger: Passenger) -> void:
	_dest_label.text = "None"