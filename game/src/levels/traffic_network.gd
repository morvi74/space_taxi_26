extends Node2D
## Builds and serves the runtime road graph used by NPC routing.
class_name TrafficNetwork

## Responsibilities:
## - build A* connectivity from traffic nodes plus raycast constraints
## - apply NoEntry/OneWay scene overrides after auto-connect
## - provide reusable path and distance queries for traffic systems
## Doc convention:
## - First line states intent in one sentence.
## - Optional Params line for non-trivial inputs.
## - Optional Returns line for non-obvious outputs.
## - Keep wording behavior-focused, not implementation-focused.

## Emitted after graph construction and manual link overrides are complete.
signal graph_built

## Maximum distance for auto-connecting two traffic nodes.
@export var auto_connect_radius: float = 300.0
## Enables spawn-node registration debug output.
@export var print_spawn_debug: bool = false
## Draws graph edges for debugging when enabled.
@export var draw_connections_on_start: bool = false
## Minimum angle to horizontal required for edges touching landing-pad/parking nodes.
@export var min_surface_connection_angle_degrees: float = 60.0

# Layers are 1-based in Godot; this blocks graph links through layers 2, 3, and 7.
## Physics layers that block automatic graph edge creation.
const BLOCKING_COLLISION_MASK: int = (1 << 1) | (1 << 2) | (1 << 6)

## A* graph backing all path queries.
var astar := AStar2D.new()
## Cached list of all traffic nodes currently in the scene.
var _all_nodes: Array[TrafficNode] = []
## Subset of traffic nodes flagged as spawn sources.
var _spawn_nodes: Array[TrafficNode] = []
## Fast lookup: A* id -> TrafficNode.
var _node_by_id: Dictionary = {}
## Fast lookup: TrafficNode -> A* id.
var _id_by_node: Dictionary = {}

## Registers this network and starts deferred graph construction.
func _ready() -> void:
	add_to_group("traffic_network")
	_build_graph_deferred()


## Waits for physics readiness, then triggers graph build to avoid stale query state.
func _build_graph_deferred() -> void:
	# Wait for physics_frame so all _ready() calls and shape registrations are done,
	# then wait one more process frame so direct_space_state has fully flushed.
	await get_tree().physics_frame
	await get_tree().process_frame
	build_graph()


## Rebuilds the complete graph from scene nodes, ray tests, and manual overrides.
## Side effects: replaces existing A* graph state and emits graph_built.
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
			if not _passes_surface_connection_angle_constraint(_all_nodes[i], _all_nodes[j]):
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


## Draws graph edges for debug visualization (one line per undirected edge).
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


## Returns a copy of all registered traffic nodes.
func get_all_nodes() -> Array[TrafficNode]:
	return _all_nodes.duplicate()


## Returns a copy of nodes that can spawn NPC cars.
func get_spawn_nodes() -> Array[TrafficNode]:
	return _spawn_nodes.duplicate()


## Returns the nearest graph node to world position.
func get_closest_node(world_position: Vector2) -> TrafficNode:
	if astar.get_point_count() == 0:
		return null
	var id := astar.get_closest_point(world_position)
	return _node_by_id.get(id, null) as TrafficNode


## Returns nearest spawn-capable node to world position.
func get_closest_spawn_node(world_position: Vector2) -> TrafficNode:
	var result: TrafficNode = null
	var min_dist := INF
	for node in _spawn_nodes:
		var dist := node.global_position.distance_to(world_position)
		if dist < min_dist:
			min_dist = dist
			result = node
	return result


## Returns world-space path between arbitrary positions via nearest graph nodes.
## Params: from_position and to_position are arbitrary world coordinates.
## Returns: PackedVector2Array path points (can be empty when graph is insufficient).
func get_path_between(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	if astar.get_point_count() < 2:
		return PackedVector2Array()

	var from_id := astar.get_closest_point(from_position)
	var to_id := astar.get_closest_point(to_position)
	if from_id == to_id:
		return PackedVector2Array([to_position])

	return astar.get_point_path(from_id, to_id)


## Returns world-space path between two explicit traffic nodes.
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


## Returns cumulative edge distance between two nodes, or -1 when no path exists.
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


## Returns path while temporarily removing selected nodes from the graph.
## Params: avoid_nodes are excluded only for this query.
## Returns: path in filtered graph, or empty array when blocked/unreachable.
func get_path_between_nodes_avoiding(from_node: TrafficNode, to_node: TrafficNode, avoid_nodes: Array[TrafficNode]) -> PackedVector2Array:
	if from_node == null or to_node == null:
		return PackedVector2Array()
	if not _id_by_node.has(from_node) or not _id_by_node.has(to_node):
		return PackedVector2Array()

	var disabled_ids := _collect_disabled_ids(avoid_nodes)
	var from_id: int = _id_by_node[from_node]
	var to_id: int = _id_by_node[to_node]
	if disabled_ids.has(from_id) or disabled_ids.has(to_id):
		return PackedVector2Array()

	if from_id == to_id:
		return PackedVector2Array([to_node.global_position])

	var filtered_astar := _build_filtered_astar(disabled_ids)
	return filtered_astar.get_point_path(from_id, to_id)


## Returns true when a valid path exists with the provided avoid-node filter.
func has_path_between_nodes_avoiding(from_node: TrafficNode, to_node: TrafficNode, avoid_nodes: Array[TrafficNode]) -> bool:
	return not get_path_between_nodes_avoiding(from_node, to_node, avoid_nodes).is_empty()


## Converts avoid-node list into an id set for filtered graph construction.
func _collect_disabled_ids(avoid_nodes: Array[TrafficNode]) -> Dictionary:
	var disabled_ids: Dictionary = {}
	for node: TrafficNode in avoid_nodes:
		if node == null:
			continue
		if _id_by_node.has(node):
			disabled_ids[_id_by_node[node]] = true
	return disabled_ids


## Builds a temporary A* graph that excludes disabled node ids.
func _build_filtered_astar(disabled_ids: Dictionary) -> AStar2D:
	var filtered_astar := AStar2D.new()

	for id_variant: Variant in astar.get_point_ids():
		var id: int = int(id_variant)
		if disabled_ids.has(id):
			continue
		filtered_astar.add_point(id, astar.get_point_position(id), astar.get_point_weight_scale(id))

	for id_variant: Variant in astar.get_point_ids():
		var from_id: int = int(id_variant)
		if disabled_ids.has(from_id) or not filtered_astar.has_point(from_id):
			continue

		for to_variant: Variant in astar.get_point_connections(from_id):
			var to_id: int = int(to_variant)
			if disabled_ids.has(to_id) or not filtered_astar.has_point(to_id):
				continue
			if from_id >= to_id:
				continue
			if filtered_astar.are_points_connected(from_id, to_id, true):
				continue
			filtered_astar.connect_points(from_id, to_id, true)

	return filtered_astar


## Applies NoEntry and OneWay scene markers onto the built graph.
## Rule: NoEntry disconnects both directions; OneWay reconnects only A -> B.
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


## Resolves link endpoint from configured node property or marker fallback.
## Returns: resolved Node2D endpoint, or null if neither source is valid.
func _resolve_link_point(link: Node, marker_name: String, property_name: String) -> Node2D:
	if property_name in link:
		var configured_point: Node2D = link.get(property_name) as Node2D
		if configured_point != null:
			return configured_point
	if link.has_node(marker_name):
		return link.get_node(marker_name) as Node2D
	return null


## Rejects edges that are too flat for surface-bound nodes.
func _passes_surface_connection_angle_constraint(node_a: TrafficNode, node_b: TrafficNode) -> bool:
	if node_a == null or node_b == null:
		return false

	if _is_surface_bound_node(node_a):
		if _connection_angle_to_horizontal_degrees(node_a.global_position, node_b.global_position) < min_surface_connection_angle_degrees:
			return false

	if _is_surface_bound_node(node_b):
		if _connection_angle_to_horizontal_degrees(node_b.global_position, node_a.global_position) < min_surface_connection_angle_degrees:
			return false

	return true


## Returns true for nodes anchored to landing pads or parking lots.
func _is_surface_bound_node(node: TrafficNode) -> bool:
	return node.get_landing_pad() != null or node.get_parking_lot() != null


## Returns absolute angle-to-horizontal between two positions in degrees.
func _connection_angle_to_horizontal_degrees(from_pos: Vector2, to_pos: Vector2) -> float:
	var direction: Vector2 = (to_pos - from_pos).normalized()
	if direction == Vector2.ZERO:
		return 0.0

	var horizontal_alignment: float = absf(direction.dot(Vector2.RIGHT))
	horizontal_alignment = clampf(horizontal_alignment, 0.0, 1.0)
	return rad_to_deg(acos(horizontal_alignment))
