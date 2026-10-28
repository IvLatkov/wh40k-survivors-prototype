extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func average(values: Array[float]) -> float:
	return values.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / max(1, values.size())

func run() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var manager: ChunkManager = main.get_node("ChunkManager")
	var player: Player = main.get_node("Player")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	manager.set_physics_process(false)
	manager.set_process(false)
	player.set_physics_process(false)
	spawner.set_process(false)
	var stress := OS.get_cmdline_user_args().has("--stress")
	var cold := OS.get_cmdline_user_args().has("--cold")
	if stress:
		for index in 200:
			spawner._spawn_enemy(Vector2.from_angle(index * TAU / 200.0) * (600.0 + index % 5 * 30.0), spawner.tier_2_enemy_scene if index % 4 == 0 else spawner.ENEMY_SCENE)
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP,
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
	var transitions: Array[float] = []
	var frame_intervals: Array[float] = []
	var max_prefetch: float = 0.0
	var cache_peak: int = 0
	for step in 24:
		var direction := directions[step % directions.size()]
		var center := manager.current_chunk_coordinate
		var target := center + direction
		# Approach within the real threshold; give the same budgeted frame
		# callbacks used by normal play enough time to finish incoming data.
		var approach := Vector2(512, 512)
		if direction.x != 0:
			approach.x = 900 if direction.x > 0 else 124
		if direction.y != 0:
			approach.y = 900 if direction.y > 0 else 124
		player.position = Vector2(center) * 1024 + approach
		player.get_node("Camera2D").reset_smoothing()
		if stress:
			maintain_enemies(player, spawner)
		manager._update_prefetch()
		for frame in 40:
			var start := Time.get_ticks_usec()
			if not cold:
				manager._prepare_pending_data()
			max_prefetch = maxf(max_prefetch, (Time.get_ticks_usec() - start) / 1000.0)
			cache_peak = maxi(cache_peak, manager.prepared_chunks.size())
			assert(manager.prepared_chunks.size() <= manager.PREPARED_CACHE_LIMIT)
			assert(manager.terrain_chunks.get_child_count() == 9)
			await process_frame
		if not cold:
			for y in range(target.y - 1, target.y + 2):
				for x in range(target.x - 1, target.x + 2):
					var coordinate := Vector2i(x, y)
					assert(manager.active_chunks.has(coordinate) or manager.prepared_chunks.has(coordinate), "Incoming chunk was prefetched")
		var before := manager.active_chunks.duplicate()
		player.position = Vector2(target) * 1024 + Vector2(512, 512)
		player.get_node("Camera2D").reset_smoothing()
		if stress:
			maintain_enemies(player, spawner)
		var start := Time.get_ticks_usec()
		manager.update_chunks()
		transitions.append((Time.get_ticks_usec() - start) / 1000.0)
		assert(manager.active_chunks.size() == 9 and manager.terrain_chunks.get_child_count() == 9)
		var retained: int = 0
		for coordinate: Vector2i in manager.active_chunks:
			var chunk := manager.active_chunks[coordinate]
			assert(chunk.ground.get_used_cells().size() == 1024)
			assert(chunk.ground.tile_set == TerrainChunk._ground_tiles)
			assert(chunk.decorations.tile_set == TerrainChunk._decoration_tiles)
			if before.has(coordinate):
				assert(before[coordinate] == chunk)
				retained += 1
		assert(retained == (6 if direction.x == 0 or direction.y == 0 else 4))
		await process_frame
		frame_intervals.append((Time.get_ticks_usec() - start) / 1000.0)
	print("TERRAIN BENCH stress=", stress, " cold=", cold, " transitions=", transitions.size(),
		" update_ms avg=", average(transitions), " worst=", transitions.max(),
		" transition_frame_interval_ms avg=", average(frame_intervals), " worst=", frame_intervals.max(),
		" prefetch_worst_ms=", max_prefetch, " cache_peak=", cache_peak,
		" FPS=", Engine.get_frames_per_second(), " enemies=", spawner.get_active_enemy_count(),
		" objects=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	main.queue_free()
	await process_frame
	quit()


# Keep enemies in full simulation range, including 25% Orks, and let their
# existing AI, weapons and spatial grid run throughout every measured frame.
func maintain_enemies(player: Player, spawner: EnemySpawner) -> void:
	var index: int = 0
	for enemy in spawner.spatial_grid._enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		enemy.global_position = player.position + Vector2.from_angle(index * TAU / 200.0) * (600.0 + index % 5 * 30.0)
		index += 1
	while spawner.get_active_enemy_count() < 200:
		var count := spawner.get_active_enemy_count()
		spawner._spawn_enemy(player.position + Vector2(650, 0).rotated(count * TAU / 200.0), spawner.tier_2_enemy_scene if count % 4 == 0 else spawner.ENEMY_SCENE)
	spawner.spatial_grid._rebuild_grid()
