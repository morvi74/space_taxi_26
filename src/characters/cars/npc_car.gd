extends RigidBody2D
class_name NPCCar

signal destination_reached(car: NPCCar)

@export var speed: float = 200.0
@export var arrival_tolerance: float = 20.0
@export var steering_lerp: float = 5.0
@export var collision_recovery_time: float = 0.35
@export var collision_steer_lock_time: float = 0.18
@export var collision_recovery_steer_factor: float = 0.3
@export var post_collision_speed_factor: float = 0.7
@export var min_relative_impact_speed: float = 40.0
@export var collision_knockback_factor: float = 0.6
@export var max_knockback_impulse: float = 140.0
@export var impact_repeat_cooldown: float = 0.18

var current_path: PackedVector2Array = []
var path_index: int = 0
var _traffic_network: TrafficNetwork
var _traffic_manager: Node  # TrafficManager reference for requesting destinations
var _destination_node: TrafficNode
func get_destination_node() -> TrafficNode:
	return _destination_node

# Parking behavior
@export var parking_wait_chance: float = 0.35
@export var parking_wait_seconds: Vector2 = Vector2(2.0, 5.0)
@export var parking_lot_radius: float = 80.0
@export var despawn_node_distance: float = 26.0
@export var min_despawn_distance_to_player: float = 140.0
@export var building_collision_mask: int = 1 << 1

var _is_paused: bool = false
var _collision_recovery_left: float = 0.0
var _steer_lock_left: float = 0.0
var _impact_cooldowns: Dictionary = {}


func _ready() -> void:
	# Keep cars stable when they collide.
	lock_rotation = true
	# Damping prevents endless drifting.
	linear_damp = 2.0 
	contact_monitor = true
	max_contacts_reported = 6
	body_entered.connect(_on_body_entered)
	add_to_group("npc_cars")


func set_network(network: TrafficNetwork) -> void:
	_traffic_network = network


func set_traffic_manager(manager: Node) -> void:
	_traffic_manager = manager


func set_new_destination(target_pos: Vector2) -> bool:
	if _traffic_network == null:
		push_warning("NPCCar has no TrafficNetwork assigned.")
		return false

	current_path = _traffic_network.get_path_between(global_position, target_pos)
	path_index = 0
	return not current_path.is_empty()


func set_new_destination_node(target: TrafficNode) -> bool:
	_destination_node = target
	if _destination_node == null:
		return false
	return set_new_destination(_destination_node.global_position)


func has_active_path() -> bool:
	return not current_path.is_empty()


func pause_movement(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_is_paused = true
	await get_tree().create_timer(seconds).timeout
	_is_paused = false


func _physics_process(delta: float) -> void:
	_update_impact_cooldowns(delta)
	_process_collision_contacts()

	if _collision_recovery_left > 0.0:
		_collision_recovery_left = maxf(0.0, _collision_recovery_left - delta)
	if _steer_lock_left > 0.0:
		_steer_lock_left = maxf(0.0, _steer_lock_left - delta)

	if _is_paused:
		linear_velocity = linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
		return

	if _steer_lock_left > 0.0:
		# Let physics response play out briefly after impact before re-steering.
		return

	if current_path.is_empty():
		linear_velocity = linear_velocity.lerp(Vector2.ZERO, delta * 8.0)
		return

	var target_pos := current_path[path_index]
	var dist := global_position.distance_to(target_pos)

	if dist < arrival_tolerance:
		path_index += 1
		if path_index >= current_path.size():
			current_path = []
			linear_velocity = Vector2.ZERO
			destination_reached.emit(self)
			# Autonomously handle parking and next destination.
			_handle_destination_reached()
			return
		target_pos = current_path[path_index]

	# Drive with direct velocity control while keeping physics interactions.
	var direction := global_position.direction_to(target_pos)

	# During post-collision recovery, reduce steering authority so physics bounce can play out.
	var steer_factor := 1.0
	if _collision_recovery_left > 0.0:
		steer_factor = clampf(collision_recovery_steer_factor, 0.0, 1.0)
	linear_velocity = linear_velocity.lerp(direction * speed, delta * steering_lerp * steer_factor)

	# Flip both sprite and collision polygon horizontally based on travel direction.
	# CollisionPolygon2D has no flip_h, so scale.x = ±1 mirrors both consistently.
	if direction.x != 0:
		var facing: float = 1.0 if direction.x < 0 else -1.0
		$Sprite2D.scale.x = facing
		$CollisionPolygon2D.scale.x = facing


func _on_body_entered(body: Node) -> void:
	_apply_collision_response(body)


func _update_impact_cooldowns(delta: float) -> void:
	var expired_ids: Array[int] = []
	for body_id_variant: Variant in _impact_cooldowns.keys():
		var body_id: int = int(body_id_variant)
		var time_left: float = float(_impact_cooldowns[body_id]) - delta
		if time_left <= 0.0:
			expired_ids.append(body_id)
		else:
			_impact_cooldowns[body_id] = time_left

	for body_id: int in expired_ids:
		_impact_cooldowns.erase(body_id)


func _process_collision_contacts() -> void:
	for body_variant: Variant in get_colliding_bodies():
		var body: Node = body_variant as Node
		if body == null:
			continue
		_apply_collision_response(body)


func _apply_collision_response(body: Node) -> void:
	var body_id: int = body.get_instance_id()
	if _impact_cooldowns.has(body_id):
		return
	_impact_cooldowns[body_id] = impact_repeat_cooldown

	var self_velocity_before: Vector2 = linear_velocity
	_collision_recovery_left = maxf(_collision_recovery_left, collision_recovery_time)
	_steer_lock_left = maxf(_steer_lock_left, collision_steer_lock_time)
	linear_velocity = self_velocity_before * post_collision_speed_factor

	var other_velocity: Vector2 = _get_body_linear_velocity(body)
	var relative_speed: float = (self_velocity_before - other_velocity).length()
	if relative_speed < min_relative_impact_speed:
		return

	var away: Vector2 = Vector2.ZERO
	if body is Node2D:
		away = (global_position - (body as Node2D).global_position).normalized()
	if away == Vector2.ZERO:
		away = self_velocity_before.normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT

	var impulse_magnitude: float = minf(relative_speed * mass * collision_knockback_factor, max_knockback_impulse)
	apply_central_impulse(away * impulse_magnitude)


func _get_body_linear_velocity(body: Node) -> Vector2:
	if body is RigidBody2D:
		return (body as RigidBody2D).linear_velocity
	if body is CharacterBody2D:
		return (body as CharacterBody2D).velocity
	return Vector2.ZERO


func _handle_destination_reached() -> void:
	"""Called when the car reaches its destination. Handles parking logic and requests next destination."""
	if _should_despawn_here():
		queue_free()
		return

	if _should_park():
		var wait_seconds: float = randf_range(parking_wait_seconds.x, parking_wait_seconds.y)
		await pause_movement(wait_seconds)
	
	_request_next_destination()


func _should_park() -> bool:
	"""Decide whether to park at current location based on proximity and chance and location."""
	if not _is_near_parking_lot():
		return false
	if randf() > parking_wait_chance:
		return false
	return true


func _is_near_parking_lot() -> bool:
	"""Check if car is near any parking lot."""
	for lot in get_tree().get_nodes_in_group("parking_lots"):
		if lot is Node2D and global_position.distance_to((lot as Node2D).global_position) <= parking_lot_radius:
			return true

	# for lot in get_tree().get_nodes_in_group("landing_pads"):
	# 	if lot is Node2D and global_position.distance_to((lot as Node2D).global_position) <= parking_lot_radius:
	# 		return true

	return false


func _request_next_destination() -> void:
	"""Request the next destination from TrafficManager."""
	if _traffic_manager == null or not _traffic_manager.has_method("request_next_destination"):
		return
	
	var closest_node: TrafficNode = _traffic_network.get_closest_node(global_position) if _traffic_network else null
	var next_dest: TrafficNode = _traffic_manager.request_next_destination(self, closest_node)
	if next_dest != null:
		set_new_destination_node(next_dest)


func _should_despawn_here() -> bool:
	if _traffic_network == null:
		return false

	var closest_spawn: TrafficNode = _traffic_network.get_closest_spawn_node(global_position)
	if closest_spawn == null:
		return false
	if closest_spawn.no_despawn:
		return false
	if global_position.distance_to(closest_spawn.global_position) > despawn_node_distance:
		return false
	return _is_despawn_location_valid(closest_spawn)


func _is_despawn_location_valid(node: TrafficNode) -> bool:
	if node == null or not node.is_spawn_node:
		return false
	if node.can_be_destination and node.is_occupied:
		return false

	var player_node: Node2D = GameData.get_taxi() as Node2D
	if player_node != null and node.global_position.distance_to(player_node.global_position) < min_despawn_distance_to_player:
		return false

	if not _is_point_visible_for_player(node.global_position):
		return true

	return _is_occluded_by_building(node.global_position)


func _is_point_visible_for_player(point: Vector2) -> bool:
	var player_camera: Camera2D = get_viewport().get_camera_2d()
	if player_camera == null:
		return false

	var viewport_rect: Rect2 = player_camera.get_viewport_rect()
	var world_size: Vector2 = viewport_rect.size * player_camera.zoom
	var top_left: Vector2 = player_camera.get_screen_center_position() - world_size * 0.5
	var world_rect: Rect2 = Rect2(top_left, world_size)
	return world_rect.has_point(point)


func _is_occluded_by_building(point: Vector2) -> bool:
	var player_node: Node2D = GameData.get_taxi() as Node2D
	var player_camera: Camera2D = get_viewport().get_camera_2d()
	var origin: Vector2 = Vector2.ZERO
	if player_node != null:
		origin = player_node.global_position
	elif player_camera != null:
		origin = player_camera.get_screen_center_position()
	else:
		return false

	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, point)
	query.collision_mask = building_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var world_2d: World2D = get_viewport().world_2d
	if world_2d == null:
		return false
	var space_state: PhysicsDirectSpaceState2D = world_2d.direct_space_state
	var hit: Dictionary = space_state.intersect_ray(query)
	return not hit.is_empty()