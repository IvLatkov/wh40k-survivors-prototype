extends SceneTree

var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func _initialize() -> void:
	run.call_deferred()

func prepare_main() -> Node2D:
	paused = false
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("Bolter").set_process(false)
	player.get_node("KnifeAttack").set_physics_process(false)
	main.get_node("RunClock").set_process(false)
	main.get_node("ChunkManager").set_process(false)
	main.get_node("ChunkManager").set_physics_process(false)
	return main

func run() -> void:
	root.size = Vector2i(1152, 648)
	for modal in ["none", "info", "upgrade", "chapter", "projectile"]:
		var main := prepare_main()
		var player: Player = main.get_node("Player")
		var spawner: EnemySpawner = main.get_node("EnemySpawner")
		var clock: RunClock = main.get_node("RunClock")
		var encounter: BossEncounter = main.get_node("BossEncounter")
		var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
		var info = main.get_node("CharacterInfoPanel")
		var bar: ProgressBar = encounter.hud.get_node("HUD/BossDisplay/HealthBar")
		check(not encounter.warboss_spawned and not encounter.hud.get_node("HUD/BossDisplay").visible, "No boss/health bar before 10:00; fresh run resets flag")
		clock._process(599.999)
		check(not encounter.warboss_spawned, "No Warboss at 09:59.999")
		spawner._spawn_enemy(Vector2(500, 100))
		var normal := spawner.spatial_grid._enemies.back() as Enemy
		normal.set_physics_process(false)
		# Normal population cap cannot postpone the one-time boss event.
		spawner._active_enemy_count = 200
		clock._process(0.001)
		check(encounter.warboss_spawned and is_instance_valid(encounter.boss), "One Warboss at exactly 10:00 regardless of normal cap")
		var boss := encounter.boss
		boss.set_physics_process(false)
		check(boss.global_position.distance_to(player.global_position) >= spawner.minimum_player_spawn_distance, "Existing safe spawn origin avoids player")
		check(not spawner.normal_spawning_enabled and not spawner.is_processing() and spawner._active_enemy_count == 200 and spawner.spatial_grid._enemies.has(boss), "Normal scheduler stops; boss registered separately")
		spawner._active_enemy_count = 1
		check(not normal is Warboss and normal.max_health == 25 and is_instance_valid(normal), "Pre-encounter Squig survives the transition")
		var original := boss.get_instance_id()
		clock.seconds_changed.emit(600)
		clock._process(1.0)
		encounter.bind_run(clock, player, spawner, rewards, info, [main.get_node("UpgradeMenu"), main.get_node("ChapterPerkMenu")])
		check(encounter.boss.get_instance_id() == original and spawner.spatial_grid._enemies.filter(func(e: Enemy): return e is Warboss).size() == 1, "Repeated notifications / rebind cannot duplicate boss")
		player.position = Vector2(4097, -4097)
		main.get_node("ChunkManager").update_chunks()
		check(encounter.boss.get_instance_id() == original, "Terrain chunk transition preserves encounter")
		check(bar.visible and bar.value == 750 and encounter.hud.get_node("HUD/BossDisplay/HealthLabel").text == "750 / 750", "Boss bar initialized live")
		boss.take_damage(25)
		check(bar.value == 730 and encounter.hud.get_node("HUD/BossDisplay/HealthLabel").text == "730 / 750", "Boss bar updates with armored damage")
		boss.position = player.position + Vector2(300, 0)
		boss._physics_process(0)
		check(boss.state == Warboss.State.GUN_WINDUP, "Kill interrupts an actual attack wind-up")
		if modal == "info":
			info.open_panel()
			check(paused and info.visible, "Character Info owns a normal pause")
		elif modal in ["upgrade", "chapter"]:
			if modal == "chapter":
				player.level = main.get_node("ChapterPerkManager").catalog.perks[0].milestone
			rewards.queue_level()
			check(paused and main.get_node("ChapterPerkMenu" if modal == "chapter" else "UpgradeMenu").visible, "Reward menu owns pause before terminal Victory")
		var xp_before := player.xp
		var level_before := player.level
		if modal == "projectile":
			var bolt := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
			bolt.damage = 10000
			bolt.position = boss.position - Vector2(100, 0)
			bolt.set_direction(Vector2.RIGHT)
			main.add_child(bolt)
			await create_timer(0.35, true).timeout
		else:
			boss.take_damage(9999)
			check(boss.state == Warboss.State.DEAD and boss.phase_timer.is_stopped() and boss.gun_timer.is_stopped() and boss.claw_timer.is_stopped(), "Death stops all attack timers/AI")
			boss._fire_shot()
			check(boss.state == Warboss.State.DEAD, "Stale gun callback cannot resurrect a dead boss")
		check(encounter.run_ended and paused and not spawner.is_processing(), "Boss death stops spawns and pauses gameplay immediately")
		check(encounter.hud.get_node("HUD/Victory").visible and not encounter.hud.get_node("HUD/BossDisplay").visible, "Victory overlay visible; boss bar hidden")
		check(not info.visible and not main.get_node("UpgradeMenu").visible and not main.get_node("ChapterPerkMenu").visible and rewards.pending_levels == 0, "Terminal Victory clears all conflicting modals/rewards")
		info.close_panel()
		info.open_panel()
		rewards._finish_reward()
		rewards.queue_level()
		rewards._offer_choices()
		rewards.select_upgrade(&"armor")
		rewards.select_chapter_perk(&"anything")
		check(paused and rewards.pending_levels == 0 and not info.visible, "Stale modal callbacks cannot unpause or queue rewards after Victory")
		clock.seconds_changed.emit(700)
		await process_frame
		await process_frame
		check(not is_instance_valid(boss) and encounter.warboss_spawned, "Dead boss removed, run spawn flag retained")
		var drops := 0
		for child in main.get_children():
			drops += int(child is XPPickup)
		check(drops == 0 and player.xp == xp_before and player.level == level_before, "Boss awards no XP or upgrade")
		var frozen_time := clock.elapsed_time
		var frozen_position := normal.position
		await create_timer(0.05, true).timeout
		check(clock.elapsed_time == frozen_time and normal.position == frozen_position, "Run clock/combat stay frozen behind Victory")
		# Fixture teardown only: the disabled gameplay subtree stays frozen,
		# while existing pause-aware explosion coroutines can finish safely.
		paused = false
		await create_timer(0.4, true).timeout
		main.queue_free()
		await process_frame
		await process_frame
		paused = false
	print("PASS: ", checks, " Warboss spawn/HUD/Victory/pause/reward checks")
	quit()
