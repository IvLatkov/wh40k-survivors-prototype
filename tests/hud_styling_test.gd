extends SceneTree

var checks: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok, message)

func capture(suffix: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.15, true).timeout
	await RenderingServer.frame_post_draw
	var base := OS.get_environment("WH40K_HUD_CAPTURE_PATH")
	if not base.is_empty():
		var path := base.get_basename() + suffix + ".png"
		check(root.get_texture().get_image().save_png(path) == OK, "HUD preview saves")
		print("HUD preview: ", path)

func check_layout(hud: HealthHud) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	var timer_frame: Control = hud.get_node("HUD/TimerFrame")
	var vitals: Control = hud.get_node("HUD/VitalsFrame")
	var counters: Control = hud.get_node("HUD/PerformanceLabel/Frame")
	for control: Control in [timer_frame, vitals, counters, hud.health_label, hud.health_bar, hud.xp_label, hud.xp_bar]:
		check(bounds.encloses(control.get_global_rect()), "HUD element stays inside viewport: " + str(control.name))
	check(not timer_frame.get_global_rect().intersects(counters.get_global_rect()), "Timer and counters never overlap")
	check(is_equal_approx(timer_frame.get_global_rect().get_center().x, root.size.x * 0.5), "Timer remains centered")
	check(is_equal_approx(vitals.get_global_rect().get_center().x, root.size.x * 0.5), "Vitals remain centered")
	check(hud.xp_bar.get_global_rect().end.y < hud.health_label.get_global_rect().position.y, "XP and HP displays do not overlap")
	for label: Label in [hud.health_label, hud.xp_label, hud.performance_label, hud.run_timer_label]:
		var text_width := label.get_theme_font("font").get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		check(text_width <= label.size.x, "Complete HUD text fits: " + str(label.name))
	for label: Label in [hud.health_label, hud.xp_label]:
		var icon: TextureRect = label.get_node("Icon")
		var text_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
		check(icon.size == Vector2(16, 16) and icon.get_global_rect().end.x + 6 <= label.get_global_rect().get_center().x - text_width * 0.5, "Native-size icon has space beside centered text")
		check(vitals.get_global_rect().encloses(label.get_global_rect()), "Vital label fits inside frame")
	check(vitals.get_global_rect().encloses(hud.health_bar.get_global_rect()) and vitals.get_global_rect().encloses(hud.xp_bar.get_global_rect()), "Both bars fit inside frame")

func run() -> void:
	root.size = Vector2i(1152, 648)
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var hud: HealthHud = main.get_node("HealthHUD")
	var player: Player = main.get_node("Player")
	var clock: RunClock = main.get_node("RunClock")
	var info = main.get_node("CharacterInfoPanel")
	var spawner: EnemySpawner = main.get_node("EnemySpawner")
	spawner.set_process(false)
	clock.set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	await process_frame
	await process_frame
	var ui: Control = hud.get_node("HUD")
	check(ui.theme == preload("res://resources/ui/hud_theme.tres") and ui.theme != preload("res://resources/ui/character_info_theme.tres"), "HUD has its own local theme")
	check(ui.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "HUD uses crisp nearest filtering")
	check(ProjectSettings.get_setting("gui/theme/custom", "") == "", "No global theme assignment")
	check(hud.health_bar.step == 0 and hud.xp_bar.step == 0 and not hud.health_bar.show_percentage and not hud.xp_bar.show_percentage, "Fractional bar values and original labels preserved")
	for bar: ProgressBar in [hud.health_bar, hud.xp_bar]:
		var fill := bar.get_theme_stylebox("fill") as StyleBoxTexture
		check(fill != null and fill.axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_TILE, "Native segmented fill tiles without stretching")
		check(bar.get_theme_stylebox("background") is StyleBoxTexture, "Pack bar track is used")
	for node in ui.find_children("*", "Control", true, false):
		if node == hud.death_label:
			continue # Preserve terminal-overlay input behavior.
		check(node.mouse_filter == Control.MOUSE_FILTER_IGNORE and node.focus_mode == Control.FOCUS_NONE, "HUD decoration does not capture menu/gameplay input")
	check(hud.health_label.text == "HP 50 / 50" and hud.health_bar.value == 50 and hud.health_bar.max_value == 50, "Production health binding unchanged")
	check(hud.xp_label.text == "LEVEL 1    XP 0 / 8" and hud.xp_bar.value == 0 and hud.xp_bar.max_value == 8, "Production XP binding unchanged")
	check(hud.run_timer_label.text == "00:00" and not hud.death_label.visible, "Fresh run timer and death state unchanged")
	check_layout(hud)
	await capture("_fresh")
	player.take_damage(12.75)
	check(is_equal_approx(hud.health_bar.value, player.current_health) and hud.health_label.text == "HP 37 / 50", "Damage retains fractional bar and original HP rounding")
	player.add_xp(3.5)
	check(hud.xp_bar.value == 3.5 and hud.xp_label.text == "LEVEL 1    XP 3 / 8", "Fractional XP and label rounding unchanged")
	clock._process(97.0)
	check(hud.run_timer_label.text == "01:37", "Real RunClock signal still updates formatted time")
	await capture("_damaged")
	info.open_panel()
	check(paused and info.visible, "Character Info opens and owns pause")
	var paused_text := hud.run_timer_label.text
	clock.set_process(true)
	await create_timer(0.06, true).timeout
	check(hud.run_timer_label.text == paused_text and clock.elapsed_time == 97.0, "Normal pause still freezes run time")
	clock.set_process(false)
	info.close_panel()
	check(not paused and not info.visible, "Closing Character Info restores gameplay")
	spawner.get_active_enemy_count() # Exercise the unchanged performance binding.
	hud._update_performance_counters()
	check(hud.performance_label.text.contains("Enemies: 0 / "), "Performance counters retain their normal values")
	hud.show_performance_counters = false
	hud.bind_enemy_spawner(spawner)
	check(not hud.performance_label.get_node("Frame").is_visible_in_tree(), "Disabling counters hides their frame too")
	await capture("_no_counters")
	hud.performance_label.show()
	player.combat_stats.add_modifier(&"max_health", 0.5)
	check(hud.health_bar.max_value == 75 and hud.health_bar.value == player.current_health, "Upgraded maximum HP reaches existing binding")
	# Large display fixture exercises text fit without changing production formulas.
	hud._on_player_xp_changed(999.75, 1000, 100)
	hud._on_run_seconds_changed(3601)
	for size in [Vector2i(1152, 648), Vector2i(1600, 900), Vector2i(800, 600), Vector2i(640, 480)]:
		root.size = size
		await process_frame
		await process_frame
		check_layout(hud)
		await capture("_%dx%d" % [size.x, size.y])
	root.size = Vector2i(1152, 648)
	await process_frame
	player.damage_invulnerability_timer.stop()
	player.take_damage(1000)
	check(paused and hud.death_label.visible and hud.death_label.text == "YOU DIED" and hud.health_bar.value == 0, "Production death still shows original message and terminal pause")
	await capture("_death")
	paused = false
	main.queue_free()
	await process_frame
	print("PASS: %d HUD styling checks" % checks)
	quit(0)
