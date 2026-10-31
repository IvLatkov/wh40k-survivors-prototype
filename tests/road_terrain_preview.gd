extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func add_label(parent: Node, text: String) -> void:
	var layer := CanvasLayer.new()
	parent.add_child(layer)
	var label := Label.new()
	label.text = text
	label.position = Vector2(12, 12)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_outline_size", 5)
	layer.add_child(label)

func show_world(center: Vector2i, radius: int, zoom: float, filename: String, focus: Vector2 = Vector2.INF) -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	camera.position = Vector2(center) * 1024 + Vector2(512, 512)
	if focus != Vector2.INF:
		camera.position = focus
	camera.zoom = Vector2.ONE * zoom
	world.add_child(camera)
	var pieces := 0
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var chunk := preload("res://scenes/systems/terrain_chunk.tscn").instantiate() as TerrainChunk
			chunk.configure(Vector2i(x, y), 1024)
			world.add_child(chunk)
			pieces += chunk.roads.get_child_count()
			var border := Line2D.new()
			border.default_color = Color(0.5, 0.8, 1.0, 0.35)
			border.width = 2.0 / zoom
			border.closed = true
			border.points = PackedVector2Array([Vector2.ZERO, Vector2(1024, 0), Vector2(1024, 1024), Vector2(0, 1024)])
			chunk.add_child(border)
	add_label(world, "NATURAL ROAD NETWORK | %d chunks / %d pieces | blue: preview-only chunk boundaries" % [(radius * 2 + 1) ** 2, pieces])
	await capture(filename)
	world.free()
	await process_frame

func run() -> void:
	root.size = Vector2i(1440, 960)
	# Find a natural active cluster containing both a bend and a junction.
	var example := Vector2i.ZERO
	for y in range(-4, 5):
		for x in range(-4, 5):
			var path := TerrainRoads._region_path(Vector2i(x, y))
			if path.size() > 30:
				example = Vector2i(x, y) * 4 + Vector2i(1, 1)
	await show_world(example, 3, 0.20, "res://docs/roads_overview.png")
	await show_world(example, 1, 0.6, "res://docs/roads_closeup.png")
	var junction_found := false
	for y in range(example.y - 3, example.y + 4):
		for x in range(example.x - 3, example.x + 4):
			if junction_found:
				continue
			var coordinate := Vector2i(x, y)
			for cell in TerrainRoads.get_layout(coordinate, 1024):
				if cell.z == 15:
					var focus := Vector2(coordinate) * 1024 + Vector2(cell.x, cell.y) * 256 + Vector2(128, 128)
					await show_world(coordinate, 1, 1.0, "res://docs/roads_junction.png", focus)
					junction_found = true
					break
	assert(junction_found, "Natural junction example found")
	var gallery := Node2D.new()
	root.add_child(gallery)
	current_scene = gallery
	for mask in range(1, 16):
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = TerrainRoads.TEXTURES[mask]
		sprite.position = Vector2((mask - 1) % 5 * 270 + 40, (mask - 1) / 5 * 280 + 70)
		gallery.add_child(sprite)
	add_label(gallery, "EXTRACTED ROAD PIECES | N=1 E=2 S=4 W=8 | masks 1..15")
	await capture("res://docs/roads_pieces.png")
	gallery.free()
	await process_frame
	quit()
