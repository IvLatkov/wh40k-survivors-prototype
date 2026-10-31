extends SceneTree

var checks: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var sha := HashingContext.new()
	sha.start(HashingContext.HASH_SHA256)
	sha.update(FileAccess.get_file_as_bytes("res://assets/art/effects/terrain/roads/road.png"))
	check(sha.finish().hex_encode() == "1eae96eebc904c5b94cf81cbf1d10bea85698054c3da53eb3e904ff7981d4523", "Original road sheet unchanged")
	var images: Array[Image] = []
	images.append(null)
	for mask in range(1, 16):
		var image := TerrainRoads.TEXTURES[mask].get_image()
		check(image.get_size() == Vector2i(256, 256) and not image.has_mipmaps(), "Native shared 256px prepared piece")
		images.append(image)
	# Pixel-for-pixel matching ports, not just matching direction flags.
	for first in range(1, 16):
		for second in range(1, 16):
			for pixel in 256:
				if first & 2 and second & 8:
					check(images[first].get_pixel(255, pixel) == images[second].get_pixel(0, pixel), "East-west seam texels")
				if first & 4 and second & 1:
					check(images[first].get_pixel(pixel, 255) == images[second].get_pixel(pixel, 0), "North-south seam texels")
	var layouts: Dictionary[Vector2i, Dictionary] = {}
	var counts: Array[int] = []
	counts.resize(16)
	counts.fill(0)
	var participating := 0
	var total := 0
	var border_connections := 0
	seed(9381)
	var expected_random := randf()
	seed(9381)
	for y in range(-50, 50):
		for x in range(-50, 50):
			var coordinate := Vector2i(x, y)
			var layout := TerrainRoads.get_layout(coordinate, 1024)
			check(layout == TerrainRoads.get_layout(coordinate, 1024), "Repeat/load-order independent layout")
			var masks: Dictionary[Vector2i, int] = {}
			for cell in layout:
				check(cell.x >= 0 and cell.x < 4 and cell.y >= 0 and cell.y < 4 and cell.z > 0 and cell.z <= 15, "Cell bounds and valid non-isolated ports")
				masks[Vector2i(cell.x, cell.y)] = cell.z
				counts[cell.z] += 1
			layouts[coordinate] = masks
			participating += int(not layout.is_empty())
			total += layout.size()
	check(randf() == expected_random, "Global RNG untouched")
	for coordinate: Vector2i in layouts:
		var masks: Dictionary = layouts[coordinate]
		for cell: Vector2i in masks:
			for direction in 4:
				var neighbor := cell + TerrainRoads.DIRECTIONS[direction]
				var next_coordinate := coordinate
				var crossed := neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= 4 or neighbor.y >= 4
				if crossed:
					next_coordinate += TerrainRoads.DIRECTIONS[direction]
					neighbor = Vector2i(posmod(neighbor.x, 4), posmod(neighbor.y, 4))
				var neighbor_masks: Dictionary = layouts.get(next_coordinate, {})
				if not layouts.has(next_coordinate):
					for next_cell in TerrainRoads.get_layout(next_coordinate, 1024):
						neighbor_masks[Vector2i(next_cell.x, next_cell.y)] = next_cell.z
				var connected: bool = (int(masks[cell]) & (1 << direction)) != 0
				var reciprocal: bool = (int(neighbor_masks.get(neighbor, 0)) & (1 << ((direction + 2) % 4))) != 0
				check(connected == reciprocal, "Reciprocal within/across chunk ports including negative coordinates")
				border_connections += int(crossed and connected)
	for mask in range(1, 16):
		check(counts[mask] > 0, "Every piece including all ends/corners/junctions occurs naturally")
	check(participating > 2000 and participating < 3500, "Moderate 20-35% road chunk participation")
	check(TerrainRoads.get_layout(Vector2i.ZERO, 128).is_empty(), "Undersized preview fixture is safe")
	var generated := 0
	var scene := preload("res://scenes/systems/terrain_chunk.tscn")
	for coordinate: Vector2i in layouts:
		if layouts[coordinate].is_empty():
			continue
		var chunk := scene.instantiate() as TerrainChunk
		chunk.configure(coordinate, 1024)
		root.add_child(chunk)
		var expected: int = layouts[coordinate].size()
		check(chunk.roads.get_child_count() == expected and expected <= 16, "Actual bounded road nodes")
		chunk.configure(coordinate, 1024)
		check(chunk.roads.get_child_count() == expected, "Reconfigure replaces instead of accumulating")
		for sprite: Sprite2D in chunk.roads.get_children():
			check(sprite.get_child_count() == 0 and sprite.material == null and not sprite.is_processing() and not sprite.is_physics_processing(), "Visual-only shared sprite without processing/physics/material")
		chunk.free()
		generated += 1
		if generated >= 256:
			break
	var report := {"chunks": 10000, "participating_chunks": participating, "chunk_frequency": participating / 10000.0,
		"pieces": total, "occupied_cell_fraction": total / 160000.0, "mask_counts": counts,
		"directed_border_connections": border_connections, "instantiated_chunks": generated, "checks": checks}
	var output := FileAccess.open("res://docs/roads_distribution.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("ROADS PASS ", report)
	quit()
