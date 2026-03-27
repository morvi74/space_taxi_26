extends RigidBody2D
class_name NPCCar

signal destination_reached(car: NPCCar)

@onready var sprite: Sprite2D = $Sprite2D
@onready var landing_gear_root: Node2D = $LandingGearRoot
@onready var body_collision: CollisionPolygon2D = $CollisionPolygon2D
@onready var gear_collision: CollisionShape2D = $GearCollision
@onready var center_ray: RayCast2D = $LandingGearRoot/CenterRay

@export_group("Flight")
## Maximum horizontal/vertical cruise speed.
@export var _max_speed: float = 200.0
## Distance at which a path waypoint counts as reached.
@export var _arrival_tolerance: float = 20.0
## Velocity interpolation strength. Higher values react faster.
@export var _steering_lerp: float = 5.0

@export_group("Sensors")
## Physics layers checked by obstacle and safety rays.
@export var surrounding_collision_mask: int = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4) | (1 << 6)
## Base distance for early slowdown before obstacles.
@export var caution_distance: float = 140.0
## Base distance for full stop before obstacle collision.
@export var stop_distance: float = 52.0
## Side offset between sensor lanes.
@export var sensor_vertical_offset: float = 16.0
## Number of forward sensor lanes. Even values are auto-corrected to odd.
@export var sensor_lane_count: int = 5
## Scales caution distance with current forward speed.
@export var caution_reaction_time: float = 0.45

@export_group("Avoidance")
## Start local avoidance when another car is inside this range.
@export var avoid_trigger_distance: float = 90.0
## Keep avoidance active until blocker is farther than this distance.
@export var avoid_resume_distance: float = 130.0
## Sideways offset used while avoiding.
@export var avoid_offset_distance: float = 34.0
## Forward offset used while avoiding.
@export var avoid_forward_distance: float = 44.0
## Max movement speed factor during active avoidance.
@export var avoid_speed_factor: float = 0.72
## Hard timeout for one avoidance action.
@export var avoid_max_time: float = 1.4
## Front-cone angle used to select likely blocking cars.
@export var avoid_front_cone_degrees: float = 50.0
## If current lateral offset is above this, prefer immediate shortest detour.
@export var avoid_lateral_now_threshold: float = 6.0
## Minimum closing speed for accepting off-cone blockers.
@export var avoid_off_cone_min_closing_speed: float = 4.0

@export_group("Landing Gear")
## Gear root Y when fully retracted.
@export var _top_gear_y_position: float = 7.0
## Gear root Y when fully deployed.
@export var _bottom_gear_y_position: float = 21.0
## Duration for full deploy/retract transition.
@export var gear_transition_duration: float = 0.5
## Minimum forced descent speed while gear is not fully retracted.
@export var gear_blocked_min_descent_speed: float = 22.0

@export_group("Lot Landing")
## Start special lot landing sequence when this close to final node.
@export var lot_landing_start_distance: float = 64.0
## Hover height above lot before gear deployment.
@export var lot_hover_height: float = 30.0
## Max speed factor while approaching hover point.
@export var lot_hover_speed_factor: float = 0.35
## Target max speed during final descent to lot.
@export var lot_touchdown_speed: float = 60.0
## Extra settle delay after touchdown before wait timer starts.
@export var lot_landed_hold_time: float = 0.15
## Minimum random wait time on lot after landing.
@export var lot_wait_time_min: float = 15.0
## Maximum random wait time on lot after landing.
@export var lot_wait_time_max: float = 30.0

@export_group("Takeoff")
## Upward kick speed at lot departure start.
@export var takeoff_impulse_speed: float = 120.0
## Required climb distance before returning to normal cruise logic.
@export var takeoff_clearance_height: float = 24.0

@export_group("Deadlock Recovery")
## Time without path-index progress before escape mode starts.
@export var deadlock_timeout: float = 10.0
## Duration of forced escape movement.
@export var deadlock_escape_duration: float = 1.0
## Raycast distance for choosing an escape direction.
@export var deadlock_scan_distance: float = 200.0

@export_group("Debug")
## Draw sensor rays for debugging in-game.
@export var debug_draw_sensors: bool = false
## Line width for debug-drawn sensor rays.
@export var debug_sensor_line_width: float = 2.0

var _traffic_manager: Node = null
var _car_id: int = 0
var _destination_node: TrafficNode = null
var _current_path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _should_notify_departure_release: bool = false
var _is_avoiding: bool = false
var _avoid_side_sign: float = 1.0
var _avoid_time_left: float = 0.0
var _blocking_car: NPCCar = null
var _no_progress_time: float = 0.0
var _last_progress_path_index: int = -1
var _is_escaping: bool = false
var _escape_direction: Vector2 = Vector2.ZERO
var _escape_time_left: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

enum FlightPhase {
	CRUISE,
	APPROACH_HOVER,
	GEAR_DEPLOYING,
	DESCENDING,
	LANDED,
	TAKEOFF,
}

var _flight_phase: FlightPhase = FlightPhase.CRUISE
var _landing_target_position: Vector2 = Vector2.ZERO
var _hover_target_position: Vector2 = Vector2.ZERO
var _landed_time_left: float = 0.0
var _takeoff_origin_y: float = 0.0
var _takeoff_impulse_pending: bool = false

var _gear_transition_active: bool = false
var _gear_transition_elapsed: float = 0.0
var _gear_transition_from_y: float = 0.0
var _gear_transition_to_y: float = 0.0


func _ready() -> void:
	lock_rotation = true
	linear_damp = 2.0
	add_to_group("npc_cars")
	_set_gear_y(_top_gear_y_position)
	_rng.randomize()


func set_traffic_manager(manager: Node) -> void:
	_traffic_manager = manager


func set_car_id(value: int) -> void:
	_car_id = value


func get_car_id() -> int:
	return _car_id


func get_destination_node() -> TrafficNode:
	return _destination_node


func has_active_path() -> bool:
	return not _current_path.is_empty() and _path_index < _current_path.size()


func set_new_destination_node(destination_node: TrafficNode) -> void:
	var previous_destination: TrafficNode = _destination_node
	_destination_node = destination_node
	_current_path = PackedVector2Array()
	_path_index = 0
	_should_notify_departure_release = previous_destination != null and previous_destination != _destination_node
	_no_progress_time = 0.0
	_last_progress_path_index = -1
	_is_escaping = false

	if _destination_node == null:
		_should_notify_departure_release = false
		return
	if _traffic_manager == null or not _traffic_manager.has_method("request_path_between"):
		return

	_current_path = _traffic_manager.request_path_between(global_position, _destination_node.global_position)
	_trim_leading_path_points()

	if _flight_phase == FlightPhase.LANDED and has_active_path():
		_begin_takeoff_from_lot()


func _physics_process(delta: float) -> void:
	_update_gear_transition(delta)
	if _update_special_flight_phases(delta):
		return

	if not has_active_path():
		linear_velocity = linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
		_no_progress_time = 0.0
		_last_progress_path_index = -1
		return

	if _is_escaping:
		_escape_time_left -= delta
		if _escape_time_left <= 0.0:
			_end_escape()
		else:
			_apply_escape_movement(delta)
		return

	if _path_index != _last_progress_path_index:
		_no_progress_time = 0.0
		_last_progress_path_index = _path_index
	else:
		_no_progress_time += delta
		if _no_progress_time >= deadlock_timeout:
			_begin_escape()
			return

	var target: Vector2 = _current_path[_path_index]
	if global_position.distance_to(target) <= _arrival_tolerance:
		_path_index += 1
		_no_progress_time = 0.0
		_last_progress_path_index = _path_index
		if _should_notify_departure_release and _path_index >= 1:
			_notify_passed_first_departure_node()
		if _path_index >= _current_path.size():
			_current_path = PackedVector2Array()
			_path_index = 0
			linear_velocity = Vector2.ZERO
			destination_reached.emit(self)
			if _try_despawn_after_destination_reached():
				return
			_request_next_destination()
			return
		target = _current_path[_path_index]

	if _path_index == _current_path.size() - 1 and _can_land_at_current_destination():
		if global_position.distance_to(target) <= lot_landing_start_distance:
			_begin_landing_sequence()
			return

	var direction: Vector2 = global_position.direction_to(target)
	_update_avoidance(direction)
	if _is_avoiding:
		direction = _get_avoidance_direction(direction)

	var safety_eval: Dictionary = _evaluate_surroundings(direction)
	var speed_factor: float = float(safety_eval.get("speed_factor", 1.0))
	var blocked: bool = bool(safety_eval.get("blocked", false))
	if _is_avoiding:
		speed_factor = minf(speed_factor, avoid_speed_factor)
	var target_velocity: Vector2 = direction * _max_speed * speed_factor
	if blocked and speed_factor <= 0.01:
		target_velocity = Vector2.ZERO
	target_velocity = _apply_gear_vertical_constraint(target_velocity, false)
	linear_velocity = linear_velocity.lerp(target_velocity, delta * _steering_lerp)

	if direction.x != 0.0:
		var facing: float = 1.0 if direction.x < 0.0 else -1.0
		sprite.scale.x = facing
		body_collision.scale.x = facing


func _request_next_destination() -> void:
	if _traffic_manager == null or not _traffic_manager.has_method("request_next_destination"):
		return

	var next_dest: TrafficNode = _traffic_manager.request_next_destination(self)
	if next_dest != null:
		set_new_destination_node(next_dest)


func _try_despawn_after_destination_reached() -> bool:
	if _traffic_manager == null:
		return false
	if not _traffic_manager.has_method("should_despawn_car_at_destination"):
		return false
	if not _traffic_manager.has_method("despawn_car"):
		return false
	if not bool(_traffic_manager.should_despawn_car_at_destination(self)):
		return false
	_traffic_manager.despawn_car(self)
	return true


func _trim_leading_path_points() -> void:
	if _current_path.is_empty():
		return

	while _current_path.size() > 1 and global_position.distance_to(_current_path[0]) <= _arrival_tolerance:
		_current_path.remove_at(0)


func _notify_passed_first_departure_node() -> void:
	_should_notify_departure_release = false
	if _traffic_manager == null or not _traffic_manager.has_method("notify_car_passed_first_departure_node"):
		return
	_traffic_manager.notify_car_passed_first_departure_node(self)


func _evaluate_surroundings(forward_hint: Vector2) -> Dictionary:
	var forward: Vector2 = forward_hint
	if forward == Vector2.ZERO:
		forward = linear_velocity.normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT
	forward = forward.normalized()

	var side: Vector2 = Vector2(-forward.y, forward.x)
	var forward_speed: float = maxf(0.0, linear_velocity.dot(forward))
	var dynamic_caution_distance: float = caution_distance + forward_speed * caution_reaction_time
	var dynamic_stop_distance: float = stop_distance + forward_speed * 0.22

	var speed_factor: float = 1.0
	var blocked: bool = false
	var lane_count: int = maxi(3, sensor_lane_count)
	if lane_count % 2 == 0:
		lane_count += 1
	var half_lanes: int = lane_count / 2
	var lane_spacing: float = maxf(6.0, sensor_vertical_offset)
	var ray_offsets: Array[float] = []
	for i: int in range(-half_lanes, half_lanes + 1):
		ray_offsets.append(float(i) * lane_spacing)
	for offset: float in ray_offsets:
		var origin: Vector2 = global_position + side * offset
		var ray_end: Vector2 = origin + forward * dynamic_caution_distance
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, ray_end)
		query.collision_mask = surrounding_collision_mask
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [self]

		var world_2d: World2D = get_viewport().world_2d
		if world_2d == null:
			continue
		var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue

		var collider: Object = hit.get("collider") as Object
		if collider == null:
			continue
		if not _should_treat_as_obstacle(collider):
			continue

		var hit_position: Vector2 = hit.get("position", ray_end)
		var hit_distance: float = origin.distance_to(hit_position)
		if hit_distance <= dynamic_stop_distance:
			speed_factor = 0.0
			blocked = true
		else:
			var lane_factor: float = clampf((hit_distance - dynamic_stop_distance) / maxf(1.0, dynamic_caution_distance - dynamic_stop_distance), 0.0, 1.0)
			speed_factor = minf(speed_factor, lane_factor)

	return {
		"speed_factor": speed_factor,
		"blocked": blocked,
	}


func _should_treat_as_obstacle(collider: Object) -> bool:
	if collider == self:
		return false
	if _is_avoiding and _blocking_car != null and collider == _blocking_car:
		return false

	if collider is NPCCar:
		return true

	var player_taxi: Node2D = GameData.get_taxi() as Node2D
	if player_taxi != null and collider == player_taxi:
		return true

	# Landing pads are always obstacles in the new rules.
	if collider is LandingPad:
		return true

	if collider is ParkikngLot:
		return not _is_destination_parking_lot(collider as ParkikngLot)

	if collider is StaticBody2D:
		return true

	# Treat all other physical hits as obstacles for conservative safety.
	return true


func _is_destination_parking_lot(lot: ParkikngLot) -> bool:
	if lot == null or _destination_node == null:
		return false
	return _destination_node.get_parking_lot() == lot


func _update_avoidance(path_forward: Vector2) -> void:
	if path_forward == Vector2.ZERO:
		_end_avoidance()
		return

	if _is_avoiding:
		_avoid_time_left -= get_physics_process_delta_time()
		if _avoid_time_left <= 0.0:
			_end_avoidance()
			return

		var still_blocking: bool = _blocking_car != null and is_instance_valid(_blocking_car)
		if still_blocking:
			still_blocking = global_position.distance_to(_blocking_car.global_position) <= avoid_resume_distance
		if not still_blocking:
			_end_avoidance()
		return

	var blocking: NPCCar = _find_blocking_car(path_forward)
	if blocking == null:
		return

	var to_other: Vector2 = blocking.global_position - global_position
	if to_other.length() > avoid_trigger_distance:
		return

	_begin_avoidance(blocking, path_forward)


func _begin_avoidance(other: NPCCar, path_forward: Vector2) -> void:
	_is_avoiding = true
	_blocking_car = other
	_avoid_time_left = avoid_max_time
	_avoid_side_sign = _compute_avoid_side_sign(other, path_forward)


# Steps away from the other car's lateral position — minimum detour.
# Fallback: deterministic world-perp tiebreaker for near head-on situations.
func _compute_avoid_side_sign(other: NPCCar, path_forward: Vector2) -> float:
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	var my_forward: Vector2 = _get_path_forward_estimate()
	var other_forward: Vector2 = other._get_path_forward_estimate()
	var my_speed: float = maxf(linear_velocity.length(), _max_speed * 0.45)
	var other_speed: float = maxf(other.linear_velocity.length(), other._max_speed * 0.45)
	var relative_position: Vector2 = other.global_position - global_position
	var relative_velocity: Vector2 = other_forward * other_speed - my_forward * my_speed
	var lookahead_time: float = 0.0
	var rel_vel_len_sq: float = relative_velocity.length_squared()
	if rel_vel_len_sq > 0.001:
		lookahead_time = clampf(-relative_position.dot(relative_velocity) / rel_vel_len_sq, 0.0, 1.2)
	var future_relative: Vector2 = relative_position + relative_velocity * lookahead_time
	var projection_now: float = lateral.dot(relative_position)
	var projection_future: float = lateral.dot(future_relative)
	# Prioritize the shortest immediate detour. Only use predicted lateral side when
	# current side is nearly ambiguous.
	if absf(projection_now) > avoid_lateral_now_threshold:
		return -1.0 if projection_now > 0.0 else 1.0
	var projection: float = projection_future
	# Step to the side the other car is NOT on.
	if absf(projection) > 10.0:
		return -1.0 if projection > 0.0 else 1.0
	# Nearly dead-ahead: both cars must agree on opposite world directions.
	return _head_on_side_sign(other, path_forward)


func _get_path_forward_estimate() -> Vector2:
	if has_active_path():
		var dir: Vector2 = global_position.direction_to(_current_path[_path_index])
		if dir != Vector2.ZERO:
			return dir.normalized()
	if linear_velocity.length() > 10.0:
		return linear_velocity.normalized()
	return Vector2.RIGHT


func _head_on_side_sign(other: NPCCar, path_forward: Vector2) -> float:
	var self_is_high: bool = _has_higher_avoid_priority_than(other)
	var low_pos: Vector2 = other.global_position if self_is_high else global_position
	var high_pos: Vector2 = global_position if self_is_high else other.global_position
	var axis: Vector2 = high_pos - low_pos
	if axis == Vector2.ZERO:
		axis = Vector2.RIGHT
	var world_ref: Vector2 = Vector2(-axis.y, axis.x).normalized()
	var target_world_dir: Vector2 = world_ref if self_is_high else -world_ref
	var lat: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	if lat == Vector2.ZERO:
		return 1.0
	var alignment: float = lat.dot(target_world_dir)
	if absf(alignment) < 0.0001:
		return 1.0
	return 1.0 if alignment > 0.0 else -1.0


func _end_avoidance() -> void:
	_is_avoiding = false
	_blocking_car = null
	_avoid_time_left = 0.0


func _find_blocking_car(path_forward: Vector2) -> NPCCar:
	var closest: NPCCar = null
	var best_score: float = INF
	var cone_cos: float = cos(deg_to_rad(avoid_front_cone_degrees))
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	var corridor_half_width: float = maxf(sensor_vertical_offset * 1.8, 22.0)

	for node: Node in get_tree().get_nodes_in_group("npc_cars"):
		var other: NPCCar = node as NPCCar
		if other == null or other == self:
			continue

		var to_other: Vector2 = other.global_position - global_position
		var distance: float = to_other.length()
		if distance <= 0.001 or distance > avoid_trigger_distance:
			continue

		var forward_distance: float = path_forward.dot(to_other)
		if forward_distance <= 0.0:
			continue
		var lateral_distance: float = absf(lateral.dot(to_other))
		var to_other_dir: Vector2 = to_other / distance
		var relative_velocity: Vector2 = other.linear_velocity - linear_velocity
		var closing_speed: float = -to_other_dir.dot(relative_velocity)

		var dir_to_other: Vector2 = to_other / distance
		if path_forward.dot(dir_to_other) < cone_cos:
			if lateral_distance > corridor_half_width or closing_speed < avoid_off_cone_min_closing_speed:
				continue

		var score: float = forward_distance + lateral_distance * 0.8
		if score < best_score:
			best_score = score
			closest = other

	return closest


func _has_higher_avoid_priority_than(other: NPCCar) -> bool:
	if other == null:
		return true
	if get_car_id() != other.get_car_id():
		return get_car_id() > other.get_car_id()
	return get_instance_id() > other.get_instance_id()


func _get_avoidance_direction(path_forward: Vector2) -> Vector2:
	if path_forward == Vector2.ZERO:
		return path_forward
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x)
	var avoid_target: Vector2 = global_position + path_forward.normalized() * avoid_forward_distance + lateral.normalized() * _avoid_side_sign * avoid_offset_distance
	return global_position.direction_to(avoid_target)


func _update_special_flight_phases(delta: float) -> bool:
	match _flight_phase:
		FlightPhase.CRUISE:
			return false
		FlightPhase.APPROACH_HOVER:
			var hover_dir: Vector2 = global_position.direction_to(_hover_target_position)
			var hover_safety: Dictionary = _evaluate_surroundings(hover_dir)
			var hover_speed_factor: float = minf(float(hover_safety.get("speed_factor", 1.0)), lot_hover_speed_factor)
			var hover_velocity: Vector2 = hover_dir * _max_speed * hover_speed_factor
			hover_velocity = _apply_gear_vertical_constraint(hover_velocity, false)
			linear_velocity = linear_velocity.lerp(hover_velocity, delta * _steering_lerp)
			if global_position.distance_to(_hover_target_position) <= _arrival_tolerance * 1.2:
				_start_gear_transition(true)
				_flight_phase = FlightPhase.GEAR_DEPLOYING
			return true
		FlightPhase.GEAR_DEPLOYING:
			var hold_velocity: Vector2 = _apply_gear_vertical_constraint(Vector2.ZERO, false)
			linear_velocity = linear_velocity.lerp(hold_velocity, delta * _steering_lerp)
			if not _gear_transition_active and _is_gear_deployed():
				_flight_phase = FlightPhase.DESCENDING
			return true
		FlightPhase.DESCENDING:
			var land_dir: Vector2 = global_position.direction_to(_landing_target_position)
			var land_safety: Dictionary = _evaluate_surroundings(land_dir)
			var land_speed_factor: float = minf(float(land_safety.get("speed_factor", 1.0)), lot_touchdown_speed / maxf(1.0, _max_speed))
			var land_velocity: Vector2 = land_dir * _max_speed * land_speed_factor
			land_velocity = _apply_gear_vertical_constraint(land_velocity, false)
			linear_velocity = linear_velocity.lerp(land_velocity, delta * _steering_lerp)
			if global_position.distance_to(_landing_target_position) <= _arrival_tolerance and linear_velocity.length() <= lot_touchdown_speed:
				_snap_touchdown_to_ground()
				linear_velocity = Vector2.ZERO
				_complete_destination_after_landing()
				_flight_phase = FlightPhase.LANDED
				_landed_time_left = _get_lot_wait_time_seconds()
			return true
		FlightPhase.LANDED:
			linear_velocity = linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
			if _landed_time_left > 0.0:
				_landed_time_left -= delta
				return true
			if not has_active_path():
				_request_next_destination()
				return true
			_begin_takeoff_from_lot()
			return true
		FlightPhase.TAKEOFF:
			if _takeoff_impulse_pending:
				_takeoff_impulse_pending = false
				linear_velocity.y = -takeoff_impulse_speed
			var takeoff_target_velocity: Vector2 = Vector2(0.0, -takeoff_impulse_speed * 0.55)
			linear_velocity = linear_velocity.lerp(takeoff_target_velocity, delta * 2.0)
			if _escape_direction.x != 0.0:
				var facing: float = 1.0 if _escape_direction.x < 0.0 else -1.0
				sprite.scale.x = facing
				body_collision.scale.x = facing
			if not _gear_transition_active and _is_gear_retracted():
				var climb_distance: float = _takeoff_origin_y - global_position.y
				if climb_distance >= takeoff_clearance_height:
					_flight_phase = FlightPhase.CRUISE
			return true
		_:
			return false


func _can_land_at_current_destination() -> bool:
	if _destination_node == null:
		return false
	return _destination_node.get_parking_lot() != null


func _begin_landing_sequence() -> void:
	if _flight_phase != FlightPhase.CRUISE:
		return
	_end_avoidance()
	_is_escaping = false
	_escape_time_left = 0.0
	_landing_target_position = _destination_node.global_position
	var min_hover_height: float = gear_blocked_min_descent_speed * gear_transition_duration + 10.0
	var hover_height: float = maxf(lot_hover_height, min_hover_height)
	_hover_target_position = _landing_target_position + Vector2(0.0, -hover_height)
	_flight_phase = FlightPhase.APPROACH_HOVER


func _begin_takeoff_from_lot() -> void:
	if _flight_phase == FlightPhase.TAKEOFF:
		return
	_takeoff_origin_y = global_position.y
	_takeoff_impulse_pending = true
	_start_gear_transition(false)
	_flight_phase = FlightPhase.TAKEOFF


func _complete_destination_after_landing() -> void:
	_current_path = PackedVector2Array()
	_path_index = 0
	_no_progress_time = 0.0
	_last_progress_path_index = -1
	destination_reached.emit(self)
	if _try_despawn_after_destination_reached():
		return
	_request_next_destination()


func _get_lot_wait_time_seconds() -> float:
	var min_wait: float = maxf(0.0, lot_wait_time_min)
	var max_wait: float = maxf(0.0, lot_wait_time_max)
	if max_wait < min_wait:
		var temp: float = min_wait
		min_wait = max_wait
		max_wait = temp
	if is_equal_approx(min_wait, max_wait):
		return min_wait
	return _rng.randf_range(min_wait, max_wait)


func _start_gear_transition(deploy_to_bottom: bool) -> void:
	_gear_transition_active = true
	_gear_transition_elapsed = 0.0
	_gear_transition_from_y = landing_gear_root.position.y
	_gear_transition_to_y = _bottom_gear_y_position if deploy_to_bottom else _top_gear_y_position


func _update_gear_transition(delta: float) -> void:
	if not _gear_transition_active:
		return
	_gear_transition_elapsed += delta
	var duration: float = maxf(0.01, gear_transition_duration)
	var t: float = clampf(_gear_transition_elapsed / duration, 0.0, 1.0)
	_set_gear_y(lerpf(_gear_transition_from_y, _gear_transition_to_y, t))
	if t >= 1.0:
		_gear_transition_active = false


func _set_gear_y(y: float) -> void:
	if landing_gear_root != null:
		landing_gear_root.position.y = y
	if gear_collision != null:
		gear_collision.position.y = y
		gear_collision.disabled = y <= (_top_gear_y_position + 0.5)


func _snap_touchdown_to_ground() -> void:
	global_position.x = _landing_target_position.x
	var surface_top_y: float = _get_destination_surface_top_y()
	if surface_top_y < INF:
		var gear_bottom_local_y: float = _get_gear_bottom_local_y()
		global_position.y = surface_top_y - gear_bottom_local_y
		return
	if center_ray == null:
		global_position.y = _landing_target_position.y
		return
	center_ray.force_raycast_update()
	if not center_ray.is_colliding():
		global_position.y = _landing_target_position.y
		return
	var hit_position: Vector2 = center_ray.get_collision_point()
	var gear_bottom_local_y: float = _get_gear_bottom_local_y()
	global_position.y = hit_position.y - gear_bottom_local_y


func _get_destination_surface_top_y() -> float:
	if _destination_node == null:
		return INF
	var lot: ParkikngLot = _destination_node.get_parking_lot()
	if lot != null:
		return _get_surface_top_y(lot)
	var pad: LandingPad = _destination_node.get_landing_pad()
	if pad != null:
		return _get_surface_top_y(pad)
	return INF


func _get_surface_top_y(surface: Node2D) -> float:
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


func _get_gear_bottom_local_y() -> float:
	if gear_collision == null:
		return landing_gear_root.position.y + center_ray.position.y
	var bottom_local_y: float = gear_collision.position.y
	var shape: Shape2D = gear_collision.shape
	if shape is RectangleShape2D:
		var rect: RectangleShape2D = shape as RectangleShape2D
		bottom_local_y += rect.size.y * 0.5 * absf(gear_collision.scale.y)
		return bottom_local_y
	if shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = shape as CapsuleShape2D
		bottom_local_y += (capsule.height * 0.5 + capsule.radius) * absf(gear_collision.scale.y)
		return bottom_local_y
	if shape is CircleShape2D:
		var circle: CircleShape2D = shape as CircleShape2D
		bottom_local_y += circle.radius * absf(gear_collision.scale.y)
		return bottom_local_y
	# Fallback to center-ray origin if shape type is unknown.
	return landing_gear_root.position.y + center_ray.position.y


func _is_gear_deployed() -> bool:
	return landing_gear_root.position.y >= (_bottom_gear_y_position - 0.1)


func _is_gear_retracted() -> bool:
	return landing_gear_root.position.y <= (_top_gear_y_position + 0.1)


func _gear_blocks_vertical_lift() -> bool:
	return not _is_gear_retracted()


func _apply_gear_vertical_constraint(target_velocity: Vector2, allow_takeoff_override: bool) -> Vector2:
	if allow_takeoff_override:
		return target_velocity
	if _gear_blocks_vertical_lift() and target_velocity.y < gear_blocked_min_descent_speed:
		target_velocity.y = gear_blocked_min_descent_speed
	return target_velocity


func _begin_escape() -> void:
	_no_progress_time = 0.0
	var escape_dir: Vector2 = _find_escape_direction()
	if escape_dir == Vector2.ZERO:
		return
	_is_escaping = true
	_escape_direction = escape_dir
	_escape_time_left = deadlock_escape_duration
	_end_avoidance()


func _end_escape() -> void:
	_is_escaping = false
	_escape_direction = Vector2.ZERO
	_escape_time_left = 0.0
	_no_progress_time = 0.0
	_last_progress_path_index = _path_index


func _apply_escape_movement(delta: float) -> void:
	var safety_eval: Dictionary = _evaluate_surroundings(_escape_direction)
	var speed_factor: float = float(safety_eval.get("speed_factor", 1.0))
	var blocked: bool = bool(safety_eval.get("blocked", false))
	if blocked and speed_factor <= 0.01:
		var new_dir: Vector2 = _find_escape_direction()
		if new_dir != Vector2.ZERO:
			_escape_direction = new_dir
		linear_velocity = linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
	else:
		var target_velocity: Vector2 = _escape_direction * _max_speed * speed_factor
		linear_velocity = linear_velocity.lerp(target_velocity, delta * _steering_lerp)
	if _escape_direction.x != 0.0:
		var facing: float = 1.0 if _escape_direction.x < 0.0 else -1.0
		sprite.scale.x = facing
		body_collision.scale.x = facing


func _find_escape_direction() -> Vector2:
	var world_2d: World2D = get_viewport().world_2d if get_viewport() != null else null
	if world_2d == null:
		return Vector2.RIGHT
	var best_direction: Vector2 = Vector2.ZERO
	var best_clearance: float = -1.0
	for i: int in 8:
		var angle: float = TAU * i / 8.0
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var ray_end: Vector2 = global_position + dir * deadlock_scan_distance
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(global_position, ray_end)
		query.collision_mask = surrounding_collision_mask
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [self]
		var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
		var clearance: float = deadlock_scan_distance
		if not hit.is_empty():
			var collider: Object = hit.get("collider") as Object
			if collider != null and _should_treat_as_obstacle(collider):
				clearance = global_position.distance_to(hit.get("position", ray_end))
		if clearance > best_clearance:
			best_clearance = clearance
			best_direction = dir
	return best_direction
