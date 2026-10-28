extends SceneTree

var checks: int = 0

class CountingSpawner extends EnemySpawner:
	var squig_bursts: int = 0
	var ork_bursts: int = 0
	var squigs: int = 0
	var orks: int = 0
	var different_sizes: int = 0
	var last_squig_burst: int = 0

	func _spawn_burst(size: int, scene: PackedScene = EnemySpawner.ENEMY_SCENE) -> void:
		if scene == ENEMY_SCENE:
			squig_bursts += 1
			squigs += size
			last_squig_burst = size
		else:
			ork_bursts += 1
			orks += size
			if size != last_squig_burst:
				different_sizes += 1

	func reset_counts() -> void:
		squig_bursts = 0
		ork_bursts = 0
		squigs = 0
		orks = 0
		different_sizes = 0
		_elapsed_time = 0.0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	var actual: EnemySpawner = main.get_node("EnemySpawner")
	var player: Player = main.get_node("Player")
	var clock: RunClock = main.get_node("RunClock")
	actual.set_process(false)
	clock.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	# Exercise the real scheduler without allocating thousands of scene instances.
	var counter := CountingSpawner.new()
	var grid := EnemySpatialGrid.new()
	grid.name = "EnemySpatialGrid"
	counter.add_child(grid)
	main.add_child(counter)
	counter.set_process(false)
	counter.bind_run_clock(clock)
	var seconds := [0.0, 149.999, 150.0, 225.0, 299.999, 300.0, 600.0]
	var factors := [0.0, 0.0, 0.1, 0.3, 0.4999973333, 1.0, 1.0]
	seed(88271)
	var started := Time.get_ticks_usec()
	for index in seconds.size():
		clock.elapsed_time = seconds[index]
		counter._on_run_seconds_changed(floori(clock.elapsed_time))
		check(is_equal_approx(counter.get_ork_spawn_factor(), factors[index]), "Exact timeline factor at %.3fs" % seconds[index])
		counter.reset_counts()
		for cycle in 20000:
			counter._process(counter._next_normal_spawn_delay)
		check(counter.squig_bursts == 20000, "Every normal cycle retains its Squig burst")
		var ratio := counter.orks / float(counter.squigs)
		check(absf(ratio - factors[index]) < 0.015, "Additive enemy frequency matches factor without replacing Squigs")
		check(absf(counter.squigs / 20000.0 - EnemySpawner.NORMAL_BURST_EXPECTED_SIZE) < 0.02, "Squig burst-size distribution remains unchanged")
		if factors[index] == 0.0:
			check(counter.orks == 0 and counter.ork_bursts == 0, "No pre-unlock Ork burst")
		else:
			check(counter.different_sizes > 0, "Independent Ork bursts can differ in size from Squig bursts")
		if factors[index] == 1.0:
			check(counter.ork_bursts == counter.squig_bursts and counter.orks + counter.squigs > counter.squigs * 1.95, "Full Ork frequency adds pressure instead of splitting a fixed total")
		print("%.3fs: factor=%.6f, Squigs=%d, additional Orks=%d, ratio=%.4f" % [seconds[index], counter.get_ork_spawn_factor(), counter.squigs, counter.orks, ratio])
	print("140000 additive spawn cycles without scene allocation: %.2f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	# Both bursts share the original cycle cadence and two-minute scaling.
	clock.elapsed_time = 300.0
	counter._on_run_seconds_changed(300)
	counter.reset_counts()
	counter._schedule_next_normal_spawn()
	var slow_delay := counter._next_normal_spawn_delay
	counter._elapsed_time = slow_delay * 0.5
	clock.elapsed_time = 360.0
	counter._on_run_seconds_changed(360)
	check(counter.spawn_tier == 3 and is_equal_approx(counter.get_effective_spawn_interval(), 0.6 * pow(0.9, 3)), "Existing global pressure formula preserved")
	check(is_equal_approx(counter._elapsed_time / counter._next_normal_spawn_delay, 0.5), "Pending cycle progress preserved at pressure transition")
	counter._process(counter._next_normal_spawn_delay - counter._elapsed_time)
	check(counter.squig_bursts == 1 and counter.ork_bursts == 1, "Scaled cycle triggers both independent streams")
	counter.reset_counts()
	counter.stress_test_enabled = true
	counter._process(counter.stress_test_spawn_interval)
	check(counter.squigs == 1 and counter.orks == 0, "Existing single-enemy stress mode unchanged")
	# Actual scene creation, safe placement, cap priority, and grid cleanup.
	clock.elapsed_time = 300.0
	actual.max_active_enemies = 4
	var burst_seed := -1
	for sample in 10000:
		seed(sample)
		if actual._roll_normal_burst_size() == 3:
			burst_seed = sample
			break
	check(burst_seed >= 0, "Found deterministic three-Squig burst")
	seed(burst_seed)
	actual._process(actual._next_normal_spawn_delay)
	var squigs := 0
	var orks := 0
	var camera := player.get_node("Camera2D") as Camera2D
	var half_view := root.get_visible_rect().size / camera.zoom * 0.5
	for enemy in actual.spatial_grid._enemies:
		enemy.set_physics_process(false)
		if enemy.damage_tier == Enemy.DamageTier.TIER_2:
			orks += 1
		else:
			squigs += 1
		var offset := enemy.global_position - camera.get_screen_center_position()
		check(absf(offset.x) > half_view.x or absf(offset.y) > half_view.y, "Both streams use off-screen spawn rules")
	check(squigs == 3 and orks == 1, "Normal Squigs are never replaced; additive Orks use remaining cap")
	check(actual.get_active_enemy_count() == 4 and actual.spatial_grid._enemies.size() == 4, "Both streams share active tracking and unchanged cap")
	actual._process(10.0)
	check(actual.get_active_enemy_count() == 4, "Combined streams never exceed shared cap")
	for enemy in actual.spatial_grid._enemies.duplicate():
		enemy.queue_free()
	await process_frame
	check(actual.get_active_enemy_count() == 0 and actual.spatial_grid._enemies.is_empty(), "Mixed stream removals clear counter and grid")
	print("PASS: %d additive Ork spawning checks" % checks)
	main.queue_free()
	await process_frame
	quit()
