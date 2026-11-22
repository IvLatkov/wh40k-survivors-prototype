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
	var imported_bytes := 0
	for texture in TerrainTrees.TEXTURES:
		check(texture.get_width() <= 256 and texture.get_height() <= 256, "Tree imports are capped at 256px")
		var source := Image.new()
		check(source.load_png_from_buffer(FileAccess.get_file_as_bytes(texture.resource_path)) == OK and source.get_size() == Vector2i(1254, 1254), "Original high-resolution tree PNGs remain intact")
		imported_bytes += texture.get_image().get_data().size()
	print("TREE_TEXTURE_BYTES ", imported_bytes)
	check(TerrainTrees.TREES_PER_CHUNK == 2, "Every chunk attempts two trees")
	var placed := 0
	var histogram: Array[int] = [0, 0, 0]
	var variants: Array[int] = [0, 0, 0]
	var example := Vector2i.ZERO
	var no_roads: Array[Vector3i] = []
	for y in range(-20, 20):
		for x in range(-30, 30):
			var coordinate := Vector2i(x, y)
			check(TerrainTrees.get_placements(coordinate, 1024, [], no_roads).size() == 2, "Every unobstructed positive or negative chunk gets two trees")
			var occupied := occupied_at(coordinate)
			var trees := TerrainTrees.get_placements(coordinate, 1024, occupied)
			var road_layout := TerrainRoads.get_layout(coordinate, 1024)
			var prepared := TerrainTrees.get_placements(coordinate, 1024, occupied, road_layout)
			check(trees.size() == prepared.size(), "Reusing an existing road layout preserves tree counts")
			check(trees.size() <= 2, "No chunk creates more than two trees")
			histogram[trees.size()] += 1
			if trees.size() == 2:
				example = coordinate
			var repeated := TerrainTrees.get_placements(coordinate, 1024, occupied)
			check(trees.size() == repeated.size(), "Placement independent of generation order")
			var seen_variants: Array[int] = []
			var seen_bounds: Array[Rect2] = []
			for index in trees.size():
				var tree := trees[index]
				check(tree.position == prepared[index].position and tree.variant == prepared[index].variant, "Reused road layout preserves exact tree variant and position")
				check(not seen_variants.has(tree.variant), "A chunk uses two different tree variants")
				seen_variants.append(tree.variant)
				check(tree.position == repeated[index].position and tree.variant == repeated[index].variant, "Variant and position deterministic")
				variants[tree.variant] += 1
				placed += 1
				var bounds := Rect2(tree.position - TerrainTrees.FOOTPRINT * 0.5, TerrainTrees.FOOTPRINT)
				check(Rect2(Vector2.ONE * TerrainTrees.EDGE_GAP, Vector2.ONE * (1024 - TerrainTrees.EDGE_GAP * 2.0)).encloses(bounds), "Full tree footprint clears chunk boundaries and neighboring trees")
				var world_bounds := Rect2(bounds.position + Vector2(coordinate) * 1024, bounds.size)
				check(Vector2.ZERO.clamp(world_bounds.position, world_bounds.end).length() >= TerrainTrees.START_CLEARANCE, "Full tree footprint clears starting area")
				for previous in seen_bounds:
					check(not bounds.intersects(previous.grow(TerrainTrees.PROP_GAP)), "Trees leave walking clearance between their footprints")
				seen_bounds.append(bounds)
				for prop in occupied:
					check(not bounds.intersects(prop.grow(TerrainTrees.PROP_GAP)), "Tree avoids existing ruins and tanks with walking clearance")
				for road in road_layout:
					check(not bounds.intersects(Rect2(Vector2(road.x, road.y) * 256, Vector2.ONE * 256).grow(TerrainTrees.ROAD_GAP)), "Tree avoids roads and roadside clearance")
	check(histogram[2] >= 2160, "At least ninety percent of real chunks retain both trees after road and obstacle exclusions")
	check(variants.all(func(count: int) -> bool: return count > 0), "All three generated tree variants are used")
	check(TerrainTrees.get_placements(example, 256, []).is_empty(), "Small chunks safely skip oversized trees")
	check(TerrainTrees.get_placements(example, 1024, [Rect2(Vector2.ZERO, Vector2.ONE * 1024)]).is_empty(), "Fully occupied chunks skip trees instead of blocking paths")
	var starter_chunk := Vector2i.ZERO
	var full_road: Array[Vector3i] = []
	for y in 4:
		for x in 4:
			full_road.append(Vector3i(x, y, 1))
	check(TerrainTrees.get_placements(starter_chunk, 1024, [], full_road).is_empty(), "A chunk covered by roads stays tree-free")
	var nearby_blocker := Rect2(Vector2.ZERO, Vector2(600, 320))
	var blocked_start: Array[Rect2] = [nearby_blocker]
	var fallback := TerrainTrees.get_placements(starter_chunk, 1024, blocked_start, no_roads)
	check(fallback.size() == 2, "Blocked opening-view positions fall back to two safe positions elsewhere in the chunk")
	for tree in fallback:
		var fallback_bounds := Rect2(tree.position - TerrainTrees.FOOTPRINT * 0.5, TerrainTrees.FOOTPRINT)
		check(not fallback_bounds.intersects(nearby_blocker.grow(TerrainTrees.PROP_GAP)), "Startup visibility preference never overrides obstacle clearance")
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
		check(actual.size() == 2, "Both trees appear in the real terrain scene")
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
	var visible_start_trees := 0
	# Default 1152x648 gameplay view, centered on the player at world origin.
	var start_view := Rect2(Vector2(-576, -324), Vector2(1152, 648))
	for coordinate: Vector2i in manager.active_chunks:
		before[coordinate] = signature(manager.active_chunks[coordinate])
		for tree: Sprite2D in manager.active_chunks[coordinate].large_props.find_children("Tree*", "Sprite2D", false, false):
			var bounds := Rect2(tree.global_position - TerrainTrees.FOOTPRINT * 0.5, TerrainTrees.FOOTPRINT)
			if tree.is_visible_in_tree() and start_view.encloses(bounds):
				visible_start_trees += 1
	check(visible_start_trees >= 1, "A new run shows at least one complete tree in the opening gameplay view")
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
	print("TREE_DENSITY chunks=2400 placed=", placed, " empty/one/two=", histogram, " average_per_chunk=", placed / 2400.0, " variants=", variants)
	print("PASS: ", checks, " tree density/determinism/clearance/streaming checks")
	quit()
