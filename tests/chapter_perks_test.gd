extends SceneTree

var checks: int = 0
var main: Node2D
var player: Player
var manager: ChapterPerkManager
var rewards: UpgradeSystem
var stats: CombatStats

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func setup() -> void:
	main = preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	manager = main.get_node("ChapterPerkManager")
	rewards = main.get_node("UpgradeSystem")
	stats = player.combat_stats
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	manager.set_process(false)

func cleanup() -> void:
	paused = false
	main.queue_free()
	await process_frame

func perk(id: StringName) -> ChapterPerkDefinition:
	for definition in manager.catalog.perks:
		if definition.id == id:
			return definition
	return null

func apply(id: StringName) -> void:
	check(manager.apply_perk(perk(id)), "Apply " + str(id))

func enemy_at(at: Vector2) -> Enemy:
	var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	# Explicit combat fixture HP; production Squigs now start at 25.
	enemy.max_health = 50.0
	enemy.position = at
	main.add_child(enemy)
	return enemy

func run() -> void:
	setup()
	check(player.chapter == SpaceMarineChapter.Type.ULTRAMARINES, "Default Chapter")
	check(not main.get_node("UpgradeMenu").visible and not main.get_node("ChapterPerkMenu").visible, "Level 1 starts without a reward")
	var xp_to_51 := 0
	for level in range(1, 51):
		xp_to_51 += player.xp_progression.get_requirement(level)
	player.add_xp(xp_to_51)
	check(player.level == 51 and rewards.pending_levels == 50, "Large XP grant captures every level")
	for level in range(2, 52):
		check(rewards.reward_levels[0] == level and paused, "Ordered reward and pause")
		if level in [10, 20, 30, 40, 50]:
			check(rewards.chapter_offered.size() == 3 and rewards.offered.is_empty(), "Milestone has three perks instead of upgrades")
			check(main.get_node("ChapterPerkMenu").visible and not main.get_node("UpgradeMenu").visible, "Chapter screen only")
			check(main.get_node("ChapterPerkMenu").can_process() and not player.can_process(), "Paused menu remains interactive")
			var ids: Dictionary = {}
			for choice in rewards.chapter_offered:
				ids[choice.id] = true
			check(ids.size() == 3, "Unique chapter choices")
			var selected := rewards.chapter_offered[0]
			main.get_node("ChapterPerkMenu").choices_container.get_child(0).pressed.emit()
			rewards.select_chapter_perk(selected.id)
			check(manager.selected.has(selected.id), "Perk selected")
			check(not manager.apply_perk(selected), "Perk cannot be reapplied")
			for choice in manager.choices_for(level):
				check(choice.id != selected.id, "Selected perks excluded")
		else:
			check(rewards.offered.size() + rewards.offered_ultimates.size() == mini(3, rewards.available_upgrades().size() + rewards.get_eligible_ultimates().size()) and rewards.chapter_offered.is_empty(), "Nonmilestone normal choices")
			check(main.get_node("UpgradeMenu").visible and not main.get_node("ChapterPerkMenu").visible, "Normal screen only")
			main.get_node("UpgradeMenu").choices_container.get_child(0).pressed.emit()
		await process_frame
	check(not paused and rewards.pending_levels == 0 and manager.selected.size() == 5, "Queue drains and perks persist")
	await cleanup()
	# Every static perk adds the defined modifiers once, independently.
	for id in [&"tactical_precision", &"combat_drills", &"codex_discipline", &"precision_drills", &"controlled_bursts", &"close_quarters_training", &"targeting_protocols", &"veteran_marksman", &"explosive_doctrine", &"battle_hardened", &"master_of_war"]:
		setup()
		var definition := perk(id)
		apply(id)
		for stat: StringName in definition.modifiers:
			check(is_equal_approx(stats.get_modifier(stat), float(definition.modifiers[stat])), "Exact static perk modifier")
		check(is_equal_approx(stats.get_crit_multiplier(), 1.5 + float(definition.modifiers.get(&"crit_damage", 0.0))), "Chapter crit damage bonus applies to multiplier")
		check(is_equal_approx(player.get_node("KnifeAttack").detection_shape.shape.radius, stats.scale_base(&"knife_range", 55.0)), "Knife collision range follows perk")
		if id == &"codex_discipline":
			check(is_equal_approx(player.get_node("Bolter").get_fire_interval(), 0.75 / 1.05), "Fire rate uses inverse interval")
			check(is_equal_approx(stats.scale_base(&"movement_speed", player.speed), 157.5), "Movement speed bonus")
		if id == &"battle_hardened":
			check(is_equal_approx(player.max_health, 57.5) and is_equal_approx(player.current_health, 57.5), "Max HP increases and heals gained HP")
			player.take_damage(10.0)
			check(is_equal_approx(player.current_health, 48.3), "Eight percent reduction")
		await cleanup()
	setup()
	apply(&"precision_drills")
	apply(&"targeting_protocols")
	apply(&"master_of_war")
	check(is_equal_approx(stats.get_crit_multiplier(), 1.95), "Chapter crit damage bonuses add to base 1.5")
	check(is_equal_approx(stats.resolve_damage(40.0, true), 78.0), "Stacked perk critical damage")
	var guaranteed := stats.roll_hit(40.0, true)
	check(guaranteed.critical and is_equal_approx(guaranteed.amount, 78.0), "Guaranteed crits include Chapter bonuses")
	await cleanup()
	setup()
	apply(&"combat_efficiency")
	for index in range(1, 6):
		var enemy := enemy_at(Vector2(1000 + index * 100, 0))
		enemy.take_damage(60.0, false, stats, &"knife")
		check(manager.efficiency_stacks == mini(index, 3), "Kill stack cap")
		check(is_equal_approx(stats.get_modifier(&"fire_rate"), 0.03 * mini(index, 3)), "Fire rate stack bonus")
		check(is_equal_approx(stats.get_modifier(&"movement_speed"), 0.03 * mini(index, 3)), "Movement stack bonus")
		manager._process(1.0)
	check(is_equal_approx(manager.efficiency_remaining, 2.0), "Kills refresh duration")
	manager.set_process(true)
	paused = true
	var remaining_before_pause := manager.efficiency_remaining
	await create_timer(0.05).timeout
	check(manager.efficiency_remaining == remaining_before_pause, "Temporary durations freeze during reward pause")
	paused = false
	manager.set_process(false)
	stats.add_modifier(&"movement_speed", 0.05)
	manager._process(2.1)
	check(manager.efficiency_stacks == 0 and is_zero_approx(stats.get_modifier(&"fire_rate")), "Temporary stacks expire")
	check(is_equal_approx(stats.get_modifier(&"movement_speed"), 0.05), "Expiry preserves permanent modifiers")
	await process_frame
	await cleanup()
	setup()
	apply(&"adaptive_warfare")
	var bolter_enemy := enemy_at(Vector2(1000, 0))
	var knife_enemy := enemy_at(Vector2(1200, 0))
	bolter_enemy.take_damage(30.0, false, stats, &"bolter")
	knife_enemy.take_damage(10.0, false, stats, &"knife")
	manager._process(19.9)
	check(is_zero_approx(stats.get_modifier(&"bolter_damage")), "Adaptive waits for full window")
	manager._process(0.2)
	check(is_equal_approx(stats.get_modifier(&"bolter_damage"), 0.15) and is_zero_approx(stats.get_modifier(&"knife_damage")), "Bolter dominant window")
	knife_enemy.take_damage(35.0, false, stats, &"knife")
	manager._process(20.0)
	check(is_zero_approx(stats.get_modifier(&"bolter_damage")) and is_equal_approx(stats.get_modifier(&"knife_damage"), 0.15), "Knife dominant replaces bonus")
	manager._process(20.0)
	check(is_zero_approx(stats.get_modifier(&"knife_damage")), "No combat expires adaptive bonus")
	await process_frame
	await cleanup()
	setup()
	var normal: UpgradeDefinition = rewards.definitions[0]
	normal.apply(stats)
	apply(&"codex_mastery")
	check(is_equal_approx(stats.get_modifier(&"bolter_damage"), 0.1), "Mastery is not retroactive")
	normal.apply(stats)
	check(is_equal_approx(stats.get_modifier(&"bolter_damage"), 0.22), "Future ten percent becomes twelve")
	check(normal.effect_text(1.2) == "+12%", "Mastery UI value")
	rewards.definitions[2].apply(stats)
	check(is_equal_approx(stats.get_modifier(&"crit_chance"), 0.015), "Crit chance remains exactly 1.5 points even with Mastery")
	rewards.definitions.back().apply(stats)
	check(stats.get_projectile_count() == 2, "Mastery preserves integer multishot")
	await cleanup()
	setup()
	apply(&"perfect_discipline")
	stats.add_modifier(&"projectile_count", 2.0)
	var bolts: Array[BoltProjectile] = []
	for volley in 4:
		var before := main.get_child_count()
		player.get_node("Bolter")._fire()
		for index in range(before, main.get_child_count()):
			var bolt := main.get_child(index) as BoltProjectile
			bolt.set_physics_process(false)
			bolt.monitoring = false
			bolts.append(bolt)
	for index in bolts.size():
		check(bolts[index].guaranteed_critical == ((index + 1) % 5 == 0), "Every fifth individual multishot projectile")
	var target := enemy_at(Vector2(2000, 0))
	bolts[4]._deal_damage(target, bolts[4].damage, bolts[4].guaranteed_critical)
	check(is_equal_approx(target.current_health, 12.5), "Guaranteed critical damage uses existing multiplier")
	await process_frame
	var red_numbers := 0
	for child in main.find_children("*", "Node2D", true, false):
		if child is FloatingDamageNumber and child.visible:
			check(child.is_critical and child.get_node("Label").modulate == Color.RED and is_equal_approx(child.damage_amount, 37.5), "Guaranteed crit displays red final damage")
			red_numbers += 1
	check(red_numbers == 1, "One guaranteed direct damage number")
	stats.crit_chance = 1.0
	check(stats.roll_hit(25.0).critical, "Random crit pathway remains functional")
	await cleanup()
	setup()
	apply(&"veteran_marksman")
	apply(&"explosive_doctrine")
	var primary := enemy_at(Vector2(1000, 0))
	var nearby := enemy_at(Vector2(1050, 0))
	var second := enemy_at(Vector2(2000, 0))
	player.get_node("Bolter")._fire()
	var penetrating := main.get_child(main.get_child_count() - 1) as BoltProjectile
	penetrating.set_physics_process(false)
	penetrating.monitoring = false
	penetrating.position = primary.position
	check(penetrating.penetration == 1, "Penetration configured on projectile")
	check(is_equal_approx(penetrating.splash_damage, 15.0) and is_equal_approx(penetrating.splash_radius, 80.5), "Explosive doctrine projectile stats")
	await physics_frame
	await physics_frame
	penetrating._on_body_entered(primary)
	check(is_equal_approx(primary.current_health, 25.0), "Direct target excluded from upgraded splash")
	check(is_equal_approx(nearby.current_health, 35.0), "Nearby upgraded splash damage")
	check(not penetrating.is_queued_for_deletion(), "Penetrating projectile survives first direct hit")
	penetrating._on_body_entered(primary)
	check(is_equal_approx(primary.current_health, 25.0), "Cannot directly hit same enemy twice")
	second.position = Vector2(1040, 0)
	penetrating.position = second.position
	penetrating._on_body_entered(second)
	check(is_equal_approx(second.current_health, 25.0) and penetrating.is_queued_for_deletion(), "One penetration permits exactly two direct targets")
	check(is_equal_approx(primary.current_health, 25.0), "Later penetration explosion still excludes prior direct targets")
	await create_timer(0.4).timeout
	await cleanup()
	print("PASS: %d Chapter perk checks" % checks)
	quit()
