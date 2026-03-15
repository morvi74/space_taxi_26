extends CharacterBody2D
class_name Taxi

# Movement constants
#const _THRUST_POWER : float = 500.0
const _ACCELERATION = 500.0
const _DECELERATION : float = 2.0
const _MAX_SPEED = 300.0
const _DAMPING = 0.6
const _SAFE_LANDING_SPEED = 100.0
@export var _min_bounce_speed = 70.0

@export var _gravity = 130.0  # For planetary landings

@export var _landing_gear_controller: LandingGearController
@export var _mono_foot_collision: CollisionShape2D
@onready var _body_collision: CollisionPolygon2D = $BodyCollision
@onready var _taxi_sprite: Sprite2D = $TaxiSprite

# Taxi body collision
#const _TAXI_COLLISION_DAMAGE = 15.0
@export var _damage_threshold_speed: float = 80.0
var _collision_was_too_fast: bool = false	
@export var _bounce_factor: float = 0.5  # How much velocity is retained after a bounce (0.5 means 50% retained)
var pre_move_velocity: Vector2 = Vector2.ZERO  # Store velocity before move_and_slide for bounce calculations

var _taxi_health: int = 100

var _input_vector: Vector2 = Vector2.ZERO

var _is_landed: bool = false
func is_landed() -> bool:
	return _is_landed

var _passengers_aboard: Array[Passenger] = []
func get_passengers_aboard() -> Array[Passenger]:
	return _passengers_aboard
var _passenger_max_capacity: int = 1
func get_passenger_count() -> int:
	return _passengers_aboard.size()
func get_passenger_capacity() -> int:
	return _passenger_max_capacity
func is_full() -> bool:
	return _passengers_aboard.size() >= _passenger_max_capacity
func erase_passenger_at(nr: int) -> void:
	_passengers_aboard.remove_at(nr)
	
func _ready() -> void:
	_landing_gear_controller.set_taxi(self)
	if _mono_foot_collision:
		_landing_gear_controller.set_mono_foot_collision(_mono_foot_collision)
	_landing_gear_controller.gear_state_changed.connect(on_landing_gear_state_changed)
	EventHub.emit_taxi_health_changed(_taxi_health)  # Emit initial health value to UI
	GameData.set_taxi(self)  # Store reference to taxi in GameData for global access
	EventHub.passenger_entered_taxi.connect(_on_passenger_entered_taxi)  # Connect signal to handle passengers entering taxi

func _physics_process(delta: float) -> void:
	_input_vector = _get_input_vector()

	_apply_flip()
	_calculate_velocity_from_input(delta)
	
	if not is_on_floor() and _gravity != 0:
		_is_landed = false  # If we're in the air, we're not landed, even if we were previously marked as landed. This allows us to properly detect new landings when we touch down again after being in the air.
		_apply_gravity(delta)	
	
	_apply_thrusters(delta)
	
	pre_move_velocity = velocity
	
	_move_taxi()
	
	_handle_taxi_collisions(delta)

	# Handle gear toggle
	if Input.is_action_just_pressed("toggle_gear"):
		toggle_landing_gear()


# Flips the taxi sprite based on horizontal movement direction. This provides visual feedback to the player, making it clear which way the taxi is moving. The sprite will flip horizontally when moving left and return to normal when moving right.
#
# @return void
func _apply_flip() -> void:
	# Flip sprite based on horizontal velocity
	if _input_vector.x > 0:
		_taxi_sprite.flip_h = false
		_body_collision.scale.x = 1.0
	elif _input_vector.x < 0:
		_taxi_sprite.flip_h = true
		_body_collision.scale.x = -1.0


# Calculates the taxi's velocity based on player input, applying acceleration, deceleration, gravity, and clamping to maximum speed. Horizontal movement is affected by input and friction, while vertical movement is influenced by input and gravity.
#
# @param delta The frame time step (in seconds).
# @return void
func _calculate_velocity_from_input(delta: float) -> void:
	# X-axis: accelerate with input, decelerate without
	if _input_vector.x != 0:
		velocity.x += _input_vector.x * _ACCELERATION * delta
	else:
		velocity.x = move_toward(velocity.x, 0, _DECELERATION)
	
	# Y-axis: accelerate with input, decelerate only for upward movement without input
	if _input_vector.y != 0:
		velocity.y += _input_vector.y * _ACCELERATION * delta
	elif velocity.y < 0:  # Only decelerate upward movement, not downward
		velocity.y = move_toward(velocity.y, 0, _DECELERATION)
	
	# Clamp horizontal speed to maximum
	if velocity.x > _MAX_SPEED:
		velocity.x = _MAX_SPEED
	if velocity.x < -_MAX_SPEED:
		velocity.x = -_MAX_SPEED


func toggle_landing_gear() -> void:
	_landing_gear_controller.toggle_gear()


func on_landing_gear_state_changed(new_state) -> void:
	# print("Landing gear state changed to:", new_state)
	if new_state == LandingGearController.GearState.RETRACTED:
		# print("Landing gear retracted")
		_mono_foot_collision.disabled = true
	else:
		_mono_foot_collision.disabled = false
	

# Reads player input for thrusters and returns a combined thrust vector.
# Thrusters only affect horizontal movement when in the air, but vertical thrusters work regardless of grounded state.
#
# @return Vector2 The combined thrust direction from player input.
func _get_input_vector() -> Vector2:
	var result = Vector2.ZERO
	if not is_on_floor():
		result.x = Input.get_action_strength("thrust_right") - Input.get_action_strength("thrust_left")
	result.y = Input.get_action_strength("thrust_down") - Input.get_action_strength("thrust_up")
	return result


func _handle_taxi_collisions(delta: float) -> void:
	for i in range(get_slide_collision_count()):
		var collision : KinematicCollision2D = get_slide_collision(i)
		var collider : Node = collision.get_collider()
		var local_shape = collision.get_local_shape()
		var collision_speed : float = pre_move_velocity.length()
		_collision_was_too_fast = collision_speed > _damage_threshold_speed

		if _is_body_collision(local_shape):
			# print("Collision with taxi body detected")

			if _collision_was_too_fast: # Only apply damage if the collision was with the body and above the damage threshold
				# print("Collision speed above damage threshold, applying damage")
				# Apply damage to taxi health
				_taxi_health -= int(round(_calculate_collision_damage(collision_speed)))
				_taxi_health = max(_taxi_health, 0)
				EventHub.emit_taxi_health_changed(_taxi_health)  # Emit signal to update UI

			if collision_speed > _min_bounce_speed: # Only apply bounce if the collision speed is above the minimum threshold
				# print("Always applying bounce with cabin collision")
				velocity = pre_move_velocity.bounce(collision.get_normal()) * _bounce_factor
				return  # Skip further collision handling for this collision since we've already applied bounce
		else:
			if _collision_was_too_fast: # Only apply damage if the collision was with the body and above the damage threshold
				# print("Collision speed above damage threshold, applying damage")
				_landing_gear_controller.apply_damage(int(round(_calculate_collision_damage(collision_speed))))

			if collision_speed > _min_bounce_speed: # Only apply bounce if the collision speed is above the minimum threshold
				# print("Landing gear not deployed, applying bounce")
				velocity = pre_move_velocity.bounce(collision.get_normal()) * _bounce_factor
				return  # Skip further collision handling for this collision since we've already applied bounce

			# If the landing gear is deployed, we need to check if the collision is with a landing pad and if the landing conditions are met. If not, we apply bounce. If the landing conditions are met, we allow the landing to proceed without bounce.			
			if _landing_gear_controller.get_state() == LandingGearController.GearState.DEPLOYED:
				if collider is LandingPad: # Only check landing conditions if we're colliding with a landing pad
					if not _landing_gear_controller.can_land():
						# print("Landing conditions not met, applying bounce")
						velocity = pre_move_velocity.bounce(collision.get_normal()) * _bounce_factor
					else: # Landing conditions are met
						# print("Landing conditions met, allowing landing without bounce")
						if _landing_gear_controller.landing_complete(delta):
							# print("Successful landing on landing pad ", _landing_gear_controller.get_current_landing_pad())
							if not _is_landed:
								_is_landed = true
								EventHub.emit_taxi_landed(_landing_gear_controller.get_current_landing_pad(), global_position.x)

		# # Calculate bounce based on collision normal and pre-move velocity
		# var bounce_direction = collision.get_normal()
		# if collider is LandingPad and local_shape == _mono_foot_collision:
		# 	var landing_speed = pre_move_velocity.length()
		# 	print("Collided with landing pad foot collision shape", "Landing speed:", landing_speed)
		# 	# Only apply bounce if the collision speed is above the minimum threshold
		# 	if pre_move_velocity.length() > _landing_gear_controller.get_max_landing_speed():
		# 		print("Too fast for landing, applying bounce")
		# 		velocity = pre_move_velocity.bounce(bounce_direction) * _bounce_factor
		# 	else:
		# 		print("Safe landing, no bounce applied")
		# else:
		# 	velocity = pre_move_velocity.bounce(bounce_direction) * _bounce_factor


# Takes in the local_shape of current collision and return true if the collision is with the taxi body, which should cause damage, and false if it's a collision with the landing gear, which should not cause damage.
func _is_body_collision(local_shape) -> bool:
	return local_shape == _body_collision


# Calculate damage value based on collision speed and returns the damage value.
# @param collision_speed The speed at which the collision occurred, used to determine how much damage to apply to the taxi.
# @return float The calculated damage value based on collision speed.
func _calculate_collision_damage(collision_speed: float) -> float:
	if collision_speed <= _damage_threshold_speed:
		return 0.0
	# Damage scales with speed above the threshold, using a simple linear formula for demonstration
	return (collision_speed - _damage_threshold_speed) * 0.1



# Applies gravity to the taxi's velocity. This is only relevant when the taxi is not on the ground, such as during planetary landings.
#
# @param delta The time elapsed since the last physics frame, used to ensure consistent gravity application regardless of frame rate.#
# @return void
func _apply_gravity(delta: float) -> void:
	# Apply gravity
	velocity.y += _gravity * delta


# Applies player-controlled thruster input to the taxi's velocity. Horizontal thrusters only affect movement when the taxi is in the air, while vertical thrusters work regardless of whether the taxi is grounded.
#
# @param delta The time elapsed since the last physics frame, used to ensure consistent thruster application regardless of frame rate.
# @return void
func _apply_thrusters(_delta: float) -> void:
	pass


# Moves the taxi based on its current velocity and the physics engine. This should be called after applying gravity and thruster forces to ensure that the taxi's movement reflects all influences.
#
# @return void
func _move_taxi() -> void:
	move_and_slide()

func _on_passenger_entered_taxi(passenger: Passenger) -> void:
	print("Passenger entered taxi:", passenger)
	if not is_full():
		_passengers_aboard.append(passenger)
		print("Passenger added. Current count:", get_passenger_count())
	else:
		printerr("Taxi is full. Cannot add more passengers. Should not happen if landing pads check for taxi capacity before sending passengers.")