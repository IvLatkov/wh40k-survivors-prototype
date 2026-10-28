extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func finish_prefetch(manager: ChunkManager) -> void:
	var slices: int = 0
	while not manager._prefetch_queue.is_empty() or manager._preparing != null:
		manager._prepare_pending_data()
		slices += 1
		assert(slices < 100)

func run() -> void:
	var player := Node2D.new()
	player.position = Vector2(512, 512)
	root.add_child(player)
	var manager := preload("res://scenes/systems/chunk_manager.tscn").instantiate() as ChunkManager
	manager.player = player
	root.add_child(manager)
	manager.set_process(false)
	manager.set_physics_process(false)
	manager._update_prefetch()
	assert(manager._prefetch_queue.is_empty())
	player.position.x = 767
	manager._update_prefetch()
	assert(manager._prefetch_queue.is_empty(), "Outside 256px band does no preparation")
	player.position.x = 800
	manager._update_prefetch()
	assert(manager._prefetch_queue.size() == 3)
	finish_prefetch(manager)
	assert(manager.prepared_chunks.size() == 3)
	var initial := manager.prepared_chunks.duplicate()
	for frame in 1000:
		manager._physics_process(1.0 / 60)
		manager._process(1.0 / 60)
	assert(manager.prepared_chunks == initial, "Stationary frames never regenerate completed data")
	player.position.y = 900
	manager._update_prefetch()
	finish_prefetch(manager)
	assert(manager.prepared_chunks.size() == 7 and manager.prepared_chunks.has(Vector2i(2, 2)), "Corners include the diagonal incoming chunk")
	player.position = Vector2(100, 512)
	manager._update_prefetch()
	finish_prefetch(manager)
	assert(manager.prepared_chunks.size() == 3)
	for coordinate: Vector2i in manager.prepared_chunks:
		assert(coordinate.x == -2, "Reversal evicts stale lookahead")
	player.position = Vector2(800, 512)
	manager._update_prefetch()
	finish_prefetch(manager)
	var prepared := manager.prepared_chunks[Vector2i(2, 0)]
	var previous := manager.active_chunks.duplicate()
	player.position.x = 1024
	manager._physics_process(1.0 / 60)
	assert(manager.active_chunks.size() == 9 and manager.terrain_chunks.get_child_count() == 9)
	assert(not manager.prepared_chunks.has(Vector2i(2, 0)), "Prepared data consumed on crossing")
	var chunk := manager.active_chunks[Vector2i(2, 0)]
	for y in 32:
		for x in 32:
			assert(chunk.ground.get_cell_atlas_coords(Vector2i(x, y)) == prepared.ground_cells[y * 32 + x])
	for coordinate: Vector2i in manager.active_chunks:
		if previous.has(coordinate):
			assert(previous[coordinate] == manager.active_chunks[coordinate])
	await process_frame
	# An unfinished task is completed and consumed if crossing comes early.
	manager._preparing = TerrainChunk.Generation.new(Vector2i(3, 0), 1024)
	manager._preparing.generate_row()
	player.position.x = 2048
	manager.update_chunks()
	assert(manager._preparing == null)
	assert(manager.active_chunks[Vector2i(3, 0)].ground.get_used_cells().size() == 1024)
	# Teleport fallback and negative edge lookahead stay bounded and hole-free.
	player.position = Vector2(-102400, -102400)
	manager._physics_process(1.0 / 60)
	finish_prefetch(manager)
	assert(manager.active_chunks.size() == 9 and manager.prepared_chunks.size() <= 7)
	manager.queue_free()
	player.queue_free()
	await process_frame
	print("PASS terrain prefetch: threshold, idle reuse, corners, reversals, consumption, partial task, teleport, bounded cache")
	quit()
