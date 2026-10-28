extends SceneTree

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
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	var system: UpgradeSystem = main.get_node("UpgradeSystem")
	var menu = main.get_node("UpgradeMenu")
	var stats := player.combat_stats
	var knife: KnifeAttack = player.get_node("KnifeAttack")
	var bolter = player.get_node("Bolter")
	player.add_xp(player.get_xp_required())
	check(paused and menu.visible, "Level-up pauses and opens menu")
	check(system.offered.size() == 3, "Exactly three choices")
	var ids: Dictionary = {}
	for definition in system.offered:
		ids[definition.id] = true
	check(ids.size() == 3, "Unique choices")
	check(menu.can_process() and not player.can_process(), "Only UI processes while paused")
	var position_before := player.position
	var timer_before: float = bolter.fire_timer.time_left
	await create_timer(0.05).timeout
	check(player.position == position_before and bolter.fire_timer.time_left == timer_before, "Movement and weapon timers frozen")
	var chosen: UpgradeDefinition = system.offered[0]
	var old_value := stats.get_modifier(chosen.stat)
	menu.choices_container.get_child(0).pressed.emit()
	check(is_equal_approx(stats.get_modifier(chosen.stat), old_value + chosen.amount), "Selection immediately applies")
	check(not paused and not menu.visible, "Selection resumes and hides menu")
	menu._select(chosen.id)
	system.select_upgrade(chosen.id)
	check(system.levels[chosen.id] == 1, "Duplicate selection rejected")
	stats.modifiers.clear()
	system.levels.clear()
	for definition in system.definitions:
		if definition.id == &"multishot":
			continue
		definition.apply(stats)
		definition.apply(stats)
	check(is_equal_approx(stats.scale_base(&"bolter_damage", 25.0), 30.0), "Damage adds 10% of base per selection")
	check(is_equal_approx(bolter.get_splash_damage(), 15.0), "Splash scaling")
	check(is_equal_approx(stats.scale_base(&"projectile_speed", 600.0), 720.0), "Projectile speed scaling")
	check(is_equal_approx(stats.get_modifier(&"crit_chance"), 0.03), "Crit chance adds 0.015 per selection")
	check(is_equal_approx(stats.get_crit_multiplier(), 1.5), "Crit multiplier remains fixed")
	check(is_equal_approx(stats.resolve_damage(100.0, true), 150.0), "Critical damage only on critical hits")
	check(stats.resolve_damage(100.0, false) == 100.0 and CombatStats.new().roll_damage(100.0) == 100.0, "Normal damage unchanged at zero chance")
	check(is_equal_approx(stats.scale_base(&"knife_damage", knife.melee_damage), 42.0), "Knife damage scaling")
	check(is_equal_approx(knife.detection_shape.shape.radius, 66.0), "Knife collision range scaling")
	knife._spawn_slash(Vector2.RIGHT, Vector2.ZERO)
	var slash := main.get_child(main.get_child_count() - 1) as KnifeSlashEffect
	check(slash != null and slash.scale.is_equal_approx(Vector2(1.2, 1.2)), "Slash scales with reach")
	var multishot: UpgradeDefinition = system.definitions.back()
	check(stats.get_projectile_count() == 1, "Starting projectile count")
	for count in range(1, 6):
		check(stats.get_projectile_count() == count, "Count increments by one")
		var angles: Dictionary = {}
		for index in count:
			var angle := stats.get_projectile_angle(index)
			angles[angle] = true
			check(absf(angle) <= deg_to_rad(6.01), "Controlled spread")
		check(angles.size() == count, "Distinct trajectories")
		check(is_zero_approx(stats.get_projectile_angle(0) + stats.get_projectile_angle(count - 1)), "Symmetric spread")
		if count < 5:
			multishot.apply(stats)
	check(not multishot.is_available(stats, 4), "Cap availability")
	check(not system.available_upgrades().has(multishot), "Capped upgrade removed")
	for iteration in 20:
		system.queue_level()
		check(system.offered.size() == 3 and not system.offered.has(multishot), "Three choices after cap")
		system.select_upgrade(system.offered[0].id)
	check(stats.get_projectile_count() == 5, "Count never exceeds five")
	var before_children := main.get_child_count()
	bolter._fire()
	check(main.get_child_count() == before_children + 5, "Bolter spawns five actual projectiles")
	var positions: Dictionary = {}
	for index in range(before_children, main.get_child_count()):
		var bolt := main.get_child(index) as BoltProjectile
		positions[bolt.position] = true
		check(is_equal_approx(bolt.damage, stats.scale_base(&"bolter_damage", 25.0)), "Actual projectile damage")
		check(is_equal_approx(bolt.projectile_speed, stats.scale_base(&"projectile_speed", 600.0)), "Actual projectile speed")
	check(positions.size() == 5, "Distinct spawn positions")
	# Isolate reward-queue timing from randomly selected Purity Seals bonuses.
	stats.modifiers.erase(&"xp_gain")
	player.add_xp(player.get_xp_required() + player.xp_progression.get_requirement(player.level + 1))
	check(system.pending_levels == 2 and paused, "Multiple levels queue")
	system.select_upgrade(system.offered[0].id)
	check(paused and system.pending_levels == 1, "Remain paused between queued levels")
	await process_frame
	check(system.offered.size() == 3 and menu.visible, "Next queued menu")
	system.select_upgrade(system.offered[0].id)
	check(not paused and system.pending_levels == 0, "Resume after final queued choice")
	print("PASS: %d upgrade checks" % checks)
	main.queue_free()
	await process_frame
	quit()

