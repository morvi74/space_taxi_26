extends RigidBody2D
class_name NPCCar

signal destination_reached(car: NPCCar)

@onready var sprite: Sprite2D = $Sprite2D
@onready var landing_gear_root: Node2D = $LandingGearRoot
@onready var body_collision: CollisionPolygon2D = $CollisionPolygon2D
@onready var gear_collision: CollisionShape2D = $GearCollision

@export var _max_speed: float = 200.0
@export var _arrival_tolerance: float = 20.0
@export var _steering_lerp: float = 5.0
@export var surrounding_collision_mask: int = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4) | (1 << 6)
@export var caution_distance: float = 140.0
@export var stop_distance: float = 52.0
@export var sensor_vertical_offset: float = 16.0
@export var caution_reaction_time: float = 0.45
@export var avoid_trigger_distance: float = 90.0
@export var avoid_resume_distance: float = 130.0
@export var avoid_offset_distance: float = 34.0
@export var avoid_forward_distance: float = 44.0
@export var avoid_speed_factor: float = 0.72
@export var avoid_max_time: float = 1.4
@export var avoid_front_cone_degrees: float = 50.0
@export var _top_gear_y_position: float = 7.0
@export var _bottom_gear_y_position: float = 21.0
@export var debug_draw_sensors: bool = false
@export var debug_sensor_line_width: float = 2.0
@export var deadlock_timeout: float = 10.0
@export var deadlock_escape_duration: float = 1.0
@export var deadlock_scan_distance: float = 200.0

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


func _ready() -> void:
	lock_rotation = true
	linear_damp = 2.0
	add_to_group("npc_cars")


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


func _physics_process(delta: float) -> void:
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
			_request_next_destination()
			return
		target = _current_path[_path_index]

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
	var ray_offsets: Array[float] = [0.0, -sensor_vertical_offset, sensor_vertical_offset]
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
	var projection: float = lateral.dot(future_relative)
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
	var closest_distance: float = avoid_trigger_distance
	var cone_cos: float = cos(deg_to_rad(avoid_front_cone_degrees))

	for node: Node in get_tree().get_nodes_in_group("npc_cars"):
		var other: NPCCar = node as NPCCar
		if other == null or other == self:
			continue

		var to_other: Vector2 = other.global_position - global_position
		var distance: float = to_other.length()
		if distance <= 0.001 or distance > avoid_trigger_distance:
			continue

		var dir_to_other: Vector2 = to_other / distance
		if path_forward.dot(dir_to_other) < cone_cos:
			continue

		if distance < closest_distance:
			closest_distance = distance
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
