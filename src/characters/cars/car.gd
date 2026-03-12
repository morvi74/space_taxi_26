extends RigidBody2D
class_name Car


var _velocity: Vector2 = Vector2.ZERO
@export var _max_speed: float = 100.0
@export var _direction: Vector2 = Vector2.ZERO

func get_velocity() -> Vector2:
	return _velocity


func set_velocity(new_velocity: Vector2) -> void:
	_velocity = clamp(new_velocity, 0.0, _max_speed)

func set_direction(new_direction: Vector2) -> void:
	_direction = new_direction.normalized()

