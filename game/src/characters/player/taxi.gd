extends CharacterBody2D
## Represents the Taxi component.
class_name Taxi

# Movement constants
#const _THRUST_POWER : float = 500.0
## Shared constant for acceleration.
const _ACCELERATION = 500.0
## Shared constant for deceleration.
const _DECELERATION : float = 2.0
## Shared constant for max speed.
const _MAX_SPEED = 300.0
## Shared constant for damping.
const _DAMPING = 0.6
## Shared constant for safe landing speed.
const _SAFE_LANDING_SPEED = 120.0
## Inspector setting for min bounce speed.
@export var _min_bounce_speed = 100.0

## Inspector setting for gravity.
@export var _gravity = 130.0  # For planetary landings

## Inspector setting for landing gear controller.
@export var _landing_gear_controller: LandingGearController
## Inspector setting for mono foot collision.
@export var _mono_foot_collision: CollisionShape2D
## Cached node reference for body collision.
@onready var _body_collision: CollisionPolygon2D = $BodyCollision
## Cached node reference for taxi sprite.
@onready var _taxi_sprite: Sprite2D = $TaxiSprite

# Taxi body collision
#const _TAXI_COLLISION_DAMAGE = 15.0
## Inspector setting for damage threshold speed.
@export var _damage_threshold_speed: float = 80.0
## Internal state for collision was too fast.
var _collision_was_too_fast: bool = false	
## Inspector setting for bounce factor.
@export var _bounce_factor: float = 0.5  # How much velocity is retained after a bounce (0.5 means 50% retained)
## Internal state for old velocity.
var _old_velocity: Vector2 = Vector2.ZERO  # Store velocity before move_and_slide for bounce calculations
## Inspector setting for lift off assist force.
@export var _lift_off_assist_force: float = -30.0 # Upward force applied when taking off to help with lift-off, can be adjusted for better feel
## Internal state for taxi health.
var _taxi_health: int = 100

## Internal state for input vector.
var _input_vector: Vector2 = Vector2.ZERO

## Internal state for is landed.
var _is_landed: bool = false
## Checks whether landed.
func is_landed() -> bool:
	return _is_landed

## Internal state for passengers aboard.
var _passengers_aboard: Array[Passenger] = []
## Returns passengers aboard.
func get_passengers_aboard() -> Array[Passenger]:
	return _passengers_aboard
## Internal state for passenger max capacity.
var _passenger_max_capacity: int = 1
## Returns passenger count.
func get_passenger_count() -> int:
	return _passengers_aboard.size()
## Returns passenger capacity.
func get_passenger_capacity() -> int:
	return _passenger_max_capacity
## Checks whether full.
func is_full() -> bool:
	return _passengers_aboard.size() >= _passenger_max_capacity
## Handles erase passenger at.
func erase_passenger_at(nr: int) -> void:
	_passengers_aboard.remove_at(nr)
	
## Runtime state for is controller.
var is_controller = false

## Runtime state for last acceleration.
var last_acceleration: Vector2 = Vector2.ZERO
## Runtime state for total jerk stress.
var total_jerk_stress: float = 0.0

## Runtime state for last input x.
var last_input_x: float = 0.0
## Runtime state for reaction timer.
var reaction_timer: float = 0.0



## Initializes runtime references and startup state.
func _ready() -> void:
	_landing_gear_controller.set_taxi(self)
	if _mono_foot_collision:
		_landing_gear_controller.set_mono_foot_collision(_mono_foot_collision)
	_landing_gear_controller.gear_state_changed.connect(on_landing_gear_state_changed)
	EventHub.emit_taxi_health_changed(_taxi_health)  # Emit initial health value to UI
	GameData.set_taxi(self)  # Store reference to taxi in GameData for global access
	EventHub.passenger_entered_taxi.connect(_on_passenger_entered_taxi)  # Connect signal to handle passengers entering taxi


## Updates physics-driven behavior.
func _physics_process(delta: float) -> void:
	_old_velocity = velocity
	_input_vector = _get_input_vector()
	_check_hectic_input(_input_vector.x, delta)
	_apply_flip()
	_calculate_velocity_from_input(delta)
	
	if not is_on_floor() and _gravity != 0:
		_is_landed = false  # If we're in the air, we're not landed, even if we were previously marked as landed. This allows us to properly detect new landings when we touch down again after being in the air.
		_apply_gravity(delta)	
	
	_apply_thrusters(delta)
	
	
	_move_taxi()
	# 1. Measure g-force (acceleration).
	#var acceleration = (velocity - _old_velocity).length() / delta
	#print("Acceleration (G-Force): ", acceleration)
	_monitor_jerk(velocity, delta)  # Monitor jerk to detect sudden acceleration changes.
	_handle_taxi_collisions(delta)
	_process_stable_landing(delta)

	# Handle gear toggle
	if Input.is_action_just_pressed("toggle_gear"):
		toggle_landing_gear()



## Handles input events.
func _input(event):
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		is_controller = true
	elif event is InputEventKey:
		is_controller = false


## Returns jerk threshold.
func get_jerk_threshold():
	return 5000.0 if is_controller else 8000.0 # Tastatur darf "ruckeliger" sein


## Internal helper that handles monitor jerk.
func _monitor_jerk(current_velocity: Vector2, delta: float):
	# Current acceleration in this frame.
	var current_accel = (current_velocity - _old_velocity) / delta
	
	# Jerk is the change in acceleration.
	var jerk = (current_accel - last_acceleration).length()
	
	# Ignore small jitters and accumulate only the larger spikes.
	if jerk > get_jerk_threshold(): # Adjust threshold as needed.
		total_jerk_stress += jerk * delta
		
	last_acceleration = current_accel



## Internal helper that handles check hectic input.
func _check_hectic_input(input_x: float, delta: float):
	reaction_timer -= delta
	if input_x != 0 and input_x != last_input_x:
		if reaction_timer > 0:
			# Player changed direction within 0.5s.
			total_jerk_stress += 20.0 
		reaction_timer = 0.5 
		last_input_x = input_x


# Flips the taxi sprite based on horizontal movement direction. This provides visual feedback to the player, making it clear which way the taxi is moving. The sprite will flip horizontally when moving left and return to normal when moving right.
#
# @return void
## Applies flip.
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
## Internal helper that handles calculate velocity from input.
func _calculate_velocity_from_input(delta: float) -> void:
	# X-axis: accelerate with input, decelerate without
	if _input_vector.x != 0:
		velocity.x += _input_vector.x * _ACCELERATION * delta
	else:
		velocity.x = move_toward(velocity.x, 0, _DECELERATION)
	
	# Y-axis: accelerate with input, decelerate only for upward movement without input
	if _is_landed:
		# Retract landing gear and give taxi an upward velocity impulse to take off.
		if _input_vector.y < 0:
			if _landing_gear_controller.get_state() == LandingGearController.GearState.DEPLOYED:
				_landing_gear_controller.toggle_gear()  # Retract gear once (guard prevents re-toggling every frame)
			velocity.y = _lift_off_assist_force  # Negative y = upward in Godot 2D; kick taxi off the ground
			_is_landed = false   # Exit landed state so normal flight controls take over next frame
	else:
		if _input_vector.y != 0:
			velocity.y += _input_vector.y * _ACCELERATION * delta
		elif velocity.y < 0:  # Only decelerate upward movement, not downward
			velocity.y = move_toward(velocity.y, 0, _DECELERATION)
	
	# Clamp horizontal speed to maximum
	if velocity.x > _MAX_SPEED:
		velocity.x = _MAX_SPEED
	if velocity.x < -_MAX_SPEED:
		velocity.x = -_MAX_SPEED


## Toggles landing gear.
func toggle_landing_gear() -> void:
	_landing_gear_controller.toggle_gear()


## Handles on landing gear state changed.
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
## Returns input vector.
func _get_input_vector() -> Vector2:
	var result = Vector2.ZERO
	if not is_on_floor():
		result.x = Input.get_action_strength("thrust_right") - Input.get_action_strength("thrust_left")
	result.y = Input.get_action_strength("thrust_down") - Input.get_action_strength("thrust_up")
	return result

@warning_ignore("unused_parameter")
## Internal helper that handles handle taxi collisions.
func _handle_taxi_collisions(delta: float) -> void:
	for i in range(get_slide_collision_count()):
		var collision : KinematicCollision2D = get_slide_collision(i)
		var collider : Node = collision.get_collider()
		var collided_landing_pad: LandingPad = _resolve_landing_pad_from_collider(collider)
		var local_shape = collision.get_local_shape()
		var gear_landing_pad: LandingPad = _landing_gear_controller.get_current_landing_pad()
		var collision_speed : float = _old_velocity.length()
		_collision_was_too_fast = collision_speed > _damage_threshold_speed
		var is_body_hit: bool = _is_body_collision(local_shape)
		var is_gear_hit: bool = _is_gear_collision(local_shape)

		if is_body_hit:
			# print("Collision with taxi body detected")

			if _collision_was_too_fast: # Only apply damage if the collision was with the body and above the damage threshold
				# print("Collision speed above damage threshold, applying damage")
				# Apply damage to taxi health
				_taxi_health -= int(round(_calculate_collision_damage(collision_speed)))
				_taxi_health = max(_taxi_health, 0)
				EventHub.emit_taxi_health_changed(_taxi_health)  # Emit signal to update UI

			if collision_speed > _min_bounce_speed: # Only apply bounce if the collision speed is above the minimum threshold
				# print("Always applying bounce with cabin collision")
				velocity = _old_velocity.bounce(collision.get_normal()) * _bounce_factor
				return  # Skip further collision handling for this collision since we've already applied bounce
		else:
			if _collision_was_too_fast: # Only apply damage if the collision was with the body and above the damage threshold
				# print("Collision speed above damage threshold, applying damage")
				_landing_gear_controller.apply_damage(int(round(_calculate_collision_damage(collision_speed))))

			if collision_speed > _min_bounce_speed: # Only apply bounce if the collision speed is above the minimum threshold
				# print("Landing gear not deployed, applying bounce")
				velocity = _old_velocity.bounce(collision.get_normal()) * _bounce_factor
				return  # Skip further collision handling for this collision since we've already applied bounce

			# Gear-side collision path: keep separate from body mechanics.
			if _landing_gear_controller.get_state() == LandingGearController.GearState.DEPLOYED and (is_gear_hit or not is_body_hit):
				var event_landing_pad: LandingPad = gear_landing_pad
				if event_landing_pad == null:
					event_landing_pad = collided_landing_pad

				if event_landing_pad != null and not _landing_gear_controller.can_land():
					velocity = _old_velocity.bounce(collision.get_normal()) * _bounce_factor

		# # Calculate bounce based on collision normal and pre-move velocity
		# var bounce_direction = collision.get_normal()
		# if collider is LandingPad and local_shape == _mono_foot_collision:
		# 	var landing_speed = pre_move_velocity.length()
		# 	print("Collided with landing pad foot collision shape", "Landing speed:", landing_speed)
		# 	# Only apply bounce if the collision speed is above the minimum threshold
		# 	if pre_move_velocity.length() > _landing_gear_controller.get_max_landing_speed():
		# 		print("Too fast for landing, applying bounce")
		# 		velocity = _old_velocity.bounce(bounce_direction) * _bounce_factor
		# 	else:
		# 		print("Safe landing, no bounce applied")
		# else:
		# 	velocity = _old_velocity.bounce(bounce_direction) * _bounce_factor


## Internal helper that handles process stable landing.
func _process_stable_landing(delta: float) -> void:
	if _is_landed:
		return
	if _landing_gear_controller.get_state() != LandingGearController.GearState.DEPLOYED:
		return

	var gear_landing_pad: LandingPad = _landing_gear_controller.get_current_landing_pad()
	if gear_landing_pad == null:
		return

	if _landing_gear_controller.can_land() and _landing_gear_controller.landing_complete(delta):
		_is_landed = true
		EventHub.emit_taxi_landed(gear_landing_pad, global_position.x)


## Resolves landing pad from collider.
func _resolve_landing_pad_from_collider(collider: Node) -> LandingPad:
	if collider == null:
		return null
	if collider is LandingPad:
		return collider as LandingPad
	if collider is WaitingZone:
		return (collider as WaitingZone).get_landing_pad()

	var current: Node = collider.get_parent()
	while current != null:
		if current is LandingPad:
			return current as LandingPad
		current = current.get_parent()

	return null


# Takes in the local_shape of current collision and return true if the collision is with the taxi body, which should cause damage, and false if it's a collision with the landing gear, which should not cause damage.
## Checks whether body collision.
func _is_body_collision(local_shape) -> bool:
	return local_shape == _body_collision


## Checks whether gear collision.
func _is_gear_collision(local_shape) -> bool:
	return local_shape == _mono_foot_collision


# Calculate damage value based on collision speed and returns the damage value.
# @param collision_speed The speed at which the collision occurred, used to determine how much damage to apply to the taxi.
# @return float The calculated damage value based on collision speed.
## Internal helper that handles calculate collision damage.
func _calculate_collision_damage(collision_speed: float) -> float:
	if collision_speed <= _damage_threshold_speed:
		return 0.0
	# Damage scales with speed above the threshold, using a simple linear formula for demonstration
	return (collision_speed - _damage_threshold_speed) * 0.1



# Applies gravity to the taxi's velocity. This is only relevant when the taxi is not on the ground, such as during planetary landings.
#
# @param delta The time elapsed since the last physics frame, used to ensure consistent gravity application regardless of frame rate.#
# @return void
## Applies gravity.
func _apply_gravity(delta: float) -> void:
	# Apply gravity
	velocity.y += _gravity * delta


# Applies player-controlled thruster input to the taxi's velocity. Horizontal thrusters only affect movement when the taxi is in the air, while vertical thrusters work regardless of whether the taxi is grounded.
#
# @param delta The time elapsed since the last physics frame, used to ensure consistent thruster application regardless of frame rate.
# @return void
## Applies thrusters.
func _apply_thrusters(_delta: float) -> void:
	pass


# Moves the taxi based on its current velocity and the physics engine. This should be called after applying gravity and thruster forces to ensure that the taxi's movement reflects all influences.
#
# @return void
## Internal helper that handles move taxi.
func _move_taxi() -> void:
	move_and_slide()

## Handles the passenger entered taxi callback.
func _on_passenger_entered_taxi(passenger: Passenger) -> void:
	print("Passenger entered taxi:", passenger)
	if not is_full():
		_passengers_aboard.append(passenger)
		print("Passenger added. Current count:", get_passenger_count())
	else:
		printerr("Taxi is full. Cannot add more passengers. Should not happen if landing pads check for taxi capacity before sending passengers.")
