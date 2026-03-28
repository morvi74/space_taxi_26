extends RefCounted
## Drives NPCCar flight phases: cruise, hover approach, gear deploy, descent, landed, and takeoff.
class_name NPCCarFlightController

## Responsibilities:
## - execute the NPCCar flight-phase state machine
## - manage landing/takeoff transitions with gear constraints
## - align touchdown height to destination surface geometry
## Doc convention:
## - First line states intent in one sentence.
## - Optional Params line for non-trivial inputs.
## - Optional Returns line for non-obvious outputs.
## - Keep wording behavior-focused, not implementation-focused.

## Owning NPCCar instance used for state transitions and physics updates.
var car: NPCCar = null


## Binds this controller to its NPCCar owner.
func setup(owner: NPCCar) -> void:
	car = owner


## Runs the flight phase state machine and returns true when movement is fully handled here.
## Params: delta is the current physics tick duration.
## Returns: true when this controller consumed movement for the frame.
func update_special_flight_phases(delta: float) -> bool:
	if car == null:
		return false
	match car.get_flight_phase():
		car.FlightPhase.CRUISE:
			return false
		car.FlightPhase.APPROACH_HOVER:
			var hover_dir: Vector2 = car.global_position.direction_to(car.get_hover_target_position())
			var hover_safety: Dictionary = car._evaluate_surroundings(hover_dir)
			var hover_speed_factor: float = minf(float(hover_safety.get("speed_factor", 1.0)), car.lot_hover_speed_factor)
			var hover_velocity: Vector2 = hover_dir * car.get_max_speed() * hover_speed_factor
			hover_velocity = apply_gear_vertical_constraint(hover_velocity, false)
			car.linear_velocity = car.linear_velocity.lerp(hover_velocity, delta * car.get_steering_lerp())
			if car.global_position.distance_to(car.get_hover_target_position()) <= car.get_arrival_tolerance() * 1.2:
				start_gear_transition(true)
				car.set_flight_phase(car.FlightPhase.GEAR_DEPLOYING)
			return true
		car.FlightPhase.GEAR_DEPLOYING:
			var hold_velocity: Vector2 = apply_gear_vertical_constraint(Vector2.ZERO, false)
			car.linear_velocity = car.linear_velocity.lerp(hold_velocity, delta * car.get_steering_lerp())
			if not car.is_gear_transition_active() and is_gear_deployed():
				car.set_flight_phase(car.FlightPhase.DESCENDING)
			return true
		car.FlightPhase.DESCENDING:
			var land_dir: Vector2 = car.global_position.direction_to(car.get_landing_target_position())
			var land_safety: Dictionary = car._evaluate_surroundings(land_dir)
			var land_speed_factor: float = minf(float(land_safety.get("speed_factor", 1.0)), car.lot_touchdown_speed / maxf(1.0, car.get_max_speed()))
			var land_velocity: Vector2 = land_dir * car.get_max_speed() * land_speed_factor
			land_velocity = apply_gear_vertical_constraint(land_velocity, false)
			car.linear_velocity = car.linear_velocity.lerp(land_velocity, delta * car.get_steering_lerp())
			if car.global_position.distance_to(car.get_landing_target_position()) <= car.get_arrival_tolerance() and car.linear_velocity.length() <= car.lot_touchdown_speed:
				snap_touchdown_to_ground()
				car.linear_velocity = Vector2.ZERO
				complete_destination_after_landing()
				car.set_flight_phase(car.FlightPhase.LANDED)
				car.set_landed_time_left(get_lot_wait_time_seconds())
			return true
		car.FlightPhase.LANDED:
			car.linear_velocity = car.linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
			if car.get_landed_time_left() > 0.0:
				car.add_landed_time_left(-delta)
				return true
			if not car.has_active_path():
				car.request_next_destination()
				return true
			begin_takeoff_from_lot()
			return true
		car.FlightPhase.TAKEOFF:
			if car.is_takeoff_impulse_pending():
				car.set_takeoff_impulse_pending(false)
				car.linear_velocity.y = -car.takeoff_impulse_speed
			var takeoff_target_velocity: Vector2 = Vector2(0.0, -car.takeoff_impulse_speed * 0.55)
			car.linear_velocity = car.linear_velocity.lerp(takeoff_target_velocity, delta * 2.0)
			var escape_direction: Vector2 = car.get_escape_direction()
			if escape_direction.x != 0.0:
				var facing: float = 1.0 if escape_direction.x < 0.0 else -1.0
				car.sprite.scale.x = facing
				car.body_collision.scale.x = facing
			if not car.is_gear_transition_active() and is_gear_retracted():
				var climb_distance: float = car.get_takeoff_origin_y() - car.global_position.y
				if climb_distance >= car.takeoff_clearance_height:
					car.set_flight_phase(car.FlightPhase.CRUISE)
			return true
		_:
			return false


## Returns true if the current destination node supports parking-lot landing behavior.
func can_land_at_current_destination() -> bool:
	if car == null or car.get_destination_node() == null:
		return false
	return car.get_destination_node().get_parking_lot() != null


## Starts lot landing: clears avoidance/escape and transitions to hover approach.
## Requires: owner is in CRUISE phase and has a landing-capable destination.
func begin_landing_sequence() -> void:
	if car == null:
		return
	if car.get_flight_phase() != car.FlightPhase.CRUISE:
		return
	car.end_avoidance_for_landing()
	car.clear_escape_for_landing()
	car.set_landing_target_position(car.get_destination_node().global_position)
	var min_hover_height: float = car.gear_blocked_min_descent_speed * car.gear_transition_duration + 10.0
	var hover_height: float = maxf(car.lot_hover_height, min_hover_height)
	car.set_hover_target_position(car.get_landing_target_position() + Vector2(0.0, -hover_height))
	car.set_flight_phase(car.FlightPhase.APPROACH_HOVER)


## Starts takeoff sequence and begins gear retraction transition.
func begin_takeoff_from_lot() -> void:
	if car == null:
		return
	if car.get_flight_phase() == car.FlightPhase.TAKEOFF:
		return
	car.set_takeoff_origin_y(car.global_position.y)
	car.set_takeoff_impulse_pending(true)
	start_gear_transition(false)
	car.set_flight_phase(car.FlightPhase.TAKEOFF)


## Finalizes landing completion, emits destination signal, then requests the next route.
func complete_destination_after_landing() -> void:
	if car == null:
		return
	car.reset_path_state_after_landing()
	car.destination_reached.emit(car)
	if car.try_despawn_after_destination_reached():
		return
	car.request_next_destination()


## Returns randomized lot wait duration within configured min/max bounds.
## Returns: wait seconds in [lot_wait_time_min, lot_wait_time_max].
func get_lot_wait_time_seconds() -> float:
	if car == null:
		return 0.0
	var min_wait: float = maxf(0.0, car.lot_wait_time_min)
	var max_wait: float = maxf(0.0, car.lot_wait_time_max)
	if max_wait < min_wait:
		var temp: float = min_wait
		min_wait = max_wait
		max_wait = temp
	if is_equal_approx(min_wait, max_wait):
		return min_wait
	return car.get_random_wait_range(min_wait, max_wait)


## Initializes gear interpolation toward deployed or retracted target.
func start_gear_transition(deploy_to_bottom: bool) -> void:
	if car == null:
		return
	var target_y: float = car.get_bottom_gear_y_position() if deploy_to_bottom else car.get_top_gear_y_position()
	car.begin_gear_transition_state(car.landing_gear_root.position.y, target_y)


## Advances gear interpolation and closes transition when target is reached.
func update_gear_transition(delta: float) -> void:
	if car == null:
		return
	if not car.is_gear_transition_active():
		return
	var elapsed: float = car.add_gear_transition_elapsed(delta)
	var duration: float = maxf(0.01, car.gear_transition_duration)
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	set_gear_y(lerpf(car.get_gear_transition_from_y(), car.get_gear_transition_to_y(), t))
	if t >= 1.0:
		car.finish_gear_transition_state()


## Applies synchronized gear Y position to visual root and collision shape.
func set_gear_y(y: float) -> void:
	if car == null:
		return
	if car.landing_gear_root != null:
		car.landing_gear_root.position.y = y
	if car.gear_collision != null:
		car.gear_collision.position.y = y
		car.gear_collision.disabled = y <= (car.get_top_gear_y_position() + 0.5)


## Snaps touchdown to detected surface so gear bottom aligns with ground contact.
func snap_touchdown_to_ground() -> void:
	if car == null:
		return
	car.global_position.x = car.get_landing_target_position().x
	var surface_top_y: float = get_destination_surface_top_y()
	if surface_top_y < INF:
		var gear_bottom_local_y: float = get_gear_bottom_local_y()
		car.global_position.y = surface_top_y - gear_bottom_local_y
		return
	if car.center_ray == null:
		car.global_position.y = car.get_landing_target_position().y
		return
	car.center_ray.force_raycast_update()
	if not car.center_ray.is_colliding():
		car.global_position.y = car.get_landing_target_position().y
		return
	var hit_position: Vector2 = car.center_ray.get_collision_point()
	var gear_bottom_local_y: float = get_gear_bottom_local_y()
	car.global_position.y = hit_position.y - gear_bottom_local_y


## Resolves top surface Y from destination parking lot or landing pad shape.
func get_destination_surface_top_y() -> float:
	if car == null or car.get_destination_node() == null:
		return INF
	var lot: ParkikngLot = car.get_destination_node().get_parking_lot()
	if lot != null:
		return get_surface_top_y(lot)
	var pad: LandingPad = car.get_destination_node().get_landing_pad()
	if pad != null:
		return get_surface_top_y(pad)
	return INF


## Computes world-space top Y from supported collision shape types.
## Params: surface is expected to contain a CollisionShape2D child.
## Returns: top world Y of the shape, or INF when unsupported/unavailable.
func get_surface_top_y(surface: Node2D) -> float:
	if surface == null:
		return INF
	var shape_node: CollisionShape2D = null
	for child: Node in surface.get_children():
		shape_node = child as CollisionShape2D
		if shape_node != null:
			break
	if shape_node == null or shape_node.shape == null:
		return INF

	var top_local: float = shape_node.position.y
	var shape: Shape2D = shape_node.shape
	if shape is RectangleShape2D:
		var rect: RectangleShape2D = shape as RectangleShape2D
		top_local -= rect.size.y * 0.5 * absf(shape_node.scale.y)
	elif shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = shape as CapsuleShape2D
		top_local -= (capsule.height * 0.5 + capsule.radius) * absf(shape_node.scale.y)
	elif shape is CircleShape2D:
		var circle: CircleShape2D = shape as CircleShape2D
		top_local -= circle.radius * absf(shape_node.scale.y)
	else:
		return INF

	var top_world: Vector2 = surface.to_global(Vector2(shape_node.position.x, top_local))
	return top_world.y


## Computes local gear-bottom Y from active gear collision geometry.
func get_gear_bottom_local_y() -> float:
	if car == null:
		return 0.0
	if car.gear_collision == null:
		return car.landing_gear_root.position.y + car.center_ray.position.y
	var bottom_local_y: float = car.gear_collision.position.y
	var shape: Shape2D = car.gear_collision.shape
	if shape is RectangleShape2D:
		var rect: RectangleShape2D = shape as RectangleShape2D
		bottom_local_y += rect.size.y * 0.5 * absf(car.gear_collision.scale.y)
		return bottom_local_y
	if shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = shape as CapsuleShape2D
		bottom_local_y += (capsule.height * 0.5 + capsule.radius) * absf(car.gear_collision.scale.y)
		return bottom_local_y
	if shape is CircleShape2D:
		var circle: CircleShape2D = shape as CircleShape2D
		bottom_local_y += circle.radius * absf(car.gear_collision.scale.y)
		return bottom_local_y
	return car.landing_gear_root.position.y + car.center_ray.position.y


## Returns true when gear is at deployed position threshold.
func is_gear_deployed() -> bool:
	if car == null:
		return false
	return car.landing_gear_root.position.y >= (car.get_bottom_gear_y_position() - 0.1)


## Returns true when gear is at retracted position threshold.
func is_gear_retracted() -> bool:
	if car == null:
		return false
	return car.landing_gear_root.position.y <= (car.get_top_gear_y_position() + 0.1)


## Returns true while partially/fully deployed gear should block upward lift.
func gear_blocks_vertical_lift() -> bool:
	return not is_gear_retracted()


## Enforces minimum downward velocity while gear is not retracted (unless takeoff override).
## Params: target_velocity is candidate velocity; allow_takeoff_override bypasses constraint.
## Returns: possibly adjusted velocity that respects active gear state.
func apply_gear_vertical_constraint(target_velocity: Vector2, allow_takeoff_override: bool) -> Vector2:
	if car == null:
		return target_velocity
	if allow_takeoff_override:
		return target_velocity
	if gear_blocks_vertical_lift() and target_velocity.y < car.gear_blocked_min_descent_speed:
		target_velocity.y = car.gear_blocked_min_descent_speed
	return target_velocity
