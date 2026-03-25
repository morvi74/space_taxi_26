@tool
extends Node2D

@onready var _point_a: Node2D = $PointA
@onready var _point_b: Node2D = $PointB

@export var node_a: Node2D: 
	set(v): node_a = v; queue_redraw()
@export var node_b: Node2D: 
	set(v): node_b = v; queue_redraw()


func _ready() -> void:
	add_to_group("NoEntryLinks")
	if node_a == null and has_node("PointA"):
		node_a = _point_a
	if node_b == null and has_node("PointB"):
		node_b = _point_b

func _draw():
	if not Engine.is_editor_hint() or not (node_a and node_b): return
	var p1 = node_a.global_position - global_position
	var p2 = node_b.global_position - global_position
	
	# Thick red line with an "X" marker in the middle.
	draw_line(p1, p2, Color.TOMATO, 4.0)
	var mid = (p1 + p2) / 2.0
	draw_arc(mid, 10.0, 0, TAU, 16, Color.WHITE, 2.0) # Prohibition sign circle.