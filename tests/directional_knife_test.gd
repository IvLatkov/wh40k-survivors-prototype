extends SceneTree

var checks: int = 0
var main: Node2D
var player: Player
var knife: KnifeAttack
var hits: Array[Dictionary] = []

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
	knife = player.get_node("KnifeAttack")
	player.set_physics_process(false)
	knife.set_physics_process(false)
	main.get_node("EnemySpawner").set_process(false)
	player.get_node("Bolter/FireTimer").stop()
	hits.clear()

func spawn_enemy(at: Vector2) -> Enemy:
	var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
	# Explicit combat fixture HP; production Squigs now start at 25.
	enemy.max_health = 50.0
	enemy.position = at
	main.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.damage_received.connect(func(amount: float, critical: bool) -> void:
		hits.append({"enemy": enemy, "amount": amount, "critical": critical})
	)
	return enemy

func cleanup() -> void:
	main.queue_free()
	await process_frame

func verify_visual(direction: Vector2, radius_scale: float = 1.0) -> void:
	var slashes := 0
	for child in main.get_children():
		if child is KnifeSlashEffect:
			slashes += 1
			check(Vector2.RIGHT.rotated(child.rotation).is_equal_approx(direction), "Slash faces the player direction")
			check((child.global_position - player.global_position).dot(direction) > 0.0, "Slash appears in front")
			check(child.scale.is_equal_approx(Vector2.ONE * radius_scale), "Slash grows with range")
	check(slashes == 1, "One visual per multi-target swing")

func run() -> void:
	for facing_right in [true, false]:
		for enemy_right in [true, false]:
			setup()
			player.facing_right = facing_right
			var enemy := spawn_enemy(Vector2(40.0 if enemy_right else -40.0, 0.0))
			await physics_frame
			await physics_frame
			knife._physics_process(0.016)
			var should_hit: bool = facing_right == enemy_right
			check(enemy.current_health == (15.0 if should_hit else 50.0), "Left/right 40px target respects facing")
			check(hits.size() == (1 if should_hit else 0), "Only valid side emits damage")
			check(knife.cooldown_timer.is_stopped() != should_hit, "Behind-only enemies do not consume cooldown")
			if should_hit:
				verify_visual(Vector2.RIGHT if facing_right else Vector2.LEFT)
			await cleanup()
	for facing_right in [true, false]:
		setup()
		player.facing_right = facing_right
		var direction := Vector2.RIGHT if facing_right else Vector2.LEFT
		var front: Array[Enemy] = []
		for offset in [Vector2(40, 0), Vector2(30, 30), Vector2(30, -30), Vector2(10, 50), Vector2(10, -50), Vector2(55, 0), Vector2(0, 50), Vector2(0, -50)]:
			front.append(spawn_enemy(Vector2(offset.x * direction.x, offset.y)))
		var excluded: Array[Enemy] = []
		for offset in [Vector2(-40, 0), Vector2(-30, 30), Vector2(-30, -30), Vector2(55.1, 0), Vector2(40, 40), Vector2(100, 0)]:
			excluded.append(spawn_enemy(Vector2(offset.x * direction.x, offset.y)))
		await physics_frame
		await physics_frame
		check(knife._nearby_enemies.has(excluded[3].get_instance_id()), "Broad detection includes edge-overlapping outside target")
		knife._physics_process(0.016)
		check(hits.size() == 8, "All six front targets and both center-line targets hit")
		for enemy in front:
			check(enemy.current_health == 15.0, "Front, diagonal, and boundary target damaged once")
		for enemy in excluded:
			check(enemy.current_health == 50.0, "Behind and out-of-radius targets unaffected")
		knife._physics_process(0.016)
		check(hits.size() == 8, "Cooldown prevents repeated attack")
		check(is_equal_approx(knife.melee_cooldown, 0.8) and is_equal_approx(knife.melee_damage, 35.0), "Damage and cooldown unchanged")
		verify_visual(direction)
		await cleanup()
	for facing_right in [true, false]:
		setup()
		player.facing_right = facing_right
		var sign_x := 1.0 if facing_right else -1.0
		var targets: Array[Enemy] = [spawn_enemy(Vector2(60.5 * sign_x, 0)), spawn_enemy(Vector2(60.6 * sign_x, 0)), spawn_enemy(Vector2(-60 * sign_x, 0))]
		player.combat_stats.add_modifier(&"knife_range", 0.1)
		await physics_frame
		await physics_frame
		check(is_equal_approx(knife.detection_shape.shape.radius, 60.5), "Range upgrade expands detection to 60.5")
		knife._physics_process(0.016)
		check(targets[0].current_health == 15.0 and targets[1].current_health == 50.0 and targets[2].current_health == 50.0, "Upgraded semicircle preserves direction and exact radius")
		verify_visual(Vector2(sign_x, 0), 1.1)
		await cleanup()
	setup()
	player.combat_stats.crit_chance = 0.5
	for index in 12:
		spawn_enemy(Vector2(25.0, -25.0 + index * 4.0))
	await physics_frame
	await physics_frame
	seed(463)
	knife._physics_process(0.016)
	check(hits.size() == 12, "Every valid target gets an independent hit")
	var critical_count := 0
	for hit in hits:
		if hit.critical:
			critical_count += 1
		check(is_equal_approx(hit.amount, 52.5 if hit.critical else 35.0), "Normal 35 and base critical 52.5 damage preserved")
		check(is_equal_approx(hit.enemy.current_health, 50.0 - hit.amount), "HP removed equals reported damage")
	check(critical_count > 0 and critical_count < 12, "Single swing independently rolls normal and critical hits")
	await process_frame
	var number_count := 0
	for child in main.get_children():
		if child is FloatingDamageNumber:
			number_count += 1
			check(child.get_node("Label").modulate == (Color.RED if child.is_critical else Color.WHITE), "Damage number color preserved")
			check(is_equal_approx(child.damage_amount, 52.5 if child.is_critical else 35.0), "Damage number uses actual final damage")
	check(number_count == 12, "One number per enemy")
	await cleanup()
	print("PASS: %d directional knife checks" % checks)
	quit()
