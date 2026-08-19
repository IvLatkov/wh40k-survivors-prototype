class_name EnemySpawner
extends Node

signal active_enemy_count_changed(current_count: int, target_count: int)

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const NORMAL_BURST_EXPECTED_SIZE: float = 1.123

@export_range(0.05, 60.0, 0.05) var spawn_interval: float = 1.0
@export_range(1, 1000, 1) var max_active_enemies: int = 200
@export var stress_test_enabled: bool = false
@export_range(1, 1000, 1) var stress_test_target: int = 200
@export_range(0.01, 1.0, 0.01) var stress_test_spawn_interval: float = 0.05
@export var minimum_spawn_margin: float = 64.0
@export var spawn_distance_variation: float = 256.0
@export_range(0.0, 100.0, 1.0) var burst_position_offset: float = 40.0
@export_range(0.0, 100.0, 1.0) var chase_offset_range: float = 25.0
@export_range(0.0, 0.5, 0.01) var movement_speed_variation: float = 0.1
@export_range(0.0, 0.5, 0.01) var spawn_timing_variation: float = 0.2

@onready var player: Player = get_parent().get_node("Player")
@onready var spatial_grid: EnemySpatialGrid = $EnemySpatialGrid

var _elapsed_time: float = 0.0
var _active_enemy_count: int = 0
var _next_normal_spawn_delay: float
var _was_stress_test_enabled: bool


func _ready() -> void:
	_was_stress_test_enabled = stress_test_enabled
	_schedule_next_normal_spawn()


func _process(delta: float) -> void:
	if stress_test_enabled != _was_stress_test_enabled:
		_was_stress_test_enabled = stress_test_enabled
		_elapsed_time = 0.0

	var target_count := get_target_enemy_count()
	if _active_enemy_count >= target_count:
		return

	_elapsed_time += delta
	var current_spawn_interval := stress_test_spawn_interval if stress_test_enabled else _next_normal_spawn_delay
	if _elapsed_time < current_spawn_interval:
		return

	_elapsed_time -= current_spawn_interval
	var burst_size := 1 if stress_test_enabled else _roll_normal_burst_size()
	_spawn_burst(mini(burst_size, target_count - _active_enemy_count))
	if not stress_test_enabled:
		_schedule_next_normal_spawn()


func get_active_enemy_count() -> int:
	return _active_enemy_count


func get_target_enemy_count() -> int:
	return stress_test_target if stress_test_enabled else max_active_enemies


func get_average_separation_candidate_count() -> float:
	return spatial_grid.get_average_candidate_count()


func _spawn_burst(burst_size: int) -> void:
	var spawn_origin := _get_spawn_origin()
	for _index: int in burst_size:
		var offset_direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		var position_offset := offset_direction * randf_range(0.0, burst_position_offset)
		_spawn_enemy(spawn_origin + position_offset)


func _spawn_enemy(spawn_position: Vector2) -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	if enemy == null:
		return

	enemy.global_position = spawn_position
	enemy.set_target(player)
	enemy.set_spatial_grid(spatial_grid)
	enemy.configure_swarm_variation(
		Vector2(
			randf_range(-chase_offset_range, chase_offset_range),
			randf_range(-chase_offset_range, chase_offset_range)
		),
		randf_range(1.0 - movement_speed_variation, 1.0 + movement_speed_variation)
	)
	enemy.tree_exiting.connect(_on_enemy_tree_exiting)
	enemy.tree_exiting.connect(spatial_grid.unregister_enemy.bind(enemy))
	get_parent().add_child(enemy)
	spatial_grid.register_enemy(enemy)
	_active_enemy_count += 1
	active_enemy_count_changed.emit(_active_enemy_count, get_target_enemy_count())


func _get_spawn_origin() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := camera.zoom if camera != null else Vector2.ONE
	var visible_world_size := viewport_size / camera_zoom
	var safe_radius := visible_world_size.length() + minimum_spawn_margin
	var spawn_distance := safe_radius + randf_range(0.0, spawn_distance_variation)
	var spawn_direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	return player.global_position + spawn_direction * spawn_distance


func _roll_normal_burst_size() -> int:
	var roll := randf()
	if roll < 0.92:
		return 1
	if roll < 0.97:
		return 2
	if roll < 0.99:
		return 3
	if roll < 0.997:
		return 4
	return 5


func _schedule_next_normal_spawn() -> void:
	var timing_multiplier := randf_range(
		1.0 - spawn_timing_variation,
		1.0 + spawn_timing_variation
	)
	_next_normal_spawn_delay = spawn_interval * NORMAL_BURST_EXPECTED_SIZE * timing_multiplier


func _on_enemy_tree_exiting() -> void:
	_active_enemy_count = maxi(0, _active_enemy_count - 1)
	active_enemy_count_changed.emit(_active_enemy_count, get_target_enemy_count())
