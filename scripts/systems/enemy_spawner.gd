class_name EnemySpawner
extends Node

signal active_enemy_count_changed(current_count: int, target_count: int)

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")

@export_range(0.05, 60.0, 0.05) var spawn_interval: float = 1.0
@export_range(1, 1000, 1) var max_active_enemies: int = 200
@export var stress_test_enabled: bool = false
@export_range(1, 1000, 1) var stress_test_target: int = 200
@export_range(0.01, 1.0, 0.01) var stress_test_spawn_interval: float = 0.05
@export var minimum_spawn_margin: float = 64.0
@export var spawn_distance_variation: float = 256.0

@onready var player: Player = get_parent().get_node("Player")
@onready var spatial_grid: EnemySpatialGrid = $EnemySpatialGrid

var _elapsed_time: float = 0.0
var _active_enemy_count: int = 0


func _process(delta: float) -> void:
	var target_count := get_target_enemy_count()
	if _active_enemy_count >= target_count:
		return

	_elapsed_time += delta
	var current_spawn_interval := stress_test_spawn_interval if stress_test_enabled else spawn_interval
	if _elapsed_time < current_spawn_interval:
		return

	_elapsed_time -= current_spawn_interval
	_spawn_enemy()


func get_active_enemy_count() -> int:
	return _active_enemy_count


func get_target_enemy_count() -> int:
	return stress_test_target if stress_test_enabled else max_active_enemies


func get_average_separation_candidate_count() -> float:
	return spatial_grid.get_average_candidate_count()


func _spawn_enemy() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	if enemy == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := camera.zoom if camera != null else Vector2.ONE
	var visible_world_size := viewport_size / camera_zoom
	var safe_radius := visible_world_size.length() + minimum_spawn_margin
	var spawn_distance := safe_radius + randf_range(0.0, spawn_distance_variation)
	var spawn_direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))

	enemy.global_position = player.global_position + spawn_direction * spawn_distance
	enemy.set_target(player)
	enemy.set_spatial_grid(spatial_grid)
	enemy.tree_exiting.connect(_on_enemy_tree_exiting)
	enemy.tree_exiting.connect(spatial_grid.unregister_enemy.bind(enemy))
	get_parent().add_child(enemy)
	spatial_grid.register_enemy(enemy)
	_active_enemy_count += 1
	active_enemy_count_changed.emit(_active_enemy_count, get_target_enemy_count())


func _on_enemy_tree_exiting() -> void:
	_active_enemy_count = maxi(0, _active_enemy_count - 1)
	active_enemy_count_changed.emit(_active_enemy_count, get_target_enemy_count())
