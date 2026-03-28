extends Control


## Cached node reference for time label.
@onready var time_label: Label = $VBoxContainer/TimeLabel



## Updates per-frame behavior.
func _process(_delta: float) -> void:
	if time_label == null:
		return
	var now: Dictionary = Time.get_time_dict_from_system()
	time_label.text = "%02d:%02d:%02d" % [int(now.get("hour", 0)), int(now.get("minute", 0)), int(now.get("second", 0))]
