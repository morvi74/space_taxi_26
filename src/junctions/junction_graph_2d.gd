@tool
class_name JunctionGraph2D
extends Node2D

@export var default_point_color: Color = Color(1.0, 0.0, 0.0, 1.0)
@export var show_points_in_game: bool = true
@export var show_graph_in_game: bool = true
@export var graph_color: Color = Color(1.0, 1.0, 0.2, 0.9)
@export var graph_width: float = 2.0
@export_flags_2d_physics var blocking_mask: int = (1 << 1) | (1 << 2) | (1 << 5)
@export var auto_rebuild_in_editor: bool = true

var connections: Dictionary = {} # Dictionary<JunctionPoint2D, Array<JunctionPoint2D>>
var _last_dragged: JunctionPoint2D = null

func _enter_tree() -> void:
	if not child_exiting_tree.is_connected(_on_child_exiting_tree):
		child_exiting_tree.connect(_on_child_exiting_tree)

func _on_child_exiting_tree(node: Node) -> void:
	if node is JunctionPoint2D:
		# Rebuild after the node is actually removed to avoid stale object references.
		call_deferred("rebuild_graph")

func _ready() -> void:
	rebuild_graph()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func get_junctions() -> Array[JunctionPoint2D]:
	var result: Array[JunctionPoint2D] = []
	for child: Node in get_children():
		if child is JunctionPoint2D:
			result.append(child as JunctionPoint2D)
	return result

func rebuild_graph() -> void:
	connections.clear()

	var junctions: Array[JunctionPoint2D] = get_junctions()
	_cleanup_invalid_exceptions(junctions)
	for junction: JunctionPoint2D in junctions:
		if junction.point_color != default_point_color:
			junction.point_color = default_point_color
		connections[junction] = []

	for i: int in range(junctions.size()):
		for j: int in range(i + 1, junctions.size()):
			var a: JunctionPoint2D = junctions[i]
			var b: JunctionPoint2D = junctions[j]

			if _is_exception(a, b):
				continue

			if _has_clear_line(a.global_position, b.global_position, a, b):
				(connections[a] as Array).append(b)
				(connections[b] as Array).append(a)

	queue_redraw()

func _cleanup_invalid_exceptions(junctions: Array[JunctionPoint2D]) -> void:
	var valid_points: Dictionary = {}
	for junction: JunctionPoint2D in junctions:
		if junction != null and is_instance_valid(junction):
			valid_points[junction] = true

	for junction: JunctionPoint2D in junctions:
		var ex: Array[JunctionPoint2D] = junction.exceptions
		for i: int in range(ex.size() - 1, -1, -1):
			var candidate: JunctionPoint2D = ex[i]
			if candidate == null or not is_instance_valid(candidate) or candidate == junction or not valid_points.has(candidate):
				ex.remove_at(i)

		var seen: Dictionary = {}
		for i: int in range(ex.size() - 1, -1, -1):
			var candidate: JunctionPoint2D = ex[i]
			if seen.has(candidate):
				ex.remove_at(i)
			else:
				seen[candidate] = true

func _is_exception(a: JunctionPoint2D, b: JunctionPoint2D) -> bool:
	if a == null or b == null:
		return false
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	return a.exceptions.has(b) or b.exceptions.has(a)

func _has_clear_line(
	from_pos: Vector2,
	to_pos: Vector2,
	a: JunctionPoint2D,
	b: JunctionPoint2D
) -> bool:
	var world_2d_ref: World2D = get_world_2d()
	if world_2d_ref == null:
		return true

	var space_state: PhysicsDirectSpaceState2D = world_2d_ref.direct_space_state
	if space_state == null:
		return true

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from_pos, to_pos)
	query.collision_mask = blocking_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true

	# Junctions selbst ignorieren.
	var exclude_rids: Array[RID] = []
	if a.get_canvas_item().is_valid():
		exclude_rids.append(a.get_canvas_item())
	if b.get_canvas_item().is_valid():
		exclude_rids.append(b.get_canvas_item())
	query.exclude = exclude_rids

	var hit: Dictionary = space_state.intersect_ray(query)
	return hit.is_empty()

func _draw() -> void:
	var draw_runtime: bool = not Engine.is_editor_hint() and (show_points_in_game or show_graph_in_game)
	var draw_editor: bool = Engine.is_editor_hint()

	if not draw_runtime and not draw_editor:
		return

	# Linien
	for from_junction_variant: Variant in connections.keys():
		var a: JunctionPoint2D = from_junction_variant as JunctionPoint2D
		if a == null or not is_instance_valid(a):
			continue

		var neighbors: Array = connections.get(a, [])
		for to_junction: Variant in neighbors:
			var b: JunctionPoint2D = to_junction as JunctionPoint2D
			if b == null or not is_instance_valid(b):
				continue

			if a.get_instance_id() < b.get_instance_id():
				draw_line(
					to_local(a.global_position),
					to_local(b.global_position),
					graph_color,
					graph_width
				)

	# for junction in get_junctions():
	# 	for ex in junction.exceptions:
	# 		draw_line(
	# 			to_local(junction.global_position),
	# 			to_local(ex.global_position),
	# 			Color(1,0,0,0.5),
	# 			1.0
	# 		)
			
	# Punkte im Game zusätzlich hier zeichnen, falls gewünscht.
	if not Engine.is_editor_hint() and show_points_in_game:
		for junction: JunctionPoint2D in get_junctions():
			draw_circle(
				to_local(junction.global_position),
				junction.radius,
				junction.point_color
			)

func get_neighbors(point: JunctionPoint2D) -> Array[JunctionPoint2D]:
	if not connections.has(point):
		return []
	var neighbors: Array[JunctionPoint2D] = []
	for candidate: Variant in connections.get(point, []):
		var as_point: JunctionPoint2D = candidate as JunctionPoint2D
		if as_point != null and is_instance_valid(as_point):
			neighbors.append(as_point)
	return neighbors

