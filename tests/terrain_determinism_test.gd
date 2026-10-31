extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func run() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/terrain_reference_hashes.json"))
	# Keep the original ground and historical decoration references untouched.
	# Decoration layout intentionally changes when its probability changes.
	var record := OS.get_cmdline_user_args().has("--record-decoration-reference")
	var decoration_path := "res://tests/terrain_decoration_reference_hashes.json"
	var decoration_golden: Dictionary = {} if record else JSON.parse_string(FileAccess.get_file_as_string(decoration_path))
	var scene := preload("res://scenes/systems/terrain_chunk.tscn")
	for key: String in golden:
		var parts := key.split(",")
		var coordinate := Vector2i(int(parts[0]), int(parts[1]))
		var data := TerrainChunk.generate_data(coordinate, 1024)
		var incremental := TerrainChunk.Generation.new(coordinate, 1024)
		while not incremental.is_complete():
			incremental.generate_row()
		assert(data.ground_cells == incremental.data.ground_cells)
		assert(data.decoration_cells == incremental.data.decoration_cells)
		var chunk := scene.instantiate() as TerrainChunk
		chunk.configure(coordinate, 1024, data)
		root.add_child(chunk)
		assert(digest(chunk.ground.tile_map_data) == golden[key][0], "Original ground bytes match at " + key)
		if record:
			assert(is_equal_approx(TerrainChunk.DECORATION_CHANCES[3], 0.007 * TerrainChunk.DECORATION_NORMALIZATION))
			decoration_golden[key] = digest(chunk.decorations.tile_map_data)
		else:
			assert(digest(chunk.decorations.tile_map_data) == decoration_golden[key], "Reduced-weight decoration bytes match at " + key)
		chunk.free()
	if record:
		var output := FileAccess.open(decoration_path, FileAccess.WRITE)
		output.store_string(JSON.stringify(decoration_golden, "  "))
		print("Recorded weight-specific decoration references; all original ground hashes passed")
	else:
		print("PASS: 25 chunks match original ground and reduced-weight decoration reference bytes, including incremental generation")
	quit()
