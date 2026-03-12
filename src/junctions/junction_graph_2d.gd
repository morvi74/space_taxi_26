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

var connections: Dictionary = {}
var _last_dragged: JunctionPoint2D = null

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
	for junction: JunctionPoint2D in junctions:
		if junction.point_color == Color(1.0, 0.0, 0.0, 1.0) and junction.point_color != default_point_color:
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

func _is_exception(a: JunctionPoint2D, b: JunctionPoint2D) -> bool:
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
	for from_junction: Variant in connections.keys():
		var neighbors: Array = connections[from_junction]
		for to_junction: Variant in neighbors:
			var a: JunctionPoint2D = from_junction as JunctionPoint2D
			var b: JunctionPoint2D = to_junction as JunctionPoint2D

			if a.get_instance_id() < b.get_instance_id():
				draw_line(
					to_local(a.global_position),
					to_local(b.global_position),
					graph_color,
					graph_width
				)

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
	return connections[point]