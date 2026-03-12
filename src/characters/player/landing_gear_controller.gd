class_name LandingGearController
extends Node

signal gear_state_changed(new_state)

enum GearState
{
	RETRACTED,
	DEPLOYING,
	DEPLOYED,
	RETRACTING,
	BROKEN
}

var _deploy_speed: float = 60.0
@export var _max_deploy_speed: float = 60.0
@export var _gear_retracted_y: float = 0.0
@export var _gear_deployed_y: float = 18.0

@export var _max_health: int = 100
@export var _max_landing_speed: float = 80.0
func get_max_landing_speed() -> float:
	return _max_landing_speed
@export var _landing_stable_time: float = 0.15

var _health: int = 0
var _state: GearState = GearState.RETRACTED
func get_state() -> GearState:
	return _state
var _current_gear_y: float = 0.0
var _stable_timer: float = 0.0

# Reference to the Taxi node
var _taxi: Taxi
func set_taxi(taxi_instance: Taxi) -> void:
	_taxi = taxi_instance

# Collision nodes for landing gear and feet
var _mono_foot_collision: Node2D
func set_mono_foot_collision(collision_node: Node2D) -> void:
	_mono_foot_collision = collision_node
	_is_dual_foot = false
	print("Mono foot collision set to: ", _mono_foot_collision)
	_apply_gear_positions()  # Ensure the collision node is positioned correctly when set
var _left_foot_collision: Node2D
var _right_foot_collision: Node2D
func set_dual_foot_collision(left_collision_node: Node2D, right_collision_node: Node2D) -> void:
	_left_foot_collision = left_collision_node
	_right_foot_collision = right_collision_node
	_is_dual_foot = true
	_apply_gear_positions()  # Ensure the collision nodes are positioned correctly when set

var _is_dual_foot: bool = false

# RayCast2D nodes for foot detection and gear root
@export var _landing_gear_root: Node2D# = $"../../LandingGearRoot"
@export var _foot_left_ray: RayCast2D# = $"../../LandingGearRoot/FootLeftRay"
@export var _foot_right_ray: RayCast2D# = $"../../LandingGearRoot/FootRightRay"
@export var _ground_ray: RayCast2D# = $"../../LandingGearRoot/GroundRay"


func _ready() -> void:
	_health = _max_health
	EventHub.emit_gear_health_changed(_health)  # Emit initial health value to UI
	_current_gear_y = _gear_retracted_y
	#_apply_gear_positions()

# Toggles the landing gear between deployed and retracted states, initiating the appropriate deployment or retraction process based on the current state of the gear. This function is typically called in response to player input, allowing the player to control the landing gear during flight and landing maneuvers.
#
# @return void
func toggle_gear() -> void:
	match _state:
		GearState.RETRACTED, GearState.RETRACTING:
			_state = GearState.DEPLOYING
			gear_state_changed.emit(_state)
		GearState.DEPLOYED, GearState.DEPLOYING:
			_state = GearState.RETRACTING
			gear_state_changed.emit(_state)


func _physics_process(delta: float) -> void:
	if _state in [GearState.DEPLOYING, GearState.RETRACTING]:
		_update_gear(delta)


# Updates the landing gear position based on the current _state and the deploy speed
func _update_gear(delta: float) -> void:
	match _state:
		GearState.DEPLOYING:
			_current_gear_y += _deploy_speed * delta

			if _current_gear_y >= _gear_deployed_y:
				_current_gear_y = _gear_deployed_y
				_state = GearState.DEPLOYED
				gear_state_changed.emit(_state)

			_apply_gear_positions()

		GearState.RETRACTING:
			_current_gear_y -= _deploy_speed * delta

			if _current_gear_y <= _gear_retracted_y:
				_current_gear_y = _gear_retracted_y
				_state = GearState.RETRACTED
				gear_state_changed.emit(_state)

			_apply_gear_positions()


# Updates the position of the landing gear based on the current gear _state
func _apply_gear_positions() -> void:
	var root_position: Vector2 = _landing_gear_root.position
	root_position.y = _current_gear_y
	_landing_gear_root.position = root_position

	var ground_ray_position: Vector2 = _ground_ray.position
	ground_ray_position.y = _current_gear_y
	_ground_ray.position = ground_ray_position

	if _is_dual_foot:
		_left_foot_collision.position.y = _current_gear_y
		_right_foot_collision.position.y = _current_gear_y
	else:
		_mono_foot_collision.position.y = _current_gear_y


# Gear _state checks
func is_deployed() -> bool:
	return _state == GearState.DEPLOYED


# Checks if the landing gear is in a _state that allows it to be deployed or retracted
func is_broken() -> bool:
	return _state == GearState.BROKEN


# Checks if the landing gear is in a _state that allows landing, and if the conditions for a safe landing are met
func can_land() -> bool:
	if _state != GearState.DEPLOYED:
		return false

	if _health <= 0:
		return false

	if not _foot_left_ray.is_colliding():
		return false

	if not _foot_right_ray.is_colliding():
		return false

	# if abs(_taxi.velocity.y) > _max_landing_speed:
	# 	return false

	return true


# Updates the landing process, checking if the landing conditions are met and if the landing has been stable for the required time to be considered successful
func update_landing(delta: float) -> bool:
	if can_land():
		_stable_timer += delta

		if _stable_timer >= _landing_stable_time:
			return true
	else:
		_stable_timer = 0.0

	return false


# Applies damage to the landing gear, reducing its _health and potentially breaking it if the _health drops to zero or below
func apply_damage(amount: int) -> void:
	if _state == GearState.BROKEN:
		return

	_health -= amount
	_health = max(_health, 0)
	EventHub.emit_gear_health_changed(_health)  # Emit signal to update UI
	_set_deploy_speed()  # Update deploy speed based on new health value
	
	if _health <= 0:
		_health = 0
		_state = GearState.BROKEN


# Set the deploy speed of the landing gear, allowing for dynamic adjustments based on game conditions or player upgrades
# Deploy speed will be reduced based on the current health of the landing gear, simulating the effect of damage on the gear's performance	
# The first 10% of damage will have no effect on deploy speed, The minimal deploy speed will be 10% of max deploy speed starting at 90% damage, and the deploy speed will decrease linearly between these points. This allows for a more forgiving damage model where minor damage does not immediately cripple the landing gear, while severe damage significantly impacts its functionality.
#
# @return void
func _set_deploy_speed() -> void:
	var damage_percent = float(_health) / float(_max_health)
	if damage_percent >= 0.9:
		_deploy_speed = _max_deploy_speed
	elif damage_percent <= 0.1:
		_deploy_speed = _max_deploy_speed * 0.1
	else:
		var speed_factor = (damage_percent - 0.1) / 0.8
		_deploy_speed = _max_deploy_speed * (0.1 + speed_factor * 0.9)
	
