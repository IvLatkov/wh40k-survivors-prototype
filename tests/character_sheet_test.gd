extends SceneTree

var checks: int = 0
var system: UpgradeSystem
var all_definitions: Array[UpgradeDefinition]

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func capture(suffix: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.15, true).timeout
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("WH40K_SHEET_CAPTURE_PATH")
	if not output.is_empty():
		check(root.get_texture().get_image().save_png(output.get_basename() + suffix + ".png") == OK, "Character Info preview saves")
		print("Character Info preview: ", output.get_basename() + suffix + ".png")

func key(action: StringName) -> void:
	for down: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame

func check_stat_rows(panel: CanvasLayer) -> void:
	check(panel._stat_rows.size() == 16, "All sixteen stats use the reusable presentation")
	for section in panel.stats_grid.get_children():
		var value_edge := -INF
		var previous: CharacterStatRow
		for node in section.get_children():
			if not node is CharacterStatRow:
				continue
			var row := node as CharacterStatRow
			check(row.scene_file_path == "res://scenes/ui/character_stat_row.tscn" and row.size.y == 24, "Every stat shares the same compact 24px component")
			var style := row.get_theme_stylebox("panel") as StyleBoxFlat
			check(style.content_margin_left == 6 and style.content_margin_top == 2 and style.border_width_bottom == 1, "Every row has consistent padding and a subtle separator")
			var bounds := row.get_global_rect()
			check(bounds.encloses(row.icon.get_global_rect()) and bounds.encloses(row.stat_label.get_global_rect()) and bounds.encloses(row.value_label.get_global_rect()), "Icon, label and value fit inside their row")
			check(row.icon.get_global_rect().end.x <= row.stat_label.get_global_rect().position.x and row.stat_label.get_global_rect().end.x <= row.value_label.get_global_rect().position.x, "Icons and text never overlap")
			check(row.icon.size == Vector2(16, 16) and row.icon.scale == Vector2.ONE and row.icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "All icons remain native-size nearest pixels")
			if row.health_bar != null:
				check(bounds.encloses(row.health_bar.get_global_rect()) and row.stat_label.get_global_rect().end.x <= row.health_bar.get_global_rect().position.x and row.health_bar.get_global_rect().end.x <= row.value_label.get_global_rect().position.x, "Health segments fit inline without changing row height")
			var edge := row.value_label.get_global_rect().end.x
			if value_edge != -INF:
				check(is_equal_approx(edge, value_edge), "Values align at the same right edge within each section")
			if previous != null:
				check(previous.get_global_rect().end.y <= bounds.position.y, "Adjacent stat rows never overlap")
			value_edge = edge
			previous = row

func check_all_values(panel: CanvasLayer, expected: Dictionary) -> void:
	for stat_name: String in expected:
		check(panel._value_labels[stat_name].text == expected[stat_name], "Correct displayed value for " + stat_name)
		check(panel._value_labels[stat_name] == panel._stat_rows[stat_name].value_label, "Existing data binding targets the correct reusable row for " + stat_name)

func definition(id: StringName) -> UpgradeDefinition:
	for value in all_definitions:
		if value.id == id:
			return value
	return null

func select(id: StringName) -> void:
	var choices: Array[UpgradeDefinition] = [definition(id)]
	for value in all_definitions:
		if value.id != id and choices.size() < 3:
			choices.append(value)
	system.definitions = choices
	system.queue_level()
	system.select_upgrade(id)
	system.definitions = all_definitions

func run() -> void:
	root.size = Vector2i(1152, 648)
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	var panel = main.get_node("CharacterInfoPanel")
	system = main.get_node("UpgradeSystem")
	all_definitions = system.definitions.duplicate()
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	var weapons: VBoxContainer = panel.content.get_node("Upgrades/Weapons")
	var generic: VBoxContainer = panel.content.get_node("Upgrades/Generic")
	panel.open_panel()
	check(panel.title.text == "CHARACTER" and panel.chapter_label.text == "Chapter: Ultramarines", "Character and Chapter headings")
	check(panel.visible and paused and panel.can_process(), "Sheet stays active while gameplay pauses")
	check(weapons.get_node("Count").text == "Weapon Upgrades: 0 / 4" and generic.get_node("Count").text == "Generic Upgrades: 0 / 4", "Empty ownership counters")
	for section in [weapons, generic]:
		check(section.get_node("Slots").get_child_count() == 4, "Exactly four slots per section")
		for slot in section.get_node("Slots").get_children():
			check(slot.get_node("Row/Name").text == "Empty" and slot.get_node("Row/Level").text == "", "Empty slots never invent ownership")
	check(panel.content.get_node("ChapterPerks/Owned").text == "None selected", "Unowned perks not displayed")
	var portrait: TextureRect = panel.content.get_node("Body/Portrait")
	check(portrait.texture == player.visual.sprite_frames.get_frame_texture(&"idle_right", 0) and portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Existing right-facing portrait remains sharp and proportional")
	await process_frame
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panel.sheet_panel.get_global_rect()), "Sheet fits current resolution")
	check(panel.content.size.y <= panel.content.get_parent().size.y, "Default sheet needs no vertical scrolling")
	check_all_values(panel, {"Health": "50 / 50", "Armor": "0", "Health Regen": "0.0 HP/s", "Movement Speed": "150", "Pickup Radius": "60 px", "XP Gain": "+0%", "Dodge Chance": "0%", "Better XP Drop Chance": "+0%", "Bolter Damage": "25", "Bolter Projectiles": "1 / 5", "Bolter Fire Rate": "1.33 /s", "Crit Chance": "0%", "Crit Bonus": "+50%", "Knife Damage": "35", "Knife Range": "55 px", "Knife Attack Rate": "1.25 /s"})
	check_stat_rows(panel)
	check(panel._stat_labels["Armor"].text == "Ceramite Plating:" and panel._stat_labels["Health Regen"].text == "Gene-Seed Resilience:", "Thematic stat names remain unchanged")
	var local_theme := panel.sheet_panel.theme as Theme
	check(local_theme.resource_path == "res://resources/ui/character_info_theme.tres", "Sci-fi theme belongs only to Character Info")
	check(str(ProjectSettings.get_setting("gui/theme/custom", "")).is_empty(), "No project-wide custom theme is installed")
	var menu := preload("res://scenes/ui/main_menu.tscn").instantiate() as MainMenu
	check(menu.theme != local_theme and menu.theme.resource_path.contains("main_menu.tscn"), "Main Menu retains its own existing theme")
	menu.free()
	for control in main.get_node("HealthHUD").find_children("*", "Control", true, false):
		check(control.theme != local_theme, "Gameplay HUD has no Character Info theme assignment")
	var frame := panel.sheet_panel.get_theme_stylebox("panel") as StyleBoxTexture
	check(frame != null and frame.texture.resource_path.ends_with("themes/cyan/panel.png"), "Sheet uses the selected pack's nine-slice frame")
	check(frame.texture.get_image().get_pixel(0, 0).a == 0, "Frame texture retains its transparent cut corner")
	check(panel.sheet_panel.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Pack textures filter sharply only in this subtree")
	check(panel.title.get_theme_font("font").resource_path.ends_with("pixel_ui_scifi_font.fnt") and panel.title.get_theme_font_size("font_size") == 24, "Pixel title uses integer 3x scale from the 8px source")
	check(panel._value_labels["Armor"].get_theme_font("font") != panel.title.get_theme_font("font"), "Body text retains the existing readable font")
	var icons: Array[Node] = panel.stats_grid.find_children("Icon", "TextureRect", true, false)
	check(icons.size() == 16, "All rows have a suitable or explicitly neutral pack icon")
	for icon: TextureRect in icons:
		check(icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and icon.texture.get_size() == Vector2(16, 16), "Pack icon stays sharp at native 16px size")
	var bar := panel._health_bar as ProgressBar
	check(bar.get_theme_stylebox("fill").texture.resource_path.ends_with("bars/bar_red.png") and bar.get_theme_stylebox("fill").axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_TILE, "Health fill tiles original segments instead of stretching them")
	check(bar.value == player.current_health and bar.max_value == player.max_health, "Health bar reads current player values")
	player.current_health = 21.5
	player.max_health = 75.5
	player.health_changed.emit(player.current_health, player.max_health)
	check(bar.value == 21.5 and bar.max_value == 75.5 and panel._value_labels["Health"].text == "22 / 76", "Live health values and existing rounded label remain in sync")
	player.current_health = 50
	player.max_health = 50
	player.health_changed.emit(player.current_health, player.max_health)
	await capture("_empty")
	var fixture: Dictionary = {&"armor": 3.0, &"health_regen": 0.6, &"movement_speed": 0.2, &"pickup_radius": 0.5, &"xp_gain": 0.25, &"dodge_chance": 0.1, &"better_xp_drop_chance": 0.2, &"bolter_damage": 0.4, &"projectile_count": 2.0, &"fire_rate": 0.5, &"crit_chance": 0.075, &"crit_damage": 0.25, &"knife_damage": 0.2, &"knife_range": 0.4, &"knife_attack_rate": 0.25}
	for id: StringName in fixture:
		player.combat_stats.add_modifier(id, fixture[id])
	check_all_values(panel, {"Health": "50 / 50", "Armor": "3", "Health Regen": "0.6 HP/s", "Movement Speed": "180", "Pickup Radius": "90 px", "XP Gain": "+25%", "Dodge Chance": "10%", "Better XP Drop Chance": "+20%", "Bolter Damage": "35", "Bolter Projectiles": "3 / 5", "Bolter Fire Rate": "2.00 /s", "Crit Chance": "7.5%", "Crit Bonus": "+75%", "Knife Damage": "42", "Knife Range": "77 px", "Knife Attack Rate": "1.56 /s"})
	for id: StringName in fixture:
		player.combat_stats.add_modifier(id, -fixture[id])
	panel.close_panel()
	var weapon_counts := {&"bolter_damage": 4, &"fire_rate": 2, &"knife_damage": 3, &"crit_chance": 1}
	var generic_counts := {&"armor": 2, &"max_health": 1, &"health_regen": 3}
	for id: StringName in weapon_counts:
		for _selection in weapon_counts[id]:
			select(id)
	for id: StringName in generic_counts:
		for _selection in generic_counts[id]:
			select(id)
	panel.open_panel()
	check(weapons.get_node("Count").text == "Weapon Upgrades: 4 / 4" and generic.get_node("Count").text == "Generic Upgrades: 3 / 4", "Actual selected types determine counters")
	for section in [weapons, generic]:
		var counts: Dictionary = weapon_counts if section == weapons else generic_counts
		var index := 0
		for id: StringName in counts:
			var slot: PanelContainer = section.get_node("Slots").get_child(index)
			check(slot.get_node("Row/Name").text == panel._upgrade_display_name(definition(id)), "Owned type shown from upgrade resource")
			check(slot.get_node("Row/Level").text == definition(id).get_level_text(player.combat_stats, counts[id]), "Level reads existing selection count")
			index += 1
	check(generic.get_node("Slots").get_child(3).get_node("Row/Name").text == "Empty", "Fourth Generic slot stays empty")
	check(panel._value_labels["Bolter Fire Rate"].text == "1.60 /s" and panel._value_labels["Knife Attack Rate"].text == "1.25 /s", "Rates use real current cooldowns")
	check(panel._value_labels["Crit Bonus"].text == "+50%" and panel._value_labels["Health Regen"].text == "0.6 HP/s", "Current crit bonus and regen")
	check(panel._value_labels["Knife Range"].text == "55 px", "Knife radius uses live weapon data")
	player.combat_stats.add_modifier(&"knife_range", 0.2)
	check(panel._value_labels["Knife Range"].text == "66 px", "Visible sheet updates real directional radius")
	panel.close_panel()
	# A fifth Weapon type must remain unavailable after four commitments.
	system.queue_level()
	system.offered.append(definition(&"knife_range"))
	system.select_upgrade(&"knife_range")
	check(not system.levels.has(&"knife_range"), "Fifth Weapon type cannot commit")
	system.select_upgrade(system.offered[0].id)
	panel.open_panel()
	check(weapons.get_node("Count").text == "Weapon Upgrades: 4 / 4" and not weapons.get_node("Overflow").visible, "Four Weapon commitments remain visible without a fifth type")
	panel.close_panel()
	var manager: ChapterPerkManager = system.chapter_manager
	var owned_perk: ChapterPerkDefinition = manager.catalog.perks[0]
	manager.apply_perk(owned_perk)
	panel.open_panel()
	check(panel.content.get_node("ChapterPerks/Title").text == "ULTRAMARINES PERKS" and panel.content.get_node("ChapterPerks/Owned").text == owned_perk.display_name.capitalize(), "Only actually owned Chapter perk displayed")
	await capture("_upgraded")
	for size in [Vector2i(1600, 900), Vector2i(800, 600), Vector2i(640, 480)]:
		root.size = size
		await process_frame
		await process_frame
		var rect: Rect2 = panel.sheet_panel.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect), "Sheet stays inside resized viewport")
		check(rect.get_center().is_equal_approx(Vector2(root.size) * 0.5), "Sheet stays centered")
		check_stat_rows(panel)
		if size.x < 800:
			check(panel.content.get_node("Upgrades").columns == 1, "Narrow window stacks upgrade sections")
		if size.x < 760:
			check(panel.stats_grid.columns == 1, "Narrow sheet stacks survival and weapons rather than clipping stat values")
			var horizontal: HScrollBar = panel.content.get_parent().get_h_scroll_bar()
			check(horizontal.max_value <= horizontal.page, "Narrow sheet needs no horizontal scrolling")
		await capture("_%dx%d" % [size.x, size.y])
	panel.close_panel()
	check(not paused, "Closing resumes gameplay")
	await key(&"character_info")
	check(panel.visible and paused, "Existing Character Info action opens the styled sheet and pauses")
	await key(&"ui_cancel")
	check(not panel.visible and not paused, "Escape closes the styled sheet and releases its own pause")
	root.size = Vector2i(1152, 648)
	await process_frame
	await process_frame
	await capture("_hud")
	main.queue_free()
	await process_frame
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		menu = preload("res://scenes/ui/main_menu.tscn").instantiate() as MainMenu
		root.add_child(menu)
		current_scene = menu
		await capture("_main_menu")
		menu.queue_free()
		await process_frame
		await process_frame
		await create_timer(0.15).timeout
	print("PASS: %d character sheet checks" % checks)
	quit()
