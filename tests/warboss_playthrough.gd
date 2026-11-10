# Rendered end-to-end fixture: natural 10:00 spawn, existing legal upgrades
# and surviving normal enemies. A deterministic orbit drives movement/aim only.
extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func grant_build(player: Player, rewards: UpgradeSystem) -> void:
	# Fast-forward a plausible earned build through the real XP/reward pipeline.
	# Fixture controls the eligible offer, never weapon formulas or boss HP.
	for id: StringName in [&"bolter_damage", &"bolter_damage", &"bolter_damage", &"bolter_damage", &"bolter_damage", &"fire_rate", &"fire_rate", &"fire_rate", &"fire_rate", &"fire_rate", &"multishot", &"multishot", &"devastator_shells"]:
		while true:
			player.add_xp(player.get_xp_required())
			if not rewards.chapter_offered.is_empty():
				rewards.select_chapter_perk(rewards.chapter_offered[0].id)
				continue
			if id == &"devastator_shells":
				var ultimate := preload("res://resources/ultimates/devastator_shells.tres")
				assert(rewards.can_select_ultimate(ultimate))
				rewards.offered_ultimates.assign([ultimate])
			else:
				for definition in rewards.definitions:
					if definition.id == id:
						assert(rewards.can_select_upgrade(definition))
						rewards.offered.assign([definition])
						break
			rewards.select_upgrade(id)
			break

func run() -> void:
	seed(4010)
	root.size = Vector2i(1280, 800)
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	var clock: RunClock = main.get_node("RunClock")
	var player: Player = main.get_node("Player")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	var encounter: BossEncounter = main.get_node("BossEncounter")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	var bolter = player.get_node("Bolter")
	player.set_physics_process(false)
	player.get_node("KnifeAttack").set_physics_process(false)
	bolter.set_process(false)
	bolter.fire_timer.stop()
	player.get_node("Camera2D").position_smoothing_enabled = false
	clock.set_process(false)
	spawner.set_process(false)
	grant_build(player, rewards)
	await create_timer(1.5).timeout
	spawner.set_process(true)
	clock.advance_to(599.999)
	# Populate a small pre-existing swarm before the production spawn cutoff.
	for index in 8:
		spawner._spawn_enemy(Vector2.from_angle(index * TAU / 8.0) * 600.0, spawner.ENEMY_SCENE if index % 2 == 0 else spawner.tier_2_enemy_scene)
	var survivor_count := spawner.get_active_enemy_count()
	clock.advance_to(600.0)
	assert(encounter.warboss_spawned and not spawner.is_processing() and not spawner.normal_spawning_enabled)
	assert(spawner.get_active_enemy_count() == survivor_count)
	var boss := encounter.boss
	# Preview framing only: bring the naturally spawned boss into camera view.
	boss.position = Vector2(200, 0)
	boss.set_physics_process(false)
	var updates: Array[float] = []
	var frames: Array[float] = []
	var shot_count := 0
	var captured_gun := false
	var captured_claw := false
	var shots: Array[int] = [0]
	boss.shot_fired.connect(func(_p: BoltProjectile): shots[0] += 1)
	# Render the real locked-direction claw telegraph and demonstrate an escape.
	player.position = Vector2(280, 0)
	boss._physics_process(1.0 / 60.0)
	assert(boss.state == Warboss.State.CLAW_WINDUP)
	await capture("res://docs/warboss_claw.png")
	captured_claw = true
	var hp_before := player.current_health
	player.position = Vector2(480, 0)
	for _tick in 65:
		await physics_frame
		boss._physics_process(1.0 / 60.0)
	assert(player.current_health == hp_before, "Leaving the claw telegraph avoids damage")
	var fire_elapsed := 0.0
	var elapsed := 0.0
	var previous := Time.get_ticks_usec()
	for tick in 4800:
		await physics_frame
		if encounter.run_ended:
			break
		if paused:
			if rewards.chapter_offered.size() > 0:
				rewards.select_chapter_perk(rewards.chapter_offered[0].id)
			elif rewards.offered_ultimates.size() > 0:
				rewards.select_upgrade(rewards.offered_ultimates[0].id)
			elif rewards.offered.size() > 0:
				rewards.select_upgrade(rewards.offered[0].id)
			elif rewards.pending_levels > 0:
				await process_frame
			else:
				await capture("res://docs/warboss_bot_failure.png")
				push_error("Bot fight paused: HP=%s boss_HP=%s time=%s" % [player.current_health, boss.current_health, elapsed])
				quit(1)
				return
			continue
		var dt := 1.0 / Engine.physics_ticks_per_second
		elapsed += dt
		player.position = boss.position + Vector2.from_angle(elapsed * 0.6) * 400.0
		var started := Time.get_ticks_usec()
		boss._physics_process(dt)
		updates.append(Time.get_ticks_usec() - started)
		root.warp_mouse(Vector2i(main.get_viewport_transform() * boss.global_position))
		bolter.rotation = (player.global_position.direction_to(boss.global_position)).angle()
		fire_elapsed += dt
		if fire_elapsed >= bolter.get_fire_interval():
			fire_elapsed -= bolter.get_fire_interval()
			bolter._fire()
			shot_count += 1
		if tick % 300 == 0:
			print("BOT_PROGRESS time=", elapsed, " boss_HP=", boss.current_health, " player_HP=", player.current_health, " normal_enemies=", spawner.get_active_enemy_count())
		if not captured_gun and boss.state == Warboss.State.GUN_BURST:
			await capture("res://docs/warboss_gun.png")
			captured_gun = true
		frames.append((Time.get_ticks_usec() - previous) / 1000.0)
		previous = Time.get_ticks_usec()
	assert(encounter.run_ended and paused, "Unmodified player weapons must kill the boss and reach Victory")
	await capture("res://docs/warboss_victory.png")
	var average_usec: float = updates.reduce(func(a: float, b: float): return a + b, 0.0) / updates.size()
	var average_frame: float = frames.reduce(func(a: float, b: float): return a + b, 0.0) / frames.size()
	var report := {"victory": encounter.run_ended, "boss_spawned": encounter.warboss_spawned, "claw_escape": captured_claw,
		"gun_preview": captured_gun, "fight_seconds": elapsed, "bolter_volleys": shot_count, "boss_projectiles": shots[0],
		"player_health": player.current_health, "player_level": player.level, "upgrade_levels": rewards.levels.duplicate(), "normal_enemies": spawner.get_active_enemy_count(), "pre_encounter_survivors": survivor_count, "normal_spawning_enabled": spawner.normal_spawning_enabled,
		"boss_updates": updates.size(), "boss_update_avg_usec": average_usec, "boss_update_worst_usec": updates.max(),
		"frame_avg_ms": average_frame, "fps": Engine.get_frames_per_second()}
	var file := FileAccess.open("res://docs/warboss_playthrough.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("WARBOSS_PLAYTHROUGH PASS ", report)
	# Drain existing explosion effect timers outside the completed fight.
	paused = false
	for child in main.get_children():
		if child is BoltProjectile:
			child.queue_free()
	await create_timer(0.6).timeout
	main.queue_free()
	await process_frame
	await process_frame
	quit()
