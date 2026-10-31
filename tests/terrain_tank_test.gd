extends SceneTree

var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	assert(ok, message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var texture := TerrainChunk.TANK_TEXTURE
	check(texture.resource_path == "res://assets/art/effects/terrain/tanks/tank1.png", "Use the existing tank artwork")
	check(texture.get_size() == Vector2(128, 128), "Native texture dimensions preserved")
	var image := texture.get_image()
	check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(64, 64).a > 0.0, "Prepared background transparent, tank opaque")
	check(not image.has_mipmaps(), "No blurry mipmap sampling")
	var placed := 0
	var first_tank := Vector2i.ZERO
	var found := false
	for y in range(-50, 50):
		for x in range(-50, 50):
			var coordinate := Vector2i(x, y)
			var at := TerrainChunk.get_tank_position(coordinate, 1024)
			check(at == TerrainChunk.get_tank_position(coordinate, 1024), "Coordinate placement deterministic")
			if at == Vector2.INF: continue
			placed += 1
			if not found:
				first_tank = coordinate
				found = true
			check(at == at.round() and at.x >= 192 and at.x <= 832 and at.y >= 192 and at.y <= 832, "Pixel-aligned centers keep edge margin")
			var half_size := texture.get_size() * TerrainChunk.TANK_SCALE * 0.5
			check((at - half_size).x >= 32 and (at - half_size).y >= 32 and (at + half_size).x <= 992 and (at + half_size).y <= 992, "Full texture comfortably fits chunk")
			var center := Vector2(coordinate) * 1024 + at
			check(Vector2.ZERO.clamp(center - half_size, center + half_size).length() >= 250.0, "Full footprint stays clear of starting disk")
	check(placed >= 3200 and placed <= 3800, "35% placement over 10,000 chunks")
	check(found, "Fixture finds eligible natural tank")
	# This independent stream must never perturb gameplay RNG.
	seed(912)
	var expected := randf()
	seed(912)
	TerrainChunk.get_tank_position(first_tank, 1024)
	check(randf() == expected, "No gameplay RNG consumption")
	check(TerrainChunk.get_tank_position(first_tank, 128) == Vector2.INF, "Undersized chunk safely skips oversized prop")
	var scene := preload("res://scenes/systems/terrain_chunk.tscn")
	var tanks := 0
	for y in range(-5, 5):
		for x in range(-5, 5):
			var coordinate := Vector2i(x, y)
			var chunk := scene.instantiate() as TerrainChunk
			chunk.configure(coordinate, 1024)
			root.add_child(chunk)
			check(chunk.get_child_count() == 4 and chunk.large_props.z_index == 2, "Dedicated visual road layer and unchanged large-prop depth")
			check(chunk.large_props.get_child_count() <= 5, "At most one tank and four independent buildings per chunk")
			check(chunk.find_children("*", "CollisionObject2D", true, false).is_empty() and chunk.find_children("*", "CollisionShape2D", true, false).is_empty(), "No prop physics")
			var before := TerrainChunk.get_tank_position(coordinate, 1024)
			if before != Vector2.INF:
				tanks += 1
				var sprite := chunk.large_props.get_node("TankWreck") as Sprite2D
				check(sprite.texture == texture and sprite.position == before and sprite.scale == Vector2(2, 2), "Shared native texture and scale")
				check(not sprite.flip_h and not sprite.flip_v and sprite.rotation == 0.0, "Original orientation and lighting retained")
			chunk.configure(coordinate, 1024)
			check(chunk.large_props.has_node("TankWreck") == (before != Vector2.INF), "Reconfiguration never duplicates prop")
			chunk.free()
	# Explicit unload/reload of an eligible coordinate.
	var original := TerrainChunk.get_tank_position(first_tank, 1024)
	for i in 2:
		var chunk := scene.instantiate() as TerrainChunk
		chunk.configure(first_tank, 1024)
		root.add_child(chunk)
		check((chunk.large_props.get_node("TankWreck") as Sprite2D).position == original, "Reload keeps identical tank")
		chunk.free()
	var timing_chunk := scene.instantiate() as TerrainChunk
	timing_chunk.configure(first_tank, 1024)
	root.add_child(timing_chunk)
	var total_usec := 0
	var peak_usec := 0
	for i in 520:
		var started := Time.get_ticks_usec()
		timing_chunk._populate_large_props()
		var elapsed := Time.get_ticks_usec() - started
		if i >= 20:
			total_usec += elapsed
			peak_usec = maxi(peak_usec, elapsed)
	print("TANK_PROP_CPU samples=500 mean_ms=", total_usec / 500000.0, " peak_ms=", peak_usec / 1000.0)
	timing_chunk.free()
	var main := preload("res://scenes/main.tscn").instantiate()
	var terrain_z: int = main.get_node("ChunkManager/TerrainChunks").z_index
	check(terrain_z + 2 == -8 and terrain_z + 1 == -9, "Large props above decorations at -9")
	check(terrain_z + 2 < main.get_node("Player").z_index, "Tank below player at zero")
	main.free()
	print("TANK_STATS chunks=10000 tanks=", placed, " frequency_percent=", placed / 100.0,
		" generated_chunks=100 generated_tanks=", tanks, " generated_percent=", tanks)
	print("PASS: ", checks, " tank placement checks")
	quit()
