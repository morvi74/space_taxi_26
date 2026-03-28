extends Area2D
## Represents the Passenger component.
class_name Passenger 




## Cached node reference for anim player.
@onready var _anim_player: AnimationPlayer = $AnimationPlayer
#@onready var _sprite: Sprite2D = $Sprite2D

## Inspector setting for walk speed.
@export var _walk_speed: float = 50.0

## Internal state for start landing pad.
var _start_landing_pad: LandingPad = null
## Updates start landing pad.
func set_start_landing_pad(landing_pad: LandingPad) -> void:
	_start_landing_pad = landing_pad
## Returns start landing pad.
func get_start_landing_pad() -> LandingPad:
	return _start_landing_pad

## Internal state for destination landing pad.
var _destination_landing_pad: LandingPad = null
## Updates destination landing pad.
func set_destination_landing_pad(landing_pad: LandingPad) -> void:
	_destination_landing_pad = landing_pad
## Returns destination landing pad.
func get_destination_landing_pad() -> LandingPad:
	return _destination_landing_pad


enum State {
	SPAWNING,
	WAITING_FOR_TAXI,
	WALKING_TO_TAXI,
	ENTER_TAXI,
	IN_TAXI,
	EXIT_TAXI,
	LEAVING,
	DESPAWNING,
	DYING
}

## Internal state for state.
var _state: State 
## Internal state for moving destination.
var _moving_destination: Vector2 = Vector2.INF
## Internal state for direction.
var _direction: Vector2 = Vector2.ZERO
## Internal state for passenger parent node.
var _passenger_parent_node: Node2D = null
## Returns passenger parent node.
func get_passenger_parent_node() -> Node2D:
	return _passenger_parent_node
## Updates passenger parent node.
func set_passenger_parent_node(node: Node2D) -> void:
	_passenger_parent_node = node

## Internal state for transport distance.
var _transport_distance: float = 0.0
## Returns transport distance.
func get_transport_distance() -> float:
	return _transport_distance


# func _ready() -> void:
# 	EventHub.taxi_landed.connect(_on_taxi_landed)

## Handles activate.
func activate() -> void:		
	_state = State.SPAWNING
	global_position = _start_landing_pad.get_waiting_zone().get_waiting_position()
	_anim_player.play("become_visible")
	if _start_landing_pad == null:
		printerr("Passenger ", name, ": start landing pad is null. This should not happen if the level is set up correctly.")
	if _destination_landing_pad == null:
		printerr("Passenger ", name, ": destination landing pad is null. This should not happen if the level is set up correctly.")
	if _start_landing_pad != null and _destination_landing_pad != null:
		_transport_distance = ManagerHub.get_traffic_manager().get_distance_between_landing_pads(_start_landing_pad, _destination_landing_pad)
	

## Updates physics-driven behavior.
func _physics_process(delta: float) -> void:
	match _state:
		State.WALKING_TO_TAXI:
			
			global_position += _direction * _walk_speed * delta
			
			if global_position.distance_to(_moving_destination) < 5.0:
				global_position = _moving_destination
				_enter_taxi()
		State.LEAVING:
			global_position += _direction * _walk_speed * delta
			
			if global_position.distance_to(_moving_destination) < 5.0:
				global_position = _moving_destination
				_state = State.DESPAWNING
				_anim_player.play("become_invisible")


## Handles the animation player animation finished callback.
func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "become_visible":
		if _state == State.SPAWNING:
			_state = State.WAITING_FOR_TAXI
			_direction = _start_landing_pad.get_waiting_zone()._direction_to_landing_pad
			if _direction == Vector2.RIGHT:
				_anim_player.play("idle_right")
			else:
				_anim_player.play("idle_left")
			EventHub.emit_passenger_request_taxi(self, _start_landing_pad)
		elif _state == State.EXIT_TAXI:
			_state = State.LEAVING
			EventHub.emit_passenger_exited_taxi(self)
			if global_position.x < _destination_landing_pad.get_waiting_zone().get_leaving_position().x:
				_direction = Vector2.RIGHT
			else:
				_direction = Vector2.LEFT
			#_direction = _destination_landing_pad.get_waiting_zone()._direction_to_landing_pad
			_moving_destination = _destination_landing_pad.get_waiting_zone().get_leaving_position()
			print("Passenger ", name, " at pos: ", global_position, " is leaving towards landing pad: ", _destination_landing_pad.get_id(), " on global position: ", _destination_landing_pad.global_position, " with destination: ", _moving_destination)
			if _direction == Vector2.RIGHT:
				_anim_player.play("walk_right")
			else:
				_anim_player.play("walk_left")
	elif anim_name == "become_invisible":
		if _state == State.ENTER_TAXI:
			_state = State.IN_TAXI
			_start_landing_pad.clear_passenger()			
			EventHub.emit_passenger_entered_taxi(self)
		elif _state == State.DESPAWNING:
			queue_free()


## Handles walk to taxi.
func walk_to_taxi(pos_x: float) -> void:
	if _state == State.WAITING_FOR_TAXI:
		_state = State.WALKING_TO_TAXI
		if _direction == Vector2.RIGHT:
			_anim_player.play("walk_right")
		else:
			_anim_player.play("walk_left")
		_moving_destination = Vector2(pos_x, global_position.y)


## Internal helper that handles enter taxi.
func _enter_taxi() -> void:
	if _state == State.WALKING_TO_TAXI:
		_state = State.ENTER_TAXI
		_anim_player.play("become_invisible")
		

## Handles exit taxi.
func exit_taxi() -> void:
	if _state == State.IN_TAXI:
		_state = State.EXIT_TAXI
		_anim_player.play("become_visible")
		reparent(_passenger_parent_node)


# func _on_taxi_landed(landing_pad: LandingPad, taxi_pos_x: float) -> void:
# 	if landing_pad == _destination_landing_pad and _state == State.IN_TAXI:
# 		print("Passenger ", name, " has arrived at their destination landing pad.")
# 		_exit_taxi()
