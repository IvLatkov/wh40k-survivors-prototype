extends SceneTree

var checks: int = 0
var world: Node2D
var events: Array[Dictionary] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func spawn_enemy(at: Vector2) -> Enemy:
	var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	# Explicit combat fixture HP; production Squigs now start at 25.
	enemy.max_health = 50.0
	enemy.position = at
	world.add_child(enemy)
	enemy.damage_received.connect(func(amount: float, critical: bool) -> void:
		events.append({"amount": amount, "critical": critical, "enemy": enemy, "health": enemy.current_health, "position": enemy.global_position})
	)
	return enemy

func verify_numbers() -> void:
	var numbers: Array[FloatingDamageNumber] = []
	for child in world.get_children():
		if child is FloatingDamageNumber:
			numbers.append(child)
	check(numbers.size() == events.size(), "One number per applied damage event")
	for index in numbers.size():
		var number := numbers[index]
		var event := events[index]
		check(number.damage_amount == event.amount, "Visual receives exact reported HP delta")
		check(number.is_critical == event.critical, "Critical metadata preserved")
		check(absf(float(number.get_node("Label").text) - event.amount) <= 0.050001, "Displayed value rounds HP delta to at most one decimal")
		check(number.position.distance_to(event.position) < 90.0, "Number appears at damaged enemy")
		check(number.get_node("Label").modulate == (Color.RED if event.critical else Color.WHITE), "Critical styling")
	if numbers.size() >= 2 and events[0].enemy == events[1].enemy:
		check(numbers[0].position != numbers[1].position, "Direct and splash visuals separated")

func clear_world() -> void:
	for child in world.get_children():
		child.queue_free()
	await process_frame
	events.clear()

func projectile_case(critical: bool, enemy_count: int, perk_bonus: float = 0.0) -> void:
	var enemies: Array[Enemy] = [spawn_enemy(Vector2.ZERO)]
	for index in range(1, enemy_count):
		enemies.append(spawn_enemy(Vector2.RIGHT.rotated(TAU * index / enemy_count) * 45.0))
	var outside: Enemy = spawn_enemy(Vector2(300, 0)) if enemy_count > 1 else null
	var stats := CombatStats.new()
	stats.crit_chance = 1.0 if critical else 0.0
	stats.add_modifier(&"bolter_damage", 0.2)
	stats.add_modifier(&"crit_damage", perk_bonus)
	var bolt := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	bolt.combat_stats = stats
	bolt.damage = stats.scale_base(&"bolter_damage", bolt.damage)
	bolt.monitoring = false
	world.add_child(bolt)
	bolt.set_physics_process(false)
	await physics_frame
	await physics_frame
	bolt._on_body_entered(enemies[0])
	check(events.size() == enemy_count, "One damage event per enemy")
	var primary_hits := 0
	var damaged_enemies: Dictionary = {}
	for event in events:
		damaged_enemies[event.enemy.get_instance_id()] = true
		if event.enemy == enemies[0]:
			primary_hits += 1
	check(primary_hits == 1, "Primary enemy takes only direct damage")
	check(damaged_enemies.size() == enemy_count, "Each nearby enemy damaged exactly once")
	var expected_direct := 30.0 * (1.5 + perk_bonus) if critical else 30.0
	var expected_splash := 15.0 * (1.5 + perk_bonus) if critical else 15.0
	check(is_equal_approx(events[0].amount, expected_direct), "Final upgraded direct damage")
	for index in range(1, enemy_count):
		check(is_equal_approx(events[index].amount, expected_splash), "Final upgraded per-enemy splash damage")
	for index in enemies.size():
		var expected_health := 50.0 - (expected_direct if index == 0 else expected_splash)
		check(is_equal_approx(enemies[index].current_health, expected_health), "HP reduced exactly once per hit")
	if outside != null:
		check(outside.current_health == 50.0, "Outside enemy receives no damage")
	for event in events:
		check(event.critical == critical, "Same crit result is reported without reroll")
	bolt._on_body_entered(enemies[0])
	check(events.size() == enemy_count, "Repeated impact does not damage twice")
	await process_frame
	verify_numbers()
	# Let existing explosion coroutines finish before clearing their nodes.
	await create_timer(0.35).timeout
	await clear_world()


func independent_splash_case() -> void:
	var stats := CombatStats.new()
	stats.crit_chance = 0.5
	var primary := spawn_enemy(Vector2.ZERO)
	for index in 12:
		spawn_enemy(Vector2.RIGHT.rotated(TAU * index / 12.0) * 45.0)
	var bolt := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	bolt.combat_stats = stats
	bolt.damage = 20.0
	bolt.monitoring = false
	world.add_child(bolt)
	bolt.set_physics_process(false)
	await physics_frame
	await physics_frame
	# Predict only crit draws. No enemies die and the visual effects consume no RNG.
	seed(463)
	var expected_critical: Array[bool] = []
	for index in 13:
		expected_critical.append(randf() < 0.5)
	seed(463)
	bolt._on_body_entered(primary)
	check(events.size() == 13, "Exactly one direct and twelve splash hits")
	var splash_critical := 0
	var primary_hits := 0
	for index in events.size():
		var event := events[index]
		check(event.critical == expected_critical[index], "Each target consumes its own independent crit roll")
		var expected_amount := (20.0 if index == 0 else 10.0) * (1.5 if expected_critical[index] else 1.0)
		check(is_equal_approx(event.amount, expected_amount), "Independent roll uses fixed 1.5 multiplier")
		check(is_equal_approx(event.health, 50.0 - expected_amount), "Independent hit HP matches final damage")
		if event.enemy == primary:
			primary_hits += 1
		elif event.critical:
			splash_critical += 1
	check(primary_hits == 1, "Primary excluded from independent splash rolls")
	check(splash_critical > 0 and splash_critical < 12, "Same explosion includes both normal and critical splash")
	await process_frame
	verify_numbers()
	await create_timer(0.35).timeout
	await clear_world()

func run() -> void:
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var fixed_stats := CombatStats.new()
	for normal_amount in [20.0, 25.0, 40.0]:
		check(fixed_stats.resolve_damage(normal_amount, true) == normal_amount * 1.5, "Requested critical damage examples")
		var forced := fixed_stats.roll_hit(normal_amount, true)
		check(forced.critical and forced.amount == normal_amount * 1.5, "Guaranteed crit uses identical fixed multiplier")
	await independent_splash_case()
	for enemy_count in [1, 2, 5]:
		await projectile_case(false, enemy_count)
		await projectile_case(true, enemy_count)
		await projectile_case(true, enemy_count, 0.2)
	for critical in [false, true]:
		var enemy := spawn_enemy(Vector2(500, 0))
		var knife := preload("res://scenes/weapons/knife.tscn").instantiate() as KnifeAttack
		world.add_child(knife)
		knife.set_physics_process(false)
		knife.combat_stats.crit_chance = 1.0 if critical else 0.0
		knife.combat_stats.add_modifier(&"knife_damage", 0.1)
		knife.combat_stats.add_modifier(&"crit_damage", 0.2)
		knife.position = enemy.position - Vector2(40, 0)
		knife._on_body_entered(enemy)
		knife._attack()
		var expected := 65.45 if critical else 38.5
		check(events.size() == 1 and is_equal_approx(events[0].amount, expected), "Knife normal/crit final damage")
		check(is_equal_approx(enemy.current_health, 50.0 - expected), "Knife damage applied once")
		check(events[0].critical == critical, "Knife crit metadata")
		await process_frame
		verify_numbers()
		await clear_world()
	# Preserve lethal-direct behavior: dead target receives no subsequent splash.
	var enemy := spawn_enemy(Vector2.ZERO)
	enemy.take_damage(60.125, true)
	enemy.take_damage(12.0)
	check(events.size() == 1 and enemy.current_health == -10.125, "Existing overkill and dead-target rejection preserved")
	await process_frame
	verify_numbers()
	check(not is_instance_valid(enemy), "Lethal number survives enemy deletion")
	await create_timer(1.0).timeout
	var remaining := 0
	for child in world.get_children():
		if child is FloatingDamageNumber:
			remaining += 1
	check(remaining == 0, "Numbers clean themselves up")
	print("PASS: %d damage-number checks" % checks)
	world.queue_free()
	await process_frame
	quit()
