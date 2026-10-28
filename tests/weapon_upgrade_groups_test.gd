extends SceneTree

var checks: int = 0
var main: Node2D
var player: Player
var system: UpgradeSystem

class CountingCritStats extends CombatStats:
	var rolls: int = 0
	func roll_hit(base_damage: float, guaranteed_critical: bool = false) -> CombatStats.DamageRoll:
		rolls += 1
		return super.roll_hit(base_damage, guaranteed_critical)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func definition(id: StringName) -> UpgradeDefinition:
	for value in system.definitions:
		if value.id == id:
			return value
	return null

func select(id: StringName) -> void:
	var chosen := definition(id)
	check(system.can_select_upgrade(chosen), "Selected upgrade is eligible")
	system.queue_level()
	system.offered = [chosen]
	for candidate in system.available_upgrades():
		if candidate.id != id and system.offered.size() < 3:
			system.offered.append(candidate)
	system.choices_ready.emit(system.offered.duplicate(), system.levels.duplicate())
	main.get_node("UpgradeMenu").choices_container.get_child(0).pressed.emit()

func enemy_at(position: Vector2) -> Enemy:
	var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	enemy.max_health = 500.0
	enemy.position = position
	main.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func run() -> void:
	root.size = Vector2i(1152, 648)
	main = preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	system = main.get_node("UpgradeSystem")
	var panel = main.get_node("CharacterInfoPanel")
	var bolter = player.get_node("Bolter")
	var knife: KnifeAttack = player.get_node("KnifeAttack")
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	bolter.fire_timer.stop()
	knife.set_physics_process(false)
	check(UpgradeDefinition.Category.keys() == ["WEAPON", "GENERIC"], "Exactly two top-level categories")
	check(UpgradeDefinition.WeaponUpgradeGroup.keys() == ["BOLTER", "KNIFE", "SHARED"], "Exactly three secondary Weapon groups")
	var mapping := {&"bolter_damage": UpgradeDefinition.WeaponUpgradeGroup.BOLTER, &"projectile_speed": UpgradeDefinition.WeaponUpgradeGroup.BOLTER, &"fire_rate": UpgradeDefinition.WeaponUpgradeGroup.BOLTER, &"multishot": UpgradeDefinition.WeaponUpgradeGroup.BOLTER, &"knife_damage": UpgradeDefinition.WeaponUpgradeGroup.KNIFE, &"knife_range": UpgradeDefinition.WeaponUpgradeGroup.KNIFE, &"knife_attack_rate": UpgradeDefinition.WeaponUpgradeGroup.KNIFE, &"crit_chance": UpgradeDefinition.WeaponUpgradeGroup.SHARED}
	var weapon_count := 0
	var generic_count := 0
	for value in system.definitions:
		if value.category == UpgradeDefinition.Category.WEAPON:
			weapon_count += 1
			check(mapping.has(value.id) and value.weapon_group == mapping[value.id], "Each Weapon type has correct secondary group")
			check(value.get_max_level() == (4 if value.id == &"multishot" else 5), "Weapon category caps and functional override remain intact")
		else:
			generic_count += 1
			check(value.get_max_level() == 8, "Generic level cap unchanged")
	check(weapon_count == 8 and generic_count == 8, "Existing full normal pool unchanged")
	var crit := definition(&"crit_chance")
	check(crit.effect_text() == "+1.5% Crit Chance" and crit.description == "Add 1.5% points to Crit Chance." and crit.amount == 0.015 and not crit.scales_with_mastery, "Shared Crit Chance effect and description unchanged")
	# Group metadata cannot affect random normal choices or category eligibility.
	seed(12345)
	system.queue_level()
	var original_choices: Array[StringName] = []
	for value in system.offered:
		original_choices.append(value.id)
	system._finish_reward()
	for id: StringName in mapping:
		definition(id).weapon_group = UpgradeDefinition.WeaponUpgradeGroup.SHARED
	seed(12345)
	system.queue_level()
	var regrouped_choices: Array[StringName] = []
	for value in system.offered:
		regrouped_choices.append(value.id)
	check(regrouped_choices == original_choices, "Identical seed gives identical normal choices regardless of secondary groups")
	system._finish_reward()
	for id: StringName in mapping:
		definition(id).weapon_group = mapping[id]
	# Select in mixed order, proving display grouping does not own slot counts.
	for id: StringName in [&"crit_chance", &"knife_range", &"fire_rate", &"bolter_damage"]:
		select(id)
	check(system.get_selected_weapon_ids().size() == 4, "Bolter plus Knife plus Shared consume the same four slots")
	for id: StringName in [&"knife_damage", &"projectile_speed", &"knife_attack_rate", &"multishot"]:
		check(not system.can_select_upgrade(definition(id)), "No separate subgroup slot budget allows fifth Weapon type")
	for _selection in 4:
		select(&"crit_chance")
	check(system.levels[&"crit_chance"] == 5 and is_equal_approx(player.combat_stats.get_modifier(&"crit_chance"), 0.075), "Five Shared Crit Chance selections contribute exactly seven point five percentage points")
	check(not system.can_select_upgrade(crit) and system.get_selected_weapon_ids().size() == 4, "Maxed Shared type keeps its Weapon slot")
	select(&"armor")
	select(&"health_regen")
	panel.open_panel()
	var weapon_section: VBoxContainer = panel.content.get_node("Upgrades/Weapons")
	var generic_section: VBoxContainer = panel.content.get_node("Upgrades/Generic")
	check(panel.content.get_node("Upgrades").get_child_count() == 2, "Only two major upgrade sections")
	check(weapon_section.get_node("Count").text == "Weapon Upgrades: 4 / 4" and generic_section.get_node("Count").text == "Generic Upgrades: 2 / 4", "One combined Weapon counter and separate Generic counter")
	check(weapon_section.get_node("Slots").get_child_count() == 4 and generic_section.get_node("Slots").get_child_count() == 4, "No subgroup-specific slot containers")
	var expected_names: Array[String] = ["Bolter Fire Rate", "Bolter Damage", "Knife Range", "Crit Chance"]
	var expected_groups: Array[String] = ["BOLTER", "BOLTER", "KNIFE", "SHARED"]
	for index in 4:
		var slot := weapon_section.get_node("Slots").get_child(index)
		check(slot.get_node("Row/Name").text == expected_names[index] and slot.get_node("Row/Group").text == expected_groups[index] and slot.get_node("Row/Group").visible, "Weapon rows grouped by explicit metadata")
	check(weapon_section.get_node("Slots").get_child(3).get_node("Row/Level").text == "Lv. 5 / 5 MAX", "Grouped maxed Shared upgrade retains level label")
	for slot in generic_section.get_node("Slots").get_children():
		check(not slot.get_node("Row/Group").visible, "Generic slots have no Weapon group label")
	panel.close_panel()
	var manager := system.chapter_manager
	for perk in manager.catalog.perks:
		if perk.id == &"tactical_precision":
			manager.apply_perk(perk)
			check(is_equal_approx(player.combat_stats.get_crit_chance(), 0.075 + float(perk.modifiers[&"crit_chance"])), "Existing Chapter Crit Chance stacks with Shared normal bonus")
	check(system.get_selected_weapon_ids().size() == 4 and system.get_selected_generic_ids().size() == 2, "Chapter perk consumes no normal slot")
	check(bolter.combat_stats == player.combat_stats and knife.combat_stats == player.combat_stats, "Both real weapons use the same player CombatStats")
	# Count real combat rolls: one direct, each splash target, then knife.
	var shared := CountingCritStats.new()
	shared.modifiers = player.combat_stats.modifiers.duplicate()
	shared.crit_chance = 1.0
	player.combat_stats = shared
	bolter.combat_stats = shared
	knife.combat_stats = shared
	check(shared.get_crit_multiplier() == 1.5, "Default crit multiplier stays one point five")
	var direct := enemy_at(Vector2(1000, 0))
	var splash_a := enemy_at(Vector2(1030, 0))
	var splash_b := enemy_at(Vector2(970, 0))
	var melee := enemy_at(Vector2(30, 0))
	var bolt := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	bolt.combat_stats = shared
	bolt.damage = bolter.get_damage()
	bolt.monitoring = false
	bolt.position = direct.position
	main.add_child(bolt)
	bolt.set_physics_process(false)
	await physics_frame
	await physics_frame
	bolt._explode(direct)
	check(shared.rolls == 3, "Direct and two splash targets each receive their own crit roll")
	check(is_equal_approx(direct.current_health, 500.0 - bolt.damage * 1.5), "Shared crit affects direct Bolter damage")
	check(is_equal_approx(splash_a.current_health, 500.0 - bolt.splash_damage * 1.5) and is_equal_approx(splash_b.current_health, splash_a.current_health), "Shared crit affects both splash targets")
	knife._nearby_enemies[melee.get_instance_id()] = melee
	knife._attack()
	check(shared.rolls == 4 and is_equal_approx(melee.current_health, 500.0 - knife.get_damage() * 1.5), "Same shared crit resource affects real Knife attack")
	await process_frame
	var red_numbers := 0
	for child in main.get_children():
		if child is FloatingDamageNumber:
			check(child.is_critical and child.get_node("Label").modulate == Color.RED, "Critical damage number remains red")
			red_numbers += 1
	check(red_numbers == 4, "Four independently rolled critical hit numbers")
	# Let the unchanged explosion effect finish its SceneTreeTimer before exit.
	await create_timer(0.35).timeout
	print("PASS: %d Weapon group checks" % checks)
	main.queue_free()
	await process_frame
	shared = null
	quit()
