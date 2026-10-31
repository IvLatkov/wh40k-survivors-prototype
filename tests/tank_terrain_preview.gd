extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func run() -> void:
	root.size = Vector2i(1280, 800)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var terrain := Node2D.new()
	terrain.z_index = -10
	world.add_child(terrain)
	var camera := Camera2D.new()
	camera.position = Vector2(0, 0)
	camera.zoom = Vector2.ONE * 0.125
	world.add_child(camera)
	var scene := preload("res://scenes/systems/terrain_chunk.tscn")
	var tanks := 0
	var detail_coordinate := Vector2i.ZERO
	var detail_distance := INF
	for y in range(-3, 3):
		for x in range(-5, 5):
			var coordinate := Vector2i(x, y)
			var chunk := scene.instantiate() as TerrainChunk
			chunk.configure(coordinate, 1024)
			terrain.add_child(chunk)
			tanks += chunk.large_props.get_child_count()
			if chunk.large_props.get_child_count() == 1:
				var tank_world := Vector2(coordinate) * 1024 + TerrainChunk.get_tank_position(coordinate, 1024)
				var marker := Line2D.new()
				marker.width = 16.0
				marker.default_color = Color(1.0, 0.7, 0.2)
				marker.z_index = 100
				marker.closed = true
				for corner: Vector2 in [Vector2(-160, -160), Vector2(160, -160), Vector2(160, 160), Vector2(-160, 160)]:
					marker.add_point(tank_world + corner)
				world.add_child(marker)
				var distance := Vector2(coordinate).length_squared()
				if distance < detail_distance:
					detail_coordinate = coordinate
					detail_distance = distance
	assert(tanks > 0)
	print("PREVIEW chunks=60 tanks=", tanks, " frequency_percent=", tanks * 100.0 / 60.0)
	# Preview-only annotations: highlight the naturally placed tank, not extra props.
	var overlay := CanvasLayer.new()
	world.add_child(overlay)
	var label := Label.new()
	label.position = Vector2(12, 12)
	label.text = "60 GENERATED CHUNKS | %d TANKS (%0.2f%%) | %.0f%% CHANCE PER CHUNK" % [tanks, tanks * 100.0 / 60.0, TerrainChunk.TANK_CHANCE * 100.0]
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_outline_size", 4)
	overlay.add_child(label)
	await capture("res://docs/tank_terrain_overview.png")
	world.queue_free()
	await process_frame
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	var manager: ChunkManager = main.get_node("ChunkManager")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	spawner.set_process(false)
	main.get_node("RunClock").set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	var center := Vector2(detail_coordinate) * 1024 + TerrainChunk.get_tank_position(detail_coordinate, 1024)
	# Intentional test overlap demonstrates that actors stay above the tank.
	player.position = center + Vector2(-20, -20)
	manager.update_chunks()
	manager.set_process(false)
	manager.set_physics_process(false)
	var detail_camera := player.get_node("Camera2D") as Camera2D
	detail_camera.position_smoothing_enabled = false
	detail_camera.drag_horizontal_enabled = false
	detail_camera.drag_vertical_enabled = false
	detail_camera.reset_smoothing()
	detail_camera.force_update_scroll()
	spawner._spawn_enemy(center + Vector2(35, 55))
	spawner._spawn_enemy(center + Vector2(55, -40), spawner.tier_2_enemy_scene)
	for enemy in spawner.spatial_grid._enemies:
		enemy.set_physics_process(false)
	var rewards: Array[XPReward] = [
		preload("res://assets/art/effects/xp/low_level/xp_reward.tres"),
		preload("res://assets/art/effects/xp/mid_level/xp_reward.tres"),
		preload("res://assets/art/effects/xp/high_level/xp_reward.tres"),
		preload("res://assets/art/effects/xp/boss/xp_reward.tres")]
	for i in rewards.size():
		var pickup := preload("res://scenes/pickups/xp_pickup.tscn").instantiate() as XPPickup
		pickup.configure(rewards[i])
		pickup.position = center + Vector2(90, -75 + i * 45)
		main.add_child(pickup)
	for frame in 90:
		await process_frame
	await capture("res://docs/tank_terrain_detail.png")
	main.queue_free()
	await process_frame
	await process_frame
	quit()
