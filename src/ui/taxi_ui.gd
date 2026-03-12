extends Control
class_name TaxiUI



@onready var _taxi_health_label: Label = $VBoxContainer/TaxiHealthHBox/ValueLabel
@onready var _gear_health_label: Label = $VBoxContainer/GearHealthHBox/ValueLabel


func _ready() -> void:
	EventHub.taxi_health_changed.connect(_on_taxi_health_changed)
	EventHub.gear_health_changed.connect(_on_gear_health_changed)


func _on_taxi_health_changed(new_health: int) -> void:
	_taxi_health_label.text = str(round(new_health))

func _on_gear_health_changed(new_health: int) -> void:
	_gear_health_label.text = str(round(new_health))