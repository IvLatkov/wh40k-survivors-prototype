extends SceneTree

const BASELINE_PATH := "res://tests/decoration_distribution_baseline.json"
const TARGET_INDEX := 3
const SAMPLE_SIDE := 20

func _initialize() -> void:
	run.call_deferred()

func digest(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func run() -> void:
	var record := OS.get_cmdline_user_args().has("--record-baseline")
	var baseline: Dictionary = {}
	if record:
		assert(is_equal_approx(TerrainChunk.DECORATION_CHANCES[TARGET_INDEX], 0.020 * TerrainChunk.DECORATION_NORMALIZATION), "Record only the actual old distribution")
	else:
		baseline = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
		assert(TerrainChunk.DECORATION_FILES == baseline.files)
		for i in TerrainChunk.DECORATION_FILES.size():
			var expected: float = baseline.chances[i] * (0.35 if i == TARGET_INDEX else 1.0)
			assert(is_equal_approx(TerrainChunk.DECORATION_CHANCES[i], expected), "Only tile 4 probability decreases, by 65%")
	var total_probability := 0.0
	for chance in TerrainChunk.DECORATION_CHANCES:
		assert(chance > 0.0)
		# Every category begins exactly where the previous one ends.
		var next := total_probability + chance
		assert(next > total_probability and next <= 1.0)
		total_probability = next
	var counts: Array[int] = []
	counts.resize(TerrainChunk.DECORATION_FILES.size())
	counts.fill(0)
	var hashes: Dictionary = {}
	var preview_cells: Array = []
	var preview_counts: Array[int] = []
	preview_counts.resize(counts.size())
	preview_counts.fill(0)
	for y in range(-SAMPLE_SIDE / 2, SAMPLE_SIDE / 2):
		for x in range(-SAMPLE_SIDE / 2, SAMPLE_SIDE / 2):
			var coordinate := Vector2i(x, y)
			var key := "%d,%d" % [x, y]
			var data := TerrainChunk.generate_data(coordinate, 1024)
			var entry := {"ground": digest(data.ground_cells), "decorations": digest(data.decoration_cells), "tank": var_to_str(TerrainChunk.get_tank_position(coordinate, 1024))}
			hashes[key] = entry
			for cell in data.decoration_cells:
				assert(cell.z >= 0 and cell.z < counts.size())
				counts[cell.z] += 1
				if coordinate == Vector2i.ZERO:
					preview_cells.append([cell.x, cell.y, cell.z, cell.w])
					preview_counts[cell.z] += 1
			if not record:
				assert(entry.ground == baseline.hashes[key].ground, "Ground stays byte-identical across the full 400-chunk sample")
				# Historical baseline uses 20%; a higher tank chance may add props.
				# Existing baseline tanks must retain their exact positions.
				if baseline.hashes[key].tank != var_to_str(Vector2.INF):
					assert(entry.tank == baseline.hashes[key].tank, "Previously placed tanks keep identical positions")
				var repeat := TerrainChunk.generate_data(coordinate, 1024)
				assert(data.ground_cells == repeat.ground_cells and data.decoration_cells == repeat.decoration_cells, "Reload determinism")
				var incremental := TerrainChunk.Generation.new(coordinate, 1024)
				while not incremental.is_complete(): incremental.generate_row()
				assert(data.ground_cells == incremental.data.ground_cells and data.decoration_cells == incremental.data.decoration_cells, "Incremental generation matches")
	for count in counts: assert(count > 0, "Every active decoration still appears")
	var cells := SAMPLE_SIDE * SAMPLE_SIDE * 1024
	var result := {"chunks": SAMPLE_SIDE * SAMPLE_SIDE, "cells": cells, "files": TerrainChunk.DECORATION_FILES,
		"chances": TerrainChunk.DECORATION_CHANCES, "counts": counts, "hashes": hashes,
		"preview_cells": preview_cells, "preview_counts": preview_counts, "total_probability": total_probability}
	var path := BASELINE_PATH if record else "res://docs/decoration_distribution_after.json"
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "  "))
	print("DISTRIBUTION baseline=", record, " chunks=", result.chunks, " cells=", cells, " total_probability=", total_probability)
	for i in counts.size():
		print(TerrainChunk.DECORATION_FILES[i], " count=", counts[i], " percent_of_cells=", counts[i] * 100.0 / cells)
	if not record:
		var observed_ratio := float(counts[TARGET_INDEX]) / float(baseline.counts[TARGET_INDEX])
		assert(observed_ratio > 0.30 and observed_ratio < 0.40, "Observed target frequency decreases approximately 60-70%")
		print("OBSERVED target_ratio=", observed_ratio, " reduction_percent=", (1.0 - observed_ratio) * 100.0)
		if OS.get_cmdline_user_args().has("--capture"):
			assert(DisplayServer.get_name() != "headless")
			await preview(baseline)
	print("PASS decoration distribution / probability intervals / ground / tanks / determinism")
	quit()

func preview(baseline: Dictionary) -> void:
	root.size = Vector2i(1280, 800)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	camera.position = Vector2(0, 512)
	camera.zoom = Vector2.ONE * 0.6
	world.add_child(camera)
	var scene := preload("res://scenes/systems/terrain_chunk.tscn")
	var overlay := CanvasLayer.new()
	world.add_child(overlay)
	for side in 2:
		var holder := Node2D.new()
		holder.position = Vector2(-1040 if side == 0 else 16, 0)
		holder.z_index = -10
		world.add_child(holder)
		var data := TerrainChunk.generate_data(Vector2i.ZERO, 1024)
		if side == 0:
			data.decoration_cells.clear()
			for values: Array in baseline.preview_cells:
				data.decoration_cells.append(Vector4i(int(values[0]), int(values[1]), int(values[2]), int(values[3])))
		var target_count := 0
		for cell in data.decoration_cells:
			target_count += int(cell.z == TARGET_INDEX)
		var chunk := scene.instantiate() as TerrainChunk
		chunk.configure(Vector2i.ZERO, 1024, data)
		holder.add_child(chunk)
		var label := Label.new()
		label.position = Vector2(16 if side == 0 else 650, 32)
		label.text = ("BEFORE" if side == 0 else "AFTER") + " | TILE 4: %d | SAME CHUNK (0,0)" % target_count
		label.add_theme_font_size_override("font_size", 20)
		overlay.add_child(label)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/decoration_weight_preview.png")
	world.queue_free()
	await process_frame
	await process_frame
