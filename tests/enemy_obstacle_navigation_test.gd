extends SceneTree

const CHUNK := preload("res://scenes/systems/terrain_chunk.tscn")
const TYPES: Array[PackedScene] = [preload("res://scenes/enemies/enemy.tscn"), preload("res://scenes/enemies/ork_boy.tscn"), preload("res://scenes/enemies/warboss.tscn")]
var checks: int = 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)


func _initialize() -> void:
	run.call_deferred()


func obstacle(at: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = at
	body.collision_layer = TerrainObstacles.COLLISION_LAYER
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	return body


func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var wall := obstacle(Vector2.ZERO, Vector2(240, 200))
	await physics_frame
	await process_frame
	var space := world.get_world_2d().direct_space_state
	for radius in [13.0, 18.0, 32.0]:
		var resolved := TerrainObstacles.find_spawn_position(space, Vector2.ZERO, radius, Vector2(-500, 0), 180, Rect2())
		check(resolved != Vector2.INF, "Blocked spawn has a bounded safe alternative for every enemy radius")
		var circle := CircleShape2D.new()
		circle.radius = radius
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = circle
		query.transform.origin = resolved
		query.collision_mask = TerrainObstacles.COLLISION_LAYER
		check(space.intersect_shape(query, 1).is_empty() and resolved.distance_to(Vector2(-500, 0)) >= 180, "Resolved spawn clears the whole body and respects player distance")
		check(TerrainObstacles.find_spawn_position(space, Vector2(500, 0), radius, Vector2(-500, 0), 180, Rect2()) == Vector2(500, 0), "Already safe spawn position is unchanged")
	seed(571)
	var expected_random := randf()
	seed(571)
	TerrainObstacles.find_spawn_position(space, Vector2.ZERO, 32, Vector2(-500, 0), 180, Rect2())
	check(randf() == expected_random, "Spawn search consumes no gameplay RNG")
	wall.free()
	var sealed := obstacle(Vector2.ZERO, Vector2.ONE * 2000)
	await physics_frame
	await process_frame
	check(TerrainObstacles.find_spawn_position(space, Vector2.ZERO, 32, Vector2(-1200, 0), 180, Rect2()) == Vector2.INF, "Fully blocked area returns failure instead of an overlapping spawn")
	sealed.free()
	# Use the real generated sprite/collider pairs, not approximations of their art.
	var props: Dictionary[String, Sprite2D] = {}
	for index in 576:
		var coordinate := Vector2i(index % 24 - 12, floori(float(index) / 24.0) - 12)
		var chunk := CHUNK.instantiate() as TerrainChunk
		chunk.configure(coordinate, 1024)
		root.add_child(chunk)
		for prop: Sprite2D in chunk.large_props.get_children():
			if not props.has(String(prop.name)):
				props[String(prop.name)] = prop.duplicate() as Sprite2D
		chunk.free()
		if props.size() == 8:
			break
	check(props.size() == 8, "All three tree trunks, four ruins and tank are tested")
	var actors: Array[Enemy] = []
	var goals: Array[Node2D] = []
	var completed: Array[bool] = []
	var lane := 0
	for prop_name: String in props:
		for type in TYPES:
			var prop := props[prop_name].duplicate() as Sprite2D
			world.add_child(prop)
			prop.position = Vector2(0, lane * 1200)
			var collision := prop.get_node("Obstacle/CollisionShape2D") as CollisionShape2D
			var bounds: Rect2 = collision.global_transform * collision.shape.get_rect()
			var goal := Node2D.new()
			goal.position = Vector2(bounds.end.x + 180, bounds.get_center().y)
			world.add_child(goal)
			var actor := type.instantiate() as Enemy
			actor.position = Vector2(bounds.position.x - 180, bounds.get_center().y)
			actor.set_target(goal)
			world.add_child(actor)
			if actor is Warboss:
				# Isolate chase steering; dedicated Warboss tests retain real attacks.
				(actor as Warboss).gun_timer.start(100)
				(actor as Warboss).claw_timer.start(100)
			actors.append(actor)
			goals.append(goal)
			completed.append(false)
			lane += 1
	for prop in props.values():
		prop.free()
	Engine.time_scale = 4.0
	for _frame in 750:
		await physics_frame
		for index in actors.size():
			var actor := actors[index]
			check(actor.velocity.length() <= actor._individual_movement_speed + 0.01, "Steering never increases configured movement speed")
			if actor.global_position.distance_to(goals[index].global_position) < 85.0:
				completed[index] = true
				actor.set_physics_process(false)
		if completed.all(func(done: bool) -> bool: return done):
			break
	Engine.time_scale = 1.0
	for index in completed.size():
		check(completed[index], "Enemy type %d traverses prop lane %d and reaches the target side" % [index % 3, index / 3])
	var cluster_a := obstacle(Vector2(5000, -5100), Vector2(160, 160))
	var cluster_b := obstacle(Vector2(5000, -4900), Vector2(160, 160))
	var cluster_target := Node2D.new()
	cluster_target.position = Vector2(5300, -5000)
	world.add_child(cluster_target)
	var cluster_actors: Array[Enemy] = []
	for type in TYPES:
		var actor := type.instantiate() as Enemy
		actor.position = Vector2(4700, -5000)
		actor.set_target(cluster_target)
		world.add_child(actor)
		if actor is Warboss:
			(actor as Warboss).gun_timer.start(100)
			(actor as Warboss).claw_timer.start(100)
		cluster_actors.append(actor)
	Engine.time_scale = 4
	for _frame in 750:
		await physics_frame
		var arrived := 0
		for actor in cluster_actors:
			if actor.position.distance_to(cluster_target.position) < 85:
				actor.set_physics_process(false)
				arrived += 1
		if arrived == 3:
			break
	Engine.time_scale = 1
	for actor in cluster_actors:
		check(actor.position.distance_to(cluster_target.position) < 85, "Narrow-gap cluster has a safe outer detour for each enemy type")
	cluster_a.free()
	cluster_b.free()
	var temporary := obstacle(Vector2(8000, 0), Vector2(160, 160))
	var probe_actor := TYPES[0].instantiate() as Enemy
	world.add_child(probe_actor)
	probe_actor.set_physics_process(false)
	probe_actor.position = Vector2(7880, 0)
	await physics_frame
	await process_frame
	probe_actor._obstacle_probe_remaining = 0
	probe_actor._steer_around_obstacles(Vector2(8300, 0), Vector2.RIGHT, 0.2)
	check(not probe_actor._obstacle_steering._waypoints.is_empty(), "Nearby obstacle produces a cached detour")
	temporary.free()
	await physics_frame
	await process_frame
	check(probe_actor._steer_around_obstacles(Vector2(8300, 0), Vector2.RIGHT, 0.2) == Vector2.RIGHT, "Unloading an obstacle discards its detour without stale references")
	# Exercise the production steering and separation together at the normal cap.
	var stress_wall := obstacle(Vector2(15000, 0), Vector2(240, 320))
	var stress_goal := Node2D.new()
	stress_goal.position = Vector2(15450, 0)
	world.add_child(stress_goal)
	var grid := EnemySpatialGrid.new()
	world.add_child(grid)
	var swarm: Array[Enemy] = []
	var crossed: Array[bool] = []
	for index in 200:
		var actor := TYPES[1 if index % 4 == 0 else 0].instantiate() as Enemy
		actor.position = Vector2(14600 - (index % 5) * 10, (index - 100) * 4)
		actor.set_target(stress_goal)
		actor.set_spatial_grid(grid)
		world.add_child(actor)
		grid.register_enemy(actor)
		swarm.append(actor)
		crossed.append(false)
	Engine.time_scale = 4
	for _frame in 900:
		await physics_frame
		for index in swarm.size():
			if swarm[index].position.x > 15200:
				crossed[index] = true
				swarm[index].set_physics_process(false)
		if crossed.all(func(done: bool) -> bool: return done):
			break
	Engine.time_scale = 1
	check(crossed.all(func(done: bool) -> bool: return done) and grid._enemies.size() == 200, "All 200 mixed enemies traverse the barrier with production separation enabled")
	stress_wall.free()
	world.queue_free()
	await process_frame
	# Verify the production spawner/controller rather than only the search helper.
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	var player: Player = main.get_node("Player")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	var encounter: BossEncounter = main.get_node("BossEncounter")
	spawner.set_process(false)
	main.get_node("RunClock").set_process(false)
	main.get_node("ChunkManager").set_process(false)
	main.get_node("ChunkManager").set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	var spawn_blocker := obstacle(Vector2(650, 0), Vector2(240, 200))
	await physics_frame
	await process_frame
	for type in [spawner.ENEMY_SCENE, spawner.tier_2_enemy_scene]:
		var before := spawner.get_active_enemy_count()
		spawner._spawn_enemy(Vector2(650, 0), type)
		check(spawner.get_active_enemy_count() == before + 1, "Production spawner relocates a blocked Squig/Ork spawn")
		var spawned := spawner.spatial_grid._enemies.back() as Enemy
		spawned.set_physics_process(false)
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = spawned.get_body_radius()
		query.shape = circle
		query.transform.origin = spawned.global_position
		query.collision_mask = TerrainObstacles.COLLISION_LAYER
		check(spawned.position != Vector2(650, 0) and spawned.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(), "Spawned enemy's full collision body is outside terrain")
	spawn_blocker.free()
	var sealed_spawn := obstacle(Vector2.ZERO, Vector2.ONE * 5000)
	await physics_frame
	await process_frame
	var count_before := spawner.get_active_enemy_count()
	spawner._spawn_enemy(Vector2(650, 0))
	check(spawner.get_active_enemy_count() == count_before, "Impossible normal spawn does not register an enemy or consume cap")
	encounter._on_seconds_changed(600)
	check(not encounter.warboss_spawned and spawner.normal_spawning_enabled and encounter.boss == null, "Blocked boss spawn remains retryable without ending normal scheduling")
	sealed_spawn.free()
	await physics_frame
	await process_frame
	encounter._on_seconds_changed(601)
	check(encounter.warboss_spawned and is_instance_valid(encounter.boss) and not spawner.normal_spawning_enabled, "Boss spawns and stops normal scheduling after space becomes available")
	encounter.boss.set_physics_process(false)
	check(encounter.boss.max_health == 2000 and encounter.boss.current_health == 2000 and encounter.boss.armor == 5 and encounter.boss.movement_speed == 40, "Boss stats unchanged by safe placement")
	var boss_query := PhysicsShapeQueryParameters2D.new()
	var boss_circle := CircleShape2D.new()
	boss_circle.radius = encounter.boss.get_body_radius()
	boss_query.shape = boss_circle
	boss_query.transform.origin = encounter.boss.global_position
	boss_query.collision_mask = TerrainObstacles.COLLISION_LAYER
	check(player.get_world_2d().direct_space_state.intersect_shape(boss_query, 1).is_empty() and encounter.boss.global_position.distance_to(player.global_position) >= spawner.minimum_player_spawn_distance, "Production boss spawn clears terrain with full-body and player clearance")
	var original_boss := encounter.boss
	encounter._on_seconds_changed(602)
	check(encounter.boss == original_boss, "Retry protection still allows only one boss")
	main.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("PASS: ", checks, " safe spawn / all prop detours / speed checks")
	quit()
