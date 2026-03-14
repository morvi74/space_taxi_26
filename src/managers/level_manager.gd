extends Node
class_name LevelManager

@onready var _start_spawn_passenger_timer: Timer = $StartSpawnPassengerTimer

@export var _passenger_scenes: Array[PackedScene]
@export var _passenger_root_node: Node2D

var _spawned_passengers: Array[Passenger] = []
var _landing_pads: Array[LandingPad]



func _ready() -> void:
	var lps = get_tree().get_nodes_in_group("landing_pads")
	for i in range(lps.size()):
		if lps[i] is LandingPad:
			_landing_pads.append(lps[i])
	
	if _landing_pads.is_empty():
		printerr(name, ": No Landing Pads in Level. This should not happen!")
		return
	
	for i in range(_landing_pads.size()):
		_landing_pads[i].setup(i+1)
	
	_start_spawn_passenger_timer.start()


func _on_start_passenger_spawn_timer_timeout() -> void:
	var p: Passenger = _spawn_passenger()
	_spawned_passengers.append(p)
	

func _spawn_passenger() -> Passenger:
	var passenger_scene: PackedScene = _passenger_scenes[randi() % _passenger_scenes.size()]
	var passenger: Passenger = passenger_scene.instantiate() as Passenger
	

	var start_lp: LandingPad = _landing_pads[randi() % _landing_pads.size()]
	passenger.set_start_landing_pad(start_lp)

	var dest_lp: LandingPad = _landing_pads[randi() % _landing_pads.size()]
	while dest_lp == start_lp:
		dest_lp = _landing_pads[randi() % _landing_pads.size()]
	passenger.set_destination_landing_pad(dest_lp)

	_passenger_root_node.add_child(passenger)
	
	return passenger