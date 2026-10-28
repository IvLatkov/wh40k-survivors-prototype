extends SceneTree

var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1152, 648)
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	var panel = main.get_node("CharacterInfoPanel")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	var clock = main.get_node("RunClock")
	main.get_node("EnemySpawner").set_process(false)
	var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	enemy.position = Vector2(400, 0)
	enemy.set_target(player)
	main.add_child(enemy)
	var projectile := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	projectile.position = Vector2(1000, 0)
	main.add_child(projectile)
	var skull := preload("res://scenes/pickups/xp_pickup.tscn").instantiate() as XPPickup
	skull.position = Vector2(-500, 0)
	main.add_child(skull)
	skull.start_collecting(player)
	await process_frame
	check(not panel.visible and not paused, "Panel initially closed")
	press_key(KEY_I)
	check(panel.visible and paused and panel.can_process(), "I opens interactive panel and pauses immediately")
	check(panel.title.text == "CHARACTER" and panel.chapter_label.text == "Chapter: Ultramarines" and panel.level_label.text == "Level: 1", "Character heading and level")
	var defaults := {"Health": "50 / 50", "Health Regen": "0.0 HP/s", "Armor": "0", "Bolter Damage": "25", "Bolter Fire Rate": "1.33 /s", "Bolter Projectiles": "1 / 5", "Crit Chance": "0%", "Crit Bonus": "+50%", "Knife Damage": "35", "Knife Attack Rate": "1.25 /s", "Knife Range": "55 px"}
	for stat: String in defaults:
		check(panel._value_labels[stat].text == defaults[stat], "Initial live " + stat)
	var portrait: TextureRect = panel.get_node("Overlay/Center/Panel/Margin/Scroll/Content/Body/Portrait")
	check(portrait.texture == player.visual.sprite_frames.get_frame_texture(&"idle_right", 0), "Portrait reuses exact right-facing idle texture")
	check(portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Sharp pixel filtering")
	var enemy_position := enemy.position
	var projectile_position := projectile.position
	var skull_position := skull.position
	var run_time: float = clock.elapsed_time
	var weapon_time: float = player.get_node("Bolter/FireTimer").time_left
	var knife_time: float = player.get_node("KnifeAttack/CooldownTimer").time_left
	var life: float = projectile._remaining_lifetime
	await create_timer(0.08).timeout
	check(enemy.position == enemy_position, "Enemies freeze")
	check(projectile.position == projectile_position and projectile._remaining_lifetime == life, "Projectiles and lifetimes freeze")
	check(skull.position == skull_position, "Flying XP freezes")
	check(clock.elapsed_time == run_time, "Run timer freezes")
	check(player.get_node("Bolter/FireTimer").time_left == weapon_time and player.get_node("KnifeAttack/CooldownTimer").time_left == knife_time, "Combat timers freeze")
	check(not player.can_process() and not enemy.can_process(), "Gameplay processing disabled")
	var count_before := main.get_child_count()
	panel.open_panel()
	check(main.get_child_count() == count_before, "Repeated open reuses panel")
	press_key(KEY_I)
	check(not panel.visible and not paused, "I closes and resumes")
	await create_timer(0.08).timeout
	check(clock.elapsed_time > run_time and enemy.position != enemy_position and projectile.position != projectile_position and skull.position != skull_position, "Gameplay entities and clock resume")
	press_key(KEY_I)
	press_key(KEY_ESCAPE)
	check(not panel.visible and not paused, "Escape closes")
	# Actual normal and Chapter modal conflicts, including a reward arriving during info.
	player.add_xp(player.get_xp_required())
	press_key(KEY_I)
	check(not panel.visible and paused and main.get_node("UpgradeMenu").visible, "Normal reward blocks info opening")
	press_key(KEY_ESCAPE)
	check(paused and main.get_node("UpgradeMenu").visible, "Escape cannot dismiss reward")
	rewards.select_upgrade(rewards.offered[0].id)
	check(not paused, "Normal reward resumes")
	press_key(KEY_I)
	player.level = 9
	player.add_xp(player.get_xp_required())
	check(not panel.visible and paused and main.get_node("ChapterPerkMenu").visible, "Reward arriving while info open transfers pause cleanly")
	press_key(KEY_I)
	check(not panel.visible and paused, "Chapter reward blocks info")
	rewards.select_chapter_perk(rewards.chapter_offered[0].id)
	check(not paused, "Chapter reward resumes without stale info pause")
	paused = true
	press_key(KEY_I)
	check(not panel.visible and paused, "Other pauses block opening")
	paused = false
	press_key(KEY_I)
	main.get_node("UpgradeMenu").show()
	press_key(KEY_I)
	check(not panel.visible and paused, "Closing cannot resume over another visible modal")
	main.get_node("UpgradeMenu").hide()
	paused = false
	# Reopen with actual current stats; mutations while visible also refresh.
	player.combat_stats.modifiers.clear()
	# Earlier random normal/Chapter choices may have changed maximum health.
	player.combat_stats.stat_changed.emit(&"max_health_bonus")
	player.combat_stats.stat_changed.emit(&"max_health")
	player.current_health = player.max_health
	player.damage_invulnerability_timer.stop()
	player.combat_stats.stat_changed.emit(&"knife_range")
	press_key(KEY_I)
	player.combat_stats.add_modifier(&"armor", 2.0)
	player.combat_stats.add_modifier(&"bolter_damage", 0.4)
	player.combat_stats.add_modifier(&"projectile_count", 2.0)
	player.combat_stats.add_modifier(&"crit_chance", 0.08)
	player.combat_stats.add_modifier(&"knife_damage", 0.2)
	player.combat_stats.add_modifier(&"knife_range", 0.2)
	player.take_damage(10.0)
	var upgraded := {"Health": "42 / 50", "Armor": "2", "Bolter Damage": "35", "Bolter Projectiles": "3 / 5", "Crit Chance": "8%", "Crit Bonus": "+50%", "Knife Damage": "42", "Knife Range": "66 px"}
	for stat: String in upgraded:
		check(panel._value_labels[stat].text == upgraded[stat], "Visible live update " + stat)
	player.combat_stats.add_modifier(&"max_health", 0.15)
	check(panel._value_labels["Health"].text == "50 / 58", "Max HP perks update health display")
	player.combat_stats.add_modifier(&"crit_damage", 0.2)
	check(panel._value_labels["Crit Bonus"].text == "+70%", "Actual Chapter-enhanced crit bonus displayed")
	press_key(KEY_I)
	press_key(KEY_I)
	check(panel._value_labels["Knife Range"].text == "66 px" and panel._value_labels["Armor"].text == "2", "Reopen reads current stats")
	if "--capture-ui" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var capture_path := OS.get_environment("TEMP").path_join("survivor_character_info.png")
		root.get_texture().get_image().save_png(capture_path)
		print("Character Info capture: " + capture_path)
	# Death pause must survive closing the informational overlay.
	player.damage_invulnerability_timer.stop()
	player.take_damage(1000.0)
	check(paused and not panel.visible and main.get_node("HealthHUD").death_label.visible, "Death retains pause")
	press_key(KEY_I)
	check(not panel.visible and paused, "Cannot reopen after death")
	print("PASS: %d Character Info checks" % checks)
	main.queue_free()
	paused = false
	await process_frame
	quit()
