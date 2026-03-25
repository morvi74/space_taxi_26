extends RigidBody2D
class_name NPCCar

signal destination_reached(car: NPCCar)

@export var speed: float = 200.0
@export var arrival_tolerance: float = 20.0
@export var steering_lerp: float = 5.0
@export var collision_recovery_time: float = 0.35
@export var collision_steer_lock_time: float = 0.18
@export var collision_recovery_steer_factor: float = 0.3
@export var post_collision_speed_factor: float = 0.7
@export var min_relative_impact_speed: float = 40.0
@export var collision_knockback_factor: float = 0.6
@export var max_knockback_impulse: float = 140.0
@export var impact_repeat_cooldown: float = 0.18

var current_path: PackedVector2Array = []
var path_index: int = 0
var _traffic_network: TrafficNetwork
var _traffic_manager: Node  # TrafficManager reference for requesting destinations
var _destination_node: TrafficNode
func get_destination_node() -> TrafficNode:
	return _destination_node

# Parking behavior
@export var parking_wait_chance: float = 0.35
@export var parking_wait_seconds: Vector2 = Vector2(2.0, 5.0)
@export var parking_lot_radius: float = 80.0
@export var despawn_node_distance: float = 26.0
@export var min_despawn_distance_to_player: float = 140.0
@export var building_collision_mask: int = 1 << 1
@export var surrounding_collision_mask: int = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4) | (1 << 6)
@export var caution_distance: float = 140.0
@export var stop_distance: float = 52.0
@export var sensor_vertical_offset: float = 18.0
@export var side_ray_tilt_degrees: float = 24.0
@export var side_ray_length_factor: float = 0.78
@export var side_ray_speed_influence: float = 0.55
@export var side_ray_stop_distance_factor: float = 0.75
@export var side_ray_hard_block_distance_factor: float = 0.62
@export var blocked_replan_time: float = 3.0
@export var blocked_speed_threshold: float = 20.0
@export var replan_cooldown: float = 1.2
@export var failed_replan_retry_time: float = 0.35
@export var final_approach_distance: float = 120.0
@export var destination_block_radius: float = 44.0
@export var fallback_half_extent: float = 18.0
@export var caution_reaction_time: float = 0.55
@export var max_brake_deceleration: float = 420.0
@export var caution_extra_buffer: float = 36.0
@export var dynamic_blocked_speed_ratio: float = 0.12
@export var debug_draw_sensors: bool = false
@export var debug_sensor_line_width: float = 2.0

var _is_paused: bool = false
var _collision_recovery_left: float = 0.0
var _steer_lock_left: float = 0.0
var _impact_cooldowns: Dictionary = {}
var _last_passed_node: TrafficNode = null
var _previous_passed_node: TrafficNode = null
var _current_target_node: TrafficNode = null
var _launch_surface_node: TrafficNode = null
var _launch_surface_pad: LandingPad = null
var _launch_surface_lot: ParkikngLot = null
var _launch_surface_return_enabled: bool = false
var _blocked_time_left: float = 0.0
var _replan_cooldown_left: float = 0.0
var _failed_replan_attempts: int = 0
var _debug_sensor_rays: Array[Dictionary] = []
var _debug_status_text: String = ""


func _ready() -> void:
	# Keep cars stable when they collide.
	lock_rotation = true
	# Damping prevents endless drifting.
	linear_damp = 2.0 
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_entered)
	add_to_group("npc_cars")


func set_network(network: TrafficNetwork) -> void:
	_traffic_network = network


func set_traffic_manager(manager: Node) -> void:
	_traffic_manager = manager


func set_new_destination(target_pos: Vector2) -> bool:
	if _traffic_network == null:
		push_warning("NPCCar has no TrafficNetwork assigned.")
		return false

	current_path = _traffic_network.get_path_between(global_position, target_pos)
	path_index = 0
	return not current_path.is_empty()


func set_new_destination_node(target: TrafficNode) -> bool:
	_destination_node = target
	_blocked_time_left = 0.0
	_replan_cooldown_left = 0.0
	_failed_replan_attempts = 0
	if _destination_node == null:
		_clear_launch_surface_context()
		_current_target_node = null
		return false
	_capture_launch_surface_context()
	return set_new_destination(_destination_node.global_position)


func has_active_path() -> bool:
	return not current_path.is_empty()


func pause_movement(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_is_paused = true
	await get_tree().create_timer(seconds).timeout
	_is_paused = false


func _physics_process(delta: float) -> void:
	_update_impact_cooldowns(delta)
	_process_collision_contacts()
	if _replan_cooldown_left > 0.0:
		_replan_cooldown_left = maxf(0.0, _replan_cooldown_left - delta)

	if _collision_recovery_left > 0.0:
		_collision_recovery_left = maxf(0.0, _collision_recovery_left - delta)
	if _steer_lock_left > 0.0:
		_steer_lock_left = maxf(0.0, _steer_lock_left - delta)

	if _is_paused:
		_set_debug_status("PAUSED")
		linear_velocity = linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
		queue_redraw()
		return

	if _steer_lock_left > 0.0:
		# Let physics response play out briefly after impact before re-steering.
		_set_debug_status("STEER_LOCK")
		queue_redraw()
		return

	if current_path.is_empty():
		_current_target_node = null
		_set_debug_status("NO_PATH")
		linear_velocity = linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
		queue_redraw()
		return

	var target_pos := current_path[path_index]
	var dist := global_position.distance_to(target_pos)

	if _has_reached_path_point(target_pos, dist):
		_set_last_passed_node_from_position(target_pos)
		path_index += 1
		if path_index >= current_path.size():
			current_path = []
			_current_target_node = null
			linear_velocity = Vector2.ZERO
			destination_reached.emit(self)
			# Autonomously handle parking and next destination.
			_handle_destination_reached()
			return
		target_pos = current_path[path_index]

	_update_current_target_node(target_pos)
	var safety_eval: Dictionary = _evaluate_surroundings(target_pos)
	var speed_factor: float = float(safety_eval.get("speed_factor", 1.0))
	var blocked: bool = bool(safety_eval.get("blocked", false))
	var destination_blocked: bool = bool(safety_eval.get("destination_blocked", false))
	_update_blocked_recovery(delta, blocked, destination_blocked)

	# Drive with direct velocity control while keeping physics interactions.
	var direction := global_position.direction_to(target_pos)

	# During post-collision recovery, reduce steering authority so physics bounce can play out.
	var steer_factor := 1.0
	if _collision_recovery_left > 0.0:
		steer_factor = clampf(collision_recovery_steer_factor, 0.0, 1.0)
	var target_velocity: Vector2 = direction * speed * speed_factor
	if blocked and speed_factor <= 0.01:
		target_velocity = Vector2.ZERO
	linear_velocity = linear_velocity.lerp(target_velocity, delta * steering_lerp * steer_factor)

	# Flip both sprite and collision polygon horizontally based on travel direction.
	# CollisionPolygon2D has no flip_h, so scale.x = ±1 mirrors both consistently.
	if direction.x != 0:
		var facing: float = 1.0 if direction.x < 0 else -1.0
		$Sprite2D.scale.x = facing
		$CollisionPolygon2D.scale.x = facing

	queue_redraw()


func _set_last_passed_node_from_position(pos: Vector2) -> void:
	if _traffic_network == null:
		return
	var node: TrafficNode = _traffic_network.get_closest_node(pos)
	if node != null and node != _last_passed_node:
		_previous_passed_node = _last_passed_node
		_last_passed_node = node
		if _launch_surface_return_enabled and _launch_surface_node != null and node != _launch_surface_node:
			_launch_surface_return_enabled = false


func _update_current_target_node(target_pos: Vector2) -> void:
	if _traffic_network == null:
		_current_target_node = null
		return
	_current_target_node = _traffic_network.get_closest_node(target_pos)


func _evaluate_surroundings(target_pos: Vector2) -> Dictionary:
	if _traffic_network == null:
		_clear_debug_sensor_rays()
		_set_debug_status("NO_NETWORK")
		return {"speed_factor": 1.0, "blocked": false, "destination_blocked": false}

	var forward: Vector2 = _get_sensor_forward_vector(target_pos)
	var side: Vector2 = Vector2(-forward.y, forward.x)
	var forward_speed: float = maxf(0.0, linear_velocity.dot(forward))
	_clear_debug_sensor_rays()

	var speed_factor: float = 1.0
	var blocked: bool = false
	var destination_blocked: bool = false
	var dynamic_caution_distance: float = _compute_dynamic_caution_distance(forward_speed)
	var tilt_tan: float = tan(deg_to_rad(side_ray_tilt_degrees))
	var ray_configs: Array[Dictionary] = [
		{"offset": 0.0, "dir": forward, "length_factor": 1.0, "speed_influence": 1.0, "stop_factor": 1.0, "hard_block_factor": 1.0},
		{"offset": -sensor_vertical_offset, "dir": (forward - side * tilt_tan).normalized(), "length_factor": side_ray_length_factor, "speed_influence": side_ray_speed_influence, "stop_factor": side_ray_stop_distance_factor, "hard_block_factor": side_ray_hard_block_distance_factor},
		{"offset": sensor_vertical_offset, "dir": (forward + side * tilt_tan).normalized(), "length_factor": side_ray_length_factor, "speed_influence": side_ray_speed_influence, "stop_factor": side_ray_stop_distance_factor, "hard_block_factor": side_ray_hard_block_distance_factor},
	]
	for ray_config: Dictionary in ray_configs:
		var y_offset: float = float(ray_config.get("offset", 0.0))
		var ray_dir: Vector2 = ray_config.get("dir", forward)
		var ray_length_factor: float = float(ray_config.get("length_factor", 1.0))
		var ray_speed_influence: float = float(ray_config.get("speed_influence", 1.0))
		var ray_stop_factor: float = float(ray_config.get("stop_factor", 1.0))
		var ray_hard_block_factor: float = float(ray_config.get("hard_block_factor", 1.0))
		if ray_dir == Vector2.ZERO:
			ray_dir = forward
		var origin := global_position + side * y_offset
		var ray_caution_distance: float = dynamic_caution_distance * ray_length_factor
		var to := origin + ray_dir * ray_caution_distance
		var query := PhysicsRayQueryParameters2D.create(origin, to)
		query.collision_mask = surrounding_collision_mask
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [self]
		var world_2d: World2D = get_viewport().world_2d
		if world_2d == null:
			continue
		var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			_push_debug_sensor_ray(origin, to, Color(0.25, 0.9, 0.3, 0.95))
			continue

		var collider: Object = hit.get("collider") as Object
		if collider == null:
			_push_debug_sensor_ray(origin, to, Color(0.55, 0.55, 0.55, 0.9))
			continue

		var hit_position: Vector2 = hit.get("position", to)
		var hit_distance: float = origin.distance_to(hit_position)
		var hit_kind: String = _classify_surrounding_hit(collider, target_pos)
		if hit_kind == "target_surface":
			_push_debug_sensor_ray(origin, hit_position, Color(0.2, 0.85, 1.0, 0.95))
			continue

		if hit_kind == "npc" or hit_kind == "player":
			if _is_destination_area_occupied():
				destination_blocked = true

		var collider_half_extent: float = _get_horizontal_half_extent_from_object(collider)
		var effective_stop_half_extent: float = _get_effective_stop_half_extent(collider, hit_kind, collider_half_extent)
		var dynamic_stop_distance: float = _compute_dynamic_stop_distance(forward_speed, effective_stop_half_extent) * ray_stop_factor
		var hard_block_distance: float = dynamic_stop_distance * ray_hard_block_factor
		var lane_factor: float = 1.0
		if hit_distance <= hard_block_distance:
			lane_factor = 0.0
			blocked = true
		else:
			lane_factor = clampf((hit_distance - dynamic_stop_distance) / maxf(1.0, ray_caution_distance - dynamic_stop_distance), 0.0, 1.0)
		var weighted_lane_factor: float = lerpf(1.0, lane_factor, clampf(ray_speed_influence, 0.0, 1.0))
		speed_factor = minf(speed_factor, weighted_lane_factor)
		var ray_color: Color = Color(0.95, 0.25, 0.25, 0.95) if lane_factor <= 0.01 else Color(1.0, 0.75, 0.2, 0.95)
		_push_debug_sensor_ray(origin, hit_position, ray_color)

	if _is_destination_area_occupied() and _is_in_final_approach(target_pos):
		destination_blocked = true
		blocked = true
		speed_factor = 0.0

	var phase: String = "CRUISE"
	if blocked:
		phase = "BLOCKED"
	elif speed_factor < 0.99:
		phase = "CAUTION"
	if destination_blocked:
		phase += " + DEST_OCCUPIED"
	_set_debug_status(phase + " sf=" + str(snappedf(speed_factor, 0.01)) + " bt=" + str(snappedf(_blocked_time_left, 0.1)))

	return {
		"speed_factor": speed_factor,
		"blocked": blocked,
		"destination_blocked": destination_blocked,
	}


func _get_sensor_forward_vector(target_pos: Vector2) -> Vector2:
	var forward: Vector2 = global_position.direction_to(target_pos)
	if forward == Vector2.ZERO:
		forward = linear_velocity.normalized()
	if forward == Vector2.ZERO:
		forward = Vector2.RIGHT if $Sprite2D.scale.x <= 0.0 else Vector2.LEFT
	return forward.normalized()


func _clear_debug_sensor_rays() -> void:
	_debug_sensor_rays.clear()


func _push_debug_sensor_ray(origin: Vector2, target: Vector2, color: Color) -> void:
	if not debug_draw_sensors:
		return
	_debug_sensor_rays.append({
		"from": to_local(origin),
		"to": to_local(target),
		"color": color,
	})


func _set_debug_status(text: String) -> void:
	if debug_draw_sensors:
		_debug_status_text = text
	else:
		_debug_status_text = ""


func _draw() -> void:
	if not debug_draw_sensors:
		return

	for ray in _debug_sensor_rays:
		draw_line(
			ray.get("from", Vector2.ZERO),
			ray.get("to", Vector2.ZERO),
			ray.get("color", Color.WHITE),
			debug_sensor_line_width
		)

	if _destination_node != null:
		draw_line(
			Vector2.ZERO,
			to_local(_destination_node.global_position),
			Color(0.45, 0.7, 1.0, 0.55),
			1.0
		)

	var font: Font = ThemeDB.fallback_font
	if font != null and not _debug_status_text.is_empty():
		draw_string(font, Vector2(-72.0, -36.0), _debug_status_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color(1, 1, 1, 0.95))


func _classify_surrounding_hit(collider: Object, target_pos: Vector2) -> String:
	if collider is NPCCar and collider != self:
		return "npc"

	var player_taxi: Node2D = GameData.get_taxi() as Node2D
	if player_taxi != null and collider == player_taxi:
		return "player"

	if collider is LandingPad:
		if _is_target_landing_pad(collider as LandingPad) and _is_target_surface_approach_context(target_pos):
			return "target_surface"
		return "obstacle"

	if collider is ParkikngLot:
		if _is_target_parking_lot(collider as ParkikngLot) and _is_target_surface_approach_context(target_pos):
			return "target_surface"
		return "obstacle"

	return "obstacle"


func _is_target_landing_pad(pad: LandingPad) -> bool:
	if _destination_node == null or pad == null:
		return false
	if _launch_surface_return_enabled and _launch_surface_pad == pad:
		return true
	return _destination_node.get_landing_pad() == pad


func _is_target_parking_lot(lot: ParkikngLot) -> bool:
	if _destination_node == null or lot == null:
		return false
	if _launch_surface_return_enabled and _launch_surface_lot == lot:
		return true
	return _destination_node.get_parking_lot() == lot


func _capture_launch_surface_context() -> void:
	_clear_launch_surface_context()
	if _traffic_network == null:
		return

	var start_node: TrafficNode = _traffic_network.get_closest_node(global_position)
	if start_node == null:
		return

	if global_position.distance_to(start_node.global_position) > arrival_tolerance * 1.5:
		return

	_launch_surface_node = start_node
	_launch_surface_pad = start_node.get_landing_pad()
	_launch_surface_lot = start_node.get_parking_lot()
	_launch_surface_return_enabled = _launch_surface_pad != null or _launch_surface_lot != null


func _clear_launch_surface_context() -> void:
	_launch_surface_node = null
	_launch_surface_pad = null
	_launch_surface_lot = null
	_launch_surface_return_enabled = false


func _is_in_final_approach(target_pos: Vector2) -> bool:
	if _destination_node == null:
		return false
	if _current_target_node != _destination_node:
		return false
	return global_position.distance_to(target_pos) <= final_approach_distance


func _is_target_surface_approach_context(target_pos: Vector2) -> bool:
	if _destination_node == null:
		return false

	# If we are already on the final path segment to the destination node,
	# the destination surface should be treated as a valid touchdown surface.
	var final_segment: bool = not current_path.is_empty() and path_index >= current_path.size() - 1 and _current_target_node == _destination_node
	if final_segment:
		return true

	return _is_in_final_approach(target_pos)


func _is_destination_area_occupied() -> bool:
	if _destination_node == null:
		return false

	var dest_pos: Vector2 = _destination_node.global_position
	var self_half_extent: float = _get_horizontal_half_extent_from_object(self)
	for node: Node in get_tree().get_nodes_in_group("npc_cars"):
		var npc: NPCCar = node as NPCCar
		if npc == null or npc == self:
			continue
		var npc_half_extent: float = _get_horizontal_half_extent_from_object(npc)
		var block_radius: float = maxf(destination_block_radius, self_half_extent + npc_half_extent)
		if npc.global_position.distance_to(dest_pos) <= block_radius:
			return true

	var player_taxi: Node2D = GameData.get_taxi() as Node2D
	if player_taxi != null:
		var player_half_extent: float = _get_horizontal_half_extent_from_object(player_taxi)
		var player_block_radius: float = maxf(destination_block_radius, self_half_extent + player_half_extent)
		if player_taxi.global_position.distance_to(dest_pos) <= player_block_radius:
			return true

	return false


func _update_blocked_recovery(delta: float, blocked: bool, destination_blocked: bool) -> void:
	if current_path.is_empty():
		_blocked_time_left = 0.0
		return

	if destination_blocked and _is_near_destination_for_reroute() and _replan_cooldown_left <= 0.0:
		if _attempt_blocked_recovery(true):
			_blocked_time_left = 0.0
			_replan_cooldown_left = replan_cooldown
			_failed_replan_attempts = 0
		else:
			_failed_replan_attempts += 1
			_replan_cooldown_left = failed_replan_retry_time
		return

	if blocked and linear_velocity.length() <= _get_effective_blocked_speed_threshold():
		_blocked_time_left += delta
	else:
		_blocked_time_left = maxf(0.0, _blocked_time_left - delta * 2.0)

	if _blocked_time_left < blocked_replan_time:
		return
	if _replan_cooldown_left > 0.0:
		return

	if _attempt_blocked_recovery(destination_blocked):
		_blocked_time_left = 0.0
		_replan_cooldown_left = replan_cooldown
		_failed_replan_attempts = 0
	else:
		_failed_replan_attempts += 1
		# Keep the timer close to threshold so we quickly retry instead of stalling.
		_blocked_time_left = blocked_replan_time
		_replan_cooldown_left = failed_replan_retry_time


func _is_near_destination_for_reroute() -> bool:
	if _destination_node == null:
		return false
	return global_position.distance_to(_destination_node.global_position) <= final_approach_distance


func _attempt_blocked_recovery(destination_blocked: bool) -> bool:
	if _traffic_manager == null:
		return false

	var blocked_node: TrafficNode = _current_target_node
	var primary_start_node: TrafficNode = _last_passed_node
	if primary_start_node == null and _traffic_network != null:
		primary_start_node = _traffic_network.get_closest_node(global_position)

	if blocked_node == _destination_node or destination_blocked:
		if _request_next_destination(_destination_node):
			return true
		return _request_next_destination()

	if _try_alternative_reroute_from_start(primary_start_node, blocked_node):
		return true

	if _failed_replan_attempts >= 2:
		if _try_alternative_reroute_from_start(_previous_passed_node, blocked_node):
			return true

	if _request_next_destination(_destination_node):
		return true
	return _request_next_destination()


func _try_alternative_reroute_from_start(start_node: TrafficNode, blocked_node: TrafficNode) -> bool:
	if _traffic_manager == null or not _traffic_manager.has_method("request_alternative_destination"):
		return false
	if start_node == null:
		return false

	var alt_dest: TrafficNode = _traffic_manager.request_alternative_destination(self, start_node, blocked_node, _destination_node)
	if alt_dest != null:
		return set_new_destination_node(alt_dest)
	return false


func _has_reached_path_point(target_pos: Vector2, dist: float) -> bool:
	if dist >= arrival_tolerance:
		return false
	if path_index <= 0 or current_path.is_empty():
		return true

	var prev_pos: Vector2 = current_path[path_index - 1]
	var segment: Vector2 = target_pos - prev_pos
	var segment_length: float = segment.length()
	if segment_length <= 0.001:
		return true

	var segment_dir: Vector2 = segment / segment_length
	var progress_on_segment: float = (global_position - prev_pos).dot(segment_dir)
	var reached_by_progress: bool = progress_on_segment >= segment_length - (arrival_tolerance * 0.5)
	return reached_by_progress or dist < arrival_tolerance * 0.5


func _on_body_entered(body: Node) -> void:
	_apply_collision_response(body)


func _update_impact_cooldowns(delta: float) -> void:
	var expired_ids: Array[int] = []
	for body_id_variant: Variant in _impact_cooldowns.keys():
		var body_id: int = int(body_id_variant)
		var time_left: float = float(_impact_cooldowns[body_id]) - delta
		if time_left <= 0.0:
			expired_ids.append(body_id)
		else:
			_impact_cooldowns[body_id] = time_left

	for body_id: int in expired_ids:
		_impact_cooldowns.erase(body_id)


func _process_collision_contacts() -> void:
	for body_variant: Variant in get_colliding_bodies():
		var body: Node = body_variant as Node
		if body == null:
			continue
		_apply_collision_response(body)


func _apply_collision_response(body: Node) -> void:
	var body_id: int = body.get_instance_id()
	if _impact_cooldowns.has(body_id):
		return
	_impact_cooldowns[body_id] = impact_repeat_cooldown

	var self_velocity_before: Vector2 = linear_velocity
	_collision_recovery_left = maxf(_collision_recovery_left, collision_recovery_time)
	_steer_lock_left = maxf(_steer_lock_left, collision_steer_lock_time)
	linear_velocity = self_velocity_before * post_collision_speed_factor

	var other_velocity: Vector2 = _get_body_linear_velocity(body)
	var relative_speed: float = (self_velocity_before - other_velocity).length()
	if relative_speed < min_relative_impact_speed:
		return

	var away: Vector2 = Vector2.ZERO
	if body is Node2D:
		away = (global_position - (body as Node2D).global_position).normalized()
	if away == Vector2.ZERO:
		away = self_velocity_before.normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT

	var impulse_magnitude: float = minf(relative_speed * mass * collision_knockback_factor, max_knockback_impulse)
	apply_central_impulse(away * impulse_magnitude)


func _get_body_linear_velocity(body: Node) -> Vector2:
	if body is RigidBody2D:
		return (body as RigidBody2D).linear_velocity
	if body is CharacterBody2D:
		return (body as CharacterBody2D).velocity
	return Vector2.ZERO


func _handle_destination_reached() -> void:
	"""Called when the car reaches its destination. Handles parking logic and requests next destination."""
	if _should_despawn_here():
		queue_free()
		return

	if _should_park():
		var wait_seconds: float = randf_range(parking_wait_seconds.x, parking_wait_seconds.y)
		await pause_movement(wait_seconds)
	
	_request_next_destination()


func _should_park() -> bool:
	"""Decide whether to park at current location based on proximity and chance and location."""
	if not _is_near_parking_lot():
		return false
	if randf() > parking_wait_chance:
		return false
	return true


func _is_near_parking_lot() -> bool:
	"""Check if car is near any parking lot."""
	for lot in get_tree().get_nodes_in_group("parking_lots"):
		if lot is Node2D and global_position.distance_to((lot as Node2D).global_position) <= parking_lot_radius:
			return true

	# for lot in get_tree().get_nodes_in_group("landing_pads"):
	# 	if lot is Node2D and global_position.distance_to((lot as Node2D).global_position) <= parking_lot_radius:
	# 		return true

	return false


func _request_next_destination(excluded_destination: TrafficNode = null) -> bool:
	"""Request the next destination from TrafficManager."""
	if _traffic_manager == null:
		return false
	
	var closest_node: TrafficNode = _traffic_network.get_closest_node(global_position) if _traffic_network else null
	var next_dest: TrafficNode = null
	if excluded_destination != null and _traffic_manager.has_method("request_next_destination_excluding"):
		next_dest = _traffic_manager.request_next_destination_excluding(self, closest_node, 0.0, excluded_destination)
	elif _traffic_manager.has_method("request_next_destination"):
		next_dest = _traffic_manager.request_next_destination(self, closest_node)
	if next_dest != null:
		return set_new_destination_node(next_dest)
	return false


func _compute_dynamic_caution_distance(speed_x: float) -> float:
	var speed_based_lookahead: float = speed_x * caution_reaction_time
	return maxf(caution_distance, _get_horizontal_half_extent_from_object(self) + speed_based_lookahead + caution_extra_buffer)


func _compute_dynamic_stop_distance(speed_x: float, collider_half_extent: float) -> float:
	var kinematic_stop: float = speed_x * speed_x / maxf(1.0, 2.0 * max_brake_deceleration)
	var geometry_stop: float = _get_horizontal_half_extent_from_object(self) + collider_half_extent + stop_distance
	return maxf(geometry_stop, kinematic_stop)


func _get_effective_stop_half_extent(collider: Object, hit_kind: String, raw_half_extent: float) -> float:
	if hit_kind == "obstacle" and collider is StaticBody2D:
		return 0.0
	return raw_half_extent


func _get_effective_blocked_speed_threshold() -> float:
	return maxf(blocked_speed_threshold, speed * dynamic_blocked_speed_ratio)


func _get_horizontal_half_extent_from_object(value: Object) -> float:
	var node: Node = value as Node
	if node == null:
		return fallback_half_extent
	return _get_horizontal_half_extent_from_node(node)


func _get_horizontal_half_extent_from_node(node: Node) -> float:
	var max_half_extent: float = 0.0

	for shape_node_variant: Variant in node.find_children("*", "CollisionShape2D", true, false):
		var shape_node: CollisionShape2D = shape_node_variant as CollisionShape2D
		if shape_node == null or shape_node.shape == null or shape_node.disabled:
			continue
		max_half_extent = maxf(max_half_extent, _get_half_extent_from_shape_node(shape_node))

	for poly_node_variant: Variant in node.find_children("*", "CollisionPolygon2D", true, false):
		var poly_node: CollisionPolygon2D = poly_node_variant as CollisionPolygon2D
		if poly_node == null or poly_node.disabled or poly_node.polygon.is_empty():
			continue
		max_half_extent = maxf(max_half_extent, _get_half_extent_from_polygon_node(poly_node))

	if max_half_extent <= 0.0:
		return fallback_half_extent
	return max_half_extent


func _get_half_extent_from_shape_node(shape_node: CollisionShape2D) -> float:
	var scale_x: float = absf(shape_node.global_scale.x)
	if shape_node.shape is RectangleShape2D:
		var rect: RectangleShape2D = shape_node.shape as RectangleShape2D
		return rect.size.x * 0.5 * scale_x
	if shape_node.shape is CircleShape2D:
		var circle: CircleShape2D = shape_node.shape as CircleShape2D
		return circle.radius * scale_x
	if shape_node.shape is CapsuleShape2D:
		var capsule: CapsuleShape2D = shape_node.shape as CapsuleShape2D
		return capsule.radius * scale_x
	if shape_node.shape is ConvexPolygonShape2D:
		var convex: ConvexPolygonShape2D = shape_node.shape as ConvexPolygonShape2D
		var max_x: float = 0.0
		for point: Vector2 in convex.points:
			max_x = maxf(max_x, absf(point.x))
		return max_x * scale_x
	if shape_node.shape is ConcavePolygonShape2D:
		var concave: ConcavePolygonShape2D = shape_node.shape as ConcavePolygonShape2D
		var max_concave_x: float = 0.0
		for point: Vector2 in concave.segments:
			max_concave_x = maxf(max_concave_x, absf(point.x))
		return max_concave_x * scale_x
	return fallback_half_extent


func _get_half_extent_from_polygon_node(poly_node: CollisionPolygon2D) -> float:
	var max_x: float = 0.0
	for point: Vector2 in poly_node.polygon:
		max_x = maxf(max_x, absf(point.x * poly_node.global_scale.x))
	return maxf(max_x, fallback_half_extent)


func _should_despawn_here() -> bool:
	if _traffic_network == null:
		return false

	var closest_spawn: TrafficNode = _traffic_network.get_closest_spawn_node(global_position)
	if closest_spawn == null:
		return false
	if closest_spawn.no_despawn:
		return false
	if global_position.distance_to(closest_spawn.global_position) > despawn_node_distance:
		return false
	return _is_despawn_location_valid(closest_spawn)


func _is_despawn_location_valid(node: TrafficNode) -> bool:
	if node == null or not node.is_spawn_node:
		return false
	if node.can_be_destination and node.is_occupied:
		return false

	var player_node: Node2D = GameData.get_taxi() as Node2D
	if player_node != null and node.global_position.distance_to(player_node.global_position) < min_despawn_distance_to_player:
		return false

	if not _is_point_visible_for_player(node.global_position):
		return true

	return _is_occluded_by_building(node.global_position)


func _is_point_visible_for_player(point: Vector2) -> bool:
	var player_camera: Camera2D = get_viewport().get_camera_2d()
	if player_camera == null:
		return false

	var viewport_rect: Rect2 = player_camera.get_viewport_rect()
	var world_size: Vector2 = viewport_rect.size * player_camera.zoom
	var top_left: Vector2 = player_camera.get_screen_center_position() - world_size * 0.5
	var world_rect: Rect2 = Rect2(top_left, world_size)
	return world_rect.has_point(point)


func _is_occluded_by_building(point: Vector2) -> bool:
	var player_node: Node2D = GameData.get_taxi() as Node2D
	var player_camera: Camera2D = get_viewport().get_camera_2d()
	var origin: Vector2 = Vector2.ZERO
	if player_node != null:
		origin = player_node.global_position
	elif player_camera != null:
		origin = player_camera.get_screen_center_position()
	else:
		return false

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, point)
	query.collision_mask = building_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var world_2d: World2D = get_viewport().world_2d
	if world_2d == null:
		return false
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	var hit: Dictionary = space_state.intersect_ray(query)
	return not hit.is_empty()