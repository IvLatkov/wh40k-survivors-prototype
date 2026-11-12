class_name EnemySpatialGrid
extends Node

@export_range(32.0, 256.0, 1.0) var cell_size: float = 80.0
@export_range(0.016, 0.2, 0.001) var grid_update_interval: float = 0.05

var _enemies: Array[Enemy] = []
var _cells: Dictionary = {}
var _enemy_cells: Dictionary = {}
var _empty_bucket: Array[Enemy] = []
var _recycled_buckets: Array = []
var _elapsed_time: float = 0.0
var _candidate_query_count: int = 0
var _candidate_result_count: int = 0


func _physics_process(delta: float) -> void:
	_elapsed_time += delta
	if _elapsed_time < grid_update_interval:
		return

	_elapsed_time = fmod(_elapsed_time, grid_update_interval)
	_rebuild_grid()


func register_enemy(enemy: Enemy) -> void:
	if not _enemies.has(enemy):
		_enemies.append(enemy)
		var remove := unregister_enemy.bind(enemy)
		if not enemy.tree_exiting.is_connected(remove):
			enemy.tree_exiting.connect(remove, CONNECT_ONE_SHOT)


func unregister_enemy(enemy: Enemy) -> void:
	_enemies.erase(enemy)
	if _enemy_cells.has(enemy):
		var cell: Vector2i = _enemy_cells[enemy]
		var bucket: Array[Enemy] = _cells[cell]
		bucket.erase(enemy)
		_enemy_cells.erase(enemy)


func append_nearby_candidates(world_position: Vector2, output: Array[Enemy]) -> void:
	output.clear()
	var center_cell := _world_to_cell(world_position)

	for y_offset: int in range(-1, 2):
		for x_offset: int in range(-1, 2):
			var cell := center_cell + Vector2i(x_offset, y_offset)
			var cell_enemies: Array = _cells.get(cell, [])
			for candidate: Variant in cell_enemies:
				if not is_instance_valid(candidate):
					continue
				var enemy := candidate as Enemy
				if enemy != null:
					output.append(enemy)

	_candidate_query_count += 1
	_candidate_result_count += output.size()


func get_average_candidate_count() -> float:
	if _candidate_query_count == 0:
		return 0.0
	return float(_candidate_result_count) / float(_candidate_query_count)


func _rebuild_grid() -> void:
	if not CombatProfile.enabled:
		_profile_enemy_spatial_grid_rebuild_grid()
		return
	var profile_start := Time.get_ticks_usec()
	_profile_enemy_spatial_grid_rebuild_grid()
	CombatProfile.finish(&"grid_rebuild", profile_start)


func _profile_enemy_spatial_grid_rebuild_grid() -> void:
	# Reuse empty buckets across rebuilds; preserve the exact insertion/query order.
	for bucket: Array in _cells.values():
		bucket.clear()
		_recycled_buckets.append(bucket)
	_cells.clear()
	_enemy_cells.clear()

	for index: int in range(_enemies.size() - 1, -1, -1):
		var candidate: Variant = _enemies[index]
		if not is_instance_valid(candidate):
			_enemies.remove_at(index)
			continue
		var enemy := candidate as Enemy
		if enemy == null or not enemy.is_inside_tree():
			_enemies.remove_at(index)
			continue

		var cell := _world_to_cell(enemy.global_position)
		if not _cells.has(cell):
			if not _recycled_buckets.is_empty():
				_cells[cell] = _recycled_buckets.pop_back()
			else:
				var bucket: Array[Enemy] = []
				_cells[cell] = bucket
		var cell_enemies: Array[Enemy] = _cells[cell]
		cell_enemies.append(enemy)
		_enemy_cells[enemy] = cell


func _world_to_cell(world_position: Vector2) -> Vector2i:
	var safe_cell_size := maxf(cell_size, 1.0)
	return Vector2i(
		floori(world_position.x / safe_cell_size),
		floori(world_position.y / safe_cell_size)
	)


func append_candidates_in_radius(world_position: Vector2, radius: float, output: Array[Enemy]) -> void:
	output.clear()
	# Include one update interval of movement padding for the periodically rebuilt grid.
	var padding := maxf(cell_size, 1.0)
	var extent := Vector2.ONE * (radius + padding)
	var first := _world_to_cell(world_position - extent)
	var last := _world_to_cell(world_position + extent)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for candidate: Variant in _cells.get(Vector2i(x, y), []):
				if is_instance_valid(candidate) and candidate is Enemy:
					output.append(candidate)


func calculate_separation(subject: Enemy) -> Vector2:
	# Same cell/candidate order and live positions as the former two-pass query.
	# Iterate buckets directly instead of copying and validating each candidate twice.
	var origin := subject.global_position
	var center := _world_to_cell(origin)
	var radius := subject.separation_radius
	var radius_squared := radius * radius
	var separation := Vector2.ZERO
	var candidate_count := 0
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var bucket: Array[Enemy] = _cells.get(Vector2i(x, y), _empty_bucket)
			candidate_count += bucket.size()
			for enemy: Enemy in bucket:
				if enemy == subject:
					continue
				var away := origin - enemy.global_position
				var distance_squared := away.length_squared()
				if distance_squared >= radius_squared:
					continue
				if distance_squared <= 0.0001:
					separation += Vector2.RIGHT if subject.get_instance_id() < enemy.get_instance_id() else Vector2.LEFT
					continue
				var distance := sqrt(distance_squared)
				var weight := 1.0 - distance / radius
				separation += away / distance * weight
	_candidate_query_count += 1
	_candidate_result_count += candidate_count
	CombatProfile.query(&"separation", candidate_count)
	return separation.limit_length(1.0)
