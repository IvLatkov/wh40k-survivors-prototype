extends SceneTree

var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	assert(ok, message)

func _initialize() -> void:
	run.call_deferred()

func reference(subject: Enemy, grid: EnemySpatialGrid) -> Vector2:
	var candidates: Array[Enemy] = []
	grid.append_nearby_candidates(subject.global_position, candidates)
	var result := Vector2.ZERO
	for enemy in candidates:
		if enemy == subject or not is_instance_valid(enemy): continue
		var away := subject.global_position - enemy.global_position
		var squared := away.length_squared()
		if squared >= subject.separation_radius * subject.separation_radius: continue
		if squared <= 0.0001:
			result += Vector2.RIGHT if subject.get_instance_id() < enemy.get_instance_id() else Vector2.LEFT
			continue
		var distance := sqrt(squared)
		result += away / distance * (1.0 - distance / subject.separation_radius)
	return result.limit_length(1.0)

func run() -> void:
	seed(741)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var grid := EnemySpatialGrid.new()
	world.add_child(grid)
	grid.set_physics_process(false)
	for i in 200:
		var enemy := preload("res://scenes/enemies/enemy.tscn").instantiate() as Enemy
		enemy.position = Vector2(randf_range(-160, 160), randf_range(-160, 160)) if i > 1 else Vector2.ZERO
		world.add_child(enemy)
		enemy.set_physics_process(false)
		grid.register_enemy(enemy)
	grid._rebuild_grid()
	for enemy in grid._enemies:
		check(grid.calculate_separation(enemy) == reference(enemy, grid), "Separation retains exact summation and positions")
	# Remove between rebuilds: the former stale-reference case must stay safe.
	var dead: Enemy = grid._enemies.back()
	grid.unregister_enemy(dead)
	dead.free()
	for enemy in grid._enemies:
		check(grid.calculate_separation(enemy) == reference(enemy, grid), "Stale references are harmless")
	var pool := BloodBurstPool.new()
	world.add_child(pool)
	check(pool._idle.size() == 64, "Blood prewarm is bounded")
	for i in 200: pool.spawn(Vector2(i, 0))
	await process_frame
	await process_frame
	var active := 0
	for child in pool.get_children():
		if child.visible: active += 1
	check(active == 200, "Every death retains a visible blood effect, including overflow")
	await create_timer(0.5).timeout
	check(pool._idle.size() == 128, "Idle pool capped after simultaneous deaths")
	check(pool.get_child_count() == 128, "Overflow nodes cleaned up")
	for i in 200: pool.spawn(Vector2(i, 10))
	await process_frame
	await process_frame
	active = 0
	for child in pool.get_children():
		if child.visible: active += 1
	check(active == 200, "Reused particles replay every burst")
	await create_timer(0.5).timeout
	check(pool.get_child_count() == 128, "Repeated bursts do not grow idle memory")
	var number_pool := DamageNumberPool.new()
	number_pool.name = "DamageNumberPool"
	world.add_child(number_pool)
	for round_index in 3:
		for i in 150:
			var number := number_pool._idle.pop_back() as FloatingDamageNumber if not number_pool._idle.is_empty() else number_pool._create()
			number.configure(37.5 if i % 2 == 0 else 25.0, i % 2 == 0)
			number.position = Vector2(i, 10)
			number.pooled_idle = false
			number.start()
			check(number.visible and number.modulate.a == 1.0, "Number reuse resets visibility/fade")
			check(number.get_node("Label").modulate == (Color.RED if i % 2 == 0 else Color.WHITE), "Number reuse resets critical styling")
			number._process(0.15)
			check(is_equal_approx(number.position.y, -12.5) and number.modulate.a == 1.0, "Linear rise and fade delay preserved")
			number._process(0.075)
			check(is_equal_approx(number.modulate.a, 0.5), "Second-half linear fade preserved")
		await create_timer(0.5).timeout
		check(number_pool._idle.size() == 128 and number_pool.get_child_count() == 128, "Number pool caps idle nodes on repeated overflow")
	# Registration owns cleanup even when callers free enemies without an explicit unregister.
	var victim: Enemy = grid._enemies.back()
	victim.free()
	for bucket: Array in grid._cells.values():
		for candidate: Variant in bucket:
			check(is_instance_valid(candidate), "Freed enemies leave buckets promptly")
	world.queue_free()
	await process_frame
	await process_frame
	print("PASS: ", checks, " combat optimization checks")
	quit()
