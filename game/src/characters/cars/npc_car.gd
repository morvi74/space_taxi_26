extends RigidBody2D
## Represents the NPCCar component.
class_name NPCCar

## Responsibilities:
## - orchestrate route following, avoidance, and flight/landing controllers
## - expose stable runtime API for manager/controller interactions
## - own transient movement/reservation state for one NPC vehicle
## Doc convention:
## - First line states intent in one sentence.
## - Optional Params line for non-trivial inputs.
## - Optional Returns line for non-obvious outputs.
## - Keep wording behavior-focused, not implementation-focused.

## Shared constant for avoid debug type.
const AvoidDebugType = preload("res://src/characters/cars/npc_car_avoid_debug.gd")
## Shared constant for flight controller type.
const FlightControllerType = preload("res://src/characters/cars/npc_car_flight_controller.gd")
## Shared constant for avoidance controller type.
const AvoidanceControllerType = preload("res://src/characters/cars/npc_car_avoidance_controller.gd")

## Emitted when destination reached.
signal destination_reached(car: NPCCar)

## Cached node reference for sprite.
@onready var sprite: Sprite2D = $Sprite2D
## Cached node reference for landing gear root.
@onready var landing_gear_root: Node2D = $LandingGearRoot
## Cached node reference for body collision.
@onready var body_collision: CollisionPolygon2D = $CollisionPolygon2D
## Cached node reference for gear collision.
@onready var gear_collision: CollisionShape2D = $GearCollision
## Cached node reference for center ray.
@onready var center_ray: RayCast2D = $LandingGearRoot/CenterRay
## Cached node reference for id label.
@onready var id_label: Label = $IdLabel

@export_group("Flight")
## Inspector setting for max speed.
@export var _max_speed: float = 200.0
## Inspector setting for arrival tolerance.
@export var _arrival_tolerance: float = 20.0
## Inspector setting for steering lerp.
@export var _steering_lerp: float = 5.0

@export_group("Sensors")
## Inspector setting for surrounding collision mask.
@export var surrounding_collision_mask: int = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 4) | (1 << 6)
## Inspector setting for caution distance.
@export var caution_distance: float = 140.0
## Inspector setting for stop distance.
@export var stop_distance: float = 52.0
## Inspector setting for sensor vertical offset.
@export var sensor_vertical_offset: float = 16.0
## Inspector setting for sensor lane count.
@export var sensor_lane_count: int = 5
## Inspector setting for caution reaction time.
@export var caution_reaction_time: float = 0.45

@export_group("Avoidance")
## Inspector setting for avoid trigger distance.
@export var avoid_trigger_distance: float = 90.0
## Inspector setting for avoid resume distance.
@export var avoid_resume_distance: float = 130.0
## Inspector setting for avoid offset distance.
@export var avoid_offset_distance: float = 34.0
## Inspector setting for avoid forward distance.
@export var avoid_forward_distance: float = 44.0
## Inspector setting for avoid speed factor.
@export var avoid_speed_factor: float = 0.72
## Inspector setting for avoid max time.
@export var avoid_max_time: float = 1.4
## Inspector setting for avoid front cone degrees.
@export var avoid_front_cone_degrees: float = 50.0
## Inspector setting for avoid lateral now threshold.
@export var avoid_lateral_now_threshold: float = 6.0
## Inspector setting for avoid off cone min closing speed.
@export var avoid_off_cone_min_closing_speed: float = 4.0
## Inspector setting for avoid pair lock seconds.
@export var avoid_pair_lock_seconds: float = 0.45
## Inspector setting for avoid timeout pair cooldown seconds.
@export var avoid_timeout_pair_cooldown_seconds: float = 0.9
## Inspector setting for avoid blocked escape seconds.
@export var avoid_blocked_escape_seconds: float = 0.45
## Inspector setting for avoid timeout flip retry enabled.
@export var avoid_timeout_flip_retry_enabled: bool = true
## Inspector setting for avoid timeout flip retry time factor.
@export var avoid_timeout_flip_retry_time_factor: float = 0.55
## Inspector setting for avoid timeout retry min seconds.
@export var avoid_timeout_retry_min_seconds: float = 0.32
## Inspector setting for avoid sync min time left.
@export var avoid_sync_min_time_left: float = 0.28
## Inspector setting for avoid clear max closing speed.
@export var avoid_clear_max_closing_speed: float = 2.5
## Inspector setting for avoid clear forward factor.
@export var avoid_clear_forward_factor: float = 0.35
## Inspector setting for avoid vertical lateral scale.
@export var avoid_vertical_lateral_scale: float = 1.9
## Inspector setting for avoid vertical corridor scale.
@export var avoid_vertical_corridor_scale: float = 1.7

@export_group("Landing Gear")
## Inspector setting for top gear y position.
@export var _top_gear_y_position: float = 7.0
## Inspector setting for bottom gear y position.
@export var _bottom_gear_y_position: float = 21.0
## Inspector setting for gear transition duration.
@export var gear_transition_duration: float = 0.5
## Inspector setting for gear blocked min descent speed.
@export var gear_blocked_min_descent_speed: float = 22.0

@export_group("Lot Landing")
## Inspector setting for lot landing start distance.
@export var lot_landing_start_distance: float = 64.0
## Inspector setting for lot hover height.
@export var lot_hover_height: float = 30.0
## Inspector setting for lot hover speed factor.
@export var lot_hover_speed_factor: float = 0.35
## Inspector setting for lot touchdown speed.
@export var lot_touchdown_speed: float = 60.0
## Inspector setting for lot landed hold time.
@export var lot_landed_hold_time: float = 0.15
## Inspector setting for lot wait time min.
@export var lot_wait_time_min: float = 15.0
## Inspector setting for lot wait time max.
@export var lot_wait_time_max: float = 30.0

@export_group("Takeoff")
## Inspector setting for takeoff impulse speed.
@export var takeoff_impulse_speed: float = 120.0
## Inspector setting for takeoff clearance height.
@export var takeoff_clearance_height: float = 24.0

@export_group("Deadlock Recovery")
## Inspector setting for deadlock timeout.
@export var deadlock_timeout: float = 10.0
## Inspector setting for deadlock escape duration.
@export var deadlock_escape_duration: float = 1.0
## Inspector setting for deadlock scan distance.
@export var deadlock_scan_distance: float = 200.0

@export_group("Debug")
## Inspector setting for debug draw sensors.
@export var debug_draw_sensors: bool = false
## Inspector setting for debug sensor line width.
@export var debug_sensor_line_width: float = 2.0

## Internal state for traffic manager.
var _traffic_manager: Node = null
## Internal state for car id.
var _car_id: int = 0
## Internal state for destination node.
var _destination_node: TrafficNode = null
## Internal state for current path.
var _current_path: PackedVector2Array = PackedVector2Array()
## Internal state for path index.
var _path_index: int = 0
## Internal state for should notify departure release.
var _should_notify_departure_release: bool = false
## Internal state for is avoiding.
var _is_avoiding: bool = false
## Internal state for avoid side sign.
var _avoid_side_sign: float = 1.0
## Internal state for avoid time left.
var _avoid_time_left: float = 0.0
## Internal state for blocking car.
var _blocking_car: NPCCar = null
## Internal state for no progress time.
var _no_progress_time: float = 0.0
## Internal state for last progress path index.
var _last_progress_path_index: int = -1
## Internal state for is escaping.
var _is_escaping: bool = false
## Internal state for escape direction.
var _escape_direction: Vector2 = Vector2.ZERO
## Internal state for escape time left.
var _escape_time_left: float = 0.0
## Internal state for rng.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

enum FlightPhase { CRUISE, APPROACH_HOVER, GEAR_DEPLOYING, DESCENDING, LANDED, TAKEOFF }

## Internal state for flight phase.
var _flight_phase: FlightPhase = FlightPhase.CRUISE
## Internal state for landing target position.
var _landing_target_position: Vector2 = Vector2.ZERO
## Internal state for hover target position.
var _hover_target_position: Vector2 = Vector2.ZERO
## Internal state for landed time left.
var _landed_time_left: float = 0.0
## Internal state for takeoff origin y.
var _takeoff_origin_y: float = 0.0
## Internal state for takeoff impulse pending.
var _takeoff_impulse_pending: bool = false
## Internal state for gear transition active.
var _gear_transition_active: bool = false
## Internal state for gear transition elapsed.
var _gear_transition_elapsed: float = 0.0
## Internal state for gear transition from y.
var _gear_transition_from_y: float = 0.0
## Internal state for gear transition to y.
var _gear_transition_to_y: float = 0.0
## Internal state for movement log time left.
var _movement_log_time_left: float = 0.0
## Internal state for last avoid decision mode.
var _last_avoid_decision_mode: String = "unknown"
## Internal state for pair partner car id.
var _pair_partner_car_id: int = -1
## Internal state for pair assigned side sign.
var _pair_assigned_side_sign: float = 1.0
## Internal state for pair assignment expire ms.
var _pair_assignment_expire_ms: int = 0
## Internal state for pair cooldown partner car id.
var _pair_cooldown_partner_car_id: int = -1
## Internal state for pair cooldown until ms.
var _pair_cooldown_until_ms: int = 0
## Internal state for avoid blocked time.
var _avoid_blocked_time: float = 0.0
## Internal state for avoid timeout retry used.
var _avoid_timeout_retry_used: bool = false
## Internal state for avoid debug.
var _avoid_debug: NPCCarAvoidDebug = null
## Internal state for flight controller.
var _flight_controller: NPCCarFlightController = null
## Internal state for avoidance controller.
var _avoidance_controller: NPCCarAvoidanceController = null

## Initializes controller components, physics defaults, and runtime RNG state.
func _ready() -> void:
	lock_rotation = true
	linear_damp = 2.0
	add_to_group("npc_cars")
	_flight_controller = FlightControllerType.new()
	_flight_controller.setup(self)
	_avoidance_controller = AvoidanceControllerType.new()
	_avoidance_controller.setup(self)
	_set_gear_y(_top_gear_y_position)
	_rng.randomize()
	_avoid_debug = AvoidDebugType.new()
	_avoid_debug.setup(self)

## Injects TrafficManager reference used for pathing, destination, and debug callbacks.
func set_traffic_manager(manager: Node) -> void: _traffic_manager = manager
## Updates car id.
func set_car_id(value: int) -> void: _car_id = value; id_label.text = str(value)
## Returns car id.
func get_car_id() -> int: return _car_id
## Returns destination node.
func get_destination_node() -> TrafficNode: return _destination_node
## Checks whether active path is available.
func has_active_path() -> bool: return not _current_path.is_empty() and _path_index < _current_path.size()

## Replaces destination, requests a new path, and resets progress/escape state.
## Params: destination_node target node (null clears current destination/path).
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

## Main per-tick movement loop: path advance, deadlock handling, avoidance, and steering.
## Params: delta physics-step duration in seconds.
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
		if _escape_time_left <= 0.0: _end_escape()
		else: _apply_escape_movement(delta)
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
		if _should_notify_departure_release and _path_index >= 1: _notify_passed_first_departure_node()
		if _path_index >= _current_path.size():
			_current_path = PackedVector2Array()
			_path_index = 0
			linear_velocity = Vector2.ZERO
			destination_reached.emit(self)
			if _try_despawn_after_destination_reached(): return
			_request_next_destination()
			return
		target = _current_path[_path_index]
	if _path_index == _current_path.size() - 1 and _can_land_at_current_destination() and global_position.distance_to(target) <= lot_landing_start_distance:
		_begin_landing_sequence()
		return
	var direction: Vector2 = global_position.direction_to(target)
	_update_avoidance(direction)
	if _is_avoiding: direction = _get_avoidance_direction(direction)
	var safety_eval: Dictionary = _evaluate_surroundings(direction)
	var speed_factor: float = float(safety_eval.get("speed_factor", 1.0))
	var blocked: bool = bool(safety_eval.get("blocked", false))
	if _is_avoiding: speed_factor = minf(speed_factor, avoid_speed_factor)
	var target_velocity: Vector2 = direction * _max_speed * speed_factor
	if blocked and speed_factor <= 0.01: target_velocity = Vector2.ZERO
	target_velocity = _apply_gear_vertical_constraint(target_velocity, false)
	linear_velocity = linear_velocity.lerp(target_velocity, delta * _steering_lerp)
	_avoid_debug.maybe_log_movement_sample(delta, target, speed_factor, blocked)
	if direction.x != 0.0:
		var facing: float = 1.0 if direction.x < 0.0 else -1.0
		sprite.scale.x = facing
		body_collision.scale.x = facing

## Requests and applies the next destination from TrafficManager when available.
func _request_next_destination() -> void:
	if _traffic_manager == null or not _traffic_manager.has_method("request_next_destination"): return
	var next_dest: TrafficNode = _traffic_manager.request_next_destination(self)
	if next_dest != null: set_new_destination_node(next_dest)

## Asks manager whether this car should despawn at destination and executes despawn if allowed.
## Returns: true if despawn was triggered.
func _try_despawn_after_destination_reached() -> bool:
	if _traffic_manager == null: return false
	if not _traffic_manager.has_method("should_despawn_car_at_destination"): return false
	if not _traffic_manager.has_method("despawn_car"): return false
	if not bool(_traffic_manager.should_despawn_car_at_destination(self)): return false
	_traffic_manager.despawn_car(self)
	return true

## Internal helper to trim leading path points already within arrival tolerance.
func _trim_leading_path_points() -> void:
	if _current_path.is_empty(): return
	while _current_path.size() > 1 and global_position.distance_to(_current_path[0]) <= _arrival_tolerance:
		_current_path.remove_at(0)

## Notifies listeners about passed first departure node.
func _notify_passed_first_departure_node() -> void:
	_should_notify_departure_release = false
	if _traffic_manager == null or not _traffic_manager.has_method("notify_car_passed_first_departure_node"): return
	_traffic_manager.notify_car_passed_first_departure_node(self)

## Delegates obstacle-lane evaluation to avoidance controller.
## Returns: Dictionary with speed_factor and blocked keys.
func _evaluate_surroundings(forward_hint: Vector2) -> Dictionary: return _avoidance_controller.evaluate_surroundings(forward_hint)
## Delegates avoidance state update to avoidance controller.
func _update_avoidance(path_forward: Vector2) -> void: _avoidance_controller.update_avoidance(path_forward)
## Internal helper to receive pair side assignment from another car.
func _receive_pair_assignment_from_leader(leader: NPCCar, side_sign: float, expire_ms: int) -> void: _avoidance_controller.receive_pair_assignment_from_leader(leader, side_sign, expire_ms)
## Returns current world avoid direction.
func _get_current_world_avoid_direction() -> Vector2: return _avoidance_controller.get_current_world_avoid_direction()
## Returns path forward estimate.
func _get_path_forward_estimate() -> Vector2: return _avoidance_controller.get_path_forward_estimate()
## Internal helper for deterministic side selection in head-on encounters.
func _head_on_side_sign(other: NPCCar, path_forward: Vector2) -> float: return _avoidance_controller.head_on_side_sign(other, path_forward)
## Returns true if this car has higher pair-priority than the other car.
func _has_higher_avoid_priority_than(other: NPCCar) -> bool: return _avoidance_controller.has_higher_avoid_priority_than(other)
## Returns avoidance direction.
func _get_avoidance_direction(path_forward: Vector2) -> Vector2: return _avoidance_controller.get_avoidance_direction(path_forward)
## Builds avoidance metrics data.
func _build_avoidance_metrics(other: NPCCar, path_forward: Vector2) -> Dictionary: return _avoidance_controller.build_avoidance_metrics(other, path_forward)
## Ends avoidance.
func _end_avoidance(reason: String = "ended") -> void: _avoidance_controller.end_avoidance(reason)
## Starts escape.
func _begin_escape(reason: String = "deadlock") -> void: _avoidance_controller.begin_escape(reason)
## Ends escape.
func _end_escape() -> void: _avoidance_controller.end_escape()
## Applies escape movement.
func _apply_escape_movement(delta: float) -> void: _avoidance_controller.apply_escape_movement(delta)
## Finds escape direction.
func _find_escape_direction() -> Vector2: return _avoidance_controller.find_escape_direction()
## Updates pair timeout cooldown.
func _set_pair_timeout_cooldown(partner: NPCCar) -> void: _avoidance_controller.set_pair_timeout_cooldown(partner)

## Logs debug event for diagnostics.
func _log_debug_event(event_name: String, payload: Dictionary = {}) -> void:
	if _traffic_manager == null or not _traffic_manager.has_method("log_npc_debug_event"): return
	_traffic_manager.log_npc_debug_event(event_name, self, payload)
## Logs debug event for diagnostics.
func log_debug_event(event_name: String, payload: Dictionary = {}) -> void: _log_debug_event(event_name, payload)

## Delegates flight-phase state machine update to flight controller.
## Returns: true when flight controller handled movement this tick.
func _update_special_flight_phases(delta: float) -> bool:
	if _flight_controller == null: return false
	return _flight_controller.update_special_flight_phases(delta)
## Checks whether the object can land at current destination.
func _can_land_at_current_destination() -> bool:
	if _flight_controller == null: return false
	return _flight_controller.can_land_at_current_destination()
## Starts landing sequence.
func _begin_landing_sequence() -> void:
	if _flight_controller != null: _flight_controller.begin_landing_sequence()
## Starts takeoff from lot.
func _begin_takeoff_from_lot() -> void:
	if _flight_controller != null: _flight_controller.begin_takeoff_from_lot()
## Internal helper to complete destination logic after touchdown.
func _complete_destination_after_landing() -> void:
	if _flight_controller != null: _flight_controller.complete_destination_after_landing()
## Returns lot wait time seconds.
func _get_lot_wait_time_seconds() -> float:
	if _flight_controller == null: return 0.0
	return _flight_controller.get_lot_wait_time_seconds()
## Internal helper to start gear transition toward deployed/retracted target.
func _start_gear_transition(deploy_to_bottom: bool) -> void:
	if _flight_controller != null: _flight_controller.start_gear_transition(deploy_to_bottom)
## Updates gear transition each frame.
func _update_gear_transition(delta: float) -> void:
	if _flight_controller != null: _flight_controller.update_gear_transition(delta)
## Updates gear y.
func _set_gear_y(y: float) -> void:
	if _flight_controller != null: _flight_controller.set_gear_y(y)
## Internal helper to snap touchdown height to destination surface.
func _snap_touchdown_to_ground() -> void:
	if _flight_controller != null: _flight_controller.snap_touchdown_to_ground()
## Returns destination surface top y.
func _get_destination_surface_top_y() -> float:
	if _flight_controller == null: return INF
	return _flight_controller.get_destination_surface_top_y()
## Returns surface top y.
func _get_surface_top_y(surface: Node2D) -> float:
	if _flight_controller == null: return INF
	return _flight_controller.get_surface_top_y(surface)
## Returns gear bottom local y.
func _get_gear_bottom_local_y() -> float:
	if _flight_controller == null: return landing_gear_root.position.y + center_ray.position.y
	return _flight_controller.get_gear_bottom_local_y()
## Checks whether gear deployed.
func _is_gear_deployed() -> bool:
	if _flight_controller == null: return landing_gear_root.position.y >= (_bottom_gear_y_position - 0.1)
	return _flight_controller.is_gear_deployed()
## Checks whether gear retracted.
func _is_gear_retracted() -> bool:
	if _flight_controller == null: return landing_gear_root.position.y <= (_top_gear_y_position + 0.1)
	return _flight_controller.is_gear_retracted()
## Internal helper that reports whether current gear state should block upward lift.
func _gear_blocks_vertical_lift() -> bool:
	if _flight_controller == null: return not _is_gear_retracted()
	return _flight_controller.gear_blocks_vertical_lift()
## Delegates gear-dependent vertical velocity clamp to flight controller.
## Returns: constrained target velocity.
func _apply_gear_vertical_constraint(target_velocity: Vector2, allow_takeoff_override: bool) -> Vector2:
	if _flight_controller == null:
		if allow_takeoff_override: return target_velocity
		if _gear_blocks_vertical_lift() and target_velocity.y < gear_blocked_min_descent_speed: target_velocity.y = gear_blocked_min_descent_speed
		return target_velocity
	return _flight_controller.apply_gear_vertical_constraint(target_velocity, allow_takeoff_override)

## Returns the currently tracked blocking car during active avoidance, else null.
func get_active_avoid_blocking_car() -> NPCCar:
	if _blocking_car == null or not is_instance_valid(_blocking_car): return null
	return _blocking_car
## Returns active avoid blocking car id.
func get_active_avoid_blocking_car_id() -> int:
	var blocker: NPCCar = get_active_avoid_blocking_car()
	if blocker == null: return -1
	return blocker.get_car_id()
## Returns avoid side sign.
func get_avoid_side_sign() -> float: return _avoid_side_sign
## Returns last avoid decision mode.
func get_last_avoid_decision_mode() -> String: return _last_avoid_decision_mode
## Updates last avoid decision mode.
func set_last_avoid_decision_mode(mode: String) -> void: _last_avoid_decision_mode = mode
## Checks whether avoiding active.
func is_avoiding_active() -> bool: return _is_avoiding
## Resets avoid logging timers.
func reset_avoid_logging_timers() -> void: _movement_log_time_left = 0.0; _avoid_blocked_time = 0.0
## Resets avoid blocked time.
func reset_avoid_blocked_time() -> void: _avoid_blocked_time = 0.0
## Adds avoid blocked time.
func add_avoid_blocked_time(delta: float) -> float: _avoid_blocked_time += delta; return _avoid_blocked_time
## Returns avoid blocked time.
func get_avoid_blocked_time() -> float: return _avoid_blocked_time
## Updates pair timeout cooldown for current blocker.
func set_pair_timeout_cooldown_for_current_blocker() -> void: _set_pair_timeout_cooldown(_blocking_car)
## Starts escape from avoidance.
func begin_escape_from_avoidance(reason: String) -> void: _begin_escape(reason)
## Returns manager-provided CSV debug interval, with local fallback when manager is absent.
func get_debug_log_interval_seconds() -> float:
	if _traffic_manager != null and _traffic_manager.has_method("get_debug_csv_log_interval_seconds"):
		return float(_traffic_manager.get_debug_csv_log_interval_seconds())
	return 0.25
## Returns movement log time left.
func get_movement_log_time_left() -> float: return _movement_log_time_left
## Adds movement log time left.
func add_movement_log_time_left(delta: float) -> float: _movement_log_time_left += delta; return _movement_log_time_left
## Updates movement log time left.
func set_movement_log_time_left(value: float) -> void: _movement_log_time_left = value
## Returns path index.
func get_path_index() -> int: return _path_index
## Returns path size.
func get_path_size() -> int: return _current_path.size()
## Clears active path/progress counters after landing completion.
func reset_path_state_after_landing() -> void:
	_current_path = PackedVector2Array()
	_path_index = 0
	_no_progress_time = 0.0
	_last_progress_path_index = -1
## Requests next destination from the manager.
func request_next_destination() -> void: _request_next_destination()
## Attempts to despawn after destination reached.
func try_despawn_after_destination_reached() -> bool: return _try_despawn_after_destination_reached()
## Returns flight phase.
func get_flight_phase() -> FlightPhase: return _flight_phase
## Updates flight phase.
func set_flight_phase(phase: FlightPhase) -> void: _flight_phase = phase
## Returns hover target position.
func get_hover_target_position() -> Vector2: return _hover_target_position
## Updates hover target position.
func set_hover_target_position(value: Vector2) -> void: _hover_target_position = value
## Returns landing target position.
func get_landing_target_position() -> Vector2: return _landing_target_position
## Updates landing target position.
func set_landing_target_position(value: Vector2) -> void: _landing_target_position = value
## Returns landed time left.
func get_landed_time_left() -> float: return _landed_time_left
## Updates landed time left.
func set_landed_time_left(value: float) -> void: _landed_time_left = value
## Adds landed time left.
func add_landed_time_left(delta: float) -> float: _landed_time_left += delta; return _landed_time_left
## Returns takeoff origin y.
func get_takeoff_origin_y() -> float: return _takeoff_origin_y
## Updates takeoff origin y.
func set_takeoff_origin_y(value: float) -> void: _takeoff_origin_y = value
## Checks whether takeoff impulse pending.
func is_takeoff_impulse_pending() -> bool: return _takeoff_impulse_pending
## Updates takeoff impulse pending.
func set_takeoff_impulse_pending(value: bool) -> void: _takeoff_impulse_pending = value
## Checks whether gear transition active.
func is_gear_transition_active() -> bool: return _gear_transition_active
## Returns escape direction.
func get_escape_direction() -> Vector2: return _escape_direction
## Updates escape direction.
func set_escape_direction(value: Vector2) -> void: _escape_direction = value
## Clears escape for landing.
func clear_escape_for_landing() -> void: _is_escaping = false; _escape_time_left = 0.0
## Ends avoidance for landing.
func end_avoidance_for_landing() -> void: _end_avoidance()
## Returns max speed.
func get_max_speed() -> float: return _max_speed
## Returns arrival tolerance.
func get_arrival_tolerance() -> float: return _arrival_tolerance
## Returns steering lerp.
func get_steering_lerp() -> float: return _steering_lerp
## Returns random wait duration sampled from inclusive [min_value, max_value] bounds.
func get_random_wait_range(min_value: float, max_value: float) -> float: return _rng.randf_range(min_value, max_value)
## Starts gear transition state.
func begin_gear_transition_state(from_y: float, to_y: float) -> void:
	_gear_transition_active = true
	_gear_transition_elapsed = 0.0
	_gear_transition_from_y = from_y
	_gear_transition_to_y = to_y
## Adds gear transition elapsed.
func add_gear_transition_elapsed(delta: float) -> float: _gear_transition_elapsed += delta; return _gear_transition_elapsed
## Returns gear transition elapsed.
func get_gear_transition_elapsed() -> float: return _gear_transition_elapsed
## Returns gear transition from y.
func get_gear_transition_from_y() -> float: return _gear_transition_from_y
## Returns gear transition to y.
func get_gear_transition_to_y() -> float: return _gear_transition_to_y
## Finishes gear transition state.
func finish_gear_transition_state() -> void: _gear_transition_active = false
## Returns top gear y position.
func get_top_gear_y_position() -> float: return _top_gear_y_position
## Returns bottom gear y position.
func get_bottom_gear_y_position() -> float: return _bottom_gear_y_position

## Returns avoid time left.
func get_avoid_time_left() -> float: return _avoid_time_left
## Updates avoid time left.
func set_avoid_time_left(value: float) -> void: _avoid_time_left = value
## Adds avoid time left.
func add_avoid_time_left(delta: float) -> float: _avoid_time_left += delta; return _avoid_time_left
## Checks whether avoid timeout retry used.
func is_avoid_timeout_retry_used() -> bool: return _avoid_timeout_retry_used
## Updates avoid timeout retry used.
func set_avoid_timeout_retry_used(value: bool) -> void: _avoid_timeout_retry_used = value
## Returns pair assigned side sign.
func get_pair_assigned_side_sign() -> float: return _pair_assigned_side_sign
## Returns pair assignment expire ms.
func get_pair_assignment_expire_ms() -> int: return _pair_assignment_expire_ms
## Returns pair partner car id.
func get_pair_partner_car_id() -> int: return _pair_partner_car_id
## Updates pair assignment data.
func set_pair_assignment_data(partner_car_id: int, side_sign: float, expire_ms: int) -> void:
	_pair_partner_car_id = partner_car_id
	_pair_assigned_side_sign = side_sign
	_pair_assignment_expire_ms = expire_ms
## Returns pair cooldown partner car id.
func get_pair_cooldown_partner_car_id() -> int: return _pair_cooldown_partner_car_id
## Returns pair cooldown until ms.
func get_pair_cooldown_until_ms() -> int: return _pair_cooldown_until_ms
## Updates pair cooldown data.
func set_pair_cooldown_data(partner_car_id: int, until_ms: int) -> void:
	_pair_cooldown_partner_car_id = partner_car_id
	_pair_cooldown_until_ms = until_ms
