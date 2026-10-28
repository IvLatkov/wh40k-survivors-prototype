extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var stress := OS.get_cmdline_user_args().has("--stress")
	if stress:
		var spawner: EnemySpawner = main.get_node("EnemySpawner")
		for index in 200:
			spawner._spawn_enemy(Vector2.from_angle(index * TAU / 200.0) * (500.0 + index % 5 * 35.0))
	for frame in 180:
		await physics_frame
	await RenderingServer.frame_post_draw
	print("Rendered preview: FPS=", Engine.get_frames_per_second(), "; enemies=", main.get_node("EnemySpawner").get_active_enemy_count(), "; active chunks=", main.get_node("ChunkManager").active_chunks.size())
	root.get_texture().get_image().save_png("res://tests/terrain_stress_preview.png" if stress else "res://tests/terrain_preview.png")
	main.queue_free()
	await process_frame
	quit()
