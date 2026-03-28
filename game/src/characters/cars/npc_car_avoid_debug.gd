extends RefCounted
## Represents the NPCCarAvoidDebug component.
class_name NPCCarAvoidDebug

## Runtime state for car.
var car: NPCCar = null


## Handles setup.
func setup(owner: NPCCar) -> void:
	car = owner


## Builds avoidance event payload data.
func build_avoidance_event_payload(phase: String, reason: String = "", other_car_id_override: int = -2, extras: Dictionary = {}) -> Dictionary:
	if car == null:
		return {}
	var blocker_id: int = _get_active_avoid_other_car_id()
	var other_car_id: int = blocker_id if other_car_id_override == -2 else other_car_id_override
	var payload: Dictionary = {
		"phase": phase,
		"avoid_side": car.get_avoid_side_sign(),
		"blocking_car_id": blocker_id,
		"other_car_id": other_car_id,
		"decision_mode": car.get_last_avoid_decision_mode(),
	}
	if not reason.is_empty():
		payload["reason"] = reason
	for key: Variant in extras.keys():
		payload[key] = extras[key]
	return payload


## Handles maybe log movement sample.
func maybe_log_movement_sample(delta: float, target: Vector2, speed_factor: float, blocked: bool) -> void:
	if car == null:
		return
	if not car.is_avoiding_active():
		car.reset_avoid_logging_timers()
		return
	if blocked and speed_factor <= 0.01:
		var blocked_time: float = car.add_avoid_blocked_time(delta)
		if blocked_time >= maxf(0.15, car.avoid_blocked_escape_seconds):
			car.set_last_avoid_decision_mode("blocked_stuck_escape")
			car.set_pair_timeout_cooldown_for_current_blocker()
			car.begin_escape_from_avoidance("blocked_stuck")
			return
	else:
		car.reset_avoid_blocked_time()
	var interval: float = _get_debug_log_interval_seconds()
	if interval <= 0.0:
		return
	var time_left: float = car.add_movement_log_time_left(-delta)
	if time_left > 0.0:
		return
	car.set_movement_log_time_left(interval)
	car.log_debug_event("avoid_move", build_avoidance_event_payload("sample", "blocked=%s speed_factor=%.3f" % [str(blocked), speed_factor], -2, {
		"path_index": car.get_path_index(),
		"path_size": car.get_path_size(),
		"target_x": target.x,
		"target_y": target.y,
		"distance_to_target": car.global_position.distance_to(target),
	}))


## Returns debug log interval seconds.
func _get_debug_log_interval_seconds() -> float:
	if car != null:
		return car.get_debug_log_interval_seconds()
	return 0.25


## Returns active avoid other car id.
func _get_active_avoid_other_car_id() -> int:
	if car == null:
		return -1
	return car.get_active_avoid_blocking_car_id()
