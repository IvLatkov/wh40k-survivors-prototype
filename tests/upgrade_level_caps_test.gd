extends SceneTree

var checks: int = 0
var exhausted: int = 0
var main: Node2D
var player: Player
var system: UpgradeSystem

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func setup() -> void:
	root.size = Vector2i(1152, 648)
	main = preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	system = main.get_node("UpgradeSystem")
	# This suite isolates normal pool exhaustion; Ultimates have their own integration suite.
	system.ultimate_definitions = []
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	system.normal_choices_exhausted.connect(func(_level: int) -> void: exhausted += 1)

func cleanup() -> void:
	paused = false
	main.queue_free()
	await process_frame

func definition(id: StringName) -> UpgradeDefinition:
	for value in system.definitions:
		if value.id == id:
			return value
	return null

func select(id: StringName) -> void:
	var chosen := definition(id)
	check(system.available_upgrades().has(chosen), "Requested type is eligible")
	system.queue_level()
	system.offered = [chosen]
	for value in system.available_upgrades():
		if value.id != id and system.offered.size() < 3:
			system.offered.append(value)
	system.choices_ready.emit(system.offered.duplicate(), system.levels.duplicate())
	var button: Button = main.get_node("UpgradeMenu").choices_container.get_child(0)
	check(button.text.contains(chosen.get_level_text(player.combat_stats, int(system.levels.get(id, 0)))), "Choice card reads central level/max rule")
	button.pressed.emit()
	check(not paused, "Choosing a normal reward resumes")

func run() -> void:
	setup()
	var ids: Array[StringName] = []
	for value in system.definitions:
		ids.append(value.id)
	await cleanup()
	# Verify every actual definition, not just representative category members.
	for id in ids:
		setup()
		var value := definition(id)
		var expected_max := 4 if id == &"multishot" else (5 if value.category == UpgradeDefinition.Category.WEAPON else 8)
		check(value.get_max_level() == expected_max, "Central category cap or projectile override")
		for selection in range(1, expected_max + 1):
			select(id)
			check(system.levels[id] == selection, "Exactly one level gained per selection")
		check(not system.available_upgrades().has(value), "Maxed type removed from eligible pool")
		check(value.get_level_text(player.combat_stats, expected_max).ends_with(" MAX"), "Maxed level label")
		var previous := player.combat_stats.get_modifier(value.stat)
		system.queue_level()
		system.offered.append(value)
		system.select_upgrade(id)
		check(system.levels[id] == expected_max and player.combat_stats.get_modifier(value.stat) == previous, "Injected maxed selection cannot apply another effect")
		system.select_upgrade(system.offered[0].id)
		match id:
			&"armor":
				check(player.combat_stats.get_armor() == 8, "Armor supports all eight normal selections")
			&"multishot":
				check(player.combat_stats.get_projectile_count() == 5, "Four count upgrades produce exactly five total projectiles")
		var panel = main.get_node("CharacterInfoPanel")
		panel.open_panel()
		var section: String = "Weapons" if value.category == UpgradeDefinition.Category.WEAPON else "Generic"
		var slot: PanelContainer
		for candidate: PanelContainer in panel.content.get_node("Upgrades/" + section + "/Slots").get_children():
			if candidate.get_node("Row/Name").text == panel._upgrade_display_name(value):
				slot = candidate
		check(slot != null and slot.get_node("Row/Level").text == "Lv. %d / %d MAX" % [expected_max, expected_max], "Character Info shows owned level, max, and MAX marker")
		panel.close_panel()
		await cleanup()

	setup()
	var weapon_ids: Array[StringName] = [&"bolter_damage", &"fire_rate", &"knife_damage", &"crit_chance"]
	var generic_ids: Array[StringName] = [&"armor", &"auto_senses", &"iron_halo", &"purity_seals"]
	for id in weapon_ids + generic_ids:
		select(id)
	for _selection in 4:
		select(&"bolter_damage")
	for _selection in 7:
		select(&"armor")
	check(system.get_selected_weapon_ids().size() == 4 and system.get_selected_generic_ids().size() == 4, "Maxed types retain all four category commitments")
	check(not system.can_select_upgrade(definition(&"knife_range")) and not system.can_select_upgrade(definition(&"combat_stims")), "Maxing a type never allows fifth Weapon or Generic type")
	check(system.can_select_upgrade(definition(&"fire_rate")) and system.can_select_upgrade(definition(&"auto_senses")), "Other committed types still levelable")
	# Finish both committed builds, leaving just two, then one, eligible choices.
	for id in weapon_ids + generic_ids:
		if id in [&"fire_rate", &"auto_senses"]:
			continue
		while system.can_select_upgrade(definition(id)):
			select(id)
	while int(system.levels[&"fire_rate"]) < 4:
		select(&"fire_rate")
	while int(system.levels[&"auto_senses"]) < 7:
		select(&"auto_senses")
	check(system.available_upgrades().size() == 2, "Exactly two valid choices remain")
	system.queue_level()
	check(system.offered.size() == 2 and main.get_node("UpgradeMenu").choices_container.get_child_count() == 2, "Screen shows only the two remaining choices")
	system.select_upgrade(&"fire_rate")
	system.queue_level()
	check(system.offered.size() == 1 and main.get_node("UpgradeMenu").choices_container.get_child_count() == 1, "Screen shows only one valid choice")
	system.select_upgrade(&"auto_senses")
	check(system.available_upgrades().is_empty(), "Fully maxed committed builds have no eligible upgrades")
	var exhausted_before := exhausted
	player.level = 9
	system.queue_level()
	check(exhausted == exhausted_before + 1 and system.pending_levels == 0 and not paused and not main.get_node("UpgradeMenu").visible, "Empty normal pool skips reward without trapping pause")
	player.level = 10
	system.queue_level()
	check(paused and system.chapter_offered.size() == 3 and main.get_node("ChapterPerkMenu").visible, "Chapter milestone still grants its perk even when normal pool is exhausted")
	system.select_chapter_perk(system.chapter_offered[0].id)
	check(not paused, "Chapter choice resumes after exhausted build")
	paused = true
	player.level = 11
	system.queue_level()
	check(paused and system.pending_levels == 0, "Exhausted reward preserves a pre-existing gameplay pause")
	paused = false
	# Exhausted normal rewards must also drain correctly around queued milestones.
	player.combat_stats.modifiers.erase(&"xp_gain")
	player.level = 28
	player.xp = 0.0
	var xp_to_31 := 0
	for level in range(28, 31):
		xp_to_31 += player.xp_progression.get_requirement(level)
	player.add_xp(xp_to_31)
	check(player.level == 31 and paused and system.reward_levels == [30, 31] and system.chapter_offered.size() == 3, "Large XP grant skips exhausted level 29 but queues Chapter 30 and normal 31")
	system.select_chapter_perk(system.chapter_offered[0].id)
	await process_frame
	check(system.pending_levels == 0 and not paused, "Queued exhausted reward drains and restores gameplay after Chapter selection")
	var projectile_upgrade := definition(&"multishot")
	var custom_projectiles := CombatStats.new()
	custom_projectiles.base_projectile_count = 4
	projectile_upgrade.apply(custom_projectiles)
	check(custom_projectiles.get_projectile_count() == 5 and not projectile_upgrade.is_available(custom_projectiles, 1), "Actual projectile cap can stop a type earlier than its level override")
	await cleanup()
	print("PASS: %d upgrade level cap checks" % checks)
	quit()
