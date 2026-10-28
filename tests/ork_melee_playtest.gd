extends SceneTree

# Test-only controlled observations. Player HP is replenished to keep all windows
# observable; this is not a survivability or human fairness verdict.
var main: Node2D
var player: Player
var spawner: EnemySpawner
var clock: RunClock
var starts: Dictionary[int, Array] = {}
var strikes: int = 0
var geometric_misses: int = 0
var starts_in_window: int = 0
var strikes_in_window: int = 0
var misses_in_window: int = 0

func _initialize() -> void:
	run.call_deferred()

func set_input(direction: Vector2) -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down"]:
		Input.action_release(action)
	if direction.x > 0: Input.action_press(&"move_right")
	if direction.x < 0: Input.action_press(&"move_left")
	if direction.y > 0: Input.action_press(&"move_down")
	if direction.y < 0: Input.action_press(&"move_up")

func observe_animation(ork: OrkBoy) -> void:
	if ork.visual.animation == &"attack":
		starts[ork.get_instance_id()].append(Engine.get_physics_frames() / 60.0)
		starts_in_window += 1

func observe_frame(ork: OrkBoy) -> void:
	if ork.state != OrkBoy.State.SWING or ork.visual.frame != ork.hit_frame:
		return
	strikes += 1
	strikes_in_window += 1
	var offset := player.global_position - ork.global_position
	if offset.length_squared() > ork.hit_range * ork.hit_range or offset.x * ork._attack_facing < 0:
		geometric_misses += 1
		misses_in_window += 1

func watch_new_orks() -> void:
	for enemy in spawner.spatial_grid._enemies:
		if not enemy is OrkBoy or starts.has(enemy.get_instance_id()):
			continue
		var ork := enemy as OrkBoy
		starts[ork.get_instance_id()] = []
		ork.visual.animation_changed.connect(observe_animation.bind(ork))
		ork.visual.frame_changed.connect(observe_frame.bind(ork))

func choose_reward() -> void:
	var upgrades: UpgradeSystem = main.get_node("UpgradeSystem")
	if not upgrades.chapter_offered.is_empty():
		upgrades.select_chapter_perk(upgrades.chapter_offered[0].id)
	elif not upgrades.offered_ultimates.is_empty():
		upgrades.select_upgrade(upgrades.offered_ultimates[0].id)
	elif not upgrades.offered.is_empty():
		upgrades.select_upgrade(upgrades.offered[0].id)

func run() -> void:
	root.size = Vector2i(1152, 648)
	seed(741)
	main = preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	spawner = main.get_node("EnemySpawner")
	clock = main.get_node("RunClock")
	var args := OS.get_cmdline_user_args()
	if args.has("--balance"):
		await balance_route()
	else:
		await group_route(args.has("--stress"), args.has("--all-orks"), args.has("--capture"), args.has("--combat"))
	set_input(Vector2.ZERO)
	# Stop the fixture, then let existing explosion coroutines finish before
	# deleting their owning scene. Abrupt exit otherwise leaves SceneTreeTimers.
	main.process_mode = Node.PROCESS_MODE_DISABLED
	paused = false
	for child in main.get_children():
		if child is BoltProjectile: child.queue_free()
	await process_frame
	await process_frame
	for child in main.get_children():
		if child is BoltProjectile: child.queue_free()
	await create_timer(0.5).timeout
	main.queue_free()
	await process_frame
	await process_frame
	quit()

func group_route(stress: bool, all_orks: bool, capture: bool, combat: bool) -> void:
	spawner.set_process(false)
	clock.set_process(false)
	if not combat:
		player.get_node("Bolter/FireTimer").stop()
		player.get_node("KnifeAttack").set_physics_process(false)
	var count := 200 if stress else 6
	for index in count:
		var is_ork := all_orks or not stress or index % 4 == 0
		var radius := 60.0 + (index % 5) * 28.0 if stress else 60.0
		spawner._spawn_enemy(Vector2.from_angle(index * TAU / count) * radius,
			spawner.tier_2_enemy_scene if is_ork else spawner.ENEMY_SCENE)
	watch_new_orks()
	var intervals: Array[float] = []
	var max_windups := 0
	var max_swings := 0
	var start := Time.get_ticks_usec()
	var replacement := 0
	for frame in 720:
		player.current_health = player.max_health
		if combat:
			choose_reward()
			while spawner.get_active_enemy_count() < count:
				var position := player.position + Vector2.from_angle(replacement * 2.4) * (180 + replacement % 5 * 30)
				spawner._spawn_enemy(position, spawner.tier_2_enemy_scene if all_orks or replacement % 4 == 0 else spawner.ENEMY_SCENE)
				replacement += 1
			watch_new_orks()
		# Hold for attacks, then step sideways and back. Production player input
		# and acceleration handle movement, rather than teleporting the player.
		var phase := frame % 240
		set_input(Vector2.RIGHT if phase >= 100 and phase < 130 else (Vector2.LEFT if phase >= 160 and phase < 190 else Vector2.ZERO))
		await process_frame
		var now := Time.get_ticks_usec()
		if frame >= 60: intervals.append((now - start) / 1000.0)
		start = now
		var windups := 0
		var swings := 0
		for enemy in spawner.spatial_grid._enemies:
			if enemy is OrkBoy:
				windups += int(enemy.state == OrkBoy.State.WINDUP)
				swings += int(enemy.state == OrkBoy.State.SWING)
		max_windups = maxi(max_windups, windups)
		max_swings = maxi(max_swings, swings)
		assert(spawner.get_active_enemy_count() <= count if combat else spawner.get_active_enemy_count() == count)
		if capture and frame == 104 and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path := OS.get_environment("TEMP").path_join("ork_melee_group.png")
			root.get_texture().get_image().save_png(path)
			print("CAPTURE ", path)
	intervals.sort()
	var total := 0.0
	for value in intervals: total += value
	var mean := total / intervals.size()
	var first_starts: Array[float] = []
	var cadence: Array[float] = []
	for values in starts.values():
		if not values.is_empty(): first_starts.append(values[0])
		for index in range(1, values.size()): cadence.append(values[index] - values[index - 1])
	print("GROUP stress=", stress, " all_orks=", all_orks, " combat=", combat, " enemies=", spawner.get_active_enemy_count(), " replacements=", replacement,
		" frame_avg_ms=", mean, " worst_ms=", intervals.max(), " p95_ms=", intervals[ceili(intervals.size() * 0.95) - 1],
		" fps=", 1000.0 / mean, " peak_windups=", max_windups, " peak_swings=", max_swings,
		" strikes=", strikes, " geometric_misses=", geometric_misses,
		" attacking_orks=", first_starts.size(), " first_start_spread_s=", first_starts.max() - first_starts.min(),
		" shortest_cadence_s=", cadence.min())

func balance_route() -> void:
	var checkpoints: Array[float] = [150.0, 240.0, 290.0, 300.0, 360.0]
	var index := 0
	var in_window := false
	var peak_orks := 0
	var peak_swings := 0
	# A bounded square keeps terrain travel out of this enemy-behavior observation.
	var corners: Array[Vector2] = [Vector2(200, 200), Vector2(-200, 200), Vector2(-200, -200), Vector2(200, -200)]
	var corner := 0
	while index < checkpoints.size():
		player.current_health = player.max_health
		choose_reward()
		var direction := player.position.direction_to(corners[corner])
		if player.position.distance_to(corners[corner]) < 25: corner = (corner + 1) % 4
		# Periodically stop to expose real wind-ups and allow an escape afterward.
		set_input(Vector2.ZERO if fmod(clock.elapsed_time, 8.0) < 1.5 else direction)
		watch_new_orks()
		await process_frame
		if not in_window and clock.elapsed_time >= checkpoints[index]:
			in_window = true
			peak_orks = 0
			peak_swings = 0
			starts_in_window = 0
			strikes_in_window = 0
			misses_in_window = 0
		if in_window:
			var orks := 0
			var swings := 0
			for enemy in spawner.spatial_grid._enemies:
				if enemy is OrkBoy:
					orks += 1
					swings += int(enemy.state == OrkBoy.State.SWING)
			peak_orks = maxi(peak_orks, orks)
			peak_swings = maxi(peak_swings, swings)
			if clock.elapsed_time >= checkpoints[index] + 10.0:
				print("BALANCE window_s=", checkpoints[index], "..", checkpoints[index] + 10,
					" active_enemies=", spawner.get_active_enemy_count(), " peak_active_orks=", peak_orks,
					" peak_simultaneous_swings=", peak_swings, " windups=", starts_in_window,
					" strikes=", strikes_in_window, " geometric_misses=", misses_in_window,
					" player_level=", player.level, " ork_spawn_factor=", spawner.get_ork_spawn_factor())
				index += 1
				in_window = false
