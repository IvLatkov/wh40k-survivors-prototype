extends SceneTree

var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1152, 648)
	seed(41063)
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	var player: Player = main.get_node("Player")
	var grid: EnemySpatialGrid = spawner.spatial_grid
	spawner.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	var camera: Camera2D = player.get_node("Camera2D")
	camera.reset_smoothing()
	camera.force_update_scroll()
	check(spawner.max_active_enemies == 200, "Normal enemy cap preserved")
	check(is_equal_approx(spawner.spawn_interval, 0.6), "Base interval is 0.6s")
	check(is_equal_approx(spawner._next_normal_spawn_delay, 0.25), "First spawn is 0.25s")
	spawner._process(0.24)
	check(spawner.get_active_enemy_count() == 0, "No enemies before first delay")
	spawner._process(0.011)
	check(spawner.get_active_enemy_count() >= 1 and spawner.get_active_enemy_count() <= 5, "First burst appears by 0.251s")
	var delay_sum := 0.0
	for iteration in 1000:
		spawner._schedule_next_normal_spawn()
		check(spawner._next_normal_spawn_delay >= 0.539039 and spawner._next_normal_spawn_delay <= 0.808561, "Burst compensation and jitter preserved")
		delay_sum += spawner._next_normal_spawn_delay
	check(absf(delay_sum / 1000.0 - 0.6738) < 0.02, "Average compensated interval")
	var burst_sizes: Dictionary = {}
	for iteration in 10000:
		burst_sizes[spawner._roll_normal_burst_size()] = true
	check(burst_sizes.size() == 5 and burst_sizes.has(1) and burst_sizes.has(5), "All original burst sizes remain possible")
	var screen_size := root.get_visible_rect().size / camera.zoom
	var old_minimum := screen_size.length() + 64.0
	var old_average := old_minimum + 128.0
	var new_total := 0.0
	var nearest := INF
	var farthest := 0.0
	var shortest_entry_time := INF
	var longest_entry_time := 0.0
	var quadrants: Dictionary = {}
	for iteration in 1000:
		var origin := spawner._get_spawn_origin()
		var offset := origin - camera.get_screen_center_position()
		check(absf(offset.x) >= screen_size.x * 0.5 + 63.99 or absf(offset.y) >= screen_size.y * 0.5 + 63.99, "Burst origins outside expanded camera rectangle")
		var distance := origin.distance_to(player.global_position)
		check(distance - spawner.burst_position_offset >= 180.0, "Burst members remain clear of player")
		new_total += distance
		nearest = minf(nearest, distance)
		farthest = maxf(farthest, distance)
		quadrants[Vector2(signf(offset.x), signf(offset.y))] = true
		var direction := offset.normalized()
		var visible_edge := minf(screen_size.x * 0.5 / maxf(absf(direction.x), 0.000001), screen_size.y * 0.5 / maxf(absf(direction.y), 0.000001))
		var entry_time := (distance - visible_edge) / 60.0
		shortest_entry_time = minf(shortest_entry_time, entry_time)
		longest_entry_time = maxf(longest_entry_time, entry_time)
	check(quadrants.size() == 4, "Random directions cover all quadrants")
	check(new_total / 1000.0 < old_average * 0.6, "Travel distance and time reduced by over 40 percent")
	# Camera lag and zoom must not put burst members on-screen or beside the player.
	camera.zoom = Vector2(2.0, 2.0)
	camera.force_update_scroll()
	player.position += Vector2(70, 40)
	for iteration in 100:
		var origin := spawner._get_spawn_origin()
		var relative := origin - camera.get_screen_center_position()
		var half_view := root.get_visible_rect().size / camera.zoom * 0.5
		check(absf(relative.x) >= half_view.x + 63.99 or absf(relative.y) >= half_view.y + 63.99, "Zoom and camera lag respected")
		check(origin.distance_to(player.global_position) >= 220.0, "Minimum safe distance under zoom")
	var before := spawner.get_active_enemy_count()
	spawner._spawn_burst(5)
	check(spawner.get_active_enemy_count() == before + 5, "Five-enemy burst increments counter")
	check(grid._enemies.size() == spawner.get_active_enemy_count(), "All spawned enemies registered in spatial grid")
	var distinct_speeds: Dictionary = {}
	var distinct_offsets: Dictionary = {}
	for enemy: Enemy in grid._enemies:
		check(enemy.target == player and enemy.spatial_grid == grid, "Swarm target and grid references preserved")
		check(enemy.max_health == 25.0 and enemy.contact_damage == 1.0 and enemy.movement_speed == 60.0, "Base combat and movement stats unchanged")
		check(enemy._movement_speed_multiplier >= 0.9 and enemy._movement_speed_multiplier <= 1.1, "Movement variation unchanged")
		check(absf(enemy._chase_offset.x) <= 25.0 and absf(enemy._chase_offset.y) <= 25.0, "Chase variation unchanged")
		check(enemy.visual.animation in Enemy.SQUIG_ANIMATIONS, "Random Squig animation preserved")
		distinct_speeds[enemy._movement_speed_multiplier] = true
		distinct_offsets[enemy._chase_offset] = true
	check(distinct_speeds.size() > 1 and distinct_offsets.size() > 1, "Swarm members retain individual variation")
	spawner.max_active_enemies = spawner.get_active_enemy_count() + 1
	spawner._process(1.0)
	check(spawner.get_active_enemy_count() == spawner.max_active_enemies, "Spawn clipped to remaining cap")
	spawner._process(20.0)
	check(spawner.get_active_enemy_count() == spawner.max_active_enemies, "No spawning above cap")
	var departing: Enemy = grid._enemies[0]
	departing.queue_free()
	await process_frame
	check(spawner.get_active_enemy_count() == spawner.max_active_enemies - 1 and grid._enemies.size() == spawner.get_active_enemy_count(), "Removal updates counter and spatial grid")
	spawner._process(1.0)
	check(spawner.get_active_enemy_count() == spawner.max_active_enemies, "Cap refills after enemy removal")
	print("Viewport: %s; old origin distance %.1f..%.1f (mean %.1f); new sampled %.1f..%.1f (mean %.1f)" % [screen_size, old_minimum, old_minimum + 256.0, old_average, nearest, farthest, new_total / 1000.0])
	print("Estimated screen entry at unchanged 60px/s, before burst offsets: %.2f..%.2fs" % [shortest_entry_time, longest_entry_time])
	print("PASS: %d enemy spawner checks" % checks)
	main.queue_free()
	await process_frame
	quit()
