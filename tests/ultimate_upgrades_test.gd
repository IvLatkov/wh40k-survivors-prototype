extends SceneTree

var checks: int = 0
var main: Node2D
var player: Player
var system: UpgradeSystem
var bolter: Node2D
var knife: KnifeAttack
var grid: EnemySpatialGrid

class AlternatingStats extends CombatStats:
	var rolls: int = 0
	func roll_hit(base_damage: float, _guaranteed: bool = false) -> CombatStats.DamageRoll:
		rolls += 1
		return DamageRoll.new(base_damage * (1.5 if rolls % 2 == 0 else 1.0), rolls % 2 == 0)

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

func ultimate(id: StringName) -> UltimateDefinition:
	for value in system.ultimate_definitions:
		if value.id == id:
			return value
	return null

func max_upgrade(id: StringName) -> void:
	var value := definition(id)
	while value.is_available(player.combat_stats, int(system.levels.get(id, 0))):
		value.apply(player.combat_stats)
		system.levels[id] = int(system.levels.get(id, 0)) + 1

func choose(id: StringName) -> void:
	system.queue_level()
	check(system.offered_ultimates.has(ultimate(id)), "Unlocked Ultimate is prioritized in offered choices")
	var buttons: Array = main.get_node("UpgradeMenu").choices_container.get_children()
	check(buttons.size() == 3, "Three mixed choices when enough eligible choices exist")
	var ids: Dictionary = {}
	for value in system.offered:
		ids[value.id] = true
	for value in system.offered_ultimates:
		ids[value.id] = true
	check(ids.size() == buttons.size(), "Mixed choice IDs are unique")
	check(buttons[0].text.begins_with("ULTIMATE |"), "Ultimate card is clearly labeled")
	var weapon_slots := system.get_selected_weapon_ids().size()
	var generic_slots := system.get_selected_generic_ids().size()
	var levels := system.levels.duplicate()
	system.select_upgrade(id)
	check(system.active_ultimates.has(id) and not paused, "Ultimate selection persists and resumes gameplay")
	check(system.levels == levels, "Ultimate does not add normal levels")
	check(system.get_selected_weapon_ids().size() == weapon_slots and system.get_selected_generic_ids().size() == generic_slots, "Ultimate adds no committed slots")
	check(not system.get_eligible_ultimates().has(ultimate(id)), "Selected Ultimate permanently excluded")
	system.select_upgrade(id)
	check(system.pending_levels == 0, "Repeated selection cannot consume another reward")

func enemy_at(pos: Vector2) -> Enemy:
	var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	enemy.max_health = 100000.0
	enemy.position = pos
	main.add_child(enemy)
	enemy.set_physics_process(false)
	grid.register_enemy(enemy)
	return enemy

func projectiles() -> Array[BoltProjectile]:
	var result: Array[BoltProjectile] = []
	for child in main.get_children():
		if child is BoltProjectile and not child.is_queued_for_deletion():
			result.append(child)
	return result

func clear_projectiles() -> void:
	for bolt in projectiles():
		bolt.free()

func run() -> void:
	root.size = Vector2i(1152, 648)
	main = preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	system = main.get_node("UpgradeSystem")
	bolter = player.get_node("Bolter")
	knife = player.get_node("KnifeAttack")
	grid = main.get_node("EnemySpawner/EnemySpatialGrid")
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	bolter.set_process(false)
	bolter.fire_timer.stop()
	knife.set_physics_process(false)
	check(system.get_eligible_ultimates().is_empty(), "All Ultimates start locked")
	max_upgrade(&"bolter_damage")
	check(not system.can_select_ultimate(ultimate(&"devastator_shells")), "Devastator requires both prerequisites")
	max_upgrade(&"fire_rate")
	check(system.can_select_ultimate(ultimate(&"devastator_shells")), "Devastator unlocks at both max levels")
	choose(&"devastator_shells")
	max_upgrade(&"multishot")
	check(system.levels[&"multishot"] == 4 and player.combat_stats.get_projectile_count() == 5, "Projectile Count actual max is level four")
	check(not system.can_select_ultimate(ultimate(&"forking_rounds")), "Forking requires speed as well as count")
	max_upgrade(&"projectile_speed")
	check(system.can_select_ultimate(ultimate(&"forking_rounds")), "Forking accepts actual Projectile Count cap")
	choose(&"forking_rounds")
	check(system.get_selected_weapon_ids().size() == 4, "Two Bolter Ultimates coexist with four normal types")
	# A custom starting count can reach the functional cap even earlier.
	system.levels[&"multishot"] = 1
	check(system.can_select_ultimate(ultimate(&"whirlwind_assault")) == false, "Unrelated Ultimate stays locked")
	system.active_ultimates.erase(&"forking_rounds")
	check(system.can_select_ultimate(ultimate(&"forking_rounds")), "Functional cap accepted before resource level cap")
	system.levels[&"multishot"] = 4
	system.active_ultimates[&"forking_rounds"] = true
	root.warp_mouse(Vector2i(900, 320))
	bolter.global_position = Vector2(100, 100)
	for volley in range(1, 7):
		bolter._fire()
		var bolts := projectiles()
		check(bolts.size() == 5, "Multishot count unchanged")
		var empowered := 0
		for bolt in bolts:
			check(bolt.can_fork and bolt.spatial_grid == grid, "Normal and empowered shots enable local forking")
			if is_equal_approx(bolt.damage, bolter.get_damage() * 1.75):
				empowered += 1
				check(is_equal_approx(bolt.splash_damage, bolter.get_damage() * 0.5 * 1.75), "Empowered splash damage increases seventy five percent")
				check(is_equal_approx(bolt.splash_radius, 105.0), "Empowered splash radius increases fifty percent")
				check(bolt.get_node("Visual").scale.is_equal_approx(Vector2.ONE * 0.75 * 1.6), "Empowered visual is larger")
				check(bolt._direction.is_equal_approx(bolter.muzzle.global_position.direction_to(bolter.get_global_mouse_position())), "Empowered primary travels centrally")
		check(empowered == (1 if volley % 3 == 0 else 0), "Exactly one empowered projectile every third volley")
		clear_projectiles()
	# Use an isolated Knife build: real normal slot limits are unchanged.
	system.levels.clear()
	max_upgrade(&"knife_damage")
	check(not system.can_select_ultimate(ultimate(&"whirlwind_assault")), "Whirlwind requires range as well as damage")
	max_upgrade(&"knife_range")
	check(system.can_select_ultimate(ultimate(&"whirlwind_assault")), "Whirlwind unlocks at both max levels")
	var front := enemy_at(player.global_position + Vector2(30, 0))
	var back := enemy_at(player.global_position - Vector2(30, 0))
	var outside := enemy_at(player.global_position + Vector2(200, 0))
	knife._nearby_enemies = {front.get_instance_id(): front, back.get_instance_id(): back, outside.get_instance_id(): outside}
	check(knife._get_attack_targets(Vector2.RIGHT, knife.current_knife_radius) == [front], "Normal Knife excludes rear target")
	var damage := knife.get_damage()
	var cooldown := knife.get_attack_cooldown()
	var radius := knife.current_knife_radius
	choose(&"whirlwind_assault")
	check(knife.get_damage() == damage and knife.get_attack_cooldown() == cooldown and knife.current_knife_radius == radius, "Whirlwind preserves damage rate and radius")
	player.combat_stats.crit_chance = 1.0
	knife.cooldown_timer.stop()
	knife._attack()
	check(is_equal_approx(front.current_health, front.max_health - damage * 1.5) and is_equal_approx(back.current_health, back.max_health - damage * 1.5), "Front and rear each receive exactly one critical Knife hit")
	check(outside.current_health == outside.max_health, "Whirlwind respects current radius")
	player.combat_stats.add_modifier(&"knife_range", 0.2)
	check(knife.current_knife_radius > radius and knife.detection_shape.shape.radius == knife.current_knife_radius, "Range still updates 360 degree reach")
	var panel = main.get_node("CharacterInfoPanel")
	panel.open_panel()
	check(panel.content.get_node("Ultimates/Owned").text.contains("Devastator Shells") and panel.content.get_node("Ultimates/Owned").text.contains("Forking Rounds") and panel.content.get_node("Ultimates/Owned").text.contains("Whirlwind Assault"), "Character Info lists all selected Ultimates separately")
	if "--capture-ui" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("survivor_ultimates.png"))
	panel.close_panel()
	# Forks use pre-crit source damage, independent crit rolls, no splash or recursion.
	var direct := enemy_at(Vector2(2000, 0))
	var target_a := enemy_at(Vector2(2040, 0))
	var target_b := enemy_at(Vector2(1960, 0))
	grid._rebuild_grid()
	var stats := AlternatingStats.new()
	var source := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	source.combat_stats = stats
	source.can_fork = true
	source.spatial_grid = grid
	source.damage = 100.0 * 1.75
	source.projectile_speed = 900.0
	source.position = direct.position
	source.monitoring = false
	main.add_child(source)
	source.set_physics_process(false)
	source.set_deferred("monitoring", false)
	await physics_frame
	await physics_frame
	main.child_entered_tree.connect(func(node: Node) -> void:
		if node is BoltProjectile:
			node.set_physics_process(false)
			node.set_deferred("monitoring", false)
	)
	source._explode(direct)
	await process_frame
	await process_frame
	var forks := projectiles()
	forks.erase(source)
	check(forks.size() == 2, "Impact creates two forks for distinct nearby targets")
	check(forks[0]._direction != forks[1]._direction, "Forks aim at different alternatives")
	check(is_equal_approx(direct.max_health - direct.current_health, source.damage), "Direct target receives no own splash")
	var rolls_before := stats.rolls
	var hp_a := target_a.current_health
	var hp_b := target_b.current_health
	for index in 2:
		var fork := forks[index]
		fork.set_physics_process(false)
		check(not fork.can_fork and fork.splash_damage == 0.0 and fork.splash_radius == 0.0, "Fork has neither recursion nor splash")
		check(fork.damage == 87.5 and fork.projectile_speed == 900.0 and not fork.guaranteed_critical, "Fork snapshots half pre-crit damage and current speed without inheriting crit")
		check(fork._direct_hit_ids.has(direct.get_instance_id()), "Fork ignores source target collision")
		fork._explode(target_a if index == 0 else target_b)
	check(stats.rolls == rolls_before + 2, "Forks make exactly two independent direct crit rolls")
	var lost_a := hp_a - target_a.current_health
	var lost_b := hp_b - target_b.current_health
	check((is_equal_approx(lost_a, 87.5) and is_equal_approx(lost_b, 131.25)) or (is_equal_approx(lost_b, 87.5) and is_equal_approx(lost_a, 131.25)), "Independent fork crit results use existing multiplier")
	await process_frame
	check(projectiles().size() == 3, "Fork impacts never spawn grandchildren")
	clear_projectiles()
	# No local alternatives means no fork objects.
	var lonely := enemy_at(Vector2(5000, 0))
	grid._rebuild_grid()
	var lone_source := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	lone_source.spatial_grid = grid
	lone_source.position = lonely.position
	main.add_child(lone_source)
	lone_source._spawn_forks(lonely)
	await process_frame
	check(projectiles().size() == 1, "No target produces no forks")
	clear_projectiles()
	var single_target := enemy_at(lonely.position + Vector2(100, 0))
	grid._rebuild_grid()
	var one_source := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	one_source.spatial_grid = grid
	one_source.position = lonely.position
	main.add_child(one_source)
	one_source._spawn_forks(lonely)
	await process_frame
	await process_frame
	var single_forks := projectiles()
	single_forks.erase(one_source)
	check(single_forks.size() == 1 and single_forks[0]._direction == lonely.position.direction_to(single_target.position), "One valid target produces one aimed fork")
	for bolt in single_forks:
		bolt._physics_process(bolt.lifetime + 0.1)
	await process_frame
	check(projectiles().size() == 1, "Fork expires through normal lifetime cleanup")
	clear_projectiles()
	# Local query stays bounded with many distant enemies.
	for index in 300:
		enemy_at(Vector2(10000 + index * 20, 10000))
	grid._rebuild_grid()
	var candidates: Array[Enemy] = []
	grid.append_candidates_in_radius(direct.position, 300.0, candidates)
	check(candidates.size() == 3, "Hundreds of distant enemies do not enter local fork query")
	var started := Time.get_ticks_usec()
	for _index in 1000:
		grid.append_candidates_in_radius(direct.position, 300.0, candidates)
	print("1000 local fork queries with 300 distant enemies: %.2f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	await create_timer(0.4).timeout
	main.queue_free()
	await process_frame
	var fresh := preload("res://scenes/main.tscn").instantiate()
	root.add_child(fresh)
	current_scene = fresh
	check(fresh.get_node("UpgradeSystem").active_ultimates.is_empty() and not fresh.get_node("Player/Bolter").devastator_active and not fresh.get_node("Player/Bolter").forking_active and not fresh.get_node("Player/KnifeAttack").whirlwind_active, "New run resets Ultimate state and weapon effects")
	fresh.get_node("CharacterInfoPanel").open_panel()
	check(fresh.get_node("CharacterInfoPanel").content.get_node("Ultimates/Owned").text == "None", "Fresh Character Info has empty Ultimate section")
	fresh.get_node("CharacterInfoPanel").close_panel()
	# Exercise actual physics collision callbacks without freezing spawned forks.
	main = fresh
	grid = fresh.get_node("EnemySpawner/EnemySpatialGrid")
	fresh.get_node("EnemySpawner").set_process(false)
	fresh.get_node("Player").set_physics_process(false)
	fresh.get_node("Player/Bolter/FireTimer").stop()
	fresh.get_node("Player/KnifeAttack").set_physics_process(false)
	var impact_target := enemy_at(Vector2(6000, 0))
	var fork_target_a := enemy_at(Vector2(6050, 0))
	var fork_target_b := enemy_at(Vector2(5950, 0))
	grid._rebuild_grid()
	var spawned: Array[BoltProjectile] = []
	fresh.child_entered_tree.connect(func(node: Node) -> void:
		if node is BoltProjectile:
			spawned.append(node)
	)
	var collision_stats := CombatStats.new()
	collision_stats.crit_chance = 1.0
	var impact := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	impact.damage *= 1.75
	impact.splash_radius *= 1.5
	impact.position = impact_target.position
	impact.combat_stats = collision_stats
	impact.can_fork = true
	impact.spatial_grid = grid
	fresh.add_child(impact)
	await create_timer(0.2).timeout
	check(spawned.size() == 3, "Real physics impact creates exactly two nonrecursive forks")
	check(is_equal_approx(impact_target.max_health - impact_target.current_health, 25.0 * 1.75 * 1.5), "Real empowered critical direct hit excludes own splash and fork collisions")
	check(fork_target_a.current_health < fork_target_a.max_health and fork_target_b.current_health < fork_target_b.max_health, "Real forks travel into nearby targets")
	var red_numbers := 0
	for child in fresh.get_children():
		if child is FloatingDamageNumber:
			check(child.is_critical and child.get_node("Label").modulate == Color.RED, "Ultimate crit damage numbers stay red")
			red_numbers += 1
	check(red_numbers >= 3, "Empowered shell and forks generate critical feedback")
	await create_timer(0.3).timeout
	fresh.queue_free()
	await process_frame
	print("PASS: %d Ultimate checks" % checks)
	quit()
