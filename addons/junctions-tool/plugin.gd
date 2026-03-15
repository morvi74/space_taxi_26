@tool
extends EditorPlugin

const GRAPH_SCRIPT := preload("uid://we3g5e1jsacl")
#const POINT_SCENE := preload("res://src/junctions/junction_point_2d.tscn")  # Changed from UID#("uid://1xae4kmotven") # PackedScene of JunctionPoint2D
const POINT_SCENE := preload("uid://1xae4kmotven") # JunctionPoint2D script, to ensure it's loaded and recognized as a type

var _dragged_point: JunctionPoint2D = null
var _drag_offset: Vector2 = Vector2.ZERO

var _exception_start: JunctionPoint2D = null # First junction node of 2 that must not be connected to each other directly

func _ready() -> void:
	pass
	# Debug: Check if POINT_SCENE loaded properly
	# print("POINT_SCENE type: ", typeof(POINT_SCENE))
	# print("POINT_SCENE value: ", POINT_SCENE)
	# print("POINT_SCENE is PackedScene: ", POINT_SCENE is PackedScene)

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
				# print("=== DRAG START ===")
				# print("Clicked point: ", clicked)
				# print("Clicked position: ", clicked.global_position)
				
				_dragged_point = clicked
				var scene_root = get_editor_interface().get_edited_scene_root()
				var scene_viewport = scene_root.get_viewport()
				var world_mouse_pos = scene_viewport.get_mouse_position()
				# print("World mouse pos at drag start: ", world_mouse_pos)
				
				_drag_offset = clicked.global_position - world_mouse_pos
				# print("Drag offset: ", _drag_offset)
				# print("=== END DRAG START ===")
				return true

			_create_point(graph, mb.position)
			return true

		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			# print("DRAG END: _dragged_point was ", _dragged_point)
			_dragged_point = null
			return false

		# --- RIGHT Click: Delete junctioin ---
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var clicked := _find_point_at(graph, mb.position)

			if clicked != null:
				for point: JunctionPoint2D in graph.get_junctions():
					if point != clicked:
						point.exceptions.erase(clicked)

				if _exception_start == clicked:
					_exception_start = null

				clicked.queue_free()
				graph.call_deferred("rebuild_graph")
				return true

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _dragged_point != null:
			# print("DRAGGING: _dragged_point = ", _dragged_point)
			var scene_root = get_editor_interface().get_edited_scene_root()
			var scene_viewport = scene_root.get_viewport()
			var world_mouse_pos = scene_viewport.get_mouse_position()
			# print("Current world mouse pos: ", world_mouse_pos)
			# print("New position will be: ", world_mouse_pos + _drag_offset)
			
			_dragged_point.global_position = world_mouse_pos + _drag_offset
			graph.rebuild_graph()
			return true

	return false

func _find_point_at(graph: JunctionGraph2D, mouse_pos: Vector2) -> JunctionPoint2D:
	# Convert canvas coordinates to world coordinates using viewport
	var editor_interface = get_editor_interface()
	var scene_root = editor_interface.get_edited_scene_root()
	var scene_viewport = scene_root.get_viewport()
	var world_mouse_pos = scene_viewport.get_mouse_position()
	
	# print("=== _find_point_at DEBUG ===")
	# print("Canvas mouse_pos: ", mouse_pos)
	# print("World mouse_pos: ", world_mouse_pos)
	# print("Looking for points near: ", world_mouse_pos)
	
	for point: JunctionPoint2D in graph.get_junctions():
		var distance = point.global_position.distance_to(world_mouse_pos)
		# print("Point: ", point.name, " at ", point.global_position, " distance: ", distance, " (radius: ", point.radius, ")")
		if distance <= point.radius + 8.0:
			# print("FOUND POINT!")
			return point
	
	# print("No point found")
	return null

func _create_point(graph: JunctionGraph2D, mouse_pos: Vector2) -> void:
	# Create the node directly instead of instantiating from scene
	var point := POINT_SCENE.instantiate() as JunctionPoint2D
	#var point: JunctionPoint2D = JunctionPoint2D.new()
	point.name = _generate_name(graph)

	var editor_interface = get_editor_interface()
	var scene_root = editor_interface.get_edited_scene_root()
	
	var scene_viewport = scene_root.get_viewport()
	var world_pos = scene_viewport.get_mouse_position()
	
	var local_pos = graph.to_local(world_pos)
	
	point.position = local_pos

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
	push_error("Junction-Plugin: Konnte keinen freien Junction-Namen erzeugen!")
	return "Junction-Error"

func _toggle_exception(a: JunctionPoint2D, b: JunctionPoint2D) -> void:
	if a.exceptions.has(b):
		a.exceptions.erase(b)
		b.exceptions.erase(a)
	else:
		a.exceptions.append(b)
		b.exceptions.append(a)