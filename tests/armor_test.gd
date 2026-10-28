extends SceneTree

var checks: int = 0
var reported_health: float = 0.0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	var system: UpgradeSystem = main.get_node("UpgradeSystem")
	var menu = main.get_node("UpgradeMenu")
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	player.health_changed.connect(func(current: float, _maximum: float) -> void: reported_health = current)
	check(player.combat_stats.get_armor() == 0, "Starting armor is zero")
	check(player.max_health == 50.0 and player.current_health == 50.0, "Starting HP unchanged")
	var armor_upgrade: UpgradeDefinition
	for definition in system.definitions:
		if definition.id == &"armor":
			armor_upgrade = definition
	check(armor_upgrade != null and armor_upgrade.effect_text() == "+1 Armor", "Armor card effect")
	check(armor_upgrade.description == "Reinforce your power armor with additional ceramite protection.", "Armor card description")
	var all_definitions := system.definitions.duplicate()
	system.definitions = [armor_upgrade, all_definitions[0], all_definitions[1]]
	for selection in range(1, 9):
		player.add_xp(player.get_xp_required())
		var armor_button: Button
		for child in menu.choices_container.get_children():
			if child.text.begins_with("CERAMITE PLATING"):
				armor_button = child
		check(armor_button != null and armor_button.text.contains("Lv. %d / 8" % (selection - 1)), "Armor shown with correct selected count")
		armor_button.pressed.emit()
		check(player.combat_stats.get_armor() == selection and system.levels[&"armor"] == selection, "Selection adds exactly one permanent Armor")
		check(not paused and not menu.visible, "Selection resumes gameplay")
	check(not armor_upgrade.is_available(player.combat_stats, 8), "Armor capped at eight")
	system.definitions = all_definitions
	check(not system.available_upgrades().has(armor_upgrade), "Capped Armor excluded from pool")
	for iteration in 20:
		system.queue_level()
		check(system.offered.size() == 3 and not system.offered.has(armor_upgrade), "Three choices without capped Armor")
		system.select_upgrade(&"armor")
		check(player.combat_stats.get_armor() == 8 and system.pending_levels == 1, "Unoffered Armor cannot exceed cap")
		system.select_upgrade(system.offered[0].id)
	# Isolate damage cases from randomly selected non-Armor stat upgrades.
	player.combat_stats.modifiers.clear()
	for armor in range(9):
		player.combat_stats.modifiers[&"armor"] = float(armor)
		for incoming in [1.0, 3.0, 5.0, 0.1]:
			player.current_health = 50.0
			player.damage_invulnerability_timer.stop()
			var expected := maxf(1.0, incoming - armor)
			player.take_damage(incoming)
			check(is_equal_approx(player.current_health, 50.0 - expected), "HP matches flat Armor with minimum one")
			check(is_equal_approx(reported_health, player.current_health), "HP signal reports post-Armor health")
			player.take_damage(incoming)
			check(is_equal_approx(player.current_health, 50.0 - expected), "Invulnerability still rejects repeated hits")
	player.damage_invulnerability_timer.stop()
	var before := player.current_health
	player.take_damage(0.0)
	player.take_damage(-5.0)
	check(player.current_health == before, "Invalid nonpositive damage ignored")
	player.combat_stats.add_modifier(&"damage_reduction", 0.08)
	player.current_health = 50.0
	player.take_damage(1.0)
	check(player.current_health == 49.0, "Squig hit remains one with Armor and Battle Hardened")
	player.damage_invulnerability_timer.stop()
	player.current_health = 50.0
	player.take_damage(10.0)
	check(is_equal_approx(player.current_health, 48.8), "Existing percent reduction precedes Armor")
	# Actual enemy contact still routes through the same damage function.
	var squig := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	main.add_child(squig)
	squig.set_physics_process(false)
	squig.set_target(player)
	squig.position = player.position + Vector2(20, 0)
	player.damage_invulnerability_timer.stop()
	player.current_health = 50.0
	squig._physics_process(0.016)
	check(squig.contact_damage == 1.0 and player.current_health == 49.0, "Squig contact still deals minimum one with Armor eight")
	player.combat_stats.modifiers.clear()
	player.combat_stats.add_modifier(&"normal_upgrade_effectiveness", 0.2)
	armor_upgrade.apply(player.combat_stats)
	check(player.combat_stats.get_armor() == 1, "Codex Mastery does not change flat Armor increment")
	print("PASS: %d Armor checks" % checks)
	main.queue_free()
	await process_frame
	quit()
