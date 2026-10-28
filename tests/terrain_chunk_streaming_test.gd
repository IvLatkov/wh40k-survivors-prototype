extends SceneTree

var checks: int = 0
var grid_changes: int = 0
var manager: ChunkManager
var player: Player

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func verify_grid(center: Vector2i) -> void:
	check(manager.current_chunk_coordinate == center, "Player chunk is the grid center")
	check(manager.active_chunks.size() == 9 and manager.terrain_chunks.get_child_count() == 9, "Exactly nine active terrain chunks")
	var instance_ids: Dictionary = {}
	for y in range(center.y - 1, center.y + 2):
		for x in range(center.x - 1, center.x + 2):
			var coordinate := Vector2i(x, y)
			check(manager.active_chunks.has(coordinate), "Every neighbor exists")
			var chunk := manager.active_chunks[coordinate]
			instance_ids[chunk.get_instance_id()] = true
			check(chunk.chunk_coordinate == coordinate and chunk.position == Vector2(coordinate) * 1024.0 and chunk.chunk_size == 1024, "Exact coordinate, size, and aligned position")
			check(chunk.get_parent() == manager.terrain_chunks and chunk.get_child_count() == 2 and chunk.ground is TileMapLayer and chunk.decorations is TileMapLayer, "Chunk owns only terrain")
			check(chunk.chunk_seed == hash(coordinate), "Stable coordinate-derived seed")
			var rect := Rect2(chunk.position, Vector2.ONE * chunk.chunk_size)
			if x < center.x + 1:
				var right := manager.active_chunks[coordinate + Vector2i.RIGHT]
				var right_rect := Rect2(right.position, Vector2.ONE * right.chunk_size)
				check(rect.end.x == right_rect.position.x and not rect.intersects(right_rect), "Horizontal borders meet without gaps or overlap")
			if y < center.y + 1:
				var down := manager.active_chunks[coordinate + Vector2i.DOWN]
				var down_rect := Rect2(down.position, Vector2.ONE * down.chunk_size)
				check(rect.end.y == down_rect.position.y and not rect.intersects(down_rect), "Vertical borders meet without gaps or overlap")
	check(instance_ids.size() == 9, "No duplicate chunk instances")

func run() -> void:
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	manager = main.get_node("ChunkManager")
	player = main.get_node("Player")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	spawner.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	manager.set_physics_process(false)
	manager.chunk_grid_changed.connect(func(_center: Vector2i) -> void: grid_changes += 1)
	check(manager.player == player and manager.chunk_size == 1024, "Manager tracks existing player with 1024 pixel chunks")
	check(manager.process_physics_priority > player.process_physics_priority, "Streaming runs after player physics movement")
	check(manager.terrain_chunks.z_index == -10, "Terrain remains behind combat")
	verify_grid(Vector2i.ZERO)
	var initial := manager.active_chunks.duplicate()
	for _frame in 1000:
		manager._physics_process(1.0 / 60.0)
	check(grid_changes == 0 and manager.active_chunks == initial, "Unchanged player chunk never rebuilds terrain")
	var coordinate_cases := {
		Vector2.ZERO: Vector2i.ZERO,
		Vector2(1023.999, 0): Vector2i.ZERO,
		Vector2(1024, 0): Vector2i(1, 0),
		Vector2(-0.001, 0): Vector2i(-1, 0),
		Vector2(-1024, -1024): Vector2i(-1, -1),
		Vector2(-1024.01, -1024.01): Vector2i(-2, -2),
		Vector2(0, -0.001): Vector2i(0, -1),
	}
	for position: Vector2 in coordinate_cases:
		check(manager.get_chunk_coordinate(position) == coordinate_cases[position], "Floor coordinates at positive and negative boundaries")
	player.position = Vector2(1024, 0)
	manager.update_chunks()
	verify_grid(Vector2i(1, 0))
	var retained := 0
	for coordinate: Vector2i in manager.active_chunks:
		if initial.has(coordinate) and manager.active_chunks[coordinate] == initial[coordinate]:
			retained += 1
	check(retained == 6 and grid_changes == 1, "Cardinal crossing reuses six chunks and loads only three")
	var old_chunk: TerrainChunk = initial[Vector2i(-1, 0)]
	check(old_chunk.is_queued_for_deletion() and not old_chunk.is_inside_tree(), "Distant chunks detached and scheduled for deletion")
	await process_frame
	check(not is_instance_valid(old_chunk), "Unloaded chunk is freed")
	for coordinate in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(2, 2), Vector2i(-3, -4)]:
		player.position = Vector2(coordinate) * 1024.0 + Vector2(10, 10)
		manager.update_chunks()
		verify_grid(coordinate)
		await process_frame
	var old_ground := manager.active_chunks[Vector2i(-3, -4)].ground.tile_map_data.duplicate()
	var old_decorations := manager.active_chunks[Vector2i(-3, -4)].decorations.tile_map_data.duplicate()
	var old_seed := manager.active_chunks[Vector2i(-3, -4)].chunk_seed
	var old_id := manager.active_chunks[Vector2i(-3, -4)].get_instance_id()
	player.position = Vector2(10000, -10000)
	manager.update_chunks()
	await process_frame
	player.position = Vector2(-3, -4) * 1024.0
	manager.update_chunks()
	check(manager.active_chunks[Vector2i(-3, -4)].chunk_seed == old_seed and manager.active_chunks[Vector2i(-3, -4)].get_instance_id() != old_id, "Returning chunk regenerates with identical seed")
	check(manager.active_chunks[Vector2i(-3, -4)].ground.tile_map_data == old_ground, "Reloaded terrain cells are identical")
	check(manager.active_chunks[Vector2i(-3, -4)].decorations.tile_map_data == old_decorations, "Reloaded decoration artwork and transforms are identical")
	# Exercise existing movement continuously over both zero and positive seams.
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized(), Vector2(-1, -1).normalized()]:
		player.position = Vector2(1023, 1023) if direction.x > 0.0 or direction.y > 0.0 else Vector2(1, 1)
		player.velocity = Vector2.ZERO
		var start := player.position
		Input.action_press("move_right", maxf(direction.x, 0.0))
		Input.action_press("move_left", maxf(-direction.x, 0.0))
		Input.action_press("move_down", maxf(direction.y, 0.0))
		Input.action_press("move_up", maxf(-direction.y, 0.0))
		player.set_physics_process(true)
		manager.set_physics_process(true)
		for _frame in 30:
			await physics_frame
		player.set_physics_process(false)
		manager.set_physics_process(false)
		for action in ["move_right", "move_left", "move_down", "move_up"]:
			Input.action_release(action)
		check((player.position - start).dot(direction) > 80.0, "Movement crosses seams freely in cardinal and diagonal directions")
		verify_grid(manager.get_chunk_coordinate(player.global_position))
	check(player.speed == 250.0 and player.max_health == 50.0, "Player movement speed and health unchanged")
	# Combat objects in terrain being removed must survive on their current parents.
	player.position = Vector2.ZERO
	manager.update_chunks()
	spawner._spawn_enemy(Vector2(40, 0))
	var enemy := main.get_child(main.get_child_count() - 1) as Enemy
	enemy.set_physics_process(false)
	var pickup := preload("res://scenes/pickups/xp_pickup.tscn").instantiate() as XPPickup
	var bolt := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	var blood := preload("res://scenes/effects/blood_burst.tscn").instantiate() as Node2D
	var number := preload("res://scenes/ui/damage_number.tscn").instantiate() as FloatingDamageNumber
	number.configure(1.0, false)
	for object: Node2D in [pickup, bolt, blood, number]:
		main.add_child(object)
	bolt.set_physics_process(false)
	blood.get_node("CleanupTimer").stop()
	var terrain_origin := manager.active_chunks[Vector2i.ZERO]
	player.position = Vector2(4096, -4096)
	manager.update_chunks()
	await process_frame
	check(not is_instance_valid(terrain_origin), "Terrain underneath combat objects is removed")
	for object: Node2D in [player, enemy, pickup, bolt, blood, number]:
		check(is_instance_valid(object) and object.get_parent() == main and not object.is_queued_for_deletion(), "Terrain unloading preserves combat object and original parent")
	check(spawner.get_active_enemy_count() == 1 and spawner.spatial_grid._enemies.has(enemy), "Enemy cap bookkeeping and spatial-grid registration survive unloading")
	spawner.spatial_grid._rebuild_grid()
	var candidates: Array[Enemy] = []
	spawner.spatial_grid.append_nearby_candidates(enemy.global_position, candidates)
	check(candidates.has(enemy), "Spatial-grid queries still find enemy under unloaded terrain")
	# Teleporting bypasses normal camera travel; center it before asserting spawn distance.
	var camera := player.get_node("Camera2D") as Camera2D
	camera.reset_smoothing()
	camera.force_update_scroll()
	spawner._spawn_burst(2)
	check(spawner.get_active_enemy_count() == 3, "Existing burst spawning works after long-distance movement")
	for object in main.get_children():
		if object is Enemy and object != enemy:
			object.set_physics_process(false)
			check(object.global_position.distance_to(player.global_position) < 1200.0 and object.get_parent() == main, "New enemies spawn relative to player independently of terrain")
	# Repeated streaming holds a fixed active count and does not accumulate children.
	var streaming_usec := 0
	var start_usec := Time.get_ticks_usec()
	for step in 100:
		player.position = Vector2(step * 1024, -step * 1024)
		var transition_start := Time.get_ticks_usec()
		manager.update_chunks()
		streaming_usec += Time.get_ticks_usec() - transition_start
		check(manager.active_chunks.size() == 9 and manager.terrain_chunks.get_child_count() == 9, "Streaming stays bounded across long travel")
		await process_frame
	print("100 streaming transitions: ", (Time.get_ticks_usec() - start_usec) / 1000.0, " ms including frame waits; active terrain: ", manager.active_chunks.size())
	print("Mean chunk update CPU time: ", streaming_usec / 100000.0, " ms")
	verify_grid(Vector2i(99, -99))
	print("PASS: %d terrain streaming checks" % checks)
	main.queue_free()
	await process_frame
	quit()

