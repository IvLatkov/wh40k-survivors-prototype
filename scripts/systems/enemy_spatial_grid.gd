class_name EnemySpatialGrid
extends Node

@export_range(32.0, 256.0, 1.0) var cell_size: float = 80.0
@export_range(0.016, 0.2, 0.001) var grid_update_interval: float = 0.05

var _enemies: Array[Enemy] = []
var _cells: Dictionary = {}
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


func unregister_enemy(enemy: Enemy) -> void:
	_enemies.erase(enemy)


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
	_cells.clear()

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
			_cells[cell] = []
		var cell_enemies: Array = _cells[cell]
		cell_enemies.append(enemy)


func _world_to_cell(world_position: Vector2) -> Vector2i:
	var safe_cell_size := maxf(cell_size, 1.0)
	return Vector2i(
		floori(world_position.x / safe_cell_size),
		floori(world_position.y / safe_cell_size)
	)
