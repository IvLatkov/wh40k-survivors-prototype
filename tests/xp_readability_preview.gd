extends SceneTree

const PICKUP := preload("res://scenes/pickups/xp_pickup.tscn")
const REWARDS := preload("res://tests/xp_pickup_visual_test.gd").REWARDS
var main: Node2D
var camera: Camera2D
var pickups: Array[XPPickup] = []

func _initialize() -> void:
	run.call_deferred()

func make_pickup(position: Vector2, tier: int, baseline: bool) -> XPPickup:
	var pickup := PICKUP.instantiate() as XPPickup
	pickup.configure(REWARDS[tier])
	pickup.position = position
	main.add_child(pickup)
	if baseline:
		pickup.visual.material = null
		pickup.visual.scale = Vector2.ONE
		pickup.get_node("Shadow").hide()
	pickups.append(pickup)
	return pickup

func run() -> void:
	root.size = Vector2i(1152, 648)
	main = preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	main.get_node("EnemySpawner").set_process(false)
	main.get_node("RunClock").set_process(false)
	main.get_node("ChunkManager").set_physics_process(false)
	main.get_node("ChunkManager").set_process(false)
	player.position = Vector2(10000, 10000)
	player.hide()
	main.get_node("HealthHUD").hide()
	camera = Camera2D.new()
	main.add_child(camera)
	camera.make_current()
	var args := OS.get_cmdline_user_args()
	var baseline := args.has("--baseline")
	if args.has("--visibility"):
		await visibility(baseline)
	else:
		await benchmark(100 if args.has("--100") else 200, baseline)
	main.queue_free()
	await process_frame
	await process_frame
	quit()

func label_at(position: Vector2, title: String) -> void:
	var label := Label.new()
	label.position = position
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	main.add_child(label)

func visibility(baseline: bool) -> void:
	var manager: ChunkManager = main.get_node("ChunkManager")
	var chosen: Array[Vector2] = []
	var names := ["DIRT", "ASH", "CRACKS", "ROCK", "CLUTTER"]
	var variants := [0, 1, 4, 2, -1]
	for site in 5:
		var best := Vector2.ZERO
		var best_score := -1000
		for chunk: TerrainChunk in manager.active_chunks.values():
			for cell in chunk.ground.get_used_cells():
				var position := chunk.position + Vector2(cell) * 32 + Vector2(16, 16)
				if absf(position.x) > 440 or absf(position.y) > 220: continue
				var close := false
				for previous in chosen:
					if previous.distance_to(position) < 165: close = true
				if close: continue
				var score := 0
				for x in range(-2, 3):
					if site == 4:
						for y in range(-1, 2):
							if chunk.decorations.get_cell_source_id(cell + Vector2i(x, y)) >= 0: score += 1
					elif int(chunk.ground.get_cell_atlas_coords(cell + Vector2i(x, 0)).x / 4.0) == variants[site]: score += 1
				if score > best_score:
					best_score = score
					best = position
		assert(best_score > 0, "Visible terrain patch must exist")
		chosen.append(best)
		for tier in 4:
			make_pickup(best + Vector2((tier - 1.5) * 28, 0), tier, baseline)
		label_at(best + Vector2(-56, 14), names[site] + "  L / M / H / B")
		print("VISIBILITY ", names[site], " position=", best, " patch_score=", best_score)
	label_at(Vector2(-530, -305), "XP readability | native camera zoom | " + ("BASELINE" if baseline else "POLISHED"))
	for frame in 150:
		if frame > 30: camera.position = Vector2(sin(frame / 25.0) * 35, cos(frame / 32.0) * 20)
		await process_frame
		if frame in [25, 120]:
			await RenderingServer.frame_post_draw
			var suffix := "_baseline" if baseline else "_polished"
			var path := OS.get_environment("TEMP").path_join("xp_readability" + suffix + ("_moving.png" if frame == 120 else "_still.png"))
			root.get_texture().get_image().save_png(path)
			print("CAPTURE ", path)

func benchmark(count: int, baseline: bool) -> void:
	seed(933)
	for index in count:
		make_pickup(Vector2((index % 20 - 9.5) * 48, (floori(index / 20.0) - (count / 20.0 - 1) * 0.5) * 48), index % 4, baseline)
	var intervals: Array[float] = []
	var resources_at_start := 0.0
	var nodes_at_start := 0.0
	var draw_calls := 0.0
	var start := Time.get_ticks_usec()
	for frame in 420:
		camera.position = Vector2(sin(frame / 70.0) * 36, cos(frame / 85.0) * 24)
		await process_frame
		var now := Time.get_ticks_usec()
		if frame >= 60: intervals.append((now - start) / 1000.0)
		start = now
		if frame == 60:
			resources_at_start = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
			nodes_at_start = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		draw_calls = maxf(draw_calls, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var sum := 0.0
	for interval in intervals: sum += interval
	intervals.sort()
	var mean := sum / intervals.size()
	print("XP BENCH count=", count, " baseline=", baseline, " mean_ms=", mean,
		" fps=", 1000.0 / mean, " p95_ms=", intervals[ceili(intervals.size() * 0.95) - 1], " worst_ms=", intervals.max(),
		" resource_delta=", Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT) - resources_at_start,
		" node_delta=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT) - nodes_at_start, " max_draw_calls=", draw_calls)
	var refs: Array[WeakRef] = []
	for pickup in pickups:
		refs.append(weakref(pickup))
		pickup.queue_free()
	pickups.clear()
	await process_frame
	await process_frame
	for reference in refs: assert(reference.get_ref() == null, "Stress pickup releases all nodes")
	print("PASS all ", count, " stress pickups freed")
