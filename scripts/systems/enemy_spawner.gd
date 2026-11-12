class_name EnemySpawner
extends Node

signal active_enemy_count_changed(current_count: int, target_count: int)

const ENEMY_SCENE := preload("res://scenes/enemies/enemy.tscn")
const NORMAL_BURST_EXPECTED_SIZE: float = 1.123
const RunClockScript = preload("res://scripts/systems/run_clock.gd")

@export_range(0.05, 60.0, 0.05) var spawn_interval: float = 0.6
@export_range(0.0, 2.0, 0.01) var first_spawn_delay: float = 0.25
@export_range(1, 1000, 1) var max_active_enemies: int = 200
@export var stress_test_enabled: bool = false
@export_range(1, 1000, 1) var stress_test_target: int = 200
@export_range(0.01, 1.0, 0.01) var stress_test_spawn_interval: float = 0.05
@export var minimum_spawn_margin: float = 24.0
@export var spawn_distance_variation: float = 48.0
@export var minimum_player_spawn_distance: float = 180.0
@export_range(0.0, 100.0, 1.0) var burst_position_offset: float = 40.0
@export_range(0.0, 100.0, 1.0) var chase_offset_range: float = 25.0
@export_range(0.0, 0.5, 0.01) var movement_speed_variation: float = 0.1
@export_range(0.0, 0.5, 0.01) var spawn_timing_variation: float = 0.2

@export_group("Enemy Types")
@export var tier_2_enemy_scene: PackedScene = preload("res://scenes/enemies/ork_boy.tscn")
@export_range(0.0, 3600.0, 1.0) var ork_unlock_seconds: float = 150.0
@export_range(0.0, 3600.0, 1.0) var ork_full_frequency_seconds: float = 300.0
@export_range(0.0, 1.0, 0.01) var ork_initial_spawn_factor: float = 0.10
@export_range(0.0, 1.0, 0.01) var ork_ramp_end_spawn_factor: float = 0.50

@export_group("Run Scaling")
@export_range(1, 600, 1) var spawn_tier_duration: int = 120
@export_range(0.0, 0.99, 0.01) var interval_reduction_per_tier: float = 0.1
@export_range(0.05, 1.0, 0.01) var minimum_spawn_interval: float = 0.22
@export var log_spawn_tier_changes: bool = false

@onready var player: Player = get_parent().get_node("Player")
@onready var spatial_grid: EnemySpatialGrid = $EnemySpatialGrid

var _run_clock: RunClockScript
var _elapsed_time: float = 0.0
var _active_enemy_count: int = 0
var _next_normal_spawn_delay: float
var _was_stress_test_enabled: bool
var spawn_tier: int = 0
var _has_scheduled_normal_spawn: bool = false
var normal_spawning_enabled: bool = true


func stop_normal_spawning() -> void:
	# Cancel the delta-based scheduler without touching living enemies or the
	# child spatial grid's physics processing. New runs get a fresh spawner.
	normal_spawning_enabled = false
	_elapsed_time = 0.0
	_has_scheduled_normal_spawn = false
	_next_normal_spawn_delay = INF
	set_process(false)


func bind_run_clock(clock: RunClockScript) -> void:
	_run_clock = clock
	clock.seconds_changed.connect(_on_run_seconds_changed)
	_on_run_seconds_changed(floori(clock.elapsed_time))


func get_effective_spawn_interval() -> float:
	return maxf(minimum_spawn_interval, spawn_interval * pow(1.0 - interval_reduction_per_tier, spawn_tier))


func _on_run_seconds_changed(seconds: int) -> void:
	var next_tier := floori(seconds / float(maxi(spawn_tier_duration, 1)))
	if next_tier == spawn_tier:
		return
	var previous_interval := get_effective_spawn_interval()
	spawn_tier = next_tier
	var current_interval := get_effective_spawn_interval()
	if _has_scheduled_normal_spawn:
		# Preserve progress and jitter when a tier changes between spawn events.
		var previous_delay := _next_normal_spawn_delay
		_next_normal_spawn_delay = maxf(minimum_spawn_interval, previous_delay * current_interval / previous_interval)
		_elapsed_time *= _next_normal_spawn_delay / previous_delay
	if log_spawn_tier_changes:
		print("Spawn tier increased to %d at %ds; base interval: %.3f" % [spawn_tier, seconds, current_interval])


func _ready() -> void:
	_was_stress_test_enabled = stress_test_enabled
	_next_normal_spawn_delay = first_spawn_delay


func _process(delta: float) -> void:
	if not normal_spawning_enabled:
		return
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
		_spawn_additional_orks()


func get_active_enemy_count() -> int:
	return _active_enemy_count


func get_target_enemy_count() -> int:
	return stress_test_target if stress_test_enabled else max_active_enemies


func get_average_separation_candidate_count() -> float:
	return spatial_grid.get_average_candidate_count()


func _spawn_burst(burst_size: int, enemy_scene: PackedScene = ENEMY_SCENE) -> void:
	if not normal_spawning_enabled:
		return
	var spawn_origin := _get_spawn_origin()
	for _index: int in burst_size:
		var offset_direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
		var position_offset := offset_direction * randf_range(0.0, burst_position_offset)
		_spawn_enemy(spawn_origin + position_offset, enemy_scene)


func _spawn_enemy(spawn_position: Vector2, enemy_scene: PackedScene = ENEMY_SCENE) -> void:
	if not CombatProfile.enabled:
		_profile_enemy_spawner_spawn_enemy(spawn_position, enemy_scene)
		return
	var profile_start := Time.get_ticks_usec()
	_profile_enemy_spawner_spawn_enemy(spawn_position, enemy_scene)
	CombatProfile.finish(&"enemy_spawn", profile_start)


func _profile_enemy_spawner_spawn_enemy(spawn_position: Vector2, enemy_scene: PackedScene = ENEMY_SCENE) -> void:
	if not normal_spawning_enabled:
		return
	var instantiate_start := Time.get_ticks_usec() if CombatProfile.enabled else 0
	var enemy := enemy_scene.instantiate() as Enemy
	CombatProfile.finish(&"enemy_instantiate", instantiate_start)
	if enemy == null:
		return

	var safe_position := find_clear_spawn_position(spawn_position, enemy)
	if safe_position == Vector2.INF:
		enemy.free()
		return
	enemy.position = (get_parent() as Node2D).to_local(safe_position)
	enemy.set_target(player)
	enemy.set_run_clock(_run_clock)
	enemy.set_spatial_grid(spatial_grid)
	var speed_variation := minf(movement_speed_variation, enemy.speed_variation_limit)
	enemy.configure_swarm_variation(
		Vector2(
			randf_range(-chase_offset_range, chase_offset_range),
			randf_range(-chase_offset_range, chase_offset_range)
		),
		randf_range(1.0 - speed_variation, 1.0 + speed_variation)
	)
	enemy.tree_exiting.connect(_on_enemy_tree_exiting)
	var insertion_start := Time.get_ticks_usec() if CombatProfile.enabled else 0
	get_parent().add_child(enemy)
	CombatProfile.finish(&"enemy_insertion", insertion_start)
	spatial_grid.register_enemy(enemy)
	_active_enemy_count += 1
	active_enemy_count_changed.emit(_active_enemy_count, get_target_enemy_count())


func find_clear_spawn_position(desired: Vector2, enemy: Enemy) -> Vector2:
	var forbidden := Rect2()
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		var size := get_viewport().get_visible_rect().size / camera.zoom
		var visible := Rect2(camera.get_screen_center_position() - size * 0.5, size).grow(minimum_spawn_margin)
		if not visible.has_point(desired):
			forbidden = visible.grow(enemy.get_body_radius())
	var distance := minf(minimum_player_spawn_distance, desired.distance_to(player.global_position))
	return TerrainObstacles.find_spawn_position(player.get_world_2d().direct_space_state, desired, enemy.get_body_radius(), player.global_position, distance, forbidden)


func get_ork_spawn_factor() -> float:
	if tier_2_enemy_scene == null or not is_instance_valid(_run_clock):
		return 0.0
	var seconds := _run_clock.elapsed_time
	if seconds < ork_unlock_seconds:
		return 0.0
	if seconds >= ork_full_frequency_seconds:
		# Deliberate difficulty jump: do not interpolate the final 50% to 100%.
		return 1.0
	var progress := (seconds - ork_unlock_seconds) / maxf(0.001, ork_full_frequency_seconds - ork_unlock_seconds)
	return lerpf(ork_initial_spawn_factor, ork_ramp_end_spawn_factor, progress)


func _spawn_additional_orks() -> void:
	if not normal_spawning_enabled:
		return
	# Squigs have already spawned at full cadence. Orks never replace that burst.
	# Preserve the shared active limit and give the original stream first claim.
	var remaining := get_target_enemy_count() - _active_enemy_count
	if remaining <= 0:
		return
	var ork_spawn_factor := get_ork_spawn_factor()
	if ork_spawn_factor <= 0.0:
		return
	if ork_spawn_factor < 1.0 and randf() >= ork_spawn_factor:
		return
	# Independent burst roll, with the same size distribution and spawn rules.
	_spawn_burst(mini(_roll_normal_burst_size(), remaining), tier_2_enemy_scene)


func _get_spawn_origin() -> Vector2:
	if not CombatProfile.enabled:
		return _profile_enemy_spawner_get_spawn_origin()
	var profile_start := Time.get_ticks_usec()
	var profile_result := _profile_enemy_spawner_get_spawn_origin()
	CombatProfile.finish(&"spawn_selection", profile_start)
	return profile_result


func _profile_enemy_spawner_get_spawn_origin() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := camera.zoom if camera != null else Vector2.ONE
	var visible_world_size := viewport_size / camera_zoom
	var view_center := camera.get_screen_center_position() if camera != null else player.global_position
	var spawn_direction := Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	# Intersect a ray from the player with the camera rectangle, including camera lag.
	# Reserve the burst offset so even the closest member stays outside the view.
	var half_extents := visible_world_size * 0.5 + Vector2.ONE * (minimum_spawn_margin + burst_position_offset)
	var player_offset := player.global_position - view_center
	var exit_x := INF
	var exit_y := INF
	if absf(spawn_direction.x) > 0.000001:
		exit_x = (half_extents.x - signf(spawn_direction.x) * player_offset.x) / absf(spawn_direction.x)
	if absf(spawn_direction.y) > 0.000001:
		exit_y = (half_extents.y - signf(spawn_direction.y) * player_offset.y) / absf(spawn_direction.y)
	var edge_distance := maxf(0.0, minf(exit_x, exit_y))
	var safe_distance := maxf(edge_distance, minimum_player_spawn_distance + burst_position_offset)
	var spawn_distance := safe_distance + randf_range(0.0, spawn_distance_variation)
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
	if not normal_spawning_enabled:
		return
	var timing_multiplier := randf_range(
		1.0 - spawn_timing_variation,
		1.0 + spawn_timing_variation
	)
	_has_scheduled_normal_spawn = true
	_next_normal_spawn_delay = maxf(minimum_spawn_interval, get_effective_spawn_interval() * NORMAL_BURST_EXPECTED_SIZE * timing_multiplier)


func _on_enemy_tree_exiting() -> void:
	_active_enemy_count = maxi(0, _active_enemy_count - 1)
	active_enemy_count_changed.emit(_active_enemy_count, get_target_enemy_count())
