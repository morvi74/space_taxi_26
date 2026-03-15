extends Node
class_name LevelManager

@onready var _start_passenger_spawn_timer: Timer = $StartPassengerSpawnTimer

@export var _passenger_scenes: Array[PackedScene]
@export var _passenger_root_node: Node2D

var _spawned_passengers: Array[Passenger] = []
var _landing_pads: Array[LandingPad]
var _free_landing_pads: Array[LandingPad] = []
var rng = RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	var lps = get_tree().get_nodes_in_group("landing_pads")
	for i in range(lps.size()):
		if lps[i] is LandingPad:
			_landing_pads.append(lps[i])
	
	if _landing_pads.is_empty():
		printerr(name, ": No Landing Pads in Level. This should not happen!")
		return
	
	for i in range(_landing_pads.size()):
		_landing_pads[i].setup(i+1)
	
	_start_passenger_spawn_timer.start()
	EventHub.passenger_entered_taxi.connect(_on_passenger_entered_taxi)
	EventHub.passenger_exited_taxi.connect(_on_passenger_exited_taxi)


# This function is called every time the _start_passenger_spawn_timer times out. 
# It checks if a new passenger should be spawned and if so, spawns one.
func _on_start_passenger_spawn_timer_timeout() -> void:
	if _check_if_passenger_should_spawn():
		var p: Passenger = _spawn_passenger()
		_spawned_passengers.append(p)


# This function spawns a passenger at a random free landing pad and assigns them a random destination landing pad.
# It returns the spawned passenger.
func _spawn_passenger() -> Passenger:
	var passenger_scene: PackedScene = _passenger_scenes[rng.randi() % _passenger_scenes.size()]
	var passenger: Passenger = passenger_scene.instantiate() as Passenger	

	var start_lp: LandingPad = _free_landing_pads[rng.randi() % _free_landing_pads.size()]
	passenger.set_start_landing_pad(start_lp)

	var dest_lp: LandingPad = _landing_pads[rng.randi() % _landing_pads.size()]
	while dest_lp == start_lp:
		dest_lp = _landing_pads[rng.randi() % _landing_pads.size()]
	passenger.set_destination_landing_pad(dest_lp)
	start_lp.assign_passenger(passenger)

	_passenger_root_node.add_child(passenger)
	passenger.activate()
	return passenger


# This function checks if enough landing pads are free to spawn a new passenger. 
# If at least half of the landing pads are free, it returns true, otherwise false.
func _check_if_passenger_should_spawn() -> bool:
	_find_free_landing_pads()
	if _free_landing_pads.size() >= int(round(_landing_pads.size() * 0.5)):
		print("Spawning new passenger. Free landing pads: ", _free_landing_pads.size(), "/", _landing_pads.size())
		return true
	else:
		return false

# This function populates the _free_landing_pads array with all currently free landing pads.
func _find_free_landing_pads() -> void:
	_free_landing_pads.clear()
	for i in range(_landing_pads.size()):
		if not _landing_pads[i].is_occupied():
			_free_landing_pads.append(_landing_pads[i])


func _on_passenger_entered_taxi(passenger: Passenger) -> void:
	print("Passenger ", passenger.name, " has entered the taxi.")
	passenger.reparent(GameData.get_taxi())

func _on_passenger_exited_taxi(passenger: Passenger) -> void:
	print("Passenger ", passenger.name, " has exited the taxi at their destination.")
	passenger.reparent(_passenger_root_node)
