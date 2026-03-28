@tool
extends Node2D

## Initializes runtime references and startup state.
func _ready() -> void:
	add_to_group("OneWayLinks")


## Updates per-frame behavior.
func _process(_delta):
	# Run this only in the editor to avoid runtime overhead.
	if Engine.is_editor_hint():
		_snap_to_closest_node($PointA)
		_snap_to_closest_node($PointB)

## Internal helper that handles snap to closest node.
func _snap_to_closest_node(marker: Marker2D):
	var nodes = get_tree().get_nodes_in_group("traffic_nodes")
	var closest_node = null
	var min_dist = 50.0 # Snapping radius in pixels.

	for node in nodes:
		if node is Marker2D and node != marker:
			var dist = marker.global_position.distance_to(node.global_position)
			if dist < min_dist:
				min_dist = dist
				closest_node = node
	
	if closest_node:
		marker.global_position = closest_node.global_position
