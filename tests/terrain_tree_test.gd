extends SceneTree

const CHUNK := preload("res://scenes/systems/terrain_chunk.tscn")
var checks: int = 0


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)


func _initialize() -> void:
	run.call_deferred()


func occupied_at(coordinate: Vector2i) -> Array[Rect2]:
	var occupied: Array[Rect2] = []
	var tank := TerrainChunk.get_tank_position(coordinate, 1024)
	if tank != Vector2.INF:
		var size := TerrainChunk.TANK_TEXTURE.get_size() * TerrainChunk.TANK_SCALE
		occupied.append(Rect2(tank - size * 0.5, size))
	for building in TerrainChunk.get_building_placements(coordinate, 1024):
		occupied.append(Rect2(building.position - TerrainChunk.BUILDING_FOOTPRINT * 0.5, TerrainChunk.BUILDING_FOOTPRINT))
	return occupied


func signature(chunk: TerrainChunk) -> Array:
	var result: Array = []
	for tree: Sprite2D in chunk.large_props.find_children("Tree*", "Sprite2D", false, false):
		result.append([tree.texture.resource_path, tree.position, tree.scale])
	return result


func run() -> void:
	var selected := 0
	var placed := 0
	var variants: Array[int] = [0, 0, 0]
	var example := Vector2i.ZERO
	for ry in range(-10, 10):
		for rx in range(-10, 10):
			var region := Vector2i(rx, ry)
			var chunks := TerrainTrees.get_region_tree_chunks(region)
			check(chunks.size() in [2, 3] and chunks == TerrainTrees.get_region_tree_chunks(region), "Each six-chunk region selects two or three stable tree chunks")
			selected += chunks.size()
			var seen: Array[Vector2i] = []
			for y in 2:
				for x in 3:
					var coordinate := region * Vector2i(3, 2) + Vector2i(x, y)
					check(TerrainTrees.get_region(coordinate) == region, "Negative and positive coordinates use floor-based region ownership")
					var occupied := occupied_at(coordinate)
					var trees := TerrainTrees.get_placements(coordinate, 1024, occupied)
					check(trees.size() <= 1 and (trees.is_empty() or chunks.has(coordinate)), "At most one tree in a selected chunk")
					var repeated := TerrainTrees.get_placements(coordinate, 1024, occupied)
					check(trees.size() == repeated.size(), "Placement independent of generation order")
					for tree in trees:
						check(not seen.has(coordinate), "No duplicate tree chunk in a region")
						seen.append(coordinate)
						check(tree.position == repeated[0].position and tree.variant == repeated[0].variant, "Variant and position deterministic")
						variants[tree.variant] += 1
						example = coordinate
						placed += 1
						var bounds := Rect2(tree.position - TerrainTrees.FOOTPRINT * 0.5, TerrainTrees.FOOTPRINT)
						check(Rect2(Vector2.ONE * TerrainTrees.EDGE_GAP, Vector2.ONE * (1024 - TerrainTrees.EDGE_GAP * 2.0)).encloses(bounds), "Full tree footprint clears chunk boundaries and neighboring trees")
						var world_bounds := Rect2(bounds.position + Vector2(coordinate) * 1024, bounds.size)
						check(Vector2.ZERO.clamp(world_bounds.position, world_bounds.end).length() >= TerrainTrees.START_CLEARANCE, "Full tree footprint clears starting area")
						for prop in occupied:
							check(not bounds.intersects(prop.grow(TerrainTrees.PROP_GAP)), "Tree avoids existing ruins and tanks with walking clearance")
						for road in TerrainRoads.get_layout(coordinate, 1024):
							check(not bounds.intersects(Rect2(Vector2(road.x, road.y) * 256, Vector2.ONE * 256).grow(TerrainTrees.ROAD_GAP)), "Tree avoids roads and roadside clearance")
	check(placed >= selected * 0.95, "Safety exclusions retain the target sparse density across the world")
	check(variants.all(func(count: int) -> bool: return count > 0), "All three generated tree variants are used")
	check(TerrainTrees.get_placements(example, 256, []).is_empty(), "Small chunks safely skip oversized trees")
	check(TerrainTrees.get_placements(example, 1024, [Rect2(Vector2.ZERO, Vector2.ONE * 1024)]).is_empty(), "Fully occupied chunks skip trees instead of blocking paths")
	seed(481)
	var expected := randf()
	seed(481)
	TerrainTrees.get_placements(example, 1024, occupied_at(example))
	check(randf() == expected, "Trees consume no gameplay RNG")
	var original: Array = []
	for reload_index in 2:
		var chunk := CHUNK.instantiate() as TerrainChunk
		chunk.configure(example, 1024)
		root.add_child(chunk)
		var actual := signature(chunk)
		check(actual.size() == 1, "Selected tree appears in the real terrain scene")
		if reload_index == 0:
			original = actual
		check(actual == original, "Unload and reload preserve tree visuals")
		check(chunk.large_props.z_index == 2 and chunk.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Trees share the existing prop layer and nearest filtering")
		var tree := chunk.large_props.find_children("Tree*", "Sprite2D", false, false)[0] as Sprite2D
		check(tree.get_node("Obstacle") is StaticBody2D and tree.get_node("Obstacle/CollisionShape2D").shape is CircleShape2D, "Trees have solid trunks instead of canopy-sized obstacles")
		chunk.configure(example, 1024)
		check(signature(chunk) == original, "Reconfigure does not duplicate trees")
		chunk.free()
	var main := preload("res://scenes/main.tscn").instantiate() as Node2D
	root.add_child(main)
	var player: Player = main.get_node("Player")
	var manager: ChunkManager = main.get_node("ChunkManager")
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	main.get_node("EnemySpawner").set_process(false)
	manager.set_process(false)
	manager.set_physics_process(false)
	var before: Dictionary[Vector2i, Array] = {}
	for coordinate: Vector2i in manager.active_chunks:
		before[coordinate] = signature(manager.active_chunks[coordinate])
	player.position = Vector2(8192, -8192)
	manager.update_chunks()
	check(manager.active_chunks.size() == 9, "Distant travel preserves the 3x3 active grid")
	player.position = Vector2.ZERO
	manager.update_chunks()
	for coordinate: Vector2i in before:
		check(signature(manager.active_chunks[coordinate]) == before[coordinate], "Real streaming unload/return regenerates identical trees")
	main.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	print("TREE_DENSITY regions=400 chunks=2400 selected=", selected, " placed=", placed, " per_six=", placed / 400.0, " variants=", variants)
	print("PASS: ", checks, " tree density/determinism/clearance/streaming checks")
	quit()
