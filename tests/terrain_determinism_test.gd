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
		assert(digest(chunk.decorations.tile_map_data) == golden[key][1], "Current decoration bytes match at " + key)
		chunk.free()
	print("PASS: 25 chunks match original ground and current decoration reference bytes, including incremental generation")
	quit()
