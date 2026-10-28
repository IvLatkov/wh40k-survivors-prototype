class_name ChunkManager
extends Node2D

signal chunk_grid_changed(center_coordinate: Vector2i)

const ACTIVE_RADIUS: int = 1

@export var player: Node2D
@export var chunk_scene: PackedScene = preload("res://scenes/systems/terrain_chunk.tscn")
@export_range(1, 8192, 1) var chunk_size: int = 1024
@export var debug_chunk_changes: bool = false
@export_range(0.0, 0.49, 0.01) var prefetch_threshold: float = 0.25
@export_range(0.1, 4.0, 0.1) var prefetch_budget_ms: float = 1.5

const PREPARED_CACHE_LIMIT: int = 9
@export var profile_transitions: bool = false
var last_transition_profile: Dictionary = {}

var prepared_chunks: Dictionary[Vector2i, TerrainChunk.ChunkData] = {}
var _prefetch_queue: Array[Vector2i] = []
var _preparing: TerrainChunk.Generation
var _prefetch_direction := Vector2i(2, 2)
var _prefetch_center := Vector2i.ZERO

@onready var terrain_chunks: Node2D = $TerrainChunks

var active_chunks: Dictionary[Vector2i, TerrainChunk] = {}
var current_chunk_coordinate: Vector2i = Vector2i.ZERO
var _has_center_chunk: bool = false


func _ready() -> void:
	update_chunks()


func _physics_process(_delta: float) -> void:
	update_chunks()
	_update_prefetch()


func _process(_delta: float) -> void:
	_prepare_pending_data()


func get_chunk_coordinate(world_position: Vector2) -> Vector2i:
	# Terrain-local coordinates keep the manager independent of world parenting.
	var terrain_position := terrain_chunks.to_local(world_position)
	return Vector2i(floori(terrain_position.x / chunk_size), floori(terrain_position.y / chunk_size))


func update_chunks() -> void:
	if not is_instance_valid(player):
		return
	var started := Time.get_ticks_usec() if profile_transitions else 0
	var center := get_chunk_coordinate(player.global_position)
	if _has_center_chunk and center == current_chunk_coordinate:
		return
	var profile: Dictionary = {"coordinate": Time.get_ticks_usec() - started if profile_transitions else 0,
		"instantiate": 0, "insert": 0, "cleanup": 0, "generation": 0,
		"ground_generation": 0, "decoration_generation": 0, "ground_population": 0,
		"decoration_population": 0, "cache_hits": 0, "created": 0, "removed": 0}
	current_chunk_coordinate = center
	_has_center_chunk = true
	var stage := Time.get_ticks_usec() if profile_transitions else 0
	var obsolete: Array[Vector2i] = []
	for coordinate: Vector2i in active_chunks:
		if absi(coordinate.x - center.x) > ACTIVE_RADIUS or absi(coordinate.y - center.y) > ACTIVE_RADIUS:
			obsolete.append(coordinate)
	profile["obsolete_detection"] = Time.get_ticks_usec() - stage if profile_transitions else 0
	stage = Time.get_ticks_usec() if profile_transitions else 0
	var missing: Array[Vector2i] = []
	for y in range(center.y - ACTIVE_RADIUS, center.y + ACTIVE_RADIUS + 1):
		for x in range(center.x - ACTIVE_RADIUS, center.x + ACTIVE_RADIUS + 1):
			var coordinate := Vector2i(x, y)
			if not active_chunks.has(coordinate):
				missing.append(coordinate)
	profile["missing_detection"] = Time.get_ticks_usec() - stage if profile_transitions else 0
	stage = Time.get_ticks_usec() if profile_transitions else 0
	for coordinate in obsolete:
		var chunk := active_chunks[coordinate]
		active_chunks.erase(coordinate)
		terrain_chunks.remove_child(chunk)
		chunk.queue_free()
	profile["cleanup"] = Time.get_ticks_usec() - stage if profile_transitions else 0
	for coordinate in missing:
		stage = Time.get_ticks_usec() if profile_transitions else 0
		var chunk := chunk_scene.instantiate() as TerrainChunk
		chunk.profile_generation = profile_transitions
		profile["instantiate"] += Time.get_ticks_usec() - stage if profile_transitions else 0
		stage = Time.get_ticks_usec() if profile_transitions else 0
		var data: TerrainChunk.ChunkData = prepared_chunks.get(coordinate)
		if data != null:
			profile["cache_hits"] += 1
		prepared_chunks.erase(coordinate)
		if data == null and _preparing != null and _preparing.coordinate == coordinate:
			_preparing.profile_enabled = profile_transitions
			while not _preparing.is_complete():
				_preparing.generate_row()
			data = _preparing.data
			profile["ground_generation"] += _preparing.ground_usec
			profile["decoration_generation"] += _preparing.decoration_usec
			_preparing = null
		if data == null:
			var generation := TerrainChunk.Generation.new(coordinate, chunk_size)
			generation.profile_enabled = profile_transitions
			while not generation.is_complete():
				generation.generate_row()
			data = generation.data
			profile["ground_generation"] += generation.ground_usec
			profile["decoration_generation"] += generation.decoration_usec
		profile["generation"] += Time.get_ticks_usec() - stage if profile_transitions else 0
		chunk.configure(coordinate, chunk_size, data)
		stage = Time.get_ticks_usec() if profile_transitions else 0
		terrain_chunks.add_child(chunk)
		profile["insert"] += Time.get_ticks_usec() - stage if profile_transitions else 0
		profile["ground_population"] += chunk.ground_population_usec
		profile["decoration_population"] += chunk.decoration_population_usec
		active_chunks[coordinate] = chunk
	profile["created"] = missing.size()
	profile["removed"] = obsolete.size()
	chunk_grid_changed.emit(center)
	profile["total"] = Time.get_ticks_usec() - started if profile_transitions else 0
	if profile_transitions:
		last_transition_profile = profile
	if debug_chunk_changes:
		print("Terrain transition ", center, " ", profile)


# Rebuild the small candidate list only when entering/leaving an edge band or
# changing center. Position checks are cheap; no cell data is rebuilt per frame.
func _update_prefetch() -> void:
	if not is_instance_valid(player):
		return
	var local_position := terrain_chunks.to_local(player.global_position) - Vector2(current_chunk_coordinate) * chunk_size
	var threshold := chunk_size * prefetch_threshold
	var direction := Vector2i.ZERO
	if local_position.x < threshold:
		direction.x = -1
	elif local_position.x > chunk_size - threshold:
		direction.x = 1
	if local_position.y < threshold:
		direction.y = -1
	elif local_position.y > chunk_size - threshold:
		direction.y = 1
	if direction == _prefetch_direction and current_chunk_coordinate == _prefetch_center:
		return
	_prefetch_direction = direction
	_prefetch_center = current_chunk_coordinate
	_prefetch_queue.clear()
	var wanted: Dictionary[Vector2i, bool] = {}
	var centers: Array[Vector2i] = []
	if direction.x != 0:
		centers.append(current_chunk_coordinate + Vector2i(direction.x, 0))
	if direction.y != 0:
		centers.append(current_chunk_coordinate + Vector2i(0, direction.y))
	if direction.x != 0 and direction.y != 0:
		centers.append(current_chunk_coordinate + direction)
	for center in centers:
		for y in range(center.y - ACTIVE_RADIUS, center.y + ACTIVE_RADIUS + 1):
			for x in range(center.x - ACTIVE_RADIUS, center.x + ACTIVE_RADIUS + 1):
				var coordinate := Vector2i(x, y)
				if active_chunks.has(coordinate) or wanted.has(coordinate):
					continue
				wanted[coordinate] = true
				if not prepared_chunks.has(coordinate):
					_prefetch_queue.append(coordinate)
	# Discard stale work on reversals/teleports, retaining only likely incoming
	# data. Corner lookahead needs at most seven prepared coordinates.
	for coordinate: Vector2i in prepared_chunks.keys():
		if not wanted.has(coordinate):
			prepared_chunks.erase(coordinate)
	if _preparing != null and not wanted.has(_preparing.coordinate):
		_preparing = null


func _prepare_pending_data() -> void:
	var deadline := Time.get_ticks_usec() + int(prefetch_budget_ms * 1000.0)
	while Time.get_ticks_usec() < deadline:
		if _preparing == null:
			if _prefetch_queue.is_empty() or prepared_chunks.size() >= PREPARED_CACHE_LIMIT:
				return
			var coordinate: Vector2i = _prefetch_queue.pop_front()
			if active_chunks.has(coordinate) or prepared_chunks.has(coordinate):
				continue
			_preparing = TerrainChunk.Generation.new(coordinate, chunk_size)
		_preparing.generate_row()
		if _preparing.is_complete():
			prepared_chunks[_preparing.coordinate] = _preparing.data
			_preparing = null

