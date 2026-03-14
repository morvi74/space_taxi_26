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

func activate() -> void:
	_state = State.SPAWNING
	_anim_player.play("become_visible")


func _physics_process(delta: float) -> void:
	match _state:
		State.WALKING_TO_TAXI:
			var direction = (_moving_destination - global_position).normalized()
			
			global_position += direction * _walk_speed * delta
			
			if global_position.distance_to(_moving_destination) < 5.0:
				global_position = _moving_destination
				_enter_taxi()


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "become_visible":
		_state = State.WAITING_FOR_TAXI
		if _start_landing_pad.get_waiting_zone()._direction_to_landing_pad == Vector2.RIGHT:
			_anim_player.play("idle_right")
		else:
			_anim_player.play("idle_left")
	elif anim_name == "become_invisible":
		if _state == State.ENTER_TAXI:
			_state = State.IN_TAXI
	elif anim_name == "exit_taxi":
		_state = State.LEAVING
	elif anim_name == "despawn":
		queue_free()


func walk_to_taxi(pos_x: float) -> void:
	if _state == State.WAITING_FOR_TAXI:
		_state = State.WALKING_TO_TAXI
		if _start_landing_pad.get_waiting_zone()._direction_to_landing_pad == Vector2.RIGHT:
			_anim_player.play("walk_right")
		else:
			_anim_player.play("walk_left")
		_moving_destination = Vector2(pos_x, global_position.y)


func _enter_taxi() -> void:
	if _state == State.WALKING_TO_TAXI:
		_state = State.ENTER_TAXI
		_anim_player.play("become_invisible")
		