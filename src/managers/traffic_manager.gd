extends Node
class_name TrafficManager

const TrafficNetworkType = preload("res://src/levels/traffic_network.gd")
const TrafficNodeType = preload("res://src/levels/traffic_node.gd")
const NPCCarType = preload("res://src/characters/cars/npc_car.gd")

@export var traffic_network: Node
@export var npc_car_scene: PackedScene
@export var npc_root_node: Node2D

@export var spawn_interval: float = 10.0
@export var max_active_cars: int = 6
@export var min_spawn_to_initial_destination_distance: float = 1200.0
@export var debug_npc_sensor_overlay: bool = false
@export var debug_npc_sensor_line_width: float = 2.0

var _traffic_network: TrafficNetworkType
var _destination_nodes: Array[TrafficNodeType] = []
var _spawn_nodes: Array[TrafficNodeType] = []
var _active_cars: Array[NPCCarType] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_debug_npc_sensor_overlay: bool = false
var _last_debug_npc_sensor_line_width: float = 0.0
var _next_car_id: int = 1
var _reserved_destination_by_car_id: Dictionary = {}
var _pending_release_destination_by_car_id: Dictionary = {}
var _reserved_destination_owner_by_node_id: Dictionary = {}

@onready var _spawn_timer: Timer = $SpawnTimer


## Initializes manager state and waits for the traffic graph to be built.
func _ready() -> void:
	_rng.randomize()
	_last_debug_npc_sensor_overlay = debug_npc_sensor_overlay
	_last_debug_npc_sensor_line_width = debug_npc_sensor_line_width

	if traffic_network == null:
		push_error("TrafficManager: 'traffic_network' export is not assigned in the inspector.")
		return

	_traffic_network = traffic_network as TrafficNetworkType
	if _traffic_network == null:
		push_error("TrafficManager: assigned node is not a TrafficNetwork.")
		return

	ManagerHub.set_traffic_manager(self)
	_traffic_network.graph_built.connect(_start, CONNECT_ONE_SHOT)


## Propagates debug visualization toggles to active NPC cars when values change.
func _process(_delta: float) -> void:
	if _last_debug_npc_sensor_overlay == debug_npc_sensor_overlay and is_equal_approx(_last_debug_npc_sensor_line_width, debug_npc_sensor_line_width):
		return

	_last_debug_npc_sensor_overlay = debug_npc_sensor_overlay
	_last_debug_npc_sensor_line_width = debug_npc_sensor_line_width
	_apply_debug_visualization_to_all_cars()


## Starts runtime systems once the traffic network graph is available.
func _start() -> void:
	_find_destination_nodes()
	_find_spawn_nodes()
	max_active_cars = min(max_active_cars, _get_max_allowed_active_cars())
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.start()
	_register_existing_cars()


## Caches all destination-capable traffic nodes from the network.
func _find_destination_nodes() -> void:
	_destination_nodes.clear()
	for node: TrafficNodeType in _traffic_network.get_all_nodes():
		if node != null and node.can_be_destination:
			_destination_nodes.append(node)


## Caches all spawn-enabled traffic nodes from the network.
func _find_spawn_nodes() -> void:
	_spawn_nodes.clear()
	for node: TrafficNodeType in _traffic_network.get_all_nodes():
		if node != null and node.is_spawn_node:
			_spawn_nodes.append(node)


## Spawns a new NPC car when limits allow it.
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


## Instantiates and registers a car at the given spawn node.
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


## Registers pre-placed cars already present in the scene tree.
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


## Registers a single car and wires manager dependencies and cleanup signals.
func _register_car(car: NPCCarType) -> void:
	if _active_cars.has(car):
		return
	_active_cars.append(car)
	_assign_car_id(car)
	car.set_traffic_manager(self)
	_apply_debug_visualization_to_car(car)
	if not car.tree_exited.is_connected(_on_car_tree_exited):
		car.tree_exited.connect(_on_car_tree_exited.bind(car))


## Handles cleanup when a registered car leaves the scene tree.
func _on_car_tree_exited(car: NPCCarType) -> void:
	release_destination_for_car(car)
	_active_cars.erase(car)


## Applies current debug visualization settings to all active cars.
func _apply_debug_visualization_to_all_cars() -> void:
	for car: NPCCarType in _active_cars:
		if car == null or not is_instance_valid(car):
			continue
		_apply_debug_visualization_to_car(car)


## Applies current debug visualization settings to one car.
func _apply_debug_visualization_to_car(car: NPCCarType) -> void:
	if car == null:
		return
	car.debug_draw_sensors = debug_npc_sensor_overlay
	car.debug_sensor_line_width = debug_npc_sensor_line_width


## Returns a next destination for a car using simple distance and occupancy constraints.
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


## Returns the currently reserved destination node for a car.
func get_reserved_destination_for_car(car: NPCCarType) -> TrafficNodeType:
	if car == null:
		return null
	return _reserved_destination_by_car_id.get(car.get_car_id(), null) as TrafficNodeType


## Releases the previous destination reservation after the car has left it via the new route.
func notify_car_passed_first_departure_node(car: NPCCarType) -> void:
	if car == null:
		return
	var car_id: int = car.get_car_id()
	var pending_node: TrafficNodeType = _pending_release_destination_by_car_id.get(car_id, null) as TrafficNodeType
	if pending_node == null:
		return
	_release_node_reservation(pending_node)
	_pending_release_destination_by_car_id.erase(car_id)


## Releases all destination reservations held by the given car.
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


## Returns the closest traffic node to a world position.
func request_closest_node(world_position: Vector2) -> TrafficNodeType:
	if _traffic_network == null:
		return null
	return _traffic_network.get_closest_node(world_position)


## Returns a traffic-network path between two world positions.
func request_path_between(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	if _traffic_network == null:
		return PackedVector2Array()
	return _traffic_network.get_path_between(from_position, to_position)


## Assigns a stable ascending runtime ID to a car.
func _assign_car_id(car: NPCCarType) -> void:
	if car == null:
		return
	if car.get_car_id() > 0:
		_next_car_id = max(_next_car_id, car.get_car_id() + 1)
		return
	car.set_car_id(_next_car_id)
	_next_car_id += 1


## Returns the maximum number of active cars allowed for the current destination count.
func _get_max_allowed_active_cars() -> int:
	return _destination_nodes.size() / 2


## Returns spawn nodes that currently also have at least one free destination available.
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


## Returns all currently free destination nodes matching the request constraints.
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


## Reserves a destination node for a car and tracks any pending release of its previous destination.
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


## Returns whether a destination node is reserved by any car.
func _is_node_reserved(node: TrafficNodeType) -> bool:
	if node == null:
		return false
	return _reserved_destination_owner_by_node_id.has(node.get_instance_id())


## Returns whether a destination node is reserved by a different car.
func _is_node_reserved_by_other_car(node: TrafficNodeType, car_id: int) -> bool:
	if node == null:
		return false
	var owner: Variant = _reserved_destination_owner_by_node_id.get(node.get_instance_id(), null)
	if owner == null:
		return false
	return int(owner) != car_id


## Returns whether a destination node is reserved for the given car.
func _is_node_reserved_for_car(node: TrafficNodeType, car_id: int) -> bool:
	if node == null:
		return false
	var owner: Variant = _reserved_destination_owner_by_node_id.get(node.get_instance_id(), null)
	if owner == null:
		return false
	return int(owner) == car_id


## Releases a single reserved node and clears its occupied flag.
func _release_node_reservation(node: TrafficNodeType) -> void:
	if node == null:
		return
	_reserved_destination_owner_by_node_id.erase(node.get_instance_id())
	node.release()


## Calculates path distance between two landing pads using traffic-network waypoints.
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
