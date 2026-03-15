extends Area2D
class_name Passenger 




@onready var _anim_player: AnimationPlayer = $AnimationPlayer
@onready var _sprite: Sprite2D = $Sprite2D

@export var _walk_speed: float = 50.0

var _start_landing_pad: LandingPad = null
func set_start_landing_pad(landing_pad: LandingPad) -> void:
	_start_landing_pad = landing_pad
func get_start_landing_pad() -> LandingPad:
	return _start_landing_pad

var _destination_landing_pad: LandingPad = null
func set_destination_landing_pad(landing_pad: LandingPad) -> void:
	_destination_landing_pad = landing_pad
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

var _state: State 
var _moving_destination: Vector2 = Vector2.INF
var _direction: Vector2 = Vector2.ZERO
var _passenger_parent_node: Node2D = null



# func _ready() -> void:
# 	EventHub.taxi_landed.connect(_on_taxi_landed)

func activate() -> void:	
	_state = State.SPAWNING
	global_position = _start_landing_pad.get_waiting_zone().get_waiting_position()
	_anim_player.play("become_visible")


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


func walk_to_taxi(pos_x: float) -> void:
	if _state == State.WAITING_FOR_TAXI:
		_state = State.WALKING_TO_TAXI
		if _direction == Vector2.RIGHT:
			_anim_player.play("walk_right")
		else:
			_anim_player.play("walk_left")
		_moving_destination = Vector2(pos_x, global_position.y)


func _enter_taxi() -> void:
	if _state == State.WALKING_TO_TAXI:
		_state = State.ENTER_TAXI
		_anim_player.play("become_invisible")
		

func exit_taxi() -> void:
	if _state == State.IN_TAXI:
		_state = State.EXIT_TAXI
		_anim_player.play("become_visible")


# func _on_taxi_landed(landing_pad: LandingPad, taxi_pos_x: float) -> void:
# 	if landing_pad == _destination_landing_pad and _state == State.IN_TAXI:
# 		print("Passenger ", name, " has arrived at their destination landing pad.")
# 		_exit_taxi()
