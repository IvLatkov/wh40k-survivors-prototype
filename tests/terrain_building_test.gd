extends SceneTree

const FILES: Array[String] = ["imperial_ruin_1.1.png", "imperial_ruin_2.1.png", "imperial_ruin_3.1.png", "imperial_ruin_4.1.png"]
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func _initialize() -> void:
	run.call_deferred()

func digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func file_digest(path: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()

func run() -> void:
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/building_terrain_baseline.json"))
	check(TerrainChunk.BUILDING_CHANCE == 0.25 and TerrainChunk.TANK_CHANCE == 0.35, "Independent 25% building rolls / unchanged 35% tank chance")
	check(TerrainChunk.BUILDING_TEXTURES.size() == 4, "All four sources")
	for i in FILES.size():
		var texture := TerrainChunk.BUILDING_TEXTURES[i]
		var path := "res://assets/art/effects/terrain/buildings/" + FILES[i]
		check(texture.resource_path == path and file_digest(path) == baseline.source_sha256[FILES[i]], "Source PNG unchanged")
		check(texture.get_size().x == 128 and texture.get_size().y == [132, 128, 128, 130][i], "Exact source dimensions")
		check(not texture.get_image().has_mipmaps() and texture.get_image().detect_alpha() != Image.ALPHA_NONE, "Transparent native pixel-art import")
		check((texture.get_size() * TerrainChunk.BUILDING_SCALE).x <= TerrainChunk.BUILDING_FOOTPRINT.x and (texture.get_size() * TerrainChunk.BUILDING_SCALE).y <= TerrainChunk.BUILDING_FOOTPRINT.y, "Common footprint fits every variant")
	var attempt_counts: Array[int] = [0, 0, 0, 0]
	var placed_counts: Array[int] = [0, 0, 0, 0]
	var roll_histogram: Array[int] = [0, 0, 0, 0, 0]
	var placed_histogram: Array[int] = [0, 0, 0, 0, 0]
	var roll_masks: Array[int] = []
	roll_masks.resize(16)
	roll_masks.fill(0)
	var skip_reasons := {"start_clearance": 0, "tank_overlap": 0, "building_overlap": 0}
	var examples: Dictionary = {}
	var tanks := 0
	var both := 0
	var empty := Vector2i.ZERO
	var found_empty := false
	var common_half := TerrainChunk.BUILDING_FOOTPRINT * 0.5
	var tank_half := TerrainChunk.TANK_TEXTURE.get_size() * TerrainChunk.TANK_SCALE * 0.5
	for y in range(-50, 50):
		for x in range(-50, 50):
			var coordinate := Vector2i(x, y)
			var attempts := TerrainChunk.get_building_attempts(coordinate, 1024)
			var placements := TerrainChunk.get_building_placements(coordinate, 1024)
			var repeat := TerrainChunk.get_building_placements(coordinate, 1024)
			check(placements.size() == repeat.size(), "Repeated placement count")
			var attempt_by_variant: Dictionary = {}
			var attempt_order: Dictionary = {}
			var mask := 0
			for candidate in attempts:
				check(not attempt_by_variant.has(candidate.variant), "One roll per texture")
				attempt_order[candidate.variant] = attempt_by_variant.size()
				attempt_by_variant[candidate.variant] = candidate
				attempt_counts[candidate.variant] += 1
				mask |= 1 << candidate.variant
			# Verify each roll using its own stream, unaffected by position draws.
			for variant in 4:
				var rolled := RandomNumberGenerator.new()
				rolled.seed = hash(Vector4i(x, y, TerrainChunk.BUILDING_RNG_SALT, variant))
				check(attempt_by_variant.has(variant) == (rolled.randf() < 0.25), "Independent 25% roll for this texture")
			roll_masks[mask] += 1
			roll_histogram[attempts.size()] += 1
			placed_histogram[placements.size()] += 1
			if placements.is_empty() and not found_empty:
				empty = coordinate
				found_empty = true
			var tank_at := TerrainChunk.get_tank_position(coordinate, 1024)
			tanks += int(tank_at != Vector2.INF)
			both += int(tank_at != Vector2.INF and not placements.is_empty())
			var actual: Dictionary = {}
			for i in placements.size():
				var placement := placements[i]
				check(placement.variant == repeat[i].variant and placement.position == repeat[i].position, "Variant/order/position deterministic")
				check(not actual.has(placement.variant) and attempt_by_variant.has(placement.variant), "Placed only once after successful roll")
				actual[placement.variant] = placement
				check(placement.position == attempt_by_variant[placement.variant].position, "Conflicts rejected without reroll/movement")
				placed_counts[placement.variant] += 1
				examples[placement.variant] = coordinate
				var at := placement.position
				check(at == at.round() and at.x >= 256 and at.x <= 768 and at.y >= 256 and at.y <= 768, "Integer positions and unchanged edge margins")
				check((at - common_half).x >= 32 and (at - common_half).y >= 32 and (at + common_half).x <= 992 and (at + common_half).y <= 992, "Whole art inside chunk")
				var center := Vector2(coordinate) * 1024 + at
				check(Vector2.ZERO.clamp(center - common_half, center + common_half).length() >= 300.0, "Whole footprint clears starting area")
				var bounds := Rect2(at - common_half, TerrainChunk.BUILDING_FOOTPRINT)
				if tank_at != Vector2.INF:
					check(not bounds.intersects(Rect2(tank_at - tank_half, tank_half * 2.0).grow(TerrainChunk.BUILDING_TANK_GAP)), "No tank overlap")
				for j in i:
					check(not bounds.intersects(Rect2(placements[j].position - common_half, TerrainChunk.BUILDING_FOOTPRINT).grow(TerrainChunk.BUILDING_GAP)), "No building/building overlap, including gap")
			# Every skipped successful roll must have a real safety conflict.
			for candidate in attempts:
				if actual.has(candidate.variant): continue
				var center := Vector2(coordinate) * 1024 + candidate.position
				var bounds := Rect2(candidate.position - common_half, TerrainChunk.BUILDING_FOOTPRINT)
				if Vector2.ZERO.clamp(center - common_half, center + common_half).length() < 300.0:
					skip_reasons.start_clearance += 1
				elif tank_at != Vector2.INF and bounds.intersects(Rect2(tank_at - tank_half, tank_half * 2.0).grow(TerrainChunk.BUILDING_TANK_GAP)):
					skip_reasons.tank_overlap += 1
				else:
					var blocked := false
					for previous in placements:
						if attempt_order[previous.variant] < attempt_order[candidate.variant] and bounds.intersects(Rect2(previous.position - common_half, TerrainChunk.BUILDING_FOOTPRINT).grow(TerrainChunk.BUILDING_GAP)):
							blocked = true
					check(blocked, "No unexplained rejected successful rolls")
					skip_reasons.building_overlap += 1
	check(tanks == 3523 and examples.size() == 4 and both > 0, "Tank frequency preserved and all sources used")
	check(placed_histogram[2] > 0, "Multiple ruins can appear together")
	for i in 4:
		check(attempt_counts[i] >= 2300 and attempt_counts[i] <= 2700, "Each source trends toward 25% per chunk")
	for mask in 16:
		var bits := 0
		for i in 4: bits += int((mask & (1 << i)) != 0)
		var expected := 10000 * pow(0.25, bits) * pow(0.75, 4 - bits)
		check(absf(roll_masks[mask] - expected) < maxf(10, 5.0 * sqrt(expected)), "Joint roll frequencies match independent Bernoulli draws")
	seed(481)
	var expected_random := randf()
	seed(481)
	TerrainChunk.get_building_placements(examples[0], 1024)
	check(randf() == expected_random, "No gameplay RNG consumption")
	check(TerrainChunk.get_building_placements(examples[0], 256).is_empty(), "Undersized chunk safely skips")
	for key: String in baseline.hashes:
		var parts := key.split(",")
		var coordinate := Vector2i(int(parts[0]), int(parts[1]))
		var data := TerrainChunk.generate_data(coordinate, 1024)
		check(digest(data.ground_cells) == baseline.hashes[key].ground, "Ground baseline unchanged")
		check(digest(data.decoration_cells) == baseline.hashes[key].decorations, "Decoration baseline unchanged")
		check(var_to_str(TerrainChunk.get_tank_position(coordinate, 1024)) == baseline.hashes[key].tank, "Tank baseline unchanged")
	var scene := preload("res://scenes/systems/terrain_chunk.tscn")
	var generated_counts: Array[int] = [0, 0, 0, 0]
	var generated_histogram: Array[int] = [0, 0, 0, 0, 0]
	for y in range(-16, 16):
		for x in range(-8, 8):
			var coordinate := Vector2i(x, y)
			var placements := TerrainChunk.get_building_placements(coordinate, 1024)
			var chunk := scene.instantiate() as TerrainChunk
			chunk.configure(coordinate, 1024)
			root.add_child(chunk)
			check(chunk.get_child_count() == 4 and chunk.large_props.z_index == 2 and chunk.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Same visual layer and filter")
			check(chunk.find_children("*", "CollisionObject2D", true, false).is_empty() and chunk.find_children("*", "CollisionShape2D", true, false).is_empty() and chunk.find_children("*", "NavigationRegion2D", true, false).is_empty(), "No physics/navigation")
			check(chunk.large_props.get_child_count() == placements.size() + int(chunk.large_props.has_node("TankWreck")), "Exactly the accepted ruins plus original tank")
			generated_histogram[placements.size()] += 1
			for placement in placements:
				var ruin := chunk.large_props.get_node("BuildingRuin%d" % (placement.variant + 1)) as Sprite2D
				generated_counts[placement.variant] += 1
				check(ruin.texture == TerrainChunk.BUILDING_TEXTURES[placement.variant] and ruin.position == placement.position and ruin.scale == Vector2(3, 3), "Shared source and exact transform")
				check(not ruin.flip_h and not ruin.flip_v and ruin.rotation == 0 and ruin.material == null and not ruin.is_processing() and not ruin.is_physics_processing(), "Static original art, no unique material")
			chunk.configure(coordinate, 1024)
			check(chunk.large_props.get_child_count() == placements.size() + int(chunk.large_props.has_node("TankWreck")), "No reconfiguration duplicates")
			chunk.configure(empty, 1024)
			check(chunk.large_props.get_child_count() == int(chunk.large_props.has_node("TankWreck")), "Old ruins removed on reconfiguration")
			chunk.free()
	for i in 4:
		for repeat_index in 2:
			var chunk := scene.instantiate() as TerrainChunk
			chunk.configure(examples[i], 1024)
			root.add_child(chunk)
			check((chunk.large_props.get_node("BuildingRuin%d" % (i + 1)) as Sprite2D).texture == TerrainChunk.BUILDING_TEXTURES[i], "All four sources reload")
			chunk.free()
	var placed_total := 0
	var attempted_total := 0
	var skipped_counts: Array[int] = []
	for i in 4:
		placed_total += placed_counts[i]
		attempted_total += attempt_counts[i]
		skipped_counts.append(attempt_counts[i] - placed_counts[i])
	check(attempted_total - placed_total == skip_reasons.start_clearance + skip_reasons.tank_overlap + skip_reasons.building_overlap, "Rejection accounting exact")
	var results := {"chunks": 10000, "attempt_counts": attempt_counts, "placed_counts": placed_counts,
		"skipped_counts": skipped_counts, "skip_reasons": skip_reasons, "total_successful_rolls": attempted_total,
		"placed": placed_total, "average_buildings_per_chunk": placed_total / 10000.0,
		"buildings_per_chunk_histogram": placed_histogram, "successful_rolls_per_chunk_histogram": roll_histogram,
		"roll_mask_counts": roll_masks, "tank_count": tanks, "both_count": both,
		"generated_chunks": 512, "generated_counts": generated_counts, "generated_histogram": generated_histogram}
	var file := FileAccess.open("res://docs/building_distribution.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	print("BUILDING_STATS ", JSON.stringify(results))
	print("PASS: ", checks, " independent-building checks; PNGs and 400 terrain/tank references unchanged")
	quit()
