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
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var clock = main.get_node("RunClock")
	var hud: HealthHud = main.get_node("HealthHUD")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	var player: Player = main.get_node("Player")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	clock.set_process(false)
	spawner.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	check(clock.elapsed_time == 0.0 and hud.run_timer_label.text == "00:00", "Run starts at zero")
	check(is_equal_approx(spawner.get_effective_spawn_interval(), 0.6), "Initial interval unchanged")
	check(is_equal_approx(spawner._next_normal_spawn_delay, 0.25), "Fast first spawn preserved")
	await process_frame
	check(hud.run_timer_label.is_visible_in_tree(), "Timer visible")
	check(is_equal_approx(hud.run_timer_label.get_global_rect().get_center().x, 576.0), "Timer at horizontal center")
	check(hud.run_timer_label.get_global_rect().position.y == 12.0, "Timer at top")
	check(hud.run_timer_label.get_theme_color("font_color") == Color.WHITE, "White timer text")
	clock._process(37.0)
	check(hud.run_timer_label.text == "00:37", "Seconds format")
	if "--capture-hud" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var capture_path := OS.get_environment("TEMP").path_join("survivor_run_timer.png")
		root.get_texture().get_image().save_png(capture_path)
		print("HUD capture: " + capture_path)
	clock._process(119.999 - clock.elapsed_time)
	check(spawner.spawn_tier == 0 and hud.run_timer_label.text == "01:59", "No early tier increase")
	spawner._schedule_next_normal_spawn()
	spawner._elapsed_time = spawner._next_normal_spawn_delay * 0.5
	clock._process(120.0 - clock.elapsed_time)
	check(spawner.spawn_tier == 1 and is_equal_approx(spawner.get_effective_spawn_interval(), 0.54), "Tier increases exactly at 120 seconds")
	check(is_equal_approx(spawner._elapsed_time / spawner._next_normal_spawn_delay, 0.5), "Tier change preserves pending spawn progress")
	clock._process(15.0)
	check(hud.run_timer_label.text == "02:15", "Minutes and seconds format")
	for tier in range(2, 11):
		clock._process(tier * 120.0 - 0.001 - clock.elapsed_time)
		check(spawner.spawn_tier == tier - 1, "Tier does not increase early")
		clock._process(tier * 120.0 - clock.elapsed_time)
		check(spawner.spawn_tier == tier, "Exact two-minute boundary")
		check(is_equal_approx(spawner.get_effective_spawn_interval(), maxf(0.22, 0.6 * pow(0.9, tier))), "Geometric scaling")
	check(is_equal_approx(spawner.get_effective_spawn_interval(), 0.22), "Minimum reached at 20 minutes")
	for iteration in 1000:
		spawner._schedule_next_normal_spawn()
		check(spawner._next_normal_spawn_delay >= 0.22, "Jitter never breaches hard minimum")
	# Normal reward pause uses real SceneTree processing, not a manual clock tick.
	clock.set_process(true)
	player.add_xp(player.get_xp_required())
	var paused_time: float = clock.elapsed_time
	var paused_tier := spawner.spawn_tier
	var paused_text := hud.run_timer_label.text
	await create_timer(0.06).timeout
	check(paused and clock.elapsed_time == paused_time and spawner.spawn_tier == paused_tier, "Normal upgrade pause freezes gameplay time and difficulty")
	check(hud.run_timer_label.text == paused_text, "HUD clock stays frozen during normal selection")
	rewards.select_upgrade(rewards.offered[0].id)
	await create_timer(0.06).timeout
	check(clock.elapsed_time > paused_time, "Clock resumes without reset")
	clock.set_process(false)
	player.level = 9
	player.add_xp(player.get_xp_required())
	clock.set_process(true)
	paused_time = clock.elapsed_time
	await create_timer(0.06).timeout
	check(rewards.chapter_offered.size() == 3 and paused and clock.elapsed_time == paused_time, "Chapter selection freezes clock")
	rewards.select_chapter_perk(rewards.chapter_offered[0].id)
	clock.set_process(false)
	paused = true
	clock.set_process(true)
	paused_time = clock.elapsed_time
	await create_timer(0.06).timeout
	check(clock.elapsed_time == paused_time, "Other gameplay pauses freeze clock")
	paused = false
	clock.set_process(false)
	# Difficulty continues advancing while the active-enemy cap is full.
	spawner.max_active_enemies = 1
	spawner._process(1.0)
	check(spawner.get_active_enemy_count() == 1 and spawner.spatial_grid._enemies.size() == 1, "Cap and grid registration preserved")
	clock._process(120.0)
	spawner._process(1.0)
	check(spawner.spawn_tier > paused_tier and spawner.get_active_enemy_count() == 1, "Clock scales difficulty while cap stays enforced")
	clock._process(120000.0)
	check(is_equal_approx(spawner.get_effective_spawn_interval(), 0.22), "Minimum persists for long runs")
	var burst_sizes: Dictionary = {}
	seed(40000)
	for iteration in 10000:
		burst_sizes[spawner._roll_normal_burst_size()] = true
	check(burst_sizes.size() == 5, "All burst outcomes preserved at high tier")
	hud._on_run_seconds_changed(642)
	check(hud.run_timer_label.text == "10:42", "Double-digit minute format")
	root.size = Vector2i(1600, 900)
	await process_frame
	check(is_equal_approx(hud.run_timer_label.get_global_rect().get_center().x, 800.0), "Timer stays centered after resize")
	print("PASS: %d run timer and scaling checks" % checks)
	main.queue_free()
	await process_frame
	quit()
