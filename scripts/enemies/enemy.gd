class_name Enemy
extends CharacterBody2D

const SQUIG_ANIMATIONS: Array[StringName] = [
	&"walk_green",
	&"walk_red",
	&"walk_purple",
]

@export var movement_speed: float = 100.0
@export var max_health: float = 50.0
@export var stop_distance: float = 35.0
@export var separation_radius: float = 40.0
@export_range(0.0, 2.0, 0.05) var separation_strength: float = 0.4
@export_range(0.016, 0.2, 0.001) var separation_update_interval: float = 0.05
@export var knockback_distance: float = 20.0
@export var knockback_duration: float = 0.12
@export var contact_damage: float = 1.0
@export var full_simulation_distance: float = 900.0
@export var reduced_simulation_distance: float = 1500.0
@export_range(0.05, 0.5, 0.01) var very_far_update_interval: float = 0.1

@onready var visual: AnimatedSprite2D = $Visual

var target: Node2D
var spatial_grid: EnemySpatialGrid
var current_health: float
var _is_knocked_back: bool = false
var _contact_knockback_ready: bool = true
var _knockback_direction: Vector2 = Vector2.ZERO
var _knockback_time_remaining: float = 0.0
var _knockback_distance_remaining: float = 0.0
var _very_far_elapsed_time: float = 0.0
var _full_simulation_enabled: bool = true
var _separation_elapsed_time: float = 0.0
var _cached_separation_direction: Vector2 = Vector2.ZERO
var _separation_candidates: Array[Enemy] = []
var _chase_offset: Vector2 = Vector2.ZERO
var _movement_speed_multiplier: float = 1.0
var _individual_movement_speed: float


func _ready() -> void:
	current_health = max_health
	_individual_movement_speed = movement_speed * _movement_speed_multiplier
	visual.play(SQUIG_ANIMATIONS.pick_random())


func set_target(new_target: Node2D) -> void:
	target = new_target


func set_spatial_grid(new_spatial_grid: EnemySpatialGrid) -> void:
	spatial_grid = new_spatial_grid


func configure_swarm_variation(chase_offset: Vector2, speed_multiplier: float) -> void:
	_chase_offset = chase_offset
	_movement_speed_multiplier = clampf(speed_multiplier, 0.1, 2.0)
	_individual_movement_speed = movement_speed * _movement_speed_multiplier


func take_damage(amount: float) -> void:
	current_health -= amount
	if current_health <= 0.0:
		die()


func die() -> void:
	queue_free()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		velocity = Vector2.ZERO
		return

	var chase_target_position := target.global_position + _chase_offset
	var distance_squared := global_position.distance_squared_to(target.global_position)
	var chase_distance_squared := global_position.distance_squared_to(chase_target_position)
	var stop_distance_squared := stop_distance * stop_distance
	var full_simulation_distance_squared := full_simulation_distance * full_simulation_distance
	var reduced_simulation_distance_squared := reduced_simulation_distance * reduced_simulation_distance
	var uses_full_simulation := distance_squared <= full_simulation_distance_squared
	_set_full_simulation_enabled(uses_full_simulation)

	if distance_squared > reduced_simulation_distance_squared:
		_process_very_far_movement(delta)
		return

	if _is_knocked_back:
		_process_knockback(delta)
		return

	if distance_squared > stop_distance_squared:
		_contact_knockback_ready = true
	elif _contact_knockback_ready:
		if target is Player:
			(target as Player).take_damage(contact_damage)
		_start_knockback()
		_process_knockback(delta)
		return

	var chase_direction := Vector2.ZERO
	if distance_squared > stop_distance_squared:
		if chase_distance_squared > stop_distance_squared:
			chase_direction = global_position.direction_to(chase_target_position)
		else:
			chase_direction = global_position.direction_to(target.global_position)

	var separation_direction := _get_separation_direction(delta) if uses_full_simulation else Vector2.ZERO
	var movement_direction := chase_direction + separation_direction * separation_strength
	velocity = movement_direction.limit_length(1.0) * _individual_movement_speed
	_update_visual_facing(velocity.x)

	move_and_slide()


func _start_knockback() -> void:
	_knockback_direction = (global_position - target.global_position).normalized()
	if _knockback_direction.is_zero_approx():
		_knockback_direction = Vector2.RIGHT

	_is_knocked_back = true
	_contact_knockback_ready = false
	_knockback_time_remaining = maxf(knockback_duration, 0.001)
	_knockback_distance_remaining = knockback_distance


func _process_knockback(delta: float) -> void:
	var safe_delta := maxf(delta, 0.000001)
	var knockback_speed := knockback_distance / maxf(knockback_duration, 0.001)
	var step_distance := minf(knockback_speed * safe_delta, _knockback_distance_remaining)
	velocity = _knockback_direction * step_distance / safe_delta
	_update_visual_facing(velocity.x)
	move_and_slide()

	_knockback_distance_remaining -= step_distance
	_knockback_time_remaining -= delta
	if _knockback_time_remaining <= 0.0 or _knockback_distance_remaining <= 0.0:
		_is_knocked_back = false
		velocity = Vector2.ZERO


func _update_visual_facing(horizontal_velocity: float) -> void:
	if not is_zero_approx(horizontal_velocity):
		visual.flip_h = horizontal_velocity < 0.0


func _set_full_simulation_enabled(enabled: bool) -> void:
	if _full_simulation_enabled == enabled:
		return

	_full_simulation_enabled = enabled
	if enabled:
		visual.play()
	else:
		_separation_candidates.clear()
		_cached_separation_direction = Vector2.ZERO
		visual.pause()


func _process_very_far_movement(delta: float) -> void:
	_very_far_elapsed_time += delta
	if _very_far_elapsed_time < very_far_update_interval:
		return

	var movement_direction := global_position.direction_to(target.global_position + _chase_offset)
	velocity = movement_direction * _individual_movement_speed
	_update_visual_facing(velocity.x)
	global_position += velocity * _very_far_elapsed_time
	_very_far_elapsed_time = 0.0


func _get_separation_direction(delta: float) -> Vector2:
	if not is_instance_valid(spatial_grid):
		_cached_separation_direction = Vector2.ZERO
		return _cached_separation_direction

	_separation_elapsed_time += delta
	if _separation_elapsed_time >= separation_update_interval:
		_separation_elapsed_time = fmod(_separation_elapsed_time, separation_update_interval)
		_cached_separation_direction = _calculate_separation_direction()

	return _cached_separation_direction


func _calculate_separation_direction() -> Vector2:
	var separation := Vector2.ZERO
	var radius_squared := separation_radius * separation_radius
	spatial_grid.append_nearby_candidates(global_position, _separation_candidates)

	for enemy: Enemy in _separation_candidates:
		if enemy == self or not is_instance_valid(enemy):
			continue

		var away := global_position - enemy.global_position
		var distance_squared := away.length_squared()
		if distance_squared >= radius_squared:
			continue

		if distance_squared <= 0.0001:
			separation += Vector2.RIGHT if get_instance_id() < enemy.get_instance_id() else Vector2.LEFT
			continue

		var distance := sqrt(distance_squared)
		var proximity_weight := 1.0 - distance / separation_radius
		separation += away / distance * proximity_weight

	return separation.limit_length(1.0)
