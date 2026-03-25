extends Node2D
class_name TrafficNetwork

signal graph_built

@export var auto_connect_radius: float = 300.0
@export var print_spawn_debug: bool = false
@export var draw_connections_on_start: bool = false

# Layers are 1-based in Godot; this blocks graph links through layers 2, 3, and 7.
const BLOCKING_COLLISION_MASK: int = (1 << 1) | (1 << 2) | (1 << 6)

var astar := AStar2D.new()
var _all_nodes: Array[TrafficNode] = []
var _spawn_nodes: Array[TrafficNode] = []
var _node_by_id: Dictionary = {}
var _id_by_node: Dictionary = {}

func _ready() -> void:
	add_to_group("traffic_network")
	_build_graph_deferred()


func _build_graph_deferred() -> void:
	# Wait for physics_frame so all _ready() calls and shape registrations are done,
	# then wait one more process frame so direct_space_state has fully flushed.
	await get_tree().physics_frame
	await get_tree().process_frame
	build_graph()


func build_graph() -> void:
	astar = AStar2D.new()
	_all_nodes.clear()
	_spawn_nodes.clear()
	_node_by_id.clear()
	_id_by_node.clear()

	var nodes_raw := get_tree().get_nodes_in_group("traffic_nodes")
	for node_variant in nodes_raw:
		var traffic_node := node_variant as TrafficNode
		if traffic_node != null:
			_all_nodes.append(traffic_node)

	# 1) Register points and collect spawn nodes.
	for i in range(_all_nodes.size()):
		var node := _all_nodes[i]
		astar.add_point(i, node.global_position)
		astar.set_point_weight_scale(i, node.weight_modifier)
		_node_by_id[i] = node
		_id_by_node[node] = i
		if node.is_spawn_node:
			_spawn_nodes.append(node)
			if print_spawn_debug:
				print("Traffic spawn node registered at: ", node.global_position)

	# 2) Auto-connect nodes by distance if no wall blocks the line.
	var space_state := get_world_2d().direct_space_state
	for i in range(_all_nodes.size()):
		for j in range(i + 1, _all_nodes.size()):
			var pos_a := _all_nodes[i].global_position
			var pos_b := _all_nodes[j].global_position
			if pos_a.distance_to(pos_b) > auto_connect_radius:
				continue

			var query := PhysicsRayQueryParameters2D.create(pos_a, pos_b)
			query.collision_mask = BLOCKING_COLLISION_MASK
			if space_state.intersect_ray(query).is_empty():
				astar.connect_points(i, j, true)

	# 3) Apply NoEntry and OneWay overrides.
	_apply_manual_overrides()

	if draw_connections_on_start:
		queue_redraw()

	graph_built.emit()


func _draw() -> void:
	if not draw_connections_on_start:
		return
	if astar.get_point_count() == 0:
		return

	var drawn_edges: Dictionary = {}
	for from_id_variant: Variant in astar.get_point_ids():
		var from_id: int = int(from_id_variant)
		var from_node: TrafficNode = _node_by_id.get(from_id, null) as TrafficNode
		if from_node == null:
			continue

		for to_id_variant: Variant in astar.get_point_connections(from_id):
			var to_id: int = int(to_id_variant)
			var to_node: TrafficNode = _node_by_id.get(to_id, null) as TrafficNode
			if to_node == null:
				continue

			# Draw each edge once, even if A* stores a bidirectional pair.
			var low_id: int = mini(from_id, to_id)
			var high_id: int = maxi(from_id, to_id)
			var edge_key: String = str(low_id) + ":" + str(high_id)
			if drawn_edges.has(edge_key):
				continue
			drawn_edges[edge_key] = true

			draw_line(
				to_local(from_node.global_position),
				to_local(to_node.global_position),
				Color.YELLOW,
				2.0
			)


func get_all_nodes() -> Array[TrafficNode]:
	return _all_nodes.duplicate()


func get_spawn_nodes() -> Array[TrafficNode]:
	return _spawn_nodes.duplicate()


func get_closest_node(world_position: Vector2) -> TrafficNode:
	if astar.get_point_count() == 0:
		return null
	var id := astar.get_closest_point(world_position)
	return _node_by_id.get(id, null) as TrafficNode


func get_closest_spawn_node(world_position: Vector2) -> TrafficNode:
	var result: TrafficNode = null
	var min_dist := INF
	for node in _spawn_nodes:
		var dist := node.global_position.distance_to(world_position)
		if dist < min_dist:
			min_dist = dist
			result = node
	return result


func get_path_between(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	if astar.get_point_count() < 2:
		return PackedVector2Array()

	var from_id := astar.get_closest_point(from_position)
	var to_id := astar.get_closest_point(to_position)
	if from_id == to_id:
		return PackedVector2Array([to_position])

	return astar.get_point_path(from_id, to_id)


func get_path_between_nodes(from_node: TrafficNode, to_node: TrafficNode) -> PackedVector2Array:
	if from_node == null or to_node == null:
		return PackedVector2Array()
	if not _id_by_node.has(from_node) or not _id_by_node.has(to_node):
		return PackedVector2Array()

	var from_id: int = _id_by_node[from_node]
	var to_id: int = _id_by_node[to_node]
	if from_id == to_id:
		return PackedVector2Array([to_node.global_position])

	return astar.get_point_path(from_id, to_id)


func get_path_distance_between_nodes(from_node: TrafficNode, to_node: TrafficNode) -> float:
	if from_node == null or to_node == null:
		return -1.0
	if not _id_by_node.has(from_node) or not _id_by_node.has(to_node):
		return -1.0

	var from_id: int = _id_by_node[from_node]
	var to_id: int = _id_by_node[to_node]
	if from_id == to_id:
		return 0.0

	var id_path: PackedInt64Array = astar.get_id_path(from_id, to_id)
	if id_path.is_empty():
		return -1.0

	var total_distance: float = 0.0
	for i in range(id_path.size() - 1):
		var current_node: TrafficNode = _node_by_id.get(int(id_path[i]), null) as TrafficNode
		var next_node: TrafficNode = _node_by_id.get(int(id_path[i + 1]), null) as TrafficNode
		if current_node == null or next_node == null:
			return -1.0
		total_distance += current_node.global_position.distance_to(next_node.global_position)

	return total_distance


func _apply_manual_overrides() -> void:
	# NoEntry: remove connectivity in both directions.
	for barrier in get_tree().get_nodes_in_group("NoEntryLinks"):
		var a := _resolve_link_point(barrier, "PointA", "node_a")
		var b := _resolve_link_point(barrier, "PointB", "node_b")
		if a == null or b == null:
			continue

		var id_a := astar.get_closest_point(a.global_position)
		var id_b := astar.get_closest_point(b.global_position)
		if id_a != id_b and astar.are_points_connected(id_a, id_b, true):
			astar.disconnect_points(id_a, id_b, true)

	# OneWay: replace any two-way edge with an A -> B one-way edge.
	for link in get_tree().get_nodes_in_group("OneWayLinks"):
		var a := _resolve_link_point(link, "PointA", "node_a")
		var b := _resolve_link_point(link, "PointB", "node_b")
		if a == null or b == null:
			continue

		var id_a := astar.get_closest_point(a.global_position)
		var id_b := astar.get_closest_point(b.global_position)
		if id_a == id_b:
			continue

		if astar.are_points_connected(id_a, id_b, true):
			astar.disconnect_points(id_a, id_b, true)
		astar.connect_points(id_a, id_b, false)


func _resolve_link_point(link: Node, marker_name: String, property_name: String) -> Node2D:
	if link.has_node(marker_name):
		return link.get_node(marker_name) as Node2D
	if property_name in link:
		return link.get(property_name) as Node2D
	return null