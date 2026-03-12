@tool
extends EditorPlugin

const GRAPH_SCRIPT := preload("uid://we3g5e1jsacl")
const POINT_SCENE := preload("uid://1xae4kmotven")

var _dragged_point: JunctionPoint2D = null
var _drag_offset: Vector2 = Vector2.ZERO

var _exception_start: JunctionPoint2D = null # First junction node of 2 that must not be connected to each other directly



func _handles(object: Object) -> bool:
	return object is JunctionGraph2D

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if Input.is_key_pressed(KEY_SPACE):
		return false
	
	var edited: Object = get_editor_interface().get_edited_scene_root()
	if edited == null:
		return false

	var selection: Node = get_editor_interface().get_selection().get_selected_nodes()[0] \
		if get_editor_interface().get_selection().get_selected_nodes().size() > 0 else null

	if selection == null or not (selection is JunctionGraph2D):
		return false

	var graph: JunctionGraph2D = selection as JunctionGraph2D

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and Input.is_key_pressed(KEY_CTRL):
			var clicked : JunctionPoint2D = _find_point_at(graph, mb.position)

			if clicked == null:
				return false
			
			if _exception_start == null:
				_exception_start = clicked
				return true
			
			if _exception_start != clicked:
				_toggle_exception(_exception_start, clicked)
				graph.rebuild_graph()
			
			_exception_start = null
			return true
		
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var clicked: JunctionPoint2D = _find_point_at(graph, mb.position)
			if clicked != null:
				_dragged_point = clicked
				_drag_offset = clicked.global_position - mb.position
				return true

			_create_point(graph, mb.position)
			return true

		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragged_point = null
			return false

		# --- RIGHT Click: Delete junctioin ---
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var clicked := _find_point_at(graph, mb.position)

			if clicked != null:
				clicked.queue_free()
				graph.rebuild_graph()
				return true

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _dragged_point != null:
			_dragged_point.global_position = mm.position + _drag_offset
			graph.rebuild_graph()
			return true

	return false

func _find_point_at(graph: JunctionGraph2D, mouse_pos: Vector2) -> JunctionPoint2D:
	# Convert mouse_pos from canvas coordinates to global world coordinates
	var editor_interface = get_editor_interface()
	var base_control = editor_interface.get_base_control()
	var viewport = base_control.get_viewport()
	var canvas_xform = viewport.canvas_transform
	var global_mouse_pos = canvas_xform.affine_inverse() * mouse_pos

	for point: JunctionPoint2D in graph.get_junctions():
		if point.global_position.distance_to(global_mouse_pos) <= point.radius + 4.0:
			return point
	return null

func _create_point(graph: JunctionGraph2D, mouse_pos: Vector2) -> void:
	var point: JunctionPoint2D = POINT_SCENE.instantiate() as JunctionPoint2D
	point.name = _generate_name(graph)

	# Convert mouse_pos from canvas coordinates to global world coordinates
	# (same approach as _find_point_at to ensure consistent coordinate space conversion)
	var editor_interface = get_editor_interface()
	var base_control = editor_interface.get_base_control()
	var viewport = base_control.get_viewport()
	var canvas_xform = viewport.canvas_transform
	var world_pos = canvas_xform.affine_inverse() * mouse_pos
	point.position = graph.to_local(world_pos)

	graph.add_child(point)
	point.owner = editor_interface.get_edited_scene_root()
	point.point_color = graph.default_point_color
	graph.rebuild_graph()

func _generate_name(graph: JunctionGraph2D) -> String:
	#var index: int = 1
	for index: int in range(1, 100000):
		var candidate: String = "Junction_%d" % index
		if graph.get_node_or_null(candidate) == null:
			return candidate
	push_error("Junction-Plugin: Konnte keinen freien Junction-Namen erezugen!")
	return "Junction-Error"

func _toggle_exception(a: JunctionPoint2D, b: JunctionPoint2D) -> void:
	if a.exceptions.has(b):
		a.exceptions.erase(b)
		b.exceptions.erase(a)
	else:
		a.exceptions.append(b)
		b.exceptions.append(a)