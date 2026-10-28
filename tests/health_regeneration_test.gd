extends SceneTree

var checks: int = 0
var notifications: int = 0
var player: Player

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func check_paused(message: String) -> void:
	var before := player.current_health
	await create_timer(0.15).timeout
	check(paused and player.current_health == before, message)

func check_resumed() -> void:
	var before := player.current_health
	await create_timer(0.12).timeout
	check(not paused and player.current_health > before, "Regeneration resumes during real gameplay")

func run() -> void:
	root.size = Vector2i(1152, 648)
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	var system: UpgradeSystem = main.get_node("UpgradeSystem")
	var menu = main.get_node("UpgradeMenu")
	var panel = main.get_node("CharacterInfoPanel")
	var hud: HealthHud = main.get_node("HealthHUD")
	main.get_node("EnemySpawner").set_process(false)
	main.get_node("ChapterPerkManager").set_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	player.set_physics_process(false)
	player.health_changed.connect(func(_hp: float, _max_hp: float) -> void: notifications += 1)
	var definitions := system.definitions.duplicate()
	var regen: UpgradeDefinition
	var max_hp: UpgradeDefinition
	for definition: UpgradeDefinition in definitions:
		if definition.id == &"health_regen":
			regen = definition
		if definition.id == &"max_health":
			max_hp = definition
	check(definitions.size() == 16 and system.available_upgrades().size() == 16, "Sixteen normal upgrades")
	check(regen != null and regen.display_name == "GENE-SEED RESILIENCE" and regen.effect_text() == "+0.2 HP/s" and regen.description == "Regenerate 0.2 Health per second.", "Exact regeneration card text")
	check(player.get_health_regen() == 0.0 and player.max_health == 50.0, "Zero starting regeneration and unchanged base health")
	player.current_health = 40.0
	player._physics_process(10.0)
	check(player.current_health == 40.0 and notifications == 0, "Zero regen does not heal or notify")
	# Flat regeneration remains exactly 0.2 even with existing Codex Mastery.
	player.combat_stats.add_modifier(&"normal_upgrade_effectiveness", 0.2)
	for selection in range(1, 6):
		system.definitions = [regen, definitions[0], definitions[1]]
		system.queue_level()
		var ids: Dictionary = {}
		for choice in system.offered:
			ids[choice.id] = true
		check(ids.size() == 3 and system.offered.has(regen), "Regen appears among three unique normal choices")
		for button: Button in menu.choices_container.get_children():
			if button.text.begins_with("GENE-SEED RESILIENCE"):
				check(button.text.contains("+0.2 HP/s"), "UI shows actual flat regen bonus")
				button.pressed.emit()
				break
		check(is_equal_approx(player.get_health_regen(), selection * 0.2), "Selections stack by exactly 0.2 HP/s")
		check(not paused and system.levels[&"health_regen"] == selection, "Normal selection applies and resumes")
		if selection == 1:
			for _frame in 300:
				player._physics_process(1.0 / 60.0)
			check(is_equal_approx(player.current_health, 41.0), "0.2 HP/s restores one HP in five seconds")
			for _frame in 300:
				player._physics_process(1.0 / 60.0)
			check(is_equal_approx(player.current_health, 42.0), "0.2 HP/s restores two HP in ten seconds")
			check(notifications > 0 and notifications <= 100, "Regen health signals are throttled instead of per-frame")
	system.definitions = definitions
	check(regen.is_available(player.combat_stats, 5) and not regen.is_available(player.combat_stats, 8), "Regen stays levelable until Generic cap eight")
	player.current_health = 49.99
	player._physics_process(0.1)
	check(player.current_health == 50.0 and hud.health_bar.value == 50.0, "Regen clamps and notifies at full health")
	var before_notifications := notifications
	player._physics_process(10.0)
	check(player.current_health == 50.0 and notifications == before_notifications, "Full health does not repeatedly notify")
	player.current_health = 42.376492
	panel.open_panel()
	check(panel._value_labels["Health"].text == "42 / 50" and panel._value_labels["Health Regen"].text == "1.0 HP/s", "Clean whole-number health and live regen stat")
	await process_frame
	var info_rect: Rect2 = panel.get_node("Overlay/Center/Panel").get_global_rect()
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(info_rect), "Eleven stats fit inside Character Info")
	player.set_physics_process(true)
	await check_paused("Character Info pauses regeneration")
	panel.close_panel()
	await check_resumed()
	player.level = 2
	system.queue_level()
	await check_paused("Normal upgrade menu pauses regeneration")
	system.select_upgrade(system.offered[0].id)
	await check_resumed()
	for milestone in [10, 20, 30, 40, 50]:
		player.level = milestone
		system.queue_level()
		check(main.get_node("ChapterPerkMenu").visible and not menu.visible and system.offered.is_empty(), "Chapter milestone replaces normal menu")
		await check_paused("Chapter perk menu pauses regeneration")
		system.select_chapter_perk(system.chapter_offered[0].id)
		await check_resumed()
	paused = true
	await check_paused("Generic gameplay pause stops regeneration")
	paused = false
	await check_resumed()
	player.set_physics_process(false)
	# Isolate damage/Max Health from randomly selected perks.
	player.combat_stats.modifiers.clear()
	player.combat_stats.temporary_modifiers.clear()
	player.combat_stats.stat_changed.emit(&"max_health_bonus")
	player.combat_stats.stat_changed.emit(&"max_health")
	player.combat_stats.add_modifier(&"health_regen", 0.2)
	player.combat_stats.add_modifier(&"armor", 1.0)
	player.current_health = 38.0
	max_hp.apply(player.combat_stats)
	check(player.current_health == 40.0 and player.max_health == 53.0, "Existing Max Health example unchanged")
	player.damage_invulnerability_timer.stop()
	player.take_damage(3.0)
	check(player.current_health == 38.0, "Armor one still reduces raw three to two")
	player._physics_process(0.1)
	check(is_equal_approx(player.current_health, 38.02), "Damage invulnerability does not delay regeneration")
	player._physics_process(0.1)
	check(is_equal_approx(hud.health_bar.value, player.current_health) and hud.health_bar.step == 0.0, "HP bar receives fractional health")
	player.damage_invulnerability_timer.stop()
	player.take_damage(1000.0)
	paused = false
	player._physics_process(10.0)
	check(player.current_health == 0.0, "Regeneration never revives dead player")
	print("PASS: %d health regeneration checks" % checks)
	main.queue_free()
	await process_frame
	quit()
