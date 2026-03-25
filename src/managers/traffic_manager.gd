extends Node
class_name TrafficManager

const TrafficNetworkType = preload("res://src/levels/traffic_network.gd")
const TrafficNodeType = preload("res://src/levels/traffic_node.gd")
const NPCCarType = preload("res://src/characters/cars/npc_car.gd")
const ParkingLotType = preload("res://src/objects/parking_lot.gd")

@export var traffic_network: Node
@export var npc_car_scene: PackedScene
@export var npc_root_node: Node2D
@export var player_camera_path: NodePath
@export var player_node_path: NodePath

@export var spawn_interval: float = 10
@export var despawn_check_interval: float = 0.6
@export var max_active_cars: int = 6
@export var min_spawn_distance_to_player: float = 140.0
@export var min_spawn_to_initial_destination_distance: float = 1200.0
@export var despawn_node_distance: float = 26.0
@export var building_collision_mask: int = 1 << 1 # Layer 2
@export var debug_npc_sensor_overlay: bool = false
@export var debug_npc_sensor_line_width: float = 2.0

var _traffic_network: TrafficNetworkType
var _destination_nodes: Array[TrafficNodeType] = []
var _spawn_nodes: Array[TrafficNodeType] = []
var _player_camera: Camera2D
var _player_node: Node2D
var _active_cars: Array[NPCCarType] = []
var _rng := RandomNumberGenerator.new()
var _last_debug_npc_sensor_overlay: bool = false
var _last_debug_npc_sensor_line_width: float = 0.0

@onready var _spawn_timer: Timer = $SpawnTimer
#@onready var _despawn_timer: Timer = $DespawnTimer

func _ready() -> void:
	_rng.randomize()
	_last_debug_npc_sensor_overlay = debug_npc_sensor_overlay
	_last_debug_npc_sensor_line_width = debug_npc_sensor_line_width
	_player_camera = _resolve_player_camera()
	_player_node = _resolve_player_node()

	if traffic_network == null:
		push_error("TrafficManager: 'traffic_network' export is not assigned in the inspector.")
		return

	_traffic_network = traffic_network as TrafficNetworkType
	if _traffic_network == null:
		push_error("TrafficManager: assigned node is not a TrafficNetwork.")
		return

	ManagerHub.set_traffic_manager(self)
	# Wait for TrafficNetwork to finish its deferred async graph build before starting.
	_traffic_network.graph_built.connect(_start, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	if _last_debug_npc_sensor_overlay == debug_npc_sensor_overlay and is_equal_approx(_last_debug_npc_sensor_line_width, debug_npc_sensor_line_width):
		return

	_last_debug_npc_sensor_overlay = debug_npc_sensor_overlay
	_last_debug_npc_sensor_line_width = debug_npc_sensor_line_width
	_apply_debug_visualization_to_all_cars()


func _start() -> void:	
	_find_destination_nodes()
	print("TrafficManager: Found ", _destination_nodes.size(), " destination nodes.")
	max_active_cars = int(round(_destination_nodes.size() * 0.5)) # Only spawn as many cars as available destinations to avoid gridlock. If there are 5 destination nodes, only spawn 4 cars at most so there's always a free spot to move into.
	_find_spawn_nodes()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.start()

	_register_existing_cars()


# Finds all nodes that can be destinations and spawn points by checking the TrafficNetwork's list of all nodes. This is more efficient than iterating over all nodes multiple times or having the TrafficNetwork maintain separate lists.
func _find_destination_nodes() -> void:
	_destination_nodes.clear()
	var nodes := _traffic_network.get_all_nodes()
	for node: TrafficNodeType in nodes:
		if node.can_be_destination:
			_destination_nodes.append(node)
			

# Note: spawn nodes are a subset of destination nodes, so we can find them by filtering the destination list instead of iterating over all nodes again.
func _find_spawn_nodes() -> void:
	_spawn_nodes.clear()
	var nodes := _traffic_network.get_all_nodes()
	for node: TrafficNodeType in nodes:
		if node.is_spawn_node:
			_spawn_nodes.append(node)


func _on_spawn_timer_timeout() -> void:
	if _traffic_network == null or npc_car_scene == null:
		return
	if _active_cars.size() >= max_active_cars:
		return

	var candidate_nodes: Array[TrafficNodeType] = []
	for node: TrafficNodeType in _spawn_nodes:
		if not _is_spawn_allowed(node):
			continue
		var candidate_stats: Dictionary = _get_destination_candidate_stats(node, min_spawn_to_initial_destination_distance)
		if bool(candidate_stats.get("has_any", false)):
			candidate_nodes.append(node)

	if candidate_nodes.is_empty():
		return

	var spawn_node := candidate_nodes[_rng.randi() % candidate_nodes.size()]
	_spawn_car_at(spawn_node)


func _on_despawn_timer_timeout() -> void:
	# Despawn decisions are owned by NPCCar now.
	return


func _spawn_car_at(spawn_node: TrafficNodeType) -> void:
	var car := npc_car_scene.instantiate() as NPCCarType
	if car == null:
		push_error("TrafficManager: npc_car_scene is not an NPCCar scene.")
		return

	car.global_position = spawn_node.global_position
	if npc_root_node != null:
		npc_root_node.add_child(car)
	else:
		add_child(car)

	_register_car(car)
	# Give the car its initial destination.
	var initial_dest := request_next_destination(car, spawn_node, min_spawn_to_initial_destination_distance)
	if initial_dest != null:
		car.set_new_destination_node(initial_dest)
	else:
		car.queue_free()


func _register_existing_cars() -> void:
	for node in get_tree().get_nodes_in_group("npc_cars"):
		var car := node as NPCCarType
		if car == null:
			continue
		_register_car(car)
		if not car.has_active_path():
			var closest_node := _traffic_network.get_closest_node(car.global_position)
			var dest := request_next_destination(car, closest_node)
			if dest != null:
				car.set_new_destination_node(dest)


func _register_car(car: NPCCarType) -> void:
	if _active_cars.has(car):
		return
	_active_cars.append(car)
	car.set_network(_traffic_network)
	car.set_traffic_manager(self)  # Cars can now request destinations autonomously
	_apply_debug_visualization_to_car(car)
	if not car.tree_exited.is_connected(_on_car_tree_exited):
		car.tree_exited.connect(_on_car_tree_exited.bind(car))


func _on_car_tree_exited(car: NPCCarType) -> void:
	# Release the destination slot so another car can use it.
	var dest: TrafficNodeType = car.get_destination_node()
	if dest != null:
		dest.release()
	_active_cars.erase(car)


func _apply_debug_visualization_to_all_cars() -> void:
	for car: NPCCarType in _active_cars:
		if car == null or not is_instance_valid(car):
			continue
		_apply_debug_visualization_to_car(car)


func _apply_debug_visualization_to_car(car: NPCCarType) -> void:
	if car == null:
		return
	car.debug_draw_sensors = debug_npc_sensor_overlay
	car.debug_sensor_line_width = debug_npc_sensor_line_width


func request_next_destination(car: NPCCarType, avoid_node: TrafficNodeType = null, min_distance_from_avoid: float = 0.0) -> TrafficNodeType:
	return _request_next_destination_internal(car, avoid_node, min_distance_from_avoid, null, null, [], true)


func request_next_destination_excluding(car: NPCCarType, avoid_node: TrafficNodeType = null, min_distance_from_avoid: float = 0.0, excluded_destination: TrafficNodeType = null) -> TrafficNodeType:
	var excluded_nodes: Array[TrafficNodeType] = []
	if excluded_destination != null:
		excluded_nodes.append(excluded_destination)
	return _request_next_destination_internal(car, avoid_node, min_distance_from_avoid, null, null, excluded_nodes, true)


func request_alternative_destination(car: NPCCarType, start_node: TrafficNodeType, temporary_no_go_node: TrafficNodeType = null, excluded_destination: TrafficNodeType = null) -> TrafficNodeType:
	var excluded_nodes: Array[TrafficNodeType] = []
	if excluded_destination != null:
		excluded_nodes.append(excluded_destination)
	# Alternative routes after a block should not be constrained by spawn-distance rules.
	return _request_next_destination_internal(car, null, 0.0, start_node, temporary_no_go_node, excluded_nodes, false)


func _request_next_destination_internal(car: NPCCarType, avoid_node: TrafficNodeType, min_distance_from_avoid: float, start_node: TrafficNodeType, temporary_no_go_node: TrafficNodeType, excluded_nodes: Array[TrafficNodeType], apply_default_min_distance: bool) -> TrafficNodeType:
	"""Called by cars to request the next destination. Returns a TrafficNode or null.
	Cars call this when they reach their destination and are ready to move to the next goal.
	"""
	if _traffic_network == null:
		return null

	var effective_min_distance: float = min_distance_from_avoid
	if apply_default_min_distance and effective_min_distance <= 0.0:
		effective_min_distance = min_spawn_to_initial_destination_distance

	# Release the car's current destination so another car can claim it.
	var old_dest: TrafficNodeType = car.get_destination_node()
	if old_dest != null:
		old_dest.release()

	var nodes := _traffic_network.get_all_nodes()
	if nodes.size() < 2:
		return null

	# Tier 1: all destination nodes (occupancy is handled by car-side awareness/re-routing).
	var candidates: Array[TrafficNodeType] = []
	for node: TrafficNodeType in nodes:
		if _is_node_excluded(node, excluded_nodes):
			continue
		if not _passes_avoid_constraints(node, avoid_node, effective_min_distance):
			continue
		if temporary_no_go_node != null and node == temporary_no_go_node:
			continue
		if not _is_reachable_with_constraints(start_node, node, temporary_no_go_node):
			continue
		if node.can_be_destination:
			candidates.append(node)

	# Tier 2: all destination spots are full — use non-destination routing nodes so
	# the car keeps circulating until a spot frees up.
	if candidates.is_empty():
		for node: TrafficNodeType in nodes:
			if _is_node_excluded(node, excluded_nodes):
				continue
			if not _passes_avoid_constraints(node, avoid_node, effective_min_distance):
				continue
			if temporary_no_go_node != null and node == temporary_no_go_node:
				continue
			if not _is_reachable_with_constraints(start_node, node, temporary_no_go_node):
				continue
			if not node.can_be_destination:
				candidates.append(node)

	if candidates.is_empty():
		return null

	var target := candidates[_rng.randi() % candidates.size()]
	# Occupation state is now informational for movement/arrival handling.
	if target.can_be_destination and not target.is_occupied:
		target.claim()
	return target


func _is_node_excluded(node: TrafficNodeType, excluded_nodes: Array[TrafficNodeType]) -> bool:
	for excluded: TrafficNodeType in excluded_nodes:
		if excluded == node:
			return true
	return false


func _is_reachable_with_constraints(start_node: TrafficNodeType, target_node: TrafficNodeType, temporary_no_go_node: TrafficNodeType) -> bool:
	if start_node == null:
		return true
	if target_node == null:
		return false
	if temporary_no_go_node != null:
		if start_node == temporary_no_go_node or target_node == temporary_no_go_node:
			return false
	if start_node == target_node:
		return true

	var avoid_nodes: Array[TrafficNodeType] = []
	if temporary_no_go_node != null:
		avoid_nodes.append(temporary_no_go_node)

	return _traffic_network.has_path_between_nodes_avoiding(start_node, target_node, avoid_nodes)


func _passes_avoid_constraints(node: TrafficNodeType, avoid_node: TrafficNodeType, effective_min_distance: float) -> bool:
	if node == avoid_node:
		return false
	if effective_min_distance > 0.0 and avoid_node != null and avoid_node.global_position.distance_to(node.global_position) < effective_min_distance:
		return false
	return true


func _get_destination_candidate_stats(avoid_node: TrafficNodeType, effective_min_distance: float) -> Dictionary:
	if _traffic_network == null:
		return {"tier1": 0, "tier2": 0, "has_any": false}

	var nodes := _traffic_network.get_all_nodes()
	var tier1_count: int = 0
	for node: TrafficNodeType in nodes:
		if not _passes_avoid_constraints(node, avoid_node, effective_min_distance):
			continue
		if node.can_be_destination:
			tier1_count += 1

	var tier2_count: int = 0
	if tier1_count == 0:
		for node: TrafficNodeType in nodes:
			if not _passes_avoid_constraints(node, avoid_node, effective_min_distance):
				continue
			if not node.can_be_destination:
				tier2_count += 1

	return {
		"tier1": tier1_count,
		"tier2": tier2_count,
		"has_any": tier1_count > 0 or tier2_count > 0,
	}


func _is_spawn_allowed(node: TrafficNodeType) -> bool:
	if node == null or not node.is_spawn_node:
		return false

	# Don't spawn at a node that doubles as a destination and is currently occupied.
	if node.can_be_destination and node.is_occupied:
		return false

	if _player_node != null and node.global_position.distance_to(_player_node.global_position) < min_spawn_distance_to_player:
		return false

	if not _is_point_visible_for_player(node.global_position):
		return true

	return _is_occluded_by_building(node.global_position)


func _is_point_visible_for_player(point: Vector2) -> bool:
	if _player_camera == null:
		_player_camera = _resolve_player_camera()
	if _player_camera == null:
		return false

	var viewport_rect := _player_camera.get_viewport_rect()
	var world_size := viewport_rect.size * _player_camera.zoom
	var top_left := _player_camera.get_screen_center_position() - world_size * 0.5
	var world_rect := Rect2(top_left, world_size)
	return world_rect.has_point(point)


func _is_occluded_by_building(point: Vector2) -> bool:
	var origin := Vector2.ZERO
	if _player_node != null:
		origin = _player_node.global_position
	elif _player_camera != null:
		origin = _player_camera.get_screen_center_position()
	else:
		return false

	var query := PhysicsRayQueryParameters2D.create(origin, point)
	query.collision_mask = building_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var world_2d: World2D = get_viewport().world_2d
	if world_2d == null:
		return false
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	var hit: Dictionary = space_state.intersect_ray(query)
	return not hit.is_empty()


func _resolve_player_camera() -> Camera2D:
	if not player_camera_path.is_empty():
		return get_node_or_null(player_camera_path) as Camera2D
	return get_viewport().get_camera_2d()


func _resolve_player_node() -> Node2D:
	if not player_node_path.is_empty():
		return get_node_or_null(player_node_path) as Node2D
	return GameData.get_taxi() as Node2D

# Utility function to measure distance between two landing pads along the traffic network paths. Used for fare calculation and passenger transport distance tracking.
func get_distance_between_landing_pads(pad_a: LandingPad, pad_b: LandingPad) -> float:
	if _traffic_network == null:
		return INF

	var node_a := pad_a.get_traffic_node()
	var node_b := pad_b.get_traffic_node()
	if node_a == null or node_b == null:
		return INF

	var path := _traffic_network.get_path_between_nodes(node_a, node_b)
	if path.size() < 2:
		return INF

	var distance := 0.0
	for i in range(path.size() - 1):
		distance += path[i].distance_to(path[i + 1])
	return distance