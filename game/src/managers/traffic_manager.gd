extends Node
## Coordinates NPC spawning, destination reservation, despawn policy, and debug telemetry.
class_name TrafficManager

## Responsibilities:
## - spawn/register/despawn NPC cars within dynamic capacity constraints
## - reserve destination nodes to avoid routing conflicts between cars
## - collect optional CSV telemetry for avoidance diagnostics
## Doc convention:
## - First line states intent in one sentence.
## - Optional Params line for non-trivial inputs.
## - Optional Returns line for non-obvious outputs.
## - Keep wording behavior-focused, not implementation-focused.

## Typed preload for runtime traffic network access.
const TrafficNetworkType = preload("res://src/levels/traffic_network.gd")
## Typed preload for traffic node references.
const TrafficNodeType = preload("res://src/levels/traffic_node.gd")
## Typed preload for NPC car instances.
const NPCCarType = preload("res://src/characters/cars/npc_car.gd")

## Scene reference to the active TrafficNetwork node.
@export var traffic_network: Node
## Packed scene used when spawning a new NPC car.
@export var npc_car_scene: PackedScene
## Optional parent node for spawned NPC cars.
@export var npc_root_node: Node2D

## Spawn timer period in seconds.
@export var spawn_interval: float = 10.0
## Upper bound for simultaneously active NPC cars.
@export var max_active_cars: int = 6
## Minimum distance between chosen spawn node and first destination.
@export var min_spawn_to_initial_destination_distance: float = 1200.0
## Minimum player distance required before destination-based despawn is allowed.
@export var despawn_min_distance_to_player: float = 1800.0
## Propagates NPC sensor ray debug rendering to all active cars.
@export var debug_npc_sensor_overlay: bool = false
## Line width used by NPC sensor debug overlay.
@export var debug_npc_sensor_line_width: float = 2.0
## Enables writing structured avoidance telemetry into CSV.
@export var debug_csv_logging_enabled: bool = false
## File path for CSV telemetry output.
@export var debug_csv_log_path: String = "user://logs/npc_avoidance_log.csv"
## Minimum sampling interval for movement/debug CSV rows.
@export var debug_csv_log_interval_seconds: float = 0.25

## Typed runtime network reference after validation.
var _traffic_network: TrafficNetworkType
## Cached destination-eligible traffic nodes.
var _destination_nodes: Array[TrafficNodeType] = []
## Cached spawn-eligible traffic nodes.
var _spawn_nodes: Array[TrafficNodeType] = []
## Current live NPC cars managed by this system.
var _active_cars: Array[NPCCarType] = []
## RNG for spawn and destination selection.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Last applied sensor-overlay value to detect runtime changes.
var _last_debug_npc_sensor_overlay: bool = false
## Last applied sensor-line width to detect runtime changes.
var _last_debug_npc_sensor_line_width: float = 0.0
## Monotonic id source for assigning unique car ids.
var _next_car_id: int = 1
## Reservation map: car id -> destination node.
var _reserved_destination_by_car_id: Dictionary = {}
## Pending release map used while cars leave previously reserved nodes.
var _pending_release_destination_by_car_id: Dictionary = {}
## Reservation owner map: node id -> car id.
var _reserved_destination_owner_by_node_id: Dictionary = {}
## Tracks whether CSV header has been emitted for current file.
var _csv_header_written: bool = false
## Last applied CSV logging toggle for change detection.
var _last_debug_csv_logging_enabled: bool = false

## Spawn timer node driving periodic spawn attempts.
@onready var _spawn_timer: Timer = $SpawnTimer


## Validates dependencies, initializes caches, and waits for network graph readiness.
func _ready() -> void:
	_rng.randomize()
	_last_debug_npc_sensor_overlay = debug_npc_sensor_overlay
	_last_debug_npc_sensor_line_width = debug_npc_sensor_line_width
	_last_debug_csv_logging_enabled = debug_csv_logging_enabled
	if debug_csv_logging_enabled:
		_ensure_csv_logger_ready()

	if traffic_network == null:
		push_error("TrafficManager: 'traffic_network' export is not assigned in the inspector.")
		return

	_traffic_network = traffic_network as TrafficNetworkType
	if _traffic_network == null:
		push_error("TrafficManager: assigned node is not a TrafficNetwork.")
		return

	ManagerHub.set_traffic_manager(self)
	_traffic_network.graph_built.connect(_start, CONNECT_ONE_SHOT)


## Pushes runtime debug-toggle changes to active cars and CSV logger state.
func _process(_delta: float) -> void:
	if _last_debug_csv_logging_enabled != debug_csv_logging_enabled:
		_last_debug_csv_logging_enabled = debug_csv_logging_enabled
		if debug_csv_logging_enabled:
			_ensure_csv_logger_ready()

	if _last_debug_npc_sensor_overlay == debug_npc_sensor_overlay and is_equal_approx(_last_debug_npc_sensor_line_width, debug_npc_sensor_line_width):
		return

	_last_debug_npc_sensor_overlay = debug_npc_sensor_overlay
	_last_debug_npc_sensor_line_width = debug_npc_sensor_line_width
	_apply_debug_visualization_to_all_cars()


## Returns clamped CSV log interval to avoid zero/too-small sampling.
func get_debug_csv_log_interval_seconds() -> float:
	return maxf(0.05, debug_csv_log_interval_seconds)


## Appends one structured NPC debug event row to CSV.
## Params: event_name identifies event type; car is optional source; payload extends columns.
func log_npc_debug_event(event_name: String, car: NPCCarType, payload: Dictionary = {}) -> void:
	if not debug_csv_logging_enabled:
		return
	if event_name.is_empty():
		return
	if not _ensure_csv_logger_ready():
		return

	var date_text: String = Time.get_date_string_from_system()
	var time_text: String = Time.get_time_string_from_system()
	var unix_ms: int = int(round(Time.get_unix_time_from_system() * 1000.0))
	var frame: int = Engine.get_frames_drawn()

	var car_id: int = -1
	var other_car_id: int = -1
	var phase: String = ""
	var avoid_side: float = 0.0
	var blocking_car_id: int = -1
	var pos_x: float = 0.0
	var pos_y: float = 0.0
	var vel_x: float = 0.0
	var vel_y: float = 0.0
	var speed: float = 0.0
	var path_index: int = -1
	var path_size: int = -1
	var target_x: float = 0.0
	var target_y: float = 0.0
	var distance_to_target: float = -1.0
	var projection_now: float = 0.0
	var projection_future: float = 0.0
	var closing_speed: float = 0.0
	var decision_mode: String = ""
	var reason: String = ""

	if car != null and is_instance_valid(car):
		car_id = car.get_car_id()
		pos_x = car.global_position.x
		pos_y = car.global_position.y
		vel_x = car.linear_velocity.x
		vel_y = car.linear_velocity.y
		speed = car.linear_velocity.length()

	if payload.has("other_car_id"):
		other_car_id = int(payload.get("other_car_id"))
	if payload.has("phase"):
		phase = str(payload.get("phase"))
	if payload.has("avoid_side"):
		avoid_side = float(payload.get("avoid_side"))
	if payload.has("blocking_car_id"):
		blocking_car_id = int(payload.get("blocking_car_id"))
	if payload.has("pos_x"):
		pos_x = float(payload.get("pos_x"))
	if payload.has("pos_y"):
		pos_y = float(payload.get("pos_y"))
	if payload.has("vel_x"):
		vel_x = float(payload.get("vel_x"))
	if payload.has("vel_y"):
		vel_y = float(payload.get("vel_y"))
	if payload.has("speed"):
		speed = float(payload.get("speed"))
	if payload.has("path_index"):
		path_index = int(payload.get("path_index"))
	if payload.has("path_size"):
		path_size = int(payload.get("path_size"))
	if payload.has("target_x"):
		target_x = float(payload.get("target_x"))
	if payload.has("target_y"):
		target_y = float(payload.get("target_y"))
	if payload.has("distance_to_target"):
		distance_to_target = float(payload.get("distance_to_target"))
	if payload.has("projection_now"):
		projection_now = float(payload.get("projection_now"))
	if payload.has("projection_future"):
		projection_future = float(payload.get("projection_future"))
	if payload.has("closing_speed"):
		closing_speed = float(payload.get("closing_speed"))
	if payload.has("decision_mode"):
		decision_mode = str(payload.get("decision_mode"))
	if payload.has("reason"):
		reason = str(payload.get("reason"))

	var row: Array = [
		date_text,
		time_text,
		unix_ms,
		frame,
		event_name,
		car_id,
		other_car_id,
		phase,
		avoid_side,
		blocking_car_id,
		pos_x,
		pos_y,
		vel_x,
		vel_y,
		speed,
		path_index,
		path_size,
		target_x,
		target_y,
		distance_to_target,
		projection_now,
		projection_future,
		closing_speed,
		decision_mode,
		reason,
	]
	_append_csv_row(row)


## Ensures log directory/file exist and header is present before writes.
func _ensure_csv_logger_ready() -> bool:
	var base_dir: String = debug_csv_log_path.get_base_dir()
	if not base_dir.is_empty() and not DirAccess.dir_exists_absolute(base_dir):
		var mk_result: int = DirAccess.make_dir_recursive_absolute(base_dir)
		if mk_result != OK:
			push_warning("TrafficManager: failed to create CSV log dir: %s" % base_dir)
			return false

	if _csv_header_written:
		return true

	var file: FileAccess = _open_csv_for_append()
	if file == null:
		push_warning("TrafficManager: failed to open CSV log: %s" % debug_csv_log_path)
		return false

	if file.get_length() <= 0:
		var header: Array = [
			"date",
			"time",
			"unix_ms",
			"frame",
			"event",
			"car_id",
			"other_car_id",
			"phase",
			"avoid_side",
			"blocking_car_id",
			"pos_x",
			"pos_y",
			"vel_x",
			"vel_y",
			"speed",
			"path_index",
			"path_size",
			"target_x",
			"target_y",
			"distance_to_target",
			"projection_now",
			"projection_future",
			"closing_speed",
			"decision_mode",
			"reason",
		]
		file.store_line(_to_csv_line(header))
		file.flush()

	_csv_header_written = true
	return true


## Appends one CSV row to the telemetry file.
func _append_csv_row(values: Array) -> void:
	var file: FileAccess = _open_csv_for_append()
	if file == null:
		push_warning("TrafficManager: failed to append CSV log row.")
		return
	file.store_line(_to_csv_line(values))
	file.flush()


## Opens CSV in append mode (creating file if missing).
func _open_csv_for_append() -> FileAccess:
	if FileAccess.file_exists(debug_csv_log_path):
		var existing_file: FileAccess = FileAccess.open(debug_csv_log_path, FileAccess.READ_WRITE)
		if existing_file != null:
			existing_file.seek_end()
		return existing_file
	return FileAccess.open(debug_csv_log_path, FileAccess.WRITE)


## Serializes an array of values into one escaped CSV line.
func _to_csv_line(values: Array) -> String:
	var cells: Array[String] = []
	for value: Variant in values:
		cells.append(_to_csv_cell(value))
	return ",".join(cells)


## Escapes a single CSV cell, including quotes and line breaks.
func _to_csv_cell(value: Variant) -> String:
	if value == null:
		return ""
	var text: String = str(value)
	text = text.replace("\r", " ").replace("\n", " ")
	if text.contains(",") or text.contains("\""):
		text = text.replace("\"", "\"\"")
		return "\"%s\"" % text
	return text


## Starts runtime traffic systems after graph build and clamps active-car budget.
func _start() -> void:
	_find_destination_nodes()
	_find_spawn_nodes()
	max_active_cars = min(max_active_cars, _get_max_allowed_active_cars())
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.start()
	_register_existing_cars()


## Refreshes destination-node cache from TrafficNetwork.
func _find_destination_nodes() -> void:
	_destination_nodes.clear()
	for node: TrafficNodeType in _traffic_network.get_all_nodes():
		if node != null and node.can_be_destination:
			_destination_nodes.append(node)


## Refreshes spawn-node cache from TrafficNetwork.
func _find_spawn_nodes() -> void:
	_spawn_nodes.clear()
	for node: TrafficNodeType in _traffic_network.get_all_nodes():
		if node != null and node.is_spawn_node:
			_spawn_nodes.append(node)


## Spawn tick: attempts one spawn when capacity and destination constraints allow.
## Trigger: connected to SpawnTimer timeout.
func _on_spawn_timer_timeout() -> void:
	if _traffic_network == null or npc_car_scene == null:
		return
	if _active_cars.size() >= _get_max_allowed_active_cars():
		return
	if _spawn_nodes.is_empty():
		return

	var candidate_spawn_nodes: Array[TrafficNodeType] = _get_spawnable_nodes()
	if candidate_spawn_nodes.is_empty():
		return

	var spawn_node: TrafficNodeType = candidate_spawn_nodes[_rng.randi() % candidate_spawn_nodes.size()]
	_spawn_car_at(spawn_node)


## Instantiates, registers, and assigns first destination to a spawned car.
func _spawn_car_at(spawn_node: TrafficNodeType) -> void:
	var car: NPCCarType = npc_car_scene.instantiate() as NPCCarType
	if car == null:
		push_error("TrafficManager: npc_car_scene is not an NPCCar scene.")
		return

	car.global_position = spawn_node.global_position
	if npc_root_node != null:
		npc_root_node.add_child(car)
	else:
		add_child(car)

	_register_car(car)
	var initial_dest: TrafficNodeType = request_next_destination(car, spawn_node, min_spawn_to_initial_destination_distance)
	if initial_dest != null:
		car.set_new_destination_node(initial_dest)
	else:
		car.queue_free()


## Registers pre-existing scene cars and assigns a destination if missing.
func _register_existing_cars() -> void:
	for node: Node in get_tree().get_nodes_in_group("npc_cars"):
		var car: NPCCarType = node as NPCCarType
		if car == null:
			continue
		_register_car(car)
		if not car.has_active_path():
			var closest_node: TrafficNodeType = request_closest_node(car.global_position)
			var dest: TrafficNodeType = request_next_destination(car, closest_node)
			if dest != null:
				car.set_new_destination_node(dest)


## Registers one car in manager state and wires lifecycle callbacks.
func _register_car(car: NPCCarType) -> void:
	if _active_cars.has(car):
		return
	_active_cars.append(car)
	_assign_car_id(car)
	car.set_traffic_manager(self)
	_apply_debug_visualization_to_car(car)
	if not car.tree_exited.is_connected(_on_car_tree_exited):
		car.tree_exited.connect(_on_car_tree_exited.bind(car))


## Cleans reservations and active list when a car leaves the scene tree.
func _on_car_tree_exited(car: NPCCarType) -> void:
	release_destination_for_car(car)
	_active_cars.erase(car)


## Applies current debug-visualization settings to all active cars.
func _apply_debug_visualization_to_all_cars() -> void:
	for car: NPCCarType in _active_cars:
		if car == null or not is_instance_valid(car):
			continue
		_apply_debug_visualization_to_car(car)


## Applies current debug-visualization settings to one car.
func _apply_debug_visualization_to_car(car: NPCCarType) -> void:
	if car == null:
		return
	car.debug_draw_sensors = debug_npc_sensor_overlay
	car.debug_sensor_line_width = debug_npc_sensor_line_width


## Selects and reserves the next valid destination respecting distance and occupancy constraints.
## Params: avoid_node can exclude a source node; min_distance_from_avoid overrides default distance gate.
## Returns: reserved destination node or null when no valid candidate exists.
func request_next_destination(car: NPCCarType, avoid_node: TrafficNodeType = null, min_distance_from_avoid: float = 0.0) -> TrafficNodeType:
	if _traffic_network == null or _destination_nodes.is_empty() or car == null:
		return null

	var effective_min_distance: float = min_distance_from_avoid
	if effective_min_distance <= 0.0:
		effective_min_distance = min_spawn_to_initial_destination_distance

	var candidates: Array[TrafficNodeType] = _get_free_destination_candidates(car, avoid_node, effective_min_distance)
	if candidates.is_empty():
		return null

	var target: TrafficNodeType = candidates[_rng.randi() % candidates.size()]
	_reserve_destination_for_car(car, target)
	return target


## Returns the currently reserved destination node for the given car.
func get_reserved_destination_for_car(car: NPCCarType) -> TrafficNodeType:
	if car == null:
		return null
	return _reserved_destination_by_car_id.get(car.get_car_id(), null) as TrafficNodeType


## Releases pending reservation once a car has safely left its previous destination node.
func notify_car_passed_first_departure_node(car: NPCCarType) -> void:
	if car == null:
		return
	var car_id: int = car.get_car_id()
	var pending_node: TrafficNodeType = _pending_release_destination_by_car_id.get(car_id, null) as TrafficNodeType
	if pending_node == null:
		return
	_release_node_reservation(pending_node)
	_pending_release_destination_by_car_id.erase(car_id)


## Releases both active and pending reservations owned by a car.
func release_destination_for_car(car: NPCCarType) -> void:
	if car == null:
		return
	var car_id: int = car.get_car_id()
	var current_node: TrafficNodeType = _reserved_destination_by_car_id.get(car_id, null) as TrafficNodeType
	if current_node != null:
		_release_node_reservation(current_node)
		_reserved_destination_by_car_id.erase(car_id)
	var pending_node: TrafficNodeType = _pending_release_destination_by_car_id.get(car_id, null) as TrafficNodeType
	if pending_node != null:
		_release_node_reservation(pending_node)
		_pending_release_destination_by_car_id.erase(car_id)


## Returns true when destination and player-distance rules permit despawning.
## Returns: true only for spawn nodes that are non-critical and far enough from player taxi.
func should_despawn_car_at_destination(car: NPCCarType) -> bool:
	if car == null:
		return false
	if despawn_min_distance_to_player <= 0.0:
		return false

	var destination_node: TrafficNodeType = get_reserved_destination_for_car(car)
	if destination_node == null:
		return false
	if not destination_node.is_spawn_node:
		return false
	if destination_node.no_despawn:
		return false
	if destination_node.get_parking_lot() != null:
		return false
	if destination_node.get_landing_pad() != null:
		return false

	var player_taxi: Node2D = GameData.get_taxi() as Node2D
	if player_taxi == null:
		return false

	var distance_to_player: float = destination_node.global_position.distance_to(player_taxi.global_position)
	return distance_to_player >= despawn_min_distance_to_player


## Despawns a car after releasing reservation ownership.
func despawn_car(car: NPCCarType) -> void:
	if car == null or not is_instance_valid(car):
		return
	release_destination_for_car(car)
	car.queue_free()


## Forwards nearest-node query to TrafficNetwork.
func request_closest_node(world_position: Vector2) -> TrafficNodeType:
	if _traffic_network == null:
		return null
	return _traffic_network.get_closest_node(world_position)


## Forwards world-position path query to TrafficNetwork.
func request_path_between(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	if _traffic_network == null:
		return PackedVector2Array()
	return _traffic_network.get_path_between(from_position, to_position)


## Assigns a stable unique id to car instances that do not have one yet.
func _assign_car_id(car: NPCCarType) -> void:
	if car == null:
		return
	if car.get_car_id() > 0:
		_next_car_id = max(_next_car_id, car.get_car_id() + 1)
		return
	car.set_car_id(_next_car_id)
	_next_car_id += 1


## Returns destination-capacity-derived hard cap for active cars.
func _get_max_allowed_active_cars() -> int:
	return _destination_nodes.size() / 2


## Returns spawn nodes that still allow at least one valid initial destination.
func _get_spawnable_nodes() -> Array[TrafficNodeType]:
	var candidates: Array[TrafficNodeType] = []
	for spawn_node: TrafficNodeType in _spawn_nodes:
		if spawn_node == null:
			continue
		if spawn_node.can_be_destination and (_is_node_reserved(spawn_node) or spawn_node.is_occupied):
			continue
		if _get_free_destination_candidates(null, spawn_node, min_spawn_to_initial_destination_distance).is_empty():
			continue
		candidates.append(spawn_node)
	return candidates


## Filters destination candidates by reservation, occupancy, and min-distance rules.
## Returns: candidate list for routing/reservation (may be empty).
func _get_free_destination_candidates(car: NPCCarType, avoid_node: TrafficNodeType, effective_min_distance: float) -> Array[TrafficNodeType]:
	var candidates: Array[TrafficNodeType] = []
	var requesting_car_id: int = car.get_car_id() if car != null else -1
	for node: TrafficNodeType in _destination_nodes:
		if node == null:
			continue
		if node == avoid_node:
			continue
		if avoid_node != null and effective_min_distance > 0.0 and avoid_node.global_position.distance_to(node.global_position) < effective_min_distance:
			continue
		if _is_node_reserved_by_other_car(node, requesting_car_id):
			continue
		if node.is_occupied and not _is_node_reserved_for_car(node, requesting_car_id):
			continue
		candidates.append(node)
	return candidates


## Moves reservation ownership to new destination and defers release of prior one.
func _reserve_destination_for_car(car: NPCCarType, node: TrafficNodeType) -> void:
	if car == null or node == null:
		return
	var car_id: int = car.get_car_id()
	var current_node: TrafficNodeType = _reserved_destination_by_car_id.get(car_id, null) as TrafficNodeType
	if current_node != null and current_node != node:
		_pending_release_destination_by_car_id[car_id] = current_node
	_reserved_destination_by_car_id[car_id] = node
	_reserved_destination_owner_by_node_id[node.get_instance_id()] = car_id
	if not node.is_occupied:
		node.claim()


## Returns true if any car currently owns this node reservation.
func _is_node_reserved(node: TrafficNodeType) -> bool:
	if node == null:
		return false
	return _reserved_destination_owner_by_node_id.has(node.get_instance_id())


## Returns true if reservation owner is different from the given car id.
func _is_node_reserved_by_other_car(node: TrafficNodeType, car_id: int) -> bool:
	if node == null:
		return false
	var owner: Variant = _reserved_destination_owner_by_node_id.get(node.get_instance_id(), null)
	if owner == null:
		return false
	return int(owner) != car_id


## Returns true if reservation owner matches the given car id.
func _is_node_reserved_for_car(node: TrafficNodeType, car_id: int) -> bool:
	if node == null:
		return false
	var owner: Variant = _reserved_destination_owner_by_node_id.get(node.get_instance_id(), null)
	if owner == null:
		return false
	return int(owner) == car_id


## Clears reservation ownership for a node and marks it as released.
func _release_node_reservation(node: TrafficNodeType) -> void:
	if node == null:
		return
	_reserved_destination_owner_by_node_id.erase(node.get_instance_id())
	node.release()


## Returns route distance between landing pads using traffic-graph path length.
## Returns: INF when graph/path data is unavailable; otherwise total route length in pixels.
func get_distance_between_landing_pads(pad_a: LandingPad, pad_b: LandingPad) -> float:
	if _traffic_network == null:
		return INF
	if pad_a == null or pad_b == null:
		return INF

	var node_a: TrafficNode = pad_a.get_traffic_node()
	var node_b: TrafficNode = pad_b.get_traffic_node()
	if node_a == null or node_b == null:
		return INF

	var path: PackedVector2Array = _traffic_network.get_path_between_nodes(node_a, node_b)
	if path.size() < 2:
		return INF

	var distance: float = 0.0
	for i: int in range(path.size() - 1):
		distance += path[i].distance_to(path[i + 1])
	return distance
