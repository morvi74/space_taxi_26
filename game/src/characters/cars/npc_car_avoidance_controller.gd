extends RefCounted
## Encapsulates local collision avoidance, pair coordination, and escape fallback for NPCCar.
class_name NPCCarAvoidanceController

## Responsibilities:
## - compute lane-based obstacle slowdown and hard-stop state
## - coordinate deterministic left/right side selection between two cars
## - trigger deadlock escape when avoidance cannot make progress
## Doc convention:
## - First line states intent in one sentence.
## - Optional Params line for non-trivial inputs.
## - Optional Returns line for non-obvious outputs.
## - Keep wording behavior-focused, not implementation-focused.

## Owning NPCCar instance. All reads/writes flow through this reference.
var car: NPCCar = null

## Binds the controller to a concrete NPCCar owner.
func setup(owner: NPCCar) -> void:
	car = owner

## Samples forward sensor lanes and returns speed reduction plus hard-block state.
## Params: forward_hint is the preferred movement direction for the current tick.
## Returns: Dictionary with keys speed_factor(float) and blocked(bool).
func evaluate_surroundings(forward_hint: Vector2) -> Dictionary:
	var forward: Vector2 = forward_hint
	if forward == Vector2.ZERO: forward = car.linear_velocity.normalized()
	if forward == Vector2.ZERO: forward = Vector2.RIGHT
	forward = forward.normalized()
	var side: Vector2 = Vector2(-forward.y, forward.x)
	var forward_speed: float = maxf(0.0, car.linear_velocity.dot(forward))
	var dynamic_caution_distance: float = car.caution_distance + forward_speed * car.caution_reaction_time
	var dynamic_stop_distance: float = car.stop_distance + forward_speed * 0.22
	var speed_factor: float = 1.0
	var blocked: bool = false
	var lane_count: int = maxi(3, car.sensor_lane_count)
	if lane_count % 2 == 0: lane_count += 1
	var half_lanes: int = lane_count / 2
	var lane_spacing: float = maxf(6.0, car.sensor_vertical_offset)
	for i: int in range(-half_lanes, half_lanes + 1):
		var origin: Vector2 = car.global_position + side * (float(i) * lane_spacing)
		var ray_end: Vector2 = origin + forward * dynamic_caution_distance
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, ray_end)
		query.collision_mask = car.surrounding_collision_mask
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [car]
		var world_2d: World2D = car.get_viewport().world_2d
		if world_2d == null: continue
		var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
		if hit.is_empty(): continue
		var collider: Object = hit.get("collider") as Object
		if collider == null or not should_treat_as_obstacle(collider): continue
		var hit_position: Vector2 = hit.get("position", ray_end)
		var hit_distance: float = origin.distance_to(hit_position)
		if hit_distance <= dynamic_stop_distance:
			speed_factor = 0.0
			blocked = true
		else:
			var lane_factor: float = clampf((hit_distance - dynamic_stop_distance) / maxf(1.0, dynamic_caution_distance - dynamic_stop_distance), 0.0, 1.0)
			speed_factor = minf(speed_factor, lane_factor)
	return {"speed_factor": speed_factor, "blocked": blocked}

## Decides whether a collider participates in avoidance and slowdown decisions.
func should_treat_as_obstacle(collider: Object) -> bool:
	if collider == car: return false
	if car._is_avoiding and car._blocking_car != null and collider == car._blocking_car: return false
	if collider is NPCCar: return true
	var player_taxi: Node2D = GameData.get_taxi() as Node2D
	if player_taxi != null and collider == player_taxi: return true
	if collider is LandingPad: return true
	if collider is ParkikngLot: return not is_destination_parking_lot(collider as ParkikngLot)
	if collider is StaticBody2D: return true
	return true

## Returns true when the candidate lot equals this car's destination parking lot.
func is_destination_parking_lot(lot: ParkikngLot) -> bool:
	if lot == null or car._destination_node == null: return false
	return car._destination_node.get_parking_lot() == lot

## Main avoidance state update: acquire blocker, maintain pair lock, timeout, and clear logic.
## Params: path_forward is the current desired path direction.
func update_avoidance(path_forward: Vector2) -> void:
	if path_forward == Vector2.ZERO:
		end_avoidance("no_path_forward")
		return
	if car._is_avoiding:
		car.add_avoid_time_left(-car.get_physics_process_delta_time())
		if car.get_avoid_time_left() <= 0.0:
			if try_timeout_side_retry(): return
			set_pair_timeout_cooldown(car._blocking_car)
			end_avoidance("timeout")
			return
		var clear_eval: Dictionary = evaluate_active_avoidance_clear(path_forward)
		if bool(clear_eval.get("clear", false)): end_avoidance(str(clear_eval.get("reason", "clear")))
		else: sync_avoid_side_with_blocking_pair(path_forward)
		return
	var blocking: NPCCar = find_blocking_car(path_forward)
	if blocking == null: return
	if (blocking.global_position - car.global_position).length() > car.avoid_trigger_distance: return
	begin_avoidance(blocking, path_forward)

## Enters avoidance mode and records telemetry for the chosen side/decision mode.
func begin_avoidance(other: NPCCar, path_forward: Vector2) -> void:
	var begin_reason: String = "trigger_distance"
	var decision_mode: String = "unknown"
	var pair_decision: Dictionary = resolve_pair_handshake_side(other, path_forward)
	if bool(pair_decision.get("ok", false)):
		car._avoid_side_sign = float(pair_decision.get("side", 1.0))
		begin_reason = str(pair_decision.get("reason", begin_reason))
		decision_mode = str(pair_decision.get("mode", "pair_handshake"))
	else:
		car._avoid_side_sign = compute_avoid_side_sign(other, path_forward)
		decision_mode = car._last_avoid_decision_mode
	car._last_avoid_decision_mode = decision_mode
	car._is_avoiding = true
	car._blocking_car = other
	car.set_avoid_time_left(car.avoid_max_time)
	car.set_avoid_timeout_retry_used(false)
	car._avoid_blocked_time = 0.0
	var metrics: Dictionary = build_avoidance_metrics(other, path_forward)
	car.log_debug_event("avoid_begin", car._avoid_debug.build_avoidance_event_payload("begin", begin_reason, other.get_car_id() if other != null else -1, {
		"projection_now": metrics.get("projection_now", 0.0),
		"projection_future": metrics.get("projection_future", 0.0),
		"closing_speed": metrics.get("closing_speed", 0.0),
		"decision_mode": decision_mode,
	}))

## Negotiates deterministic opposite sides for close encounters between two cars.
## Params: other is the candidate blocking car; path_forward is current travel direction.
## Returns: Dictionary with handshake status and selected side metadata.
func resolve_pair_handshake_side(other: NPCCar, path_forward: Vector2) -> Dictionary:
	if other == null: return {"ok": false}
	if is_pair_timeout_cooldown_active(other.get_car_id(), Time.get_ticks_msec()): return {"ok": false}
	if not should_force_pair_priority_side(other): return {"ok": false}
	var now_ms: int = Time.get_ticks_msec()
	if has_active_pair_assignment(other.get_car_id(), now_ms):
		return {"ok": true, "side": car.get_pair_assigned_side_sign(), "mode": "pair_handshake_reuse", "reason": "pair_handshake_reuse"}
	var lock_expire_ms: int = now_ms + get_pair_lock_duration_ms()
	if has_higher_avoid_priority_than(other):
		var leader_world_dir: Vector2 = compute_pair_world_avoid_direction(other, path_forward)
		var my_side: float = side_sign_for_world_direction(leader_world_dir, path_forward)
		var other_forward: Vector2 = other._get_path_forward_estimate()
		var other_side: float = other._avoidance_controller.side_sign_for_world_direction(-leader_world_dir, other_forward)
		set_pair_assignment(other.get_car_id(), my_side, lock_expire_ms)
		other._receive_pair_assignment_from_leader(car, other_side, lock_expire_ms)
		return {"ok": true, "side": my_side, "mode": "pair_handshake_leader", "reason": "pair_handshake_leader"}
	var fallback_dir: Vector2 = other._avoidance_controller.compute_pair_world_avoid_direction(car, other._get_path_forward_estimate())
	var fallback_side: float = side_sign_for_world_direction(-fallback_dir, path_forward)
	set_pair_assignment(other.get_car_id(), fallback_side, lock_expire_ms)
	return {"ok": true, "side": fallback_side, "mode": "pair_handshake_follower", "reason": "pair_handshake_follower"}

## Applies side assignment from the pair leader and syncs active avoidance state.
func receive_pair_assignment_from_leader(leader: NPCCar, side_sign: float, expire_ms: int) -> void:
	if leader == null or not is_instance_valid(leader): return
	set_pair_assignment(leader.get_car_id(), side_sign, expire_ms)
	car._last_avoid_decision_mode = "pair_handshake_follower_assigned"
	if car._is_avoiding and car._blocking_car == leader:
		var previous_side: float = car._avoid_side_sign
		car._avoid_side_sign = side_sign
		car.set_avoid_time_left(maxf(car.get_avoid_time_left(), car.avoid_max_time * 0.5))
		if not is_equal_approx(previous_side, car._avoid_side_sign):
			car.log_debug_event("avoid_sync", car._avoid_debug.build_avoidance_event_payload("sync", "pair_handshake_leader_update", leader.get_car_id()))
		return
	car._is_avoiding = true
	car._blocking_car = leader
	car.set_avoid_time_left(car.avoid_max_time)
	car._avoid_side_sign = side_sign
	car.log_debug_event("avoid_begin", car._avoid_debug.build_avoidance_event_payload("begin", "pair_handshake_follower_assigned", leader.get_car_id()))

## Writes pair lock metadata on the owning car.
func set_pair_assignment(partner_car_id: int, side_sign: float, expire_ms: int) -> void:
	car.set_pair_assignment_data(partner_car_id, side_sign, expire_ms)

## Applies a temporary cooldown to avoid immediate re-pairing after timeout.
func set_pair_timeout_cooldown(partner: NPCCar) -> void:
	if partner == null or not is_instance_valid(partner): return
	var partner_car_id: int = partner.get_car_id()
	var cooldown_ms: int = int(round(maxf(0.0, car.avoid_timeout_pair_cooldown_seconds) * 1000.0))
	car.set_pair_cooldown_data(partner_car_id, Time.get_ticks_msec() + cooldown_ms)

## Returns true while a timeout cooldown for this partner is still active.
func is_pair_timeout_cooldown_active(partner_car_id: int, now_ms: int) -> bool:
	if car.get_pair_cooldown_partner_car_id() != partner_car_id: return false
	return now_ms <= car.get_pair_cooldown_until_ms()

## Performs one timeout retry by flipping side and shortening retry horizon.
func try_timeout_side_retry() -> bool:
	if not car.avoid_timeout_flip_retry_enabled: return false
	if car.is_avoid_timeout_retry_used(): return false
	if car._blocking_car == null or not is_instance_valid(car._blocking_car): return false
	car.set_avoid_timeout_retry_used(true)
	car._avoid_blocked_time = 0.0
	car._avoid_side_sign *= -1.0
	car.set_avoid_time_left(maxf(maxf(0.12, car.avoid_timeout_retry_min_seconds), car.avoid_max_time * clampf(car.avoid_timeout_flip_retry_time_factor, 0.2, 1.0)))
	set_pair_assignment(car._blocking_car.get_car_id(), car._avoid_side_sign, Time.get_ticks_msec() + get_pair_lock_duration_ms())
	car._last_avoid_decision_mode = "timeout_flip_retry"
	car.log_debug_event("avoid_sync", car._avoid_debug.build_avoidance_event_payload("sync", "timeout_flip_retry"))
	return true

## Evaluates whether current blocker can be considered cleared by distance, pass, or lateral separation.
## Params: path_forward is used to project forward/lateral separation from the blocker.
## Returns: Dictionary with clear(bool) and reason(String).
func evaluate_active_avoidance_clear(path_forward: Vector2) -> Dictionary:
	if car._blocking_car == null or not is_instance_valid(car._blocking_car): return {"clear": true, "reason": "clear_invalid_blocker"}
	var to_other: Vector2 = car._blocking_car.global_position - car.global_position
	var distance: float = to_other.length()
	if distance > car.avoid_resume_distance: return {"clear": true, "reason": "clear_distance"}
	if distance <= 0.001: return {"clear": false}
	var forward_sep: float = path_forward.dot(to_other)
	var lateral_axis: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	var lateral_sep: float = absf(lateral_axis.dot(to_other))
	var rel_velocity: Vector2 = car._blocking_car.linear_velocity - car.linear_velocity
	var closing_speed: float = -to_other.normalized().dot(rel_velocity)
	var clear_closing_speed: float = maxf(0.5, car.avoid_clear_max_closing_speed)
	var clear_forward_factor: float = clampf(car.avoid_clear_forward_factor, 0.15, 0.6)
	var clear_lateral_threshold: float = effective_avoid_lateral_offset(path_forward) * 1.35
	if forward_sep <= -6.0 and closing_speed <= clear_closing_speed: return {"clear": true, "reason": "clear_passed"}
	if forward_sep <= car.avoid_trigger_distance * clear_forward_factor and lateral_sep >= clear_lateral_threshold and closing_speed <= clear_closing_speed:
		return {"clear": true, "reason": "clear_lateral_sep"}
	return {"clear": false}

## Returns true when an unexpired pair lock exists for the given partner id.
func has_active_pair_assignment(partner_car_id: int, now_ms: int) -> bool:
	if car.get_pair_partner_car_id() != partner_car_id: return false
	return now_ms <= car.get_pair_assignment_expire_ms()

## Converts pair lock duration seconds into milliseconds.
func get_pair_lock_duration_ms() -> int:
	return int(round(maxf(0.1, car.avoid_pair_lock_seconds) * 1000.0))

## Chooses global detour direction with minimal combined penalty for both vehicles.
func compute_pair_world_avoid_direction(other: NPCCar, path_forward: Vector2) -> Vector2:
	var axis: Vector2 = other.global_position - car.global_position
	if axis == Vector2.ZERO: axis = path_forward if path_forward != Vector2.ZERO else Vector2.RIGHT
	var candidate_a: Vector2 = Vector2(-axis.y, axis.x).normalized()
	if candidate_a == Vector2.ZERO: candidate_a = Vector2.RIGHT
	var candidate_b: Vector2 = -candidate_a
	var score_a: float = pair_world_direction_cost(candidate_a, other, path_forward)
	var score_b: float = pair_world_direction_cost(candidate_b, other, path_forward)
	return candidate_a if score_a <= score_b else candidate_b

## Scores a global detour direction for both participants in the pair.
func pair_world_direction_cost(world_direction: Vector2, other: NPCCar, path_forward: Vector2) -> float:
	var my_sign: float = side_sign_for_world_direction(world_direction, path_forward)
	var other_forward: Vector2 = other._get_path_forward_estimate()
	var other_sign: float = other._avoidance_controller.side_sign_for_world_direction(-world_direction, other_forward)
	var my_penalty: float = pair_detour_penalty(other.global_position - car.global_position, path_forward, my_sign)
	var other_penalty: float = other._avoidance_controller.pair_detour_penalty(car.global_position - other.global_position, other_forward, other_sign)
	return my_penalty + other_penalty

## Penalizes side choices that force a longer immediate lateral detour.
func pair_detour_penalty(relative_position: Vector2, forward: Vector2, chosen_sign: float) -> float:
	var lateral: Vector2 = Vector2(-forward.y, forward.x).normalized()
	if lateral == Vector2.ZERO: return 0.0
	var projection: float = lateral.dot(relative_position)
	var magnitude: float = absf(projection)
	if magnitude <= car.avoid_lateral_now_threshold: return magnitude * 0.05
	var preferred_sign: float = -1.0 if projection > 0.0 else 1.0
	if is_equal_approx(preferred_sign, chosen_sign): return 0.0
	return magnitude

## Computes the local lateral sign, including mirrored and head-on tie-break cases.
func compute_avoid_side_sign(other: NPCCar, path_forward: Vector2) -> float:
	if other != null and should_force_pair_priority_side(other):
		car._last_avoid_decision_mode = "pair_priority_head_on"
		return head_on_side_sign(other, path_forward)
	if other != null and other._is_avoiding and other._blocking_car == car:
		var other_world_avoid: Vector2 = other._get_current_world_avoid_direction()
		if other_world_avoid != Vector2.ZERO:
			car._last_avoid_decision_mode = "mirror_blocking_pair"
			return side_sign_for_world_direction(-other_world_avoid, path_forward)
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	var my_forward: Vector2 = get_path_forward_estimate()
	var other_forward: Vector2 = other._get_path_forward_estimate()
	var my_speed: float = maxf(car.linear_velocity.length(), car._max_speed * 0.45)
	var other_speed: float = maxf(other.linear_velocity.length(), other._max_speed * 0.45)
	var relative_position: Vector2 = other.global_position - car.global_position
	var relative_velocity: Vector2 = other_forward * other_speed - my_forward * my_speed
	var lookahead_time: float = 0.0
	var rel_vel_len_sq: float = relative_velocity.length_squared()
	if rel_vel_len_sq > 0.001: lookahead_time = clampf(-relative_position.dot(relative_velocity) / rel_vel_len_sq, 0.0, 1.2)
	var future_relative: Vector2 = relative_position + relative_velocity * lookahead_time
	var projection_now: float = lateral.dot(relative_position)
	if absf(projection_now) > car.avoid_lateral_now_threshold:
		car._last_avoid_decision_mode = "projection_now"
		return -1.0 if projection_now > 0.0 else 1.0
	var projection: float = lateral.dot(future_relative)
	if absf(projection) > 10.0:
		car._last_avoid_decision_mode = "projection_future"
		return -1.0 if projection > 0.0 else 1.0
	car._last_avoid_decision_mode = "head_on_tiebreak"
	return head_on_side_sign(other, path_forward)

## Detects near head-on encounters where pair-priority assignment should override heuristics.
func should_force_pair_priority_side(other: NPCCar) -> bool:
	if other == null: return false
	var to_other: Vector2 = other.global_position - car.global_position
	var distance: float = to_other.length()
	if distance <= 0.001 or distance > car.avoid_trigger_distance * 1.35: return false
	var dir_to_other: Vector2 = to_other / distance
	var my_forward: Vector2 = get_path_forward_estimate()
	var other_forward: Vector2 = other._get_path_forward_estimate()
	if my_forward.dot(dir_to_other) <= 0.15: return false
	if other_forward.dot(-dir_to_other) <= 0.15: return false
	var relative_velocity: Vector2 = other.linear_velocity - car.linear_velocity
	var closing_speed: float = -dir_to_other.dot(relative_velocity)
	return closing_speed >= car.avoid_off_cone_min_closing_speed * 0.5

## Keeps side decisions synchronized with blocker state and active pair locks.
func sync_avoid_side_with_blocking_pair(path_forward: Vector2) -> void:
	if car._blocking_car == null or not is_instance_valid(car._blocking_car): return
	var now_ms: int = Time.get_ticks_msec()
	if is_pair_timeout_cooldown_active(car._blocking_car.get_car_id(), now_ms):
		set_pair_timeout_cooldown(car._blocking_car)
		end_avoidance("pair_timeout_cooldown")
		return
	if has_active_pair_assignment(car._blocking_car.get_car_id(), now_ms):
		car._last_avoid_decision_mode = "pair_lock_reuse"
		car._avoid_side_sign = car.get_pair_assigned_side_sign()
		car.set_avoid_time_left(maxf(car.get_avoid_time_left(), car.avoid_sync_min_time_left))
		return
	if not car._blocking_car._is_avoiding or car._blocking_car._blocking_car != car: return
	var other_world_avoid: Vector2 = car._blocking_car._get_current_world_avoid_direction()
	if other_world_avoid == Vector2.ZERO: return
	var previous_side: float = car._avoid_side_sign
	car._avoid_side_sign = side_sign_for_world_direction(-other_world_avoid, path_forward)
	if not is_equal_approx(previous_side, car._avoid_side_sign):
		car._last_avoid_decision_mode = "sync_mirror_blocking_pair"
		car.set_avoid_time_left(maxf(car.get_avoid_time_left(), car.avoid_sync_min_time_left))
		car.log_debug_event("avoid_sync", car._avoid_debug.build_avoidance_event_payload("sync", "mirror_blocking_pair"))

## Returns the current world-space lateral avoidance direction from side sign plus path forward.
func get_current_world_avoid_direction() -> Vector2:
	var path_forward: Vector2 = get_path_forward_estimate()
	if path_forward == Vector2.ZERO: return Vector2.ZERO
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	if lateral == Vector2.ZERO: return Vector2.ZERO
	return (lateral * car._avoid_side_sign).normalized()

## Projects a world direction into local left/right sign relative to path forward.
func side_sign_for_world_direction(world_direction: Vector2, path_forward: Vector2) -> float:
	if world_direction == Vector2.ZERO: return 1.0
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	if lateral == Vector2.ZERO: return 1.0
	var alignment: float = lateral.dot(world_direction.normalized())
	if absf(alignment) < 0.0001: return 1.0
	return 1.0 if alignment > 0.0 else -1.0

## Estimates forward direction from path target first, then velocity fallback.
func get_path_forward_estimate() -> Vector2:
	if car.has_active_path():
		var dir: Vector2 = car.global_position.direction_to(car._current_path[car._path_index])
		if dir != Vector2.ZERO: return dir.normalized()
	if car.linear_velocity.length() > 10.0: return car.linear_velocity.normalized()
	return Vector2.RIGHT

## Resolves head-on side choice deterministically from priority and world reference axis.
func head_on_side_sign(other: NPCCar, path_forward: Vector2) -> float:
	var self_is_high: bool = has_higher_avoid_priority_than(other)
	var low_pos: Vector2 = other.global_position if self_is_high else car.global_position
	var high_pos: Vector2 = car.global_position if self_is_high else other.global_position
	var axis: Vector2 = high_pos - low_pos
	if axis == Vector2.ZERO: axis = Vector2.RIGHT
	var world_ref: Vector2 = Vector2(-axis.y, axis.x).normalized()
	var target_world_dir: Vector2 = world_ref if self_is_high else -world_ref
	var lat: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	if lat == Vector2.ZERO: return 1.0
	var alignment: float = lat.dot(target_world_dir)
	if absf(alignment) < 0.0001: return 1.0
	return 1.0 if alignment > 0.0 else -1.0

## Leaves avoidance mode and resets transient timers/flags.
func end_avoidance(reason: String = "ended") -> void:
	if car._is_avoiding: car.log_debug_event("avoid_end", car._avoid_debug.build_avoidance_event_payload("end", reason))
	car._is_avoiding = false
	car._blocking_car = null
	car.set_avoid_time_left(0.0)
	car._movement_log_time_left = 0.0
	car._avoid_blocked_time = 0.0
	car.set_avoid_timeout_retry_used(false)

## Finds best blocker candidate in front corridor using distance, lateral error, and closing speed.
## Params: path_forward defines forward cone and corridor projection.
## Returns: NPCCar blocker candidate or null when no blocker should be tracked.
func find_blocking_car(path_forward: Vector2) -> NPCCar:
	var closest: NPCCar = null
	var best_score: float = INF
	var cone_cos: float = cos(deg_to_rad(car.avoid_front_cone_degrees))
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	var corridor_half_width: float = effective_blocker_corridor_half_width(path_forward)
	var now_ms: int = Time.get_ticks_msec()
	for node: Node in car.get_tree().get_nodes_in_group("npc_cars"):
		var other: NPCCar = node as NPCCar
		if other == null or other == car: continue
		if is_pair_timeout_cooldown_active(other.get_car_id(), now_ms): continue
		var to_other: Vector2 = other.global_position - car.global_position
		var distance: float = to_other.length()
		if distance <= 0.001 or distance > car.avoid_trigger_distance: continue
		var forward_distance: float = path_forward.dot(to_other)
		if forward_distance <= 0.0: continue
		var lateral_distance: float = absf(lateral.dot(to_other))
		var to_other_dir: Vector2 = to_other / distance
		var relative_velocity: Vector2 = other.linear_velocity - car.linear_velocity
		var closing_speed: float = -to_other_dir.dot(relative_velocity)
		var in_mutual_pair: bool = other._is_avoiding and other._blocking_car == car
		if closing_speed <= 0.0 and distance > car.stop_distance * 1.1 and not in_mutual_pair: continue
		var dir_to_other: Vector2 = to_other / distance
		if path_forward.dot(dir_to_other) < cone_cos:
			if lateral_distance > corridor_half_width or closing_speed < car.avoid_off_cone_min_closing_speed: continue
		var score: float = forward_distance + lateral_distance * 0.8
		if score < best_score:
			best_score = score
			closest = other
	return closest

## Returns deterministic pair-leadership priority (car id, then instance id).
func has_higher_avoid_priority_than(other: NPCCar) -> bool:
	if other == null: return true
	if car.get_car_id() != other.get_car_id(): return car.get_car_id() > other.get_car_id()
	return car.get_instance_id() > other.get_instance_id()

## Builds steer direction toward a forward-plus-lateral temporary avoidance target.
func get_avoidance_direction(path_forward: Vector2) -> Vector2:
	if path_forward == Vector2.ZERO: return path_forward
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x)
	var avoid_target: Vector2 = car.global_position + path_forward.normalized() * car.avoid_forward_distance + lateral.normalized() * car._avoid_side_sign * effective_avoid_lateral_offset(path_forward)
	return car.global_position.direction_to(avoid_target)

## Returns how vertical the current movement is, used to scale anisotropic avoidance.
func vertical_encounter_factor(path_forward: Vector2) -> float:
	if path_forward == Vector2.ZERO: return 0.0
	return clampf(absf(path_forward.normalized().y), 0.0, 1.0)

## Computes effective lateral offset with extra scaling during vertical encounters.
func effective_avoid_lateral_offset(path_forward: Vector2) -> float:
	var vertical_scale: float = maxf(1.0, car.avoid_vertical_lateral_scale)
	return car.avoid_offset_distance * lerpf(1.0, vertical_scale, vertical_encounter_factor(path_forward))

## Computes blocker corridor width, widened for vertical movement cases.
func effective_blocker_corridor_half_width(path_forward: Vector2) -> float:
	var base_width: float = maxf(car.sensor_vertical_offset * 1.8, 22.0)
	var vertical_scale: float = maxf(1.0, car.avoid_vertical_corridor_scale)
	return base_width * lerpf(1.0, vertical_scale, vertical_encounter_factor(path_forward))

## Computes diagnostics metrics (lateral projection now/future and relative closing speed).
## Params: other is the comparison car; path_forward is current owner heading.
## Returns: Dictionary with projection_now, projection_future, and closing_speed.
func build_avoidance_metrics(other: NPCCar, path_forward: Vector2) -> Dictionary:
	if other == null: return {"projection_now": 0.0, "projection_future": 0.0, "closing_speed": 0.0}
	var lateral: Vector2 = Vector2(-path_forward.y, path_forward.x).normalized()
	var my_forward: Vector2 = get_path_forward_estimate()
	var other_forward: Vector2 = other._get_path_forward_estimate()
	var my_speed: float = maxf(car.linear_velocity.length(), car._max_speed * 0.45)
	var other_speed: float = maxf(other.linear_velocity.length(), other._max_speed * 0.45)
	var relative_position: Vector2 = other.global_position - car.global_position
	var relative_velocity: Vector2 = other_forward * other_speed - my_forward * my_speed
	var lookahead_time: float = 0.0
	var rel_vel_len_sq: float = relative_velocity.length_squared()
	if rel_vel_len_sq > 0.001: lookahead_time = clampf(-relative_position.dot(relative_velocity) / rel_vel_len_sq, 0.0, 1.2)
	var future_relative: Vector2 = relative_position + relative_velocity * lookahead_time
	var to_other: Vector2 = relative_position.normalized() if relative_position.length() > 0.001 else Vector2.ZERO
	return {
		"projection_now": lateral.dot(relative_position),
		"projection_future": lateral.dot(future_relative),
		"closing_speed": -to_other.dot(other.linear_velocity - car.linear_velocity),
	}

## Starts deadlock escape mode with a sampled free direction.
func begin_escape(reason: String = "deadlock") -> void:
	car._no_progress_time = 0.0
	var escape_dir: Vector2 = find_escape_direction()
	if escape_dir == Vector2.ZERO: return
	car._is_escaping = true
	car._escape_direction = escape_dir
	car._escape_time_left = car.deadlock_escape_duration
	end_avoidance(reason)

## Ends escape mode and restores progress tracking baseline.
func end_escape() -> void:
	car._is_escaping = false
	car._escape_direction = Vector2.ZERO
	car._escape_time_left = 0.0
	car._no_progress_time = 0.0
	car._last_progress_path_index = car._path_index

## Applies escape steering and re-samples direction when the chosen ray is blocked.
func apply_escape_movement(delta: float) -> void:
	var safety_eval: Dictionary = evaluate_surroundings(car._escape_direction)
	var speed_factor: float = float(safety_eval.get("speed_factor", 1.0))
	var blocked: bool = bool(safety_eval.get("blocked", false))
	if blocked and speed_factor <= 0.01:
		var new_dir: Vector2 = find_escape_direction()
		if new_dir != Vector2.ZERO: car._escape_direction = new_dir
		car.linear_velocity = car.linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
	else:
		var target_velocity: Vector2 = car._escape_direction * car._max_speed * speed_factor
		car.linear_velocity = car.linear_velocity.lerp(target_velocity, delta * car._steering_lerp)
	if car._escape_direction.x != 0.0:
		var facing: float = 1.0 if car._escape_direction.x < 0.0 else -1.0
		car.sprite.scale.x = facing
		car.body_collision.scale.x = facing

## Scans 8 rays and picks the direction with maximum obstacle clearance.
## Returns: normalized escape direction, or Vector2.RIGHT fallback when world state is unavailable.
func find_escape_direction() -> Vector2:
	var world_2d: World2D = car.get_viewport().world_2d if car.get_viewport() != null else null
	if world_2d == null: return Vector2.RIGHT
	var best_direction: Vector2 = Vector2.ZERO
	var best_clearance: float = -1.0
	for i: int in 8:
		var angle: float = TAU * i / 8.0
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var ray_end: Vector2 = car.global_position + dir * car.deadlock_scan_distance
		var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(car.global_position, ray_end)
		query.collision_mask = car.surrounding_collision_mask
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.exclude = [car]
		var hit: Dictionary = world_2d.direct_space_state.intersect_ray(query)
		var clearance: float = car.deadlock_scan_distance
		if not hit.is_empty():
			var collider: Object = hit.get("collider") as Object
			if collider != null and should_treat_as_obstacle(collider): clearance = car.global_position.distance_to(hit.get("position", ray_end))
		if clearance > best_clearance:
			best_clearance = clearance
			best_direction = dir
	return best_direction
