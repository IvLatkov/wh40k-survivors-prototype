extends SceneTree

var checks: int = 0
var main: Node2D
var player: Player
var system: UpgradeSystem
var menu: CanvasLayer
var panel: CanvasLayer
var definitions: Array[UpgradeDefinition]
var shots: int = 0
var hits: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func definition(id: StringName) -> UpgradeDefinition:
	for value in definitions:
		if value.id == id:
			return value
	return null

func select(id: StringName) -> void:
	# Keep all three new choices on the actual screen for deterministic selection.
	system.definitions = [definition(&"fire_rate"), definition(&"knife_attack_rate"), definition(&"max_health")]
	system.queue_level()
	check(system.offered.size() == 3, "Three normal choices")
	var selected := definition(id)
	var clicked := false
	for button: Button in menu.choices_container.get_children():
		if button.text.begins_with(selected.display_name):
			check(button.text.contains(selected.effect_text()) and button.text.contains(selected.description), "Correct choice text and description")
			button.pressed.emit()
			clicked = true
			break
	check(clicked and not paused and not menu.visible, "Selection through normal UI applies and resumes")
	system.definitions = definitions

func run() -> void:
	root.size = Vector2i(1152, 648)
	main = preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	system = main.get_node("UpgradeSystem")
	menu = main.get_node("UpgradeMenu")
	panel = main.get_node("CharacterInfoPanel")
	definitions = system.definitions.duplicate()
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	var bolter = player.get_node("Bolter")
	var knife: KnifeAttack = player.get_node("KnifeAttack")
	bolter.fire_timer.stop()
	knife.set_physics_process(false)
	check(definitions.size() == 16 and system.available_upgrades().size() == 16, "Full normal pool contains sixteen unique choices")
	for id in [&"bolter_damage", &"projectile_speed", &"fire_rate", &"multishot", &"crit_chance", &"knife_damage", &"knife_range", &"knife_attack_rate", &"armor", &"max_health", &"health_regen"]:
		check(definition(id) != null, "Normal pool includes " + str(id))
	check(definition(&"fire_rate").effect_text() == "+10% Fire Rate", "Fire Rate effect label")
	check(definition(&"knife_attack_rate").effect_text() == "+10% Attack Rate", "Attack Rate effect label")
	check(definition(&"max_health").effect_text() == "+5% Max Health", "Max Health effect label")
	check(bolter.fire_interval == 0.75 and knife.melee_cooldown == 0.8, "Original base cooldowns")
	var bolter_damage: float = bolter.get_damage()
	var knife_damage := knife.get_damage()
	var knife_range := knife.current_knife_radius
	select(&"fire_rate")
	check(is_equal_approx(bolter.get_fire_interval(), 0.75 / 1.1), "First Bolter interval is 0.681818")
	check(is_equal_approx(bolter.fire_timer.wait_time, bolter.get_fire_interval()), "Actual fire timer uses upgraded interval")
	bolter.fire_timer.timeout.connect(func() -> void: shots += 1)
	bolter.fire_timer.start()
	await create_timer(1.43).timeout
	bolter.fire_timer.stop()
	check(shots == 2, "Two actual firing events before base timer could fire twice")
	select(&"fire_rate")
	check(is_equal_approx(bolter.get_fire_interval(), 0.625) and bolter.fire_interval == 0.75, "Second upgrade adds to base multiplier")
	select(&"knife_attack_rate")
	check(is_equal_approx(knife.get_attack_cooldown(), 0.8 / 1.1), "First knife cooldown is 0.727273")
	var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	enemy.max_health = 10000.0
	enemy.position = player.position + Vector2(30, 0)
	main.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.damage_received.connect(func(_amount: float, _critical: bool) -> void: hits += 1)
	knife._nearby_enemies[enemy.get_instance_id()] = enemy
	knife._attack()
	check(is_equal_approx(knife.cooldown_timer.wait_time, knife.get_attack_cooldown()), "Actual attack starts upgraded cooldown")
	knife.set_physics_process(true)
	await create_timer(1.53).timeout
	knife.set_physics_process(false)
	check(hits == 3, "Three actual knife attacks before base cooldown allows three")
	var fraction := knife.cooldown_timer.time_left / knife.cooldown_timer.wait_time
	select(&"knife_attack_rate")
	check(is_equal_approx(knife.get_attack_cooldown(), 0.8 / 1.2), "Second knife rate adds to base multiplier")
	check(is_equal_approx(knife.cooldown_timer.time_left / knife.cooldown_timer.wait_time, fraction), "Active cooldown preserves attack progress")
	check(knife.melee_cooldown == 0.8 and knife.get_damage() == knife_damage and knife.current_knife_radius == knife_range, "Knife base cooldown, damage, and range preserved")
	check(bolter.get_damage() == bolter_damage and player.combat_stats.get_crit_multiplier() == 1.5 and player.combat_stats.get_crit_chance() == 0.0 and player.combat_stats.get_projectile_count() == 1, "Other combat stats unchanged")
	player.current_health = 38.0
	select(&"max_health")
	check(player.max_health == 53.0 and player.current_health == 40.0, "Injured example becomes 40 of 53")
	for expected in [55.0, 58.0, 60.0]:
		player.current_health = player.max_health
		select(&"max_health")
		check(player.max_health == expected and player.current_health == expected, "Additive base health and full-health scaling")
	check(is_equal_approx(player.combat_stats.get_modifier(&"max_health_bonus"), 0.2) and player._base_max_health == 50.0, "Four selections store twenty percent on original base")
	player.current_health = 1.0
	select(&"max_health")
	check(player.max_health == 63.0 and player.current_health == 1.0, "Low health scales proportionally without flat healing")
	panel.open_panel()
	check(panel._value_labels["Health"].text == "1 / 63", "Character Info shows live upgraded health")
	check(panel._value_labels["Bolter Fire Rate"].text == "1.60 /s", "Character Info derives real Bolter rate")
	check(panel._value_labels["Knife Attack Rate"].text == "1.50 /s", "Character Info derives real knife rate")
	player.combat_stats.add_modifier(&"fire_rate", 0.1)
	player.combat_stats.add_modifier(&"knife_attack_rate", 0.1)
	check(panel._value_labels["Bolter Fire Rate"].text == "1.73 /s" and panel._value_labels["Knife Attack Rate"].text == "%.2f /s" % (1.0 / knife.get_attack_cooldown()), "Visible info refreshes after actual rate changes")
	await process_frame
	var info_rect: Rect2 = panel.get_node("Overlay/Center/Panel").get_global_rect()
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(info_rect), "Ten live stats fit in the viewport")
	panel.close_panel()
	for id in [&"fire_rate", &"knife_attack_rate", &"max_health"]:
		check(not definition(id).is_available(player.combat_stats, definition(id).get_max_level()), "Upgrade obeys category level cap")
	# Existing Chapter Mastery continues to affect percentage normal rewards.
	player.combat_stats.add_modifier(&"normal_upgrade_effectiveness", 0.2)
	var previous := player.combat_stats.get_modifier(&"max_health_bonus")
	definition(&"max_health").apply(player.combat_stats)
	check(is_equal_approx(player.combat_stats.get_modifier(&"max_health_bonus"), previous + 0.06), "Existing Mastery applies to new percentage reward")
	check(player.current_health <= player.max_health, "Current HP cannot exceed maximum")
	print("PASS: %d normal rate and health checks" % checks)
	main.queue_free()
	await process_frame
	quit()
