extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func capture(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func fill_terrain(parent: Node, center: Vector2i, radius: int = 1) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var chunk := preload("res://scenes/systems/terrain_chunk.tscn").instantiate() as TerrainChunk
			chunk.configure(Vector2i(x, y), 1024)
			parent.add_child(chunk)

func label_at(parent: Node, text: String, at: Vector2) -> void:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_outline_size", 4)
	parent.add_child(label)

func outline(parent: Node, bounds: Rect2, color: Color) -> void:
	var line := Line2D.new()
	line.width = 12.0
	line.default_color = color
	line.z_index = 100
	line.closed = true
	for corner in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		line.add_point(corner)
	parent.add_child(line)

func find_building(coordinate: Vector2i, variant: int) -> TerrainChunk.BuildingPlacement:
	for building in TerrainChunk.get_building_placements(coordinate, 1024):
		if building.variant == variant:
			return building
	return null

func run() -> void:
	seed(741)
	root.size = Vector2i(1280, 800)
	var overview := Node2D.new()
	root.add_child(overview)
	current_scene = overview
	var terrain := Node2D.new()
	terrain.z_index = -10
	overview.add_child(terrain)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * 0.125
	overview.add_child(camera)
	var tanks := 0
	var buildings := 0
	var variants: Array[int] = [0, 0, 0, 0]
	var histogram: Array[int] = [0, 0, 0, 0, 0]
	var scene := preload("res://scenes/systems/terrain_chunk.tscn")
	for y in range(-3, 3):
		for x in range(-5, 5):
			var coordinate := Vector2i(x, y)
			var chunk := scene.instantiate() as TerrainChunk
			chunk.configure(coordinate, 1024)
			terrain.add_child(chunk)
			var origin := Vector2(coordinate) * 1024
			var tank := chunk.large_props.get_node_or_null("TankWreck") as Sprite2D
			if tank != null:
				tanks += 1
				outline(overview, Rect2(origin + tank.position - Vector2(144, 144), Vector2(288, 288)), Color(1.0, 0.7, 0.2))
			var placements := TerrainChunk.get_building_placements(coordinate, 1024)
			histogram[placements.size()] += 1
			for building in placements:
				buildings += 1
				variants[building.variant] += 1
				outline(overview, Rect2(origin + building.position - TerrainChunk.BUILDING_FOOTPRINT * 0.5, TerrainChunk.BUILDING_FOOTPRINT), Color(0.25, 0.85, 1.0))
	var hud := CanvasLayer.new()
	overview.add_child(hud)
	label_at(hud, "60 NATURAL CHUNKS | %d TANKS (GOLD) | %d RUINS (CYAN) | PREVIEW MARKERS ONLY" % [tanks, buildings], Vector2(12, 12))
	print("BUILDING_PREVIEW chunks=60 tanks=", tanks, " buildings=", buildings, " variants=", variants, " histogram_0_to_4=", histogram)
	await capture("res://docs/building_terrain_overview.png")
	overview.queue_free()
	await process_frame
	var examples: Dictionary = {}
	var together := Vector2i.ZERO
	var together_found := false
	var together_variant := -1
	var multiple_coordinate := Vector2i.ZERO
	var multiple_found := false
	for y in range(-20, 20):
		for x in range(-20, 20):
			var coordinate := Vector2i(x, y)
			var placements := TerrainChunk.get_building_placements(coordinate, 1024)
			if placements.size() > 1 and not multiple_found:
				multiple_coordinate = coordinate
				multiple_found = true
			for building in placements:
				if not examples.has(building.variant): examples[building.variant] = coordinate
				var tank_at := TerrainChunk.get_tank_position(coordinate, 1024)
				if tank_at == Vector2.INF or together_found: continue
				var bounds := Rect2(building.position - TerrainChunk.BUILDING_FOOTPRINT * 0.5, TerrainChunk.BUILDING_FOOTPRINT).merge(Rect2(tank_at - Vector2(128, 128), Vector2(256, 256)))
				if bounds.size.x <= 1100 and bounds.size.y <= 620:
					together = coordinate
					together_variant = building.variant
					together_found = true
	assert(examples.size() == 4 and together_found)
	root.size = Vector2i(1536, 1024)
	var gallery := Node.new()
	root.add_child(gallery)
	for variant in 4:
		var container := SubViewportContainer.new()
		container.position = Vector2((variant % 2) * 768, (variant / 2) * 512)
		container.size = Vector2(768, 512)
		container.stretch = true
		gallery.add_child(container)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(768, 512)
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(viewport)
		var holder := Node2D.new()
		holder.z_index = -10
		viewport.add_child(holder)
		var coordinate: Vector2i = examples[variant]
		fill_terrain(holder, coordinate)
		var building := find_building(coordinate, variant)
		var view_camera := Camera2D.new()
		view_camera.position = Vector2(coordinate) * 1024 + building.position
		viewport.add_child(view_camera)
		label_at(container, "%s | NATURAL CHUNK %s | 3x NEAREST" % [TerrainChunk.BUILDING_TEXTURES[variant].resource_path.get_file(), coordinate], Vector2(12, 12))
	await capture("res://docs/building_variants.png")
	gallery.queue_free()
	await process_frame
	assert(multiple_found)
	root.size = Vector2i(1280, 1024)
	var multi_world := Node2D.new()
	root.add_child(multi_world)
	current_scene = multi_world
	var multi_terrain := Node2D.new()
	multi_terrain.z_index = -10
	multi_world.add_child(multi_terrain)
	fill_terrain(multi_terrain, multiple_coordinate)
	var multi_placements := TerrainChunk.get_building_placements(multiple_coordinate, 1024)
	var multi_bounds := Rect2(Vector2(multiple_coordinate) * 1024 + multi_placements[0].position - TerrainChunk.BUILDING_FOOTPRINT * 0.5, TerrainChunk.BUILDING_FOOTPRINT)
	for placement in multi_placements:
		multi_bounds = multi_bounds.merge(Rect2(Vector2(multiple_coordinate) * 1024 + placement.position - TerrainChunk.BUILDING_FOOTPRINT * 0.5, TerrainChunk.BUILDING_FOOTPRINT))
	var multi_camera := Camera2D.new()
	multi_camera.position = multi_bounds.get_center()
	multi_world.add_child(multi_camera)
	var multi_hud := CanvasLayer.new()
	multi_world.add_child(multi_hud)
	label_at(multi_hud, "NATURAL MULTI-RUIN CHUNK %s | %d RUINS | NO PROBABILITY OR PLACEMENT OVERRIDES" % [multiple_coordinate, multi_placements.size()], Vector2(12, 12))
	print("MULTIPLE_PREVIEW coordinate=", multiple_coordinate, " count=", multi_placements.size())
	await capture("res://docs/building_multiple.png")
	multi_world.queue_free()
	await process_frame
	root.size = Vector2i(1280, 800)
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
	var placement := find_building(together, together_variant)
	var center := Vector2(together) * 1024 + placement.position
	var tank_center := Vector2(together) * 1024 + TerrainChunk.get_tank_position(together, 1024)
	player.position = center + Vector2(-45, 30)
	manager.update_chunks()
	manager.set_physics_process(false)
	manager.set_process(false)
	var combined := Rect2(center - TerrainChunk.BUILDING_FOOTPRINT * 0.5, TerrainChunk.BUILDING_FOOTPRINT).merge(Rect2(tank_center - Vector2(128, 128), Vector2(256, 256)))
	var detail_camera := player.get_node("Camera2D") as Camera2D
	detail_camera.position_smoothing_enabled = false
	detail_camera.drag_horizontal_enabled = false
	detail_camera.drag_vertical_enabled = false
	detail_camera.position = combined.get_center() - player.position
	detail_camera.reset_smoothing()
	detail_camera.force_update_scroll()
	spawner._spawn_enemy(center + Vector2(-90, 40))
	spawner._spawn_enemy(center + Vector2(60, 80), spawner.tier_2_enemy_scene)
	for enemy in spawner.spatial_grid._enemies: enemy.set_physics_process(false)
	var rewards: Array[XPReward] = [
		preload("res://assets/art/effects/xp/low_level/xp_reward.tres"),
		preload("res://assets/art/effects/xp/mid_level/xp_reward.tres"),
		preload("res://assets/art/effects/xp/high_level/xp_reward.tres"),
		preload("res://assets/art/effects/xp/boss/xp_reward.tres")]
	for i in 4:
		var pickup := preload("res://scenes/pickups/xp_pickup.tscn").instantiate() as XPPickup
		pickup.configure(rewards[i])
		pickup.position = center + Vector2(135, -90 + i * 45)
		main.add_child(pickup)
	var bolt := preload("res://scenes/projectiles/bolt_projectile.tscn").instantiate() as BoltProjectile
	bolt.monitoring = false
	bolt.position = center + Vector2(105, -25)
	bolt.set_direction(Vector2.RIGHT)
	main.add_child(bolt)
	bolt.set_physics_process(false)
	# Let the real HUD FPS window settle after the heavy multi-viewport gallery.
	await create_timer(2.0).timeout
	print("READABILITY natural_coexistence_chunk=", together, " building_variant=", placement.variant)
	await capture("res://docs/building_readability.png")
	main.queue_free()
	await process_frame
	await process_frame
	quit()
