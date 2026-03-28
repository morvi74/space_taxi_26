extends StaticBody2D
## Represents the LandingPad component.
class_name LandingPad



## Inspector setting for id.
@export var _id: int = 0
## Returns id.
func get_id() -> int:
	return _id

#var _is_occupied: bool = false
## Checks whether occupied.
func is_occupied() -> bool:
	return _waiting_zone.is_occupied()

## Cached node reference for label id.
@onready var _label_id: Label = $IdLabel
## Cached node reference for waiting zone node.
@onready var _waiting_zone_node: Node = get_node_or_null("WaitingZone")

## Internal state for waiting zone.
var _waiting_zone: WaitingZone
## Returns waiting zone.
func get_waiting_zone() -> WaitingZone:
	return _waiting_zone

## Internal state for traffic node.
var _traffic_node: TrafficNode = null
## Returns traffic node.
func get_traffic_node() -> TrafficNode:
	return _traffic_node
## Updates traffic node.
func set_traffic_node(traffic_node: TrafficNode) -> void:
	_traffic_node = traffic_node


## Initializes runtime references and startup state.
func _ready() -> void:
	EventHub.taxi_landed.connect(_on_taxi_landed)

## Handles setup.
func setup(id: int) -> void:
	_id = id
	name = "LandingPad" + str(_id).pad_zeros(2)
	_label_id.text = str(_id).pad_zeros(2)
	_waiting_zone = _resolve_waiting_zone_direct()
	if _waiting_zone == null:
		printerr("Error: LandingPad ", _id, " has no waiting zone assigned. This should not happen if the level is set up correctly.")
	
	else:
		_waiting_zone.set_landing_pad(self)
	# else:
	# 	printerr("Error: LandingPad ", _id, " has no waiting zone assigned. This should not happen if the level is set up correctly.")


## Resolves waiting zone direct.
func _resolve_waiting_zone_direct() -> WaitingZone:
	if _waiting_zone_node is WaitingZone:
		return _waiting_zone_node as WaitingZone

	for child in get_children():
		var waiting_zone := child as WaitingZone
		if waiting_zone != null:
			return waiting_zone

	return null


# func _resolve_waiting_zone_by_rays() -> WaitingZone:
# 	_left_ray.collide_with_areas = true
# 	_right_ray.collide_with_areas = true
# 	_left_ray.force_raycast_update()
# 	_right_ray.force_raycast_update()

# 	if _left_ray.is_colliding():
# 		return _left_ray.get_collider() as WaitingZone
# 	if _right_ray.is_colliding():
# 		return _right_ray.get_collider() as WaitingZone

# 	printerr("Error: LandingPad ", _id, " has no waiting zone detected by direct child lookup or by rays. This can happen when the physics engine updates query state differently.")
# 	return null

## Handles assign passenger.
func assign_passenger(passenger: Passenger) -> void:
	_waiting_zone.set_passenger(passenger)

## Handles clear passenger.
func clear_passenger() -> void:
	_waiting_zone.clear_passenger()


## Handles the taxi landed callback.
func _on_taxi_landed(landing_pad: LandingPad, taxi_pos_x: float) -> void:
	if landing_pad == self:
		var passengers_in_taxi: Array[Passenger] = GameData.get_taxi().get_passengers_aboard()
		var passengers_to_remove_from_taxi: Array[int] = []
		for i in range(passengers_in_taxi.size()):
			if passengers_in_taxi[i].get_destination_landing_pad() == landing_pad:
				passengers_to_remove_from_taxi.append(i)
				passengers_in_taxi[i].exit_taxi()
		for i in range(passengers_to_remove_from_taxi.size()):
				GameData.get_taxi().erase_passenger_at(passengers_to_remove_from_taxi[i])
			
		if not GameData.get_taxi().is_full():
			_waiting_zone.send_passenger_to_taxi(taxi_pos_x)
