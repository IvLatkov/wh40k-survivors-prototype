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

func press(key: Key, echo: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	event.echo = echo
	event.shift_pressed = shift
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func run() -> void:
	check(OS.is_debug_build(), "Fixture runs in a debug engine")
	root.size = Vector2i(1152, 648)
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	var clock: RunClock = main.get_node("RunClock")
	var player: Player = main.get_node("Player")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	var encounter: BossEncounter = main.get_node("BossEncounter")
	var hud: HealthHud = main.get_node("HealthHUD")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	var info = main.get_node("CharacterInfoPanel")
	clock.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	await process_frame
	check(clock.elapsed_time == 0 and hud.run_timer_label.text == "00:00" and not encounter.warboss_spawned, "Fresh gameplay starts at 0:00 without a boss")
	press(KEY_F9)
	press(KEY_F10, true)
	press(KEY_F10, false, true)
	check(clock.elapsed_time == 0 and not encounter.warboss_spawned, "Unrelated keys, repeats and modified F10 do nothing")
	# Focused text controls must not invoke a gameplay shortcut.
	for control in [LineEdit.new(), TextEdit.new()]:
		control.size = Vector2(200, 60)
		main.add_child(control)
		control.grab_focus()
		press(KEY_F10)
		check(clock.elapsed_time == 0 and not encounter.warboss_spawned, "F10 ignored while typing")
		control.release_focus()
		control.queue_free()
		await process_frame
	press(KEY_I)
	check(info.visible and paused, "I still opens Character Info")
	press(KEY_F10)
	check(clock.elapsed_time == 0 and not encounter.warboss_spawned, "F10 ignored during Character Info pause")
	press(KEY_ESCAPE)
	check(not info.visible and not paused, "Esc still closes Character Info")
	rewards.queue_level()
	press(KEY_F10)
	check(clock.elapsed_time == 0 and paused, "F10 ignored during Upgrade selection")
	rewards.select_upgrade(rewards.offered[0].id)
	player.level = main.get_node("ChapterPerkManager").catalog.perks[0].milestone
	rewards.queue_level()
	press(KEY_F10)
	check(clock.elapsed_time == 0 and paused, "F10 ignored during Chapter selection")
	rewards.select_chapter_perk(rewards.chapter_offered[0].id)
	# Preserve a non-default current build, including wounded HP.
	player.current_health = 31
	player.health_changed.emit(player.current_health, player.max_health)
	var player_before := var_to_bytes([player.current_health, player.max_health, player.xp, player.level, player.combat_stats.modifiers, player.combat_stats.temporary_modifiers, rewards.levels, rewards.active_ultimates])
	press(KEY_F10)
	check(clock.elapsed_time == 600 and hud.run_timer_label.text == "10:00", "F10 updates real clock and HUD immediately")
	check(encounter.warboss_spawned and is_instance_valid(encounter.boss), "Real clock notification spawns the production Warboss")
	var boss := encounter.boss
	boss.set_physics_process(false)
	check(boss.max_health == 750 and boss.armor == 5 and boss.movement_speed == 40, "Production boss stats preserved")
	check(encounter.hud.get_node("HUD/BossDisplay").visible, "Real boss health bar appears")
	check(spawner.is_processing() and spawner.spawn_tier == 5 and spawner.get_ork_spawn_factor() == 1.0, "Normal 10-minute enemy behavior stays active")
	check(player_before == var_to_bytes([player.current_health, player.max_health, player.xp, player.level, player.combat_stats.modifiers, player.combat_stats.temporary_modifiers, rewards.levels, rewards.active_ultimates]), "F10 preserves current HP/XP/level/stats/upgrades")
	if OS.get_cmdline_user_args().has("--capture"):
		await process_frame
		await RenderingServer.frame_post_draw
		var capture_path := OS.get_environment("TEMP").path_join("wh40k_debug_boss_skip.png")
		root.get_texture().get_image().save_png(capture_path)
	clock.advance_to(610)
	press(KEY_F10)
	check(clock.elapsed_time == 610 and encounter.boss == boss and spawner.spatial_grid._enemies.filter(func(e: Enemy): return e is Warboss).size() == 1, "Repeated F10 neither rewinds time nor duplicates the boss")
	clock.advance_to(599)
	check(clock.elapsed_time == 610, "RunClock advance_to cannot rewind")
	boss.take_damage(10000)
	check(encounter.run_ended and paused and not spawner.is_processing() and encounter.hud.get_node("HUD/Victory").visible, "Boss death still invokes production Victory")
	press(KEY_F10)
	press(KEY_I)
	press(KEY_ESCAPE)
	check(paused and clock.elapsed_time == 610 and not info.visible, "F10/I/Esc cannot restart gameplay after Victory")
	main.queue_free()
	await process_frame
	await process_frame
	paused = false
	print("PASS: ", checks, " F10 debug boss skip/input/modal/state checks")
	quit()
