extends Node
class_name LevelManager

var _landing_pads: Array[LandingPad]

func _ready() -> void:
	var lps = get_tree().get_nodes_in_group("landing_pads")
	for i in range(lps.size()):
		if lps[i] is LandingPad:
			_landing_pads.append(lps[i])
	
	if _landing_pads.is_empty():
		printerr(name, ": No Landing Pads in Level. This should not happen!")
		return
	
	for i in range(_landing_pads.size()):
		_landing_pads[i].setup(i+1)