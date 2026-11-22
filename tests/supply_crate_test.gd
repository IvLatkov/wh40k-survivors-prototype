extends SceneTree

const MAIN := preload("res://scenes/main.tscn")
var checks: int = 0
var main: Node2D
var player: Player
var rewards: UpgradeSystem
var encounter: SupplyCrateEncounter
var clock: RunClock


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error(message)
		quit(1)
		assert(value, message)


func fresh_run() -> void:
	if is_instance_valid(main):
		main.queue_free()
		await process_frame
		await process_frame
	paused = false
	main = MAIN.instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	player = main.get_node("Player")
	rewards = main.get_node("UpgradeSystem")
	encounter = main.get_node("SupplyCrateEncounter")
	clock = main.get_node("RunClock")
	clock.set_process(false)
	main.get_node("EnemySpawner").set_process(false)
	main.get_node("ChunkManager").set_process(false)
	main.get_node("ChunkManager").set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	await physics_frame
	await process_frame


func choose_first() -> void:
	check(not rewards.offered.is_empty(), "A normal upgrade is offered")
	var button := main.get_node("UpgradeMenu").choices_container.get_child(0) as Button
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await process_frame
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame
	await process_frame
	await process_frame


func capture(suffix: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.15, true).timeout
	await RenderingServer.frame_post_draw
	var base := OS.get_environment("WH40K_CRATE_CAPTURE_PATH")
	if not base.is_empty():
		check(root.get_texture().get_image().save_png(base.get_basename() + suffix + ".png") == OK, "Crate preview saved")


func run() -> void:
	root.size = Vector2i(1152, 648)
	await fresh_run()
	clock.advance_to(299.999)
	check(not encounter.supply_crate_spawned and not is_instance_valid(encounter.crate), "No crate before 5:00")
	var first_candidate := encounter.find_spawn_position()
	var enemy_body := StaticBody2D.new()
	enemy_body.collision_layer = 2
	var enemy_shape := CollisionShape2D.new()
	var enemy_circle := CircleShape2D.new()
	enemy_circle.radius = 40
	enemy_shape.shape = enemy_circle
	enemy_body.add_child(enemy_shape)
	main.add_child(enemy_body)
	enemy_body.global_position = first_candidate
	await physics_frame
	await process_frame
	check(encounter.find_spawn_position().distance_to(first_candidate) > 68, "Placement avoids an occupied enemy-layer location")
	enemy_body.queue_free()
	await physics_frame
	await process_frame
	var random_state := seed_and_get_random()
	var spawn_started := Time.get_ticks_usec()
	clock.advance_to(300)
	print("SUPPLY_PLACEMENT clear_tick_usec=", Time.get_ticks_usec() - spawn_started)
	check(randf() == random_state, "Crate placement consumes no shared gameplay RNG")
	check(encounter.supply_crate_spawned and is_instance_valid(encounter.crate), "Exactly one crate spawns at 5:00")
	var crate := encounter.crate
	var distance := crate.global_position.distance_to(player.global_position)
	check(distance >= 250 and distance <= 400, "Crate is near the player but outside their body")
	var chunks: ChunkManager = main.get_node("ChunkManager")
	check(chunks.active_chunks.has(chunks.get_chunk_coordinate(crate.global_position)), "Crate is on loaded terrain")
	check(crate.collision_layer == 0 and crate.collision_mask == 1 and crate.find_children("*", "PhysicsBody2D", true, false).is_empty(), "Crate is detection-only, with no solid obstacle")
	for _repeat in 5:
		clock.seconds_changed.emit(300)
		clock.advance_to(301)
	check(main.find_children("*", "SupplyCrate", true, false).size() == 1 and encounter.crate == crate, "Repeated milestones never create duplicates")
	await capture("_world")
	var before_level := player.level
	var before_xp := player.xp
	var before_required := player.get_xp_required()
	var collections: Array[int] = [0]
	crate.collected.connect(func(): collections[0] += 1)
	crate.body_entered.connect(func(body: Node2D):
		crate._on_body_entered(body)
		crate._on_body_entered(body)
	)
	player.global_position = crate.global_position
	await physics_frame
	await process_frame
	await create_timer(0.08, true).timeout
	check(collections[0] == 1 and not is_instance_valid(crate), "Real player overlap collects exactly once and removes the crate")
	check(paused and rewards.is_supply_reward() and main.get_node("UpgradeMenu").visible, "Collection uses the shared paused reward queue")
	var content := main.get_node("UpgradeMenu/Overlay/Center/Panel/Margin/Content")
	check(content.get_node("Title").text == "SUPPLY CRATE" and content.get_node("Subtitle").visible and content.get_node("Subtitle").text == "Choose Requisition", "Reused UI clearly identifies the supply reward")
	check(rewards.offered.size() == 3 and rewards.offered_ultimates.is_empty(), "Three normal choices, no crate evolution")
	var ids: Dictionary = {}
	for definition in rewards.offered:
		check(rewards.can_select_upgrade(definition), "Offered crate upgrade follows normal eligibility")
		ids[definition.id] = true
	check(ids.size() == 3, "All three options are unique")
	await capture("_reward")
	var selected_definition := rewards.offered[0]
	var selected := selected_definition.id
	var before_modifier := player.combat_stats.get_modifier(selected_definition.stat)
	await choose_first()
	check(int(rewards.levels.get(selected, 0)) == 1 and not paused and not main.get_node("UpgradeMenu").visible, "One selected upgrade applies and the owned pause releases")
	check(player.combat_stats.get_modifier(selected_definition.stat) > before_modifier, "The selected upgrade actually modifies the normal combat stat")
	rewards.select_upgrade(selected)
	check(int(rewards.levels.get(selected, 0)) == 1, "Repeated selection cannot grant a second reward")
	check(player.level == before_level and player.xp == before_xp and player.get_xp_required() == before_required, "Crate never changes level, XP or XP progression")
	clock.seconds_changed.emit(300)
	check(not is_instance_valid(encounter.crate), "Collected crate never respawns")
	# Reuse normal ownership/cap logic, including maxed types occupying slots.
	await fresh_run()
	for category: UpgradeDefinition.Category in [UpgradeDefinition.Category.WEAPON, UpgradeDefinition.Category.GENERIC]:
		var owned := 0
		for definition in rewards.definitions:
			if definition.category == category and owned < 4:
				rewards.levels[definition.id] = 1
				owned += 1
	var maxed := rewards.get_eligible_upgrades()[0]
	rewards.levels[maxed.id] = maxed.get_max_level()
	var eligible := rewards.get_eligible_upgrades()
	rewards.queue_supply_reward()
	check(rewards.offered.size() == mini(3, eligible.size()), "Crate offers up to three eligible remaining choices")
	for definition in rewards.offered:
		check(definition in eligible and int(rewards.levels.get(definition.id, 0)) > 0 and definition != maxed, "Full slots reject new types and maxed upgrades stay excluded")
	await choose_first()
	# Chapter reward and normal level-up remain ordered alongside a free crate.
	await fresh_run()
	player.level = 10
	rewards.queue_level()
	rewards.queue_supply_reward()
	check(rewards.reward_levels == [10, 0] and main.get_node("ChapterPerkMenu").visible, "Crate queues behind a Chapter perk without a second modal")
	rewards.select_chapter_perk(rewards.chapter_offered[0].id)
	await process_frame
	await process_frame
	check(paused and rewards.is_supply_reward() and main.get_node("UpgradeMenu").visible and not main.get_node("ChapterPerkMenu").visible, "Chapter selection hands the owned pause to the crate reward")
	player.level = 11
	rewards.queue_level()
	await choose_first()
	check(paused and not rewards.is_supply_reward() and rewards.pending_levels == 1, "Crate hands pause to the next normal level reward")
	check(content == null or not is_instance_valid(content), "Previous run UI was freed")
	check(main.get_node("UpgradeMenu/Overlay/Center/Panel/Margin/Content/Title").text.begins_with("LEVEL UP"), "Normal reward title is restored after crate")
	await choose_first()
	check(not paused, "Mixed queue resumes only after every reward")
	main.get_node("CharacterInfoPanel").open_panel()
	check(paused, "Character Info owns its pause")
	rewards.queue_supply_reward()
	check(not main.get_node("CharacterInfoPanel").visible and paused, "Crate safely takes pause ownership from Character Info")
	await choose_first()
	check(not paused, "Character Info handoff does not strand the run paused")
	paused = true
	rewards.queue_supply_reward()
	await choose_first()
	check(paused, "Finishing a crate preserves an unrelated pre-existing pause")
	paused = false
	# Exhausted normal pool does not offer an evolution or strand an empty modal.
	for definition in rewards.definitions:
		rewards.levels[definition.id] = definition.get_max_level()
	check(not rewards.get_eligible_ultimates().is_empty(), "Fixture has unlocked existing Ultimates")
	rewards.queue_supply_reward()
	check(rewards.pending_levels == 0 and rewards.offered_ultimates.is_empty() and not paused and not main.get_node("UpgradeMenu").visible, "No eligible normal upgrades safely skips the empty reward, without evolving a weapon")
	# An all-blocked loaded area retries rather than spawning inside a solid.
	await fresh_run()
	var solid := StaticBody2D.new()
	solid.collision_layer = TerrainObstacles.COLLISION_LAYER
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 1000
	shape.shape = circle
	solid.add_child(shape)
	main.add_child(solid)
	solid.global_position = player.global_position
	await physics_frame
	await process_frame
	var blocked_started := Time.get_ticks_usec()
	clock.advance_to(300)
	print("SUPPLY_PLACEMENT fully_blocked_tick_usec=", Time.get_ticks_usec() - blocked_started)
	check(not encounter.supply_crate_spawned, "Blocked terrain produces no unsafe crate")
	solid.queue_free()
	await physics_frame
	await process_frame
	clock.advance_to(301)
	check(encounter.supply_crate_spawned, "Next clock tick retries safely after space becomes available")
	clock.advance_to(600)
	await process_frame
	check(encounter.milestone_closed and not is_instance_valid(encounter.crate), "Boss milestone removes an uncollected crate")
	check(main.get_node("BossEncounter").warboss_spawned and not main.get_node("EnemySpawner").normal_spawning_enabled, "Real boss still spawns and normal spawning stops")
	# F10 goes directly to the real boss, closing the crate window before any spawn.
	await fresh_run()
	var skip := InputEventKey.new()
	skip.keycode = KEY_F10
	skip.pressed = true
	main._unhandled_key_input(skip)
	main._unhandled_key_input(skip)
	clock.seconds_changed.emit(300)
	check(encounter.milestone_closed and not encounter.supply_crate_spawned and not is_instance_valid(encounter.crate), "F10 and stale milestone notifications never create a crate")
	check(main.find_children("*", "Warboss", true, false).size() == 1, "Repeated F10 creates exactly one real Warboss")
	var boss: Warboss = main.get_node("BossEncounter").boss
	boss.set_physics_process(false)
	rewards.queue_supply_reward()
	boss.take_damage(100000)
	rewards.select_upgrade(&"armor")
	check(paused and rewards.run_ended and rewards.pending_levels == 0 and not main.get_node("UpgradeMenu").visible, "Victory closes crate reward and stale selection cannot unpause")
	await fresh_run()
	rewards.queue_supply_reward()
	var death_choice := rewards.offered[0].id
	player.take_damage(100000)
	rewards.select_upgrade(death_choice)
	check(paused and rewards.run_ended and rewards.pending_levels == 0 and not rewards.levels.has(death_choice) and not main.get_node("UpgradeMenu").visible, "Death cancels crate selection without applying an upgrade or unpausing")
	main.queue_free()
	await process_frame
	await process_frame
	paused = false
	await create_timer(0.1).timeout
	print("PASS: ", checks, " supply crate milestone / placement / overlap / reward / pause / F10 / boss checks")
	quit(0)


func seed_and_get_random() -> float:
	seed(45678)
	var value := randf()
	seed(45678)
	return value
