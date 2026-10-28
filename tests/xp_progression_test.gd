extends SceneTree

const PROGRESSION = preload("res://resources/progression/default_xp_progression.tres")
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
	var expected := [8, 10, 12, 15, 18, 22, 26, 30, 35, 40, 50, 60, 72, 85, 100]
	for index in expected.size():
		check(PROGRESSION.get_requirement(index + 1) == expected[index], "Exact table entry")
	check(PROGRESSION.get_requirement(16) == 115, "First extrapolated level")
	check(PROGRESSION.get_requirement(17) == 130, "Linear growth")
	check(PROGRESSION.get_requirement(50) == 625, "Later levels remain scalable")
	var old_total := 0
	var new_total := 0
	for level in range(1, 10):
		old_total += roundi(10.0 + (level - 1) * (level - 1) * 2.5)
		new_total += PROGRESSION.get_requirement(level)
	check(old_total == 602 and new_total == 176, "Level 10 is about 71 percent cheaper")
	var custom = PROGRESSION.duplicate(true)
	custom.requirements.append(120)
	check(custom.get_requirement(16) == 120 and custom.get_requirement(17) == 135, "Extending table moves growth boundary")
	custom.subsequent_level_increase = 20
	check(custom.get_requirement(17) == 140, "Growth increment configurable")
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.get_node("EnemySpawner").set_process(false)
	var player: Player = main.get_node("Player")
	var hud: HealthHud = main.get_node("HealthHUD")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	player.get_node("Bolter/FireTimer").stop()
	check(hud.xp_bar.value == 0 and hud.xp_bar.max_value == 8, "Initial HUD uses table")
	player.add_xp(175)
	check(player.level == 9 and player.xp == 34 and player.get_xp_required() == 35, "One large reward carries XP across levels")
	check(hud.xp_bar.value == 34 and hud.xp_bar.max_value == 35, "HUD shows carry-over and current requirement")
	player.add_xp(1)
	check(player.level == 10 and player.xp == 0, "Exact level 10 boundary")
	player.add_xp(47)
	check(player.level == 11 and player.xp == 7 and player.get_xp_required() == 50, "Carry-over beyond milestone")
	check(hud.xp_bar.value == 7 and hud.xp_bar.max_value == 50 and hud.xp_label.text == "LEVEL 11    XP 7 / 50", "HUD after multiple rewards")
	player.add_xp(0)
	player.add_xp(-10)
	check(player.level == 11 and player.xp == 7, "Nonpositive rewards unchanged")
	for level in range(2, 12):
		check(rewards.reward_levels[0] == level and paused, "Ordered paused reward queue")
		if level == 10:
			check(rewards.chapter_offered.size() == 3 and rewards.offered.is_empty(), "Level 10 still grants Chapter perk")
			rewards.select_chapter_perk(rewards.chapter_offered[0].id)
		else:
			check(rewards.offered.size() == 3 and rewards.chapter_offered.is_empty(), "Other levels still grant normal upgrades")
			rewards.select_upgrade(rewards.offered[0].id)
		await process_frame
	check(not paused and rewards.pending_levels == 0, "Gameplay resumes after rewards")
	check(player.xp == 7 and hud.xp_bar.value == 7, "Selecting rewards never consumes remaining XP")
	print("PASS: %d XP progression checks" % checks)
	main.queue_free()
	await process_frame
	quit()
