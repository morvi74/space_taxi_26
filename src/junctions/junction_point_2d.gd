@tool
class_name JunctionPoint2D
extends Area2D
var is_at_landing_zone: bool = false
var my_landing_zone: Node2D = null

# @onready var _collision_shape: CollisionShape2D = $CollisionShape2D
# @onready var _sprite: Sprite2D = $Sprite2D


@export var point_color: Color = Color(1.0, 0.0, 0.0, 1.0):
	set(value):
		point_color = value
		queue_redraw()
		_notify_graph_changed()	

@export_range(2.0, 64.0, 1.0) var radius: float = 8.0:
	set(value):
		radius = value
		queue_redraw()
		_notify_graph_changed()

@export var exceptions: Array[JunctionPoint2D] = []:
	set(value):
		exceptions = value
		_notify_graph_changed()

func _ready() -> void:
	if not is_node_ready():
		return
	
	# Only connect in runtime, not in editor
	if not Engine.is_editor_hint():
		var body_entered_callable: Callable = Callable(self, "_on_body_entered")
		if not body_entered.is_connected(body_entered_callable):
			body_entered.connect(body_entered_callable)

		# Catch overlaps that already exist at scene start.
		await get_tree().physics_frame
		_process_startup_overlaps()
	
	queue_redraw()
	_notify_graph_changed()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, point_color)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_notify_graph_changed()

func _notify_graph_changed() -> void:
	var parent_node: Node = get_parent()
	if parent_node != null and parent_node is JunctionGraph2D:
		(parent_node as JunctionGraph2D).rebuild_graph()


func _process_startup_overlaps() -> void:
	for body: Node2D in get_overlapping_bodies():
		_register_landing_zone(body)


func _on_body_entered(body: Node2D) -> void:
	_register_landing_zone(body)


func _register_landing_zone(body: Node2D) -> void:
	if body == null:
		return
	if my_landing_zone == body and is_at_landing_zone:
		return

	if body is LandingPad:
		var lp: LandingPad = body as LandingPad
		print(name, ": I belong to LandingPad: ", lp.get_id())
		is_at_landing_zone = true
		my_landing_zone = body
