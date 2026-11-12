extends SceneTree

const CHUNK := preload("res://scenes/systems/terrain_chunk.tscn")
const ACTORS: Array[PackedScene] = [
	preload("res://scenes/player/player.tscn"),
	preload("res://scenes/enemies/enemy.tscn"),
	preload("res://scenes/enemies/ork_boy.tscn"),
	preload("res://scenes/enemies/warboss.tscn"),
]
var checks: int = 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)


func _initialize() -> void:
	run.call_deferred()


func stop_actor(actor: CharacterBody2D) -> void:
	actor.set_physics_process(false)
	if actor is Player:
		actor.get_node("Bolter/FireTimer").stop()
		actor.get_node("KnifeAttack").set_physics_process(false)


func collect_props() -> Dictionary[String, Sprite2D]:
	var examples: Dictionary[String, Sprite2D] = {}
	for y in range(-12, 12):
		for x in range(-12, 12):
			var chunk := CHUNK.instantiate() as TerrainChunk
			chunk.configure(Vector2i(x, y), 1024)
			root.add_child(chunk)
			check(chunk.find_children("*", "StaticBody2D", true, false).size() == chunk.large_props.get_child_count(), "Each generated tree, tank and ruin owns exactly one static obstacle")
			check(chunk.roads.find_children("*", "CollisionObject2D", true, false).is_empty() and not chunk.ground.collision_enabled and not chunk.decorations.collision_enabled, "Roads, ground and small ground decorations stay passable")
			for prop: Sprite2D in chunk.large_props.get_children():
				var key := String(prop.name)
				if not examples.has(key):
					examples[key] = prop.duplicate() as Sprite2D
			chunk.free()
			if examples.size() == 8:
				return examples
	return examples


func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var examples := collect_props()
	check(examples.size() == 8, "Real terrain generation supplies one tank, all four ruins and all three trees")
	for name: String in examples:
		var prop := examples[name]
		world.add_child(prop)
		prop.position = Vector2.ZERO
		var obstacle := prop.get_node("Obstacle") as StaticBody2D
		var collision := obstacle.get_node("CollisionShape2D") as CollisionShape2D
		check(obstacle.collision_layer == TerrainObstacles.COLLISION_LAYER and obstacle.collision_mask == 0, "Terrain uses only its dedicated obstacle layer")
		check(not collision.disabled, "Terrain obstacle is enabled")
		if name.begins_with("Tree"):
			check(collision.shape is CircleShape2D and collision.position.y > 0, "Tree collision fits the trunk/root base below its canopy")
		else:
			check(collision.shape is ConvexPolygonShape2D and collision.shape.points.size() >= 3, "Tank/ruin collision follows a solid outline")
		await physics_frame
		await process_frame
		var bounds: Rect2 = collision.global_transform * collision.shape.get_rect()
		var center := bounds.get_center()
		for actor_scene in ACTORS:
			var actor := actor_scene.instantiate() as CharacterBody2D
			world.add_child(actor)
			stop_actor(actor)
			check(actor.collision_mask & TerrainObstacles.COLLISION_LAYER != 0, "Player, Squig, Ork and Warboss all scan terrain obstacles")
			actor.position = Vector2(bounds.position.x - 150, center.y)
			await physics_frame
			await process_frame
			var hit := actor.move_and_collide(Vector2(bounds.size.x + 300, 0))
			check(hit != null and hit.get_collider() == obstacle and actor.position.x < center.x, "Actual actor movement is stopped by " + name)
			actor.free()
		# The actual player's WASD movement must stop as well, without changing speed.
		var player := ACTORS[0].instantiate() as Player
		world.add_child(player)
		stop_actor(player)
		player.position = Vector2(bounds.position.x - 45, center.y)
		await physics_frame
		Input.action_press("move_right")
		for _step in 30:
			await physics_frame
			player._physics_process(1.0 / 60.0)
		Input.action_release("move_right")
		check(player.position.x < center.x and player.get_slide_collision_count() > 0 and player.speed == 150, "WASD movement stops at " + name + " without changing player speed")
		# Distant enemies must sweep through physics on their throttled update too.
		player.position = center + Vector2(4000, 0)
		var distant := ACTORS[1].instantiate() as Enemy
		world.add_child(distant)
		stop_actor(distant)
		distant.position = Vector2(bounds.position.x - 150, center.y)
		distant.set_target(player)
		await physics_frame
		await process_frame
		distant._process_very_far_movement(30.0)
		check(distant.position.x < center.x, "Throttled distant movement cannot teleport through " + name)
		distant.free()
		player.free()
		prop.free()
		await physics_frame
		await process_frame
		var ray := PhysicsRayQueryParameters2D.create(Vector2(bounds.position.x - 150, center.y), Vector2(bounds.end.x + 150, center.y), TerrainObstacles.COLLISION_LAYER)
		check(world.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(), "Removing terrain removes its collider without a ghost obstacle")
	# Roads themselves must not block any of the production character types.
	var roads := TerrainRoads.new()
	world.add_child(roads)
	for index in 256:
		var coordinate := Vector2i(index % 16 - 8, floori(float(index) / 16.0) - 8)
		if not TerrainRoads.get_layout(coordinate, 1024).is_empty():
			roads.populate(coordinate, 1024)
			break
	check(roads.get_child_count() > 0, "Traversal fixture includes an actual generated road")
	var road_y := (roads.get_child(0) as Sprite2D).position.y + TerrainRoads.CELL_SIZE * 0.5
	for actor_scene in ACTORS:
		var actor := actor_scene.instantiate() as CharacterBody2D
		world.add_child(actor)
		stop_actor(actor)
		actor.position = Vector2(0, road_y)
		await physics_frame
		check(actor.move_and_collide(Vector2(1024, 0)) == null and actor.position.x == 1024, "Roads and open terrain remain traversable")
		actor.free()
	roads.free()
	# Reconfigure actual chunks and stream away/back, checking body lifetimes.
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	var manager: ChunkManager = main.get_node("ChunkManager")
	var run_player: Player = main.get_node("Player")
	stop_actor(run_player)
	main.get_node("EnemySpawner").set_process(false)
	manager.set_process(false)
	manager.set_physics_process(false)
	var bodies_before := manager.find_children("*", "StaticBody2D", true, false).size()
	for chunk: TerrainChunk in manager.active_chunks.values():
		chunk.configure(chunk.chunk_coordinate, 1024)
	check(manager.find_children("*", "StaticBody2D", true, false).size() == bodies_before, "Reconfiguration replaces colliders without duplication")
	var old_body := manager.find_children("*", "StaticBody2D", true, false)[0]
	run_player.position = Vector2(8192, -8192)
	manager.update_chunks()
	await process_frame
	check(not is_instance_valid(old_body) and manager.active_chunks.size() == 9, "Streaming unloads old collision bodies with their chunks")
	run_player.position = Vector2.ZERO
	manager.update_chunks()
	check(manager.find_children("*", "StaticBody2D", true, false).size() == bodies_before, "Returning rebuilds exactly the original obstacle count")
	main.queue_free()
	world.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("PASS: ", checks, " solid terrain / actor movement / WASD / roads / streaming checks")
	quit()
