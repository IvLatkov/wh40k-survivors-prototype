extends SceneTree

var checks: int = 0
var main: Node2D
var player: Player
var system: UpgradeSystem
var clock: RunClock

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
	clock = main.get_node("RunClock")
	clock.set_process(false)
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)

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
	check(system.available_upgrades().has(chosen), "Upgrade is actually available: " + str(id))
	system.queue_level()
	# Deterministic choice presentation uses the complete real catalog for caps.
	system.offered = [chosen]
	for candidate in system.available_upgrades():
		if candidate.id != id and system.offered.size() < 3:
			system.offered.append(candidate)
	system.choices_ready.emit(system.offered.duplicate(), system.levels.duplicate())
	var menu = main.get_node("UpgradeMenu")
	check(menu.choices_container.get_child_count() == 3, "Three normal choices")
	check(menu.choices_container.get_child(0).text.contains(chosen.display_name + "  |  " + chosen.effect_text()), "Player-facing card has correct name and effect")
	menu.choices_container.get_child(0).pressed.emit()
	check(not paused, "Selection resumes gameplay")

func run() -> void:
	setup()
	var names := {&"armor": "CERAMITE PLATING", &"max_health": "ASTARTES PHYSIOLOGY", &"health_regen": "GENE-SEED RESILIENCE", &"auto_senses": "AUTO-SENSES", &"combat_stims": "COMBAT STIMS", &"purity_seals": "PURITY SEALS", &"iron_halo": "IRON HALO", &"battlefield_salvage": "BATTLEFIELD SALVAGE"}
	var effects := {&"armor": "+1 Armor", &"max_health": "+5% Max Health", &"health_regen": "+0.2 HP/s", &"auto_senses": "+10% Pickup Radius", &"combat_stims": "+5% Movement Speed", &"purity_seals": "+10% XP Gain", &"iron_halo": "+2% Dodge Chance", &"battlefield_salvage": "+5% Better XP Drop Chance"}
	var generic_count := 0
	for value in system.definitions:
		if value.category == UpgradeDefinition.Category.GENERIC:
			generic_count += 1
			check(names.has(value.id) and value.display_name == names[value.id] and value.effect_text() == effects[value.id], "Exact Generic IDs, names, and effects")
	check(generic_count == 8 and system.definitions.size() == 16, "Eight Generic and eight unchanged Weapon upgrades")
	var mastery_stats := CombatStats.new()
	mastery_stats.add_modifier(&"normal_upgrade_effectiveness", 0.2)
	for id: StringName in [&"auto_senses", &"combat_stims", &"purity_seals", &"iron_halo", &"battlefield_salvage"]:
		var value := definition(id)
		value.apply(mastery_stats)
		check(is_equal_approx(mastery_stats.get_modifier(value.stat), value.amount), "New Generic grants exact increment even with existing Mastery")
	# Existing Generic IDs retain effects while all owned names are renamed.
	for id: StringName in [&"armor", &"max_health", &"health_regen"]:
		select(id)
	var renamed_panel = main.get_node("CharacterInfoPanel")
	renamed_panel.open_panel()
	var renamed_slots: VBoxContainer = renamed_panel.content.get_node("Upgrades/Generic/Slots")
	var renamed_names: PackedStringArray = []
	for slot in renamed_slots.get_children():
		renamed_names.append(slot.get_node("Row/Name").text)
	check(renamed_names == PackedStringArray(["Ceramite Plating", "Astartes Physiology", "Gene-Seed Resilience", "Empty"]), "Owned Generic slots preserve the exact renamed labels and hyphens")
	check(player.combat_stats.get_armor() == 1 and player.max_health == 53.0 and is_equal_approx(player.get_health_regen(), 0.2), "Renamed upgrades retain original gameplay effects")
	await cleanup()
	setup()
	select(&"auto_senses")
	select(&"combat_stims")
	select(&"purity_seals")
	select(&"iron_halo")
	check(system.get_selected_generic_ids().size() == 4, "Four different Generic types committed")
	for value in system.available_upgrades():
		check(value.category == UpgradeDefinition.Category.WEAPON or system.levels.has(value.id), "No new Generic type offered after four commitments")
	check(system.available_upgrades().has(definition(&"auto_senses")), "Committed Generic remains levelable")
	select(&"auto_senses")
	check(system.levels[&"auto_senses"] == 2 and is_equal_approx(player.get_pickup_radius(), 72.0), "Committed type relevels without consuming another slot")
	system.queue_level()
	system.offered.append(definition(&"armor"))
	system.select_upgrade(&"armor")
	check(not system.levels.has(&"armor") and player.combat_stats.get_armor() == 0 and system.pending_levels == 1, "Forged fifth Generic selection is rejected")
	system.select_upgrade(system.offered[0].id)
	await cleanup()

	setup()
	var pickup := preload("res://scenes/pickups/xp_pickup.tscn").instantiate() as XPPickup
	pickup.position = Vector2(75, 0)
	main.add_child(pickup)
	await physics_frame
	await physics_frame
	check(not pickup._magnetized and player.get_pickup_radius() == 60.0, "Skull outside original pickup area is not collected")
	for radius in [66.0, 72.0, 78.0]:
		select(&"auto_senses")
		check(is_equal_approx(player.get_pickup_radius(), radius) and player._base_pickup_radius == 60.0, "Auto-Senses stacks from actual base circle")
	await physics_frame
	await physics_frame
	check(pickup._magnetized and pickup._idle_tween == null and pickup.travel_speed == 220.0, "Enlarged actual Area2D starts unchanged skull magnet travel")
	var another := preload("res://scenes/player/player.tscn").instantiate() as Player
	main.add_child(another)
	another.set_physics_process(false)
	another.get_node("Bolter/FireTimer").stop()
	another.get_node("KnifeAttack").set_physics_process(false)
	check(another.get_pickup_radius() == 60.0 and another.xp_collection_shape.shape != player.xp_collection_shape.shape, "Pickup shape bonuses are private to each player")
	another.queue_free()
	for multiplier in [1.05, 1.10, 1.15]:
		select(&"combat_stims")
		check(is_equal_approx(player.get_movement_speed(), 250.0 * multiplier) and player.speed == 250.0, "Movement stacks from original speed")
	Input.action_press("move_right")
	player.set_physics_process(true)
	for _frame in 20:
		await physics_frame
	check(is_equal_approx(player.velocity.x, 287.5), "Actual movement reaches upgraded speed")
	Input.action_release("move_right")
	player.set_physics_process(false)
	await cleanup()

	setup()
	select(&"purity_seals")
	player.level = 100
	var resources: Array[XPReward] = [preload("res://assets/art/effects/xp/low_level/xp_reward.tres"), preload("res://assets/art/effects/xp/mid_level/xp_reward.tres"), preload("res://assets/art/effects/xp/high_level/xp_reward.tres"), preload("res://assets/art/effects/xp/boss/xp_reward.tres")]
	var base_values: Array[int] = [1, 5, 15, 25]
	for index in resources.size():
		player.xp = 0.0
		var skull := preload("res://scenes/pickups/xp_pickup.tscn").instantiate() as XPPickup
		skull.configure(resources[index])
		main.add_child(skull)
		skull.start_collecting(player)
		skull._process(0.1)
		check(is_equal_approx(player.xp, base_values[index] * 1.1), "Pickup awards exact fractional XP with Purity Seals")
		check(skull.xp_value == base_values[index] and resources[index].xp_per_pickup == base_values[index], "Skull and reward retain original XP value")
	player.xp = 0.0
	for _pickup in 100:
		player.add_xp(1.0)
	check(is_equal_approx(player.xp, 110.0), "Small bonuses accumulate without lost XP")
	check(main.get_node("HealthHUD").xp_label.text == "LEVEL 100    XP 110 / 1375", "XP label uses clean whole-number earned XP")
	select(&"purity_seals")
	player.xp = 0.0
	player.add_xp(5.0)
	check(is_equal_approx(player.xp, 6.0), "Two Purity Seals stack additively")
	var xp_panel = main.get_node("CharacterInfoPanel")
	xp_panel.open_panel()
	check(xp_panel._value_labels["XP Gain"].text == "+20%", "Character Info displays live Purity Seals XP bonus")
	xp_panel.close_panel()
	# Ten base-one pickups at twenty percent produce twelve XP across the threshold.
	player.level = 1
	player.xp = 0.0
	for _pickup in 10:
		player.add_xp(1.0)
	check(player.level == 2 and is_equal_approx(player.xp, 4.0), "Fractional XP carries cleanly through unchanged level requirements")
	while system.pending_levels > 0:
		system.select_upgrade(system.offered[0].id)
		await process_frame
	await cleanup()

	setup()
	select(&"iron_halo")
	select(&"armor")
	check(is_equal_approx(player.combat_stats.get_dodge_chance(), 0.02), "Iron Halo adds two percentage points")
	seed(123456)
	var dodges := 0
	for _roll in 100000:
		if player.combat_stats.roll_dodge():
			dodges += 1
	check(absf(dodges / 100000.0 - 0.02) < 0.003, "Approximately two percent dodge chance")
	var successful_seed := -1
	var failed_seed := -1
	for value in 10000:
		seed(value)
		if randf() < 0.02:
			successful_seed = value
		else:
			failed_seed = value
		if successful_seed >= 0 and failed_seed >= 0:
			break
	seed(successful_seed)
	player.take_damage(3.0)
	check(player.current_health == 50.0 and not player.damage_invulnerability_timer.is_stopped(), "Dodge avoids all HP loss and consumes existing damage window")
	seed(42)
	var expected_rng := randf()
	seed(42)
	player.take_damage(3.0)
	check(randf() == expected_rng and player.current_health == 50.0, "Invulnerability rejects event before dodge RNG")
	player.damage_invulnerability_timer.stop()
	seed(failed_seed)
	player.take_damage(3.0)
	check(player.current_health == 48.0, "Failed dodge applies unchanged Armor after roll")
	player.damage_invulnerability_timer.stop()
	player.combat_stats.modifiers[&"armor"] = 100.0
	seed(successful_seed)
	player.take_damage(3.0)
	check(player.current_health == 48.0, "Successful dodge bypasses minimum-one Armor damage")
	player.damage_invulnerability_timer.stop()
	seed(failed_seed)
	player.take_damage(3.0)
	check(player.current_health == 47.0, "Failed dodge with high Armor still deals minimum one")
	select(&"iron_halo")
	select(&"iron_halo")
	check(is_equal_approx(player.combat_stats.get_dodge_chance(), 0.06), "Iron Halo stacks additively")
	seed(7)
	expected_rng = randf()
	seed(7)
	player.take_damage(0.0)
	check(randf() == expected_rng, "Invalid damage does not roll dodge")
	await cleanup()

	setup()
	var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	main.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_target(player)
	enemy.set_run_clock(clock)
	clock.elapsed_time = 299.999
	select(&"battlefield_salvage")
	for _roll in 1000:
		check(enemy.roll_xp_reward() == enemy.low_xp_reward, "Salvage never unlocks MID before five minutes")
	clock.elapsed_time = 300.0
	check(is_equal_approx(enemy.get_mid_xp_upgrade_chance(), 0.15), "One Salvage raises MID chance to fifteen percent")
	select(&"battlefield_salvage")
	check(is_equal_approx(enemy.get_mid_xp_upgrade_chance(), 0.20), "Two Salvage raise MID chance to twenty percent")
	seed(123456)
	var mids := 0
	var doubles := 0
	for _roll in 100000:
		if enemy.roll_xp_reward() == enemy.mid_xp_reward:
			mids += 1
		if enemy.low_xp_reward.roll_pickup_count() == 2:
			doubles += 1
	check(absf(mids / 100000.0 - 0.20) < 0.01 and absf(doubles / 100000.0 - 0.07) < 0.005, "Salvage distribution and independent seven-percent doubles")
	for _selection in 6:
		select(&"battlefield_salvage")
	check(is_equal_approx(enemy.get_mid_xp_upgrade_chance(), 0.50) and not system.available_upgrades().has(definition(&"battlefield_salvage")), "Existing stat cap stops Salvage at fifty-percent MID chance")
	player.combat_stats.modifiers[&"better_xp_drop_chance"] = 5.0
	check(enemy.get_mid_xp_upgrade_chance() == 0.50, "MID probability cannot exceed configured fifty-percent cap")
	player.combat_stats.modifiers[&"better_xp_drop_chance"] = 0.4
	# Exercise a real MID double death with Salvage active.
	var mid_double_seed := -1
	for value in 10000:
		seed(value)
		if enemy.roll_xp_reward() == enemy.mid_xp_reward and enemy.low_xp_reward.roll_pickup_count() == 2:
			mid_double_seed = value
			break
	seed(mid_double_seed)
	enemy.die()
	await process_frame
	var dropped_mids := 0
	for child in main.get_children():
		if child is XPPickup:
			dropped_mids += 1
			check(child.xp_value == 5 and child.visual.texture.resource_path.ends_with("mid_level/Skull_head_with_little_wings_blue.png"), "Salvage death retains MID art and base XP on every double skull")
	check(dropped_mids == 2, "Salvage MID double creates two matching skulls")
	select(&"auto_senses")
	select(&"combat_stims")
	select(&"iron_halo")
	var panel = main.get_node("CharacterInfoPanel")
	panel.open_panel()
	var expected := {"Movement Speed": "262.5", "Pickup Radius": "66 px", "XP Gain": "+0%", "Dodge Chance": "2%", "Better XP Drop Chance": "+40%"}
	for name: String in expected:
		check(panel._value_labels[name].text == expected[name], "Character Info reads actual live " + name)
	check(panel._value_labels["Better XP Drop Chance"].visible, "Owned Salvage stat displayed")
	var generic: VBoxContainer = panel.content.get_node("Upgrades/Generic")
	check(generic.get_node("Count").text == "Generic Upgrades: 4 / 4", "Generic UI shows four committed types")
	check(generic.get_node("Slots").get_child(0).get_node("Row/Level").text == "Lv. 8 / 8 MAX", "Salvage level uses existing selection counts")
	print("Salvage sample: MID=", mids, " doubles=", doubles, "; dodge sample=", dodges)
	await cleanup()
	print("PASS: %d Generic upgrade checks" % checks)
	quit()
