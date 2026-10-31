extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var ground_folder := "res://assets/art/effects/terrain/battlefield_biome/"
	var ground_pngs := Array(DirAccess.get_files_at(ground_folder)).filter(func(file: String) -> bool: return file.ends_with(".png"))
	assert(ground_pngs == ["ChatGPT Image Oct 21, 2026, 07_17_37 PM-1.png"])
	var original_ground := load(ground_folder + ground_pngs[0]) as Texture2D
	assert(original_ground.get_size() == Vector2(1536, 1024))
	assert(TerrainChunk.GROUND_ATLAS.get_size() == Vector2(768, 128))
	assert(not TerrainChunk.GROUND_ATLAS.get_image().has_mipmaps())
	var decoration_pngs := Array(DirAccess.get_files_at(TerrainChunk.DECORATION_FOLDER)).filter(func(file: String) -> bool: return file.ends_with(".png"))
	assert(decoration_pngs.size() == 14)
	for file in TerrainChunk.DECORATION_FILES:
		assert(decoration_pngs.has(file))
		var texture := load(TerrainChunk.DECORATION_FOLDER + file) as Texture2D
		assert(texture.get_size() == Vector2(48, 48))
		assert(not texture.get_image().has_mipmaps())
	var presentation := load(TerrainChunk.DECORATION_FOLDER + "ChatGPT Image Oct 21, 2026, 07_17_38 PM-2.png") as Texture2D
	assert(presentation.get_size() == Vector2(1536, 1024))
	var expected_files: Array[String] = [
		"dark_dirt_ash_tile.png", "dark_dirt_ash_tile_2.png",
		"dark_dirt_ash_tile_3.png", "dark_dirt_ash_tile_4.png",
		"dark_dirt_ash_tile_5.png", "dark_dirt_ash_tile_6.png",
		"dark_dirt_ash_tile_11.png", "dark_dirt_ash_tile_12.png",
	]
	assert(TerrainChunk.DECORATION_FILES == expected_files)
	assert(TerrainChunk.DECORATION_CHANCES.size() == expected_files.size())
	var probability: float = 0.0
	for chance in TerrainChunk.DECORATION_CHANCES:
		assert(chance > 0.0)
		probability += chance
	assert(is_equal_approx(probability, 0.036 * 0.0705 / 0.0515))
	var seen_sources: Dictionary[int, bool] = {}
	var scene := preload("res://scenes/systems/terrain_chunk.tscn")
	var counts: Array[int] = [0, 0, 0, 0, 0, 0]
	var decoration_count: int = 0
	var adjacent_matches: int = 0
	var total: int = 0
	for cy in range(-2, 3):
		for cx in range(-2, 3):
			var chunk := scene.instantiate() as TerrainChunk
			chunk.configure(Vector2i(cx, cy), 1024)
			root.add_child(chunk)
			assert(chunk.get_child_count() == 3 and chunk.get_node("Ground") == chunk.ground and chunk.get_node("Decorations") == chunk.decorations)
			assert(chunk.ground.get_used_cells().size() == 1024)
			assert(chunk.ground.tile_set.get_physics_layers_count() == 0)
			assert(chunk.decorations.tile_set.get_physics_layers_count() == 0)
			assert(not chunk.decorations.collision_enabled)
			assert(chunk.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
			assert(chunk.decorations.tile_set.get_source_count() == 8)
			for cell in chunk.ground.get_used_cells():
				var variant := floori(chunk.ground.get_cell_atlas_coords(cell).x / 4.0)
				counts[variant] += 1
				total += 1
				if cell.x < 31 and floori(chunk.ground.get_cell_atlas_coords(cell + Vector2i.RIGHT).x / 4.0) == variant:
					adjacent_matches += 1
			for index in expected_files.size():
				var source := chunk.decorations.tile_set.get_source(index) as TileSetAtlasSource
				assert(source.texture.resource_path == TerrainChunk.DECORATION_FOLDER + expected_files[index])
			for cell in chunk.decorations.get_used_cells():
				var source_id := chunk.decorations.get_cell_source_id(cell)
				assert(source_id >= 0 and source_id < expected_files.size())
				seen_sources[source_id] = true
			decoration_count += chunk.decorations.get_used_cells().size()
			chunk.free()
	assert(seen_sources.size() == expected_files.size(), "Every remaining decoration generates")
	assert(counts.all(func(count: int) -> bool: return count > 0))
	assert(float(adjacent_matches) / total > 0.70, "Ground forms coherent patches")
	assert(absf(float(decoration_count) / total - probability) < 0.01)
	print("PASS terrain artwork: variants=", counts, "; decoration density=", 100.0 * decoration_count / total, "%; matching right neighbors=", 100.0 * adjacent_matches / total, "%")
	quit()


