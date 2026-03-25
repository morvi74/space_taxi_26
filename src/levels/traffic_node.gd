extends Marker2D
class_name TrafficNode

@export var is_spawn_node: bool = false
@export var weight_modifier: float = 1.0
@export var can_be_destination: bool = false
@export var no_despawn: bool = false # If true, TrafficManager will never despawn cars at this node, even if they meet other despawn criteria. Useful for key locations like parking lots or garages that should remain active.

@onready var _detection_area: Area2D = $Area2D

var _landing_pad: LandingPad = null
func get_landing_pad() -> LandingPad:
	return _landing_pad
func set_landing_pad(landing_pad: LandingPad) -> void:
	_landing_pad = landing_pad

var _parking_lot: ParkikngLot = null
func get_parking_lot() -> ParkikngLot:
	return _parking_lot
func set_parking_lot(parking_lot: ParkikngLot) -> void:
	_parking_lot = parking_lot


func _ready() -> void:
	call_deferred("_bind_touching_surfaces")


func _bind_touching_surfaces() -> void:
	await get_tree().physics_frame
	if _landing_pad != null and _parking_lot != null:
		return

	if _detection_area == null:
		printerr(name, ": TrafficNode has no Area2D for surface detection.")
		return

	var touching_pads: Array[LandingPad] = []
	var seen_pad_ids: Dictionary = {}
	var touching_lots: Array[ParkikngLot] = []
	var seen_lot_ids: Dictionary = {}
	for body_variant: Variant in _detection_area.get_overlapping_bodies():
		var landing_pad: LandingPad = body_variant as LandingPad
		if landing_pad != null:
			var pad_id: int = landing_pad.get_instance_id()
			if seen_pad_ids.has(pad_id):
				continue
			seen_pad_ids[pad_id] = true
			touching_pads.append(landing_pad)

		var parking_lot: ParkikngLot = body_variant as ParkikngLot
		if parking_lot != null:
			var lot_id: int = parking_lot.get_instance_id()
			if seen_lot_ids.has(lot_id):
				continue
			seen_lot_ids[lot_id] = true
			touching_lots.append(parking_lot)

	# if touching_pads.is_empty():
	# 	printerr(name, ": Expected exactly 1 touching LandingPad, got 0")
	# 	return

	if touching_pads.size() > 1:
		printerr(name, ": Expected 0 or 1 touching LandingPad, got ", touching_pads.size())
		return
	if touching_lots.size() > 1:
		printerr(name, ": Expected 0 or 1 touching ParkingLot, got ", touching_lots.size())
		return

	if touching_pads.size() == 1:
		var candidate_pad: LandingPad = touching_pads[0]
		if candidate_pad.get_traffic_node() != null and candidate_pad.get_traffic_node() != self:
			printerr(name, ": LandingPad ", candidate_pad.name, " is already bound to TrafficNode ", candidate_pad.get_traffic_node().name)
			return

		set_landing_pad(candidate_pad)
		candidate_pad.set_traffic_node(self)

	if touching_lots.size() == 1:
		var candidate_lot: ParkikngLot = touching_lots[0]
		if candidate_lot.get_traffic_node() != null and candidate_lot.get_traffic_node() != self:
			printerr(name, ": ParkingLot ", candidate_lot.name, " is already bound to TrafficNode ", candidate_lot.get_traffic_node().name)
			return

		set_parking_lot(candidate_lot)
		candidate_lot.set_traffic_node(self)


# Runtime occupation state — managed by TrafficManager, not saved.
var is_occupied: bool = false

func claim() -> void:
	is_occupied = true

func release() -> void:
	is_occupied = false