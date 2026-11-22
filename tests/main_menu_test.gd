extends SceneTree

const MENU := preload("res://scenes/ui/main_menu.tscn")
var checks: int = 0


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)


func click_button(button: Control) -> void:
	await process_frame
	await process_frame
	(current_scene.get_node("%Scroll") as ScrollContainer).ensure_control_visible(button)
	await process_frame
	await process_frame
	var at := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func capture_page(suffix: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("WH40K_MENU_CAPTURE_PATH")
	if not output.is_empty():
		check(root.get_texture().get_image().save_png(output.get_basename() + suffix + ".png") == OK, "Selection preview saves successfully")


func check_page(menu: MainMenu, expected: MainMenu.Page) -> void:
	check(menu.current_page == expected, "Expected menu page is active")
	for key: int in menu.pages:
		check(menu.pages[key].visible == (key == expected), "Only the selected page is visible")
	check(menu.find_children("*", "Player", true, false).is_empty(), "No gameplay player runs behind the menu")
	check(menu.find_children("*", "AudioStreamPlayer", true, false).size() == 1, "Every menu page keeps exactly one music player")
	check(not menu.has_node("BackgroundAtmosphere"), "Gameplay ambience does not play in the menu")


func run() -> void:
	# Headless Window defaults to 64x64; exercise the actual desktop-sized UI.
	root.size = Vector2i(1152, 648)
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/ui/main_menu.tscn", "F5/project startup points to the menu")
	var menu := MENU.instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await process_frame
	await create_timer(0.1).timeout
	var music := menu.get_node("BackgroundMusic") as AudioStreamPlayer
	var stream := music.stream as AudioStreamWAV
	check(stream != null and stream.resource_path == "res://assets/audio/Background/Background foley.wav", "Menu owns the existing music track")
	check(music.autoplay and music.playing and music.get_playback_position() > 0.0, "Menu music starts automatically")
	check(music.volume_db == -26.0 and music.bus == &"Music", "Menu music preserves quiet gain and Music routing")
	check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and is_equal_approx(float(stream.loop_end) / stream.mix_rate, stream.get_length()), "Menu music natively loops the full WAV")
	check(music.get_signal_connection_list(&"finished").is_empty(), "Menu music has no script restart callback")
	for _cycle in 2:
		music.seek(stream.get_length() - 0.15)
		var playback := music.get_stream_playback()
		await create_timer(0.45).timeout
		check(music.playing and music.get_playback_position() < 1.0 and music.get_stream_playback() == playback, "Menu loop wraps without replacing playback")
	var menu_playback := music.get_stream_playback()
	check_page(menu, MainMenu.Page.MAIN)
	check(not paused, "Menu startup does not pause the tree")
	check((menu.get_node("%GameTitle") as Label).text == "WH40K SURVIVOR", "Menu displays the game title")
	check(menu.get_node("%CurrencyDisplay").text == "Currency: 0", "Currency is a display-only zero placeholder")
	check(menu.get_node("%CharacterName").text == "ULTRAMARINE", "Dashboard shows selected Ultramarine")
	check(menu.get_node("%StartingWeapon").text == "Starting Weapon: Bolter", "Dashboard shows starting Bolter")
	check(menu.get_node("%Chapter").text == "Chapter: Ultramarines", "Dashboard shows the Chapter")
	check(menu.get_node("%Portrait").texture.resource_path.contains("Ultramarine_bolter_right_still"), "Portrait reuses the existing player art without instantiating gameplay")
	check(menu.get_node("%MissionName").text == "BATTLEFIELD ALPHA", "Dashboard shows Battlefield Alpha")
	check(menu.get_node("%Duration").text == "Duration: 10 Minutes", "Dashboard shows ten-minute mission")
	check(menu.get_node("%Boss").text == "Boss: Ork Warboss", "Dashboard shows the current boss")
	check(menu.get_node("%BattlefieldPreview").texture != null, "Mission uses an existing terrain preview")
	check(menu.get_node("%Summary").text == "Ultramarine\nBolter\nBattlefield Alpha\n10:00 Mission", "Deploy summary matches the selected character and mission")
	check(menu.get_node("%Deploy").text == "DEPLOY" and menu.get_node("%Deploy").size.y > menu.get_node("%OpenSettings").size.y, "Deploy is the prominent primary action")
	check(menu.find_children("Play", "Button", true, false).is_empty(), "Old primary Play button has been replaced")
	if "--quit-button" in OS.get_cmdline_user_args():
		print("Checking desktop Quit through mouse input...")
		await click_button(menu.get_node("%Quit") as Button)
		await create_timer(0.2).timeout
		push_error("Quit did not close the process")
		quit(1)
		return
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var capture_path := OS.get_environment("WH40K_MENU_CAPTURE_PATH")
		if capture_path.is_empty():
			capture_path = OS.get_environment("TEMP").path_join("wh40k_main_menu.png")
		check(root.get_texture().get_image().save_png(capture_path) == OK, "Rendered menu preview saves successfully")
		print("Menu preview: ", capture_path)
	var buttons: Array[String] = ["CharacterSelect", "MapSelect", "OpenUpgrades", "OpenCollection", "OpenSettings"]
	var pages: Array[MainMenu.Page] = [MainMenu.Page.CHARACTER, MainMenu.Page.MAP, MainMenu.Page.UPGRADES, MainMenu.Page.COLLECTION, MainMenu.Page.SETTINGS]
	for index in buttons.size():
		await click_button(menu.get_node("%" + buttons[index]) as Button)
		check_page(menu, pages[index])
		if pages[index] == MainMenu.Page.CHARACTER:
			await capture_page("_character")
		elif pages[index] == MainMenu.Page.MAP:
			await capture_page("_mission")
		elif pages[index] == MainMenu.Page.UPGRADES:
			await capture_page("_armory")
		var page: Control = menu.pages[pages[index]]
		await click_button(page.get_node("Back") as Button)
		check_page(menu, MainMenu.Page.MAIN)
		await click_button(menu.get_node("%" + buttons[index]) as Button)
		await escape()
		check_page(menu, MainMenu.Page.MAIN)
	await escape()
	check_page(menu, MainMenu.Page.MAIN)
	var details := menu.get_node("%CharacterDetails/Padding/Content")
	check(details.get_node("Name").text == "ULTRAMARINE", "Selected character details show Ultramarine")
	check(details.get_node("Chapter").text == "Chapter: Ultramarines" and details.get_node("StartingWeapon").text == "Starting Weapon: Bolter", "Details show the current Chapter and starting weapon")
	var source := MenuSelectionData.PLAYER_SCENE.instantiate() as Player
	var expected_stats := "Max HP: %s\nMovement Speed: %s px/s\nArmor: %d\nCrit Chance: %s%%" % [str(source.max_health), str(source.get_movement_speed()), source.combat_stats.get_armor(), str(source.combat_stats.get_crit_chance() * 100.0)]
	check(details.get_node("Stats").text == expected_stats, "Displayed stats match actual player defaults")
	check(source.max_health == 50.0 and source.get_movement_speed() == 150.0 and source.combat_stats.get_armor() == 0 and source.combat_stats.get_crit_chance() == 0.0, "Starting stats remain 50 HP, 150 speed, 0 armor and 0% crit")
	# Scene overrides must reach display data, rather than duplicated UI constants.
	source.max_health = 75.0
	source.speed = 180.0
	source.combat_stats = source.combat_stats.duplicate(true)
	source.combat_stats.crit_chance = 0.125
	source.combat_stats.add_modifier(&"armor", 3.0)
	var alternate := PackedScene.new()
	check(alternate.pack(source) == OK, "Prepare player-scene override fixture")
	var override_data := MenuSelectionData.read_character(alternate)
	check(override_data.max_hp == 75.0 and override_data.movement_speed == 180.0 and override_data.armor == 3 and override_data.crit_chance == 0.125, "Display reader honors scene and stat overrides")
	source.free()
	check(details.get_node("PassiveBonus").text == "Passive Bonus: None", "No unearned Chapter perk is presented as a starting passive")
	for perk in MenuSelectionData.CHAPTER.perks:
		check(perk.milestone >= 10, "Chapter catalog grants milestone choices, not a starting passive")
	check(menu.get_node("%UltramarineCard").get_node("%Portrait").texture != null and details.get_node("UnlockState").text == "Unlocked · Selected", "Character details show portrait and real current availability")
	var mission_details := menu.get_node("%MissionDetails/Padding/Content")
	check(mission_details.get_node("Name").text == "BATTLEFIELD ALPHA", "Mission details show Battlefield Alpha")
	check(mission_details.get_node("Duration").text == "Duration: 10 Minutes", "Mission duration matches ten minutes")
	check(mission_details.get_node("EnemyTypes").text == "Enemy Types:\nSquigs\nOrks\nOrk Warboss", "Mission lists all current enemy types")
	check(mission_details.get_node("Difficulty").text == "Difficulty: Normal", "Normal is a display value, not a difficulty selector")
	check(mission_details.get_node("Boss").text == "Boss: Ork Warboss — 10:00" and menu.selection_data.mission.duration_seconds == BossEncounter.SPAWN_SECONDS, "Boss display uses the actual encounter timing")
	check(mission_details.get_node("UnlockState").text == "Unlocked · Selected" and menu.get_node("%BattlefieldAlphaCard").get_node("%Portrait").texture != null, "Mission details show selection and preview")
	for card_name: String in ["UltramarineCard", "BattlefieldAlphaCard"]:
		var card := menu.get_node("%" + card_name) as SelectionCard
		check(card.button_pressed and card.get_node("%SelectionState").text == "Selected", "Selected card has pressed styling and explicit selected text")
		check(card.get_node("%UnlockState").text == "Unlocked" and card.get_node("%Portrait").texture != null, "Selection card has availability and portrait")
	check(menu.get_node("%CharacterCards").get_child_count() == 1 and menu.get_node("%MapCards").get_child_count() == 1, "Only the existing character and stage are available")
	await click_button(menu.get_node("%CharacterPanel") as Control)
	check_page(menu, MainMenu.Page.CHARACTER)
	await click_button(menu.get_node("%UltramarineCard") as Control)
	check(menu.get_node("%UltramarineCard").button_pressed, "Clicking the only character keeps it selected")
	await escape()
	await click_button(menu.get_node("%MissionPanel") as Control)
	check_page(menu, MainMenu.Page.MAP)
	await click_button(menu.get_node("%BattlefieldAlphaCard") as Control)
	check(menu.get_node("%BattlefieldAlphaCard").button_pressed, "Clicking the only mission keeps it selected")
	await escape()
	menu.show_page(MainMenu.Page.UPGRADES)
	var armory: Control = menu.pages[MainMenu.Page.UPGRADES]
	var upgrade_grid := menu.get_node("%UpgradeGrid") as GridContainer
	check(armory.get_node("ArmoryHeader/Title").text == "ARMORY UPGRADES", "Armory has a clear permanent-upgrades heading")
	check(armory.get_node("%ArmoryCurrency").text == "Currency: 0", "Armory currency is display-only zero")
	check(upgrade_grid.get_child_count() == 4, "Exactly four initial upgrade cards")
	var titles := ["ARMOR", "BOLTER DAMAGE", "MOVEMENT", "MAX HEALTH"]
	var descriptions := ["Increase flat damage reduction.", "Increase Bolter base damage.", "Increase movement speed.", "Increase maximum health."]
	for index in 4:
		var card := upgrade_grid.get_child(index) as ArmoryUpgradeCard
		check(card != null and card.get_node("%UpgradeName").text == titles[index], "Requested upgrade title")
		check(card.get_node("%Rank").text == "0 / 5" and card.get_node("%RankPips").get_child_count() == 5, "Display-only zero rank with five unfilled rank markers")
		check(card.get_node("%Description").text == descriptions[index], "Short equipment description")
		check(card.get_node("%Cost").text == "Cost: —", "Placeholder cost does not invent a real price")
		check(card.get_node("%Availability").text == "LOCKED" and not card.disabled, "Locked presentation remains focusable for inspection")
		card.grab_focus()
		check(card.has_focus() and card.get_theme_stylebox("focus") != card.get_theme_stylebox("normal"), "Keyboard focus has a visible distinct border")
		await click_button(card)
		check(card.is_hovered() and card.get_theme_stylebox("hover") != card.get_theme_stylebox("normal"), "Mouse hover has a visible distinct style")
		check(card.get_node("%Rank").text == "0 / 5" and armory.get_node("%ArmoryCurrency").text == "Currency: 0", "Clicks cannot purchase, change ranks or spend currency")
	check(menu.find_children("*", "Player", true, false).is_empty(), "Armory does not initialize gameplay")
	await escape()
	check(menu.pages[MainMenu.Page.COLLECTION].get_node("Description").text == "Coming Soon", "Collection is a placeholder with no new progression")
	menu.show_page(MainMenu.Page.SETTINGS)
	for bus: String in ["Master", "Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus)
		check(index >= 0, "Audio bus exists: " + bus)
		var slider := menu.pages[MainMenu.Page.SETTINGS].get_node(bus + "/Slider") as HSlider
		slider.value = 37.0
		check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(index)), 0.37), "Slider changes actual bus gain")
		slider.value = 0.0
		check(AudioServer.is_bus_mute(index), "Zero volume mutes the bus")
		slider.value = 100.0
		check(not AudioServer.is_bus_mute(index) and is_zero_approx(AudioServer.get_bus_volume_db(index)), "Restoring volume unmutes the bus")
		if bus != "Master":
			check(AudioServer.get_bus_send(index) == &"Master", "Child audio buses send to Master")
	# The same runtime AudioServer survives the scene transition without an autoload.
	(menu.pages[MainMenu.Page.SETTINGS].get_node("Music/Slider") as HSlider).value = 63.0
	menu.show_page(MainMenu.Page.MAIN)
	for window_size: Vector2i in [Vector2i(1152, 648), Vector2i(1600, 900), Vector2i(960, 540), Vector2i(800, 600), Vector2i(360, 480)]:
		root.size = window_size
		await process_frame
		await process_frame
		await process_frame
		var grid := menu.get_node("%MainContent") as GridContainer
		check(grid.columns == (1 if window_size.x < 900 else 3), "Dashboard columns adapt to window width")
		var previous: Control
		for panel_name: String in ["CharacterPanel", "DeployPanel", "MissionPanel"]:
			var card := menu.get_node("%" + panel_name) as Control
			var rect := card.get_global_rect()
			check(rect.position.x >= 0.0 and rect.end.x <= window_size.x, "Dashboard card stays inside window horizontally")
			if previous != null:
				check(not rect.intersects(previous.get_global_rect()), "Dashboard cards never overlap")
			previous = card
		check((menu.get_node("%GameTitle") as Control).get_global_rect().end.x <= window_size.x, "Title remains within the window")
		var currency := menu.get_node("%CurrencyDisplay") as Label
		check(currency.size.x >= currency.get_minimum_size().x and currency.get_global_rect().end.x <= window_size.x and currency.size.y < 50.0, "Currency is readable and remains within the top bar")
		if window_size == Vector2i(1152, 648):
			check(menu.get_node("%Quit").get_global_rect().end.y <= window_size.y, "Bottom navigation is immediately visible at the project resolution")
			var scrollbar := (menu.get_node("%Scroll") as ScrollContainer).get_v_scroll_bar()
			check(scrollbar.max_value <= scrollbar.page, "Full dashboard fits without scrolling at project resolution")
		for selection_page: MainMenu.Page in [MainMenu.Page.CHARACTER, MainMenu.Page.MAP]:
			menu.show_page(selection_page)
			await process_frame
			await process_frame
			await process_frame
			var selection_grid := menu.get_node("%CharacterSelection" if selection_page == MainMenu.Page.CHARACTER else "%MapSelection") as GridContainer
			check(selection_grid.columns == (1 if window_size.x < 800 else 2), "Selection details stack on narrow windows")
			check(menu.panel.get_global_rect().position.x >= 0.0 and menu.panel.get_global_rect().end.x <= window_size.x, "Selection panel stays inside window horizontally")
			var card := menu.get_node("%UltramarineCard" if selection_page == MainMenu.Page.CHARACTER else "%BattlefieldAlphaCard") as SelectionCard
			check(card.size.y >= card.get_node("Padding").get_combined_minimum_size().y, "Card expands to fit wrapped details and state labels")
			check(not selection_grid.get_child(0).get_global_rect().intersects(selection_grid.get_child(1).get_global_rect()), "Card list and details never overlap")
			await capture_page(("_character" if selection_page == MainMenu.Page.CHARACTER else "_mission") + "_%dx%d" % [window_size.x, window_size.y])
		menu.show_page(MainMenu.Page.UPGRADES)
		await process_frame
		await process_frame
		await process_frame
		check(upgrade_grid.columns == (1 if window_size.x < 700 else 2), "Armory switches from 2x2 to a single column on narrow windows")
		check(menu.panel.get_global_rect().position.x >= 0 and menu.panel.get_global_rect().end.x <= window_size.x, "Armory panel stays inside the window")
		check(armory.get_node("ArmoryHeader/Title").get_global_rect().position.y >= 0, "Armory opens at its header instead of scrolling to Back")
		check(armory.get_node("ArmoryHeader/Title").get_global_rect().position.y >= 0, "Opening armory starts at its header, not a stale scroll position")
		for index in 4:
			var card := upgrade_grid.get_child(index) as ArmoryUpgradeCard
			var bounds := card.get_global_rect()
			check(bounds.position.x >= 0 and bounds.end.x <= window_size.x, "Upgrade card does not clip horizontally")
			check(card.size.y >= card.get_node("Padding").get_combined_minimum_size().y, "Card grows to contain wrapped titles/descriptions")
			check(bounds.encloses(card.get_node("%Cost").get_global_rect()), "Cost remains inside card boundaries")
			for other in range(index):
				check(not bounds.intersects((upgrade_grid.get_child(other) as Control).get_global_rect()), "Upgrade cards never overlap")
		if window_size == Vector2i(1152, 648):
			check(armory.get_node("Back").get_global_rect().end.y <= window_size.y, "Desktop 2x2 armory and Back fit on screen")
		await capture_page("_armory_%dx%d" % [window_size.x, window_size.y])
		await click_button(armory.get_node("Back"))
		check_page(menu, MainMenu.Page.MAIN)
		menu.show_page(MainMenu.Page.MAIN)

	root.size = Vector2i(360, 480)
	await process_frame
	await process_frame
	check((menu.get_node("%MainContent") as Control).get_global_rect().end.x <= 360.0, "Dashboard fits a narrow window without horizontal clipping")
	await click_button(menu.get_node("%OpenCollection") as Button)
	check_page(menu, MainMenu.Page.COLLECTION)
	check(menu.panel.get_global_rect().position.x >= 0.0 and menu.panel.get_global_rect().end.x <= 360.0, "Submenu fits a narrow window")
	await click_button(menu.pages[MainMenu.Page.COLLECTION].get_node("Back") as Button)
	check_page(menu, MainMenu.Page.MAIN)
	root.size = Vector2i(1152, 648)
	await process_frame
	await process_frame
	check(music.playing and music.get_stream_playback() == menu_playback, "Navigation and settings keep the same menu playback")
	await click_button(menu.get_node("%Deploy") as Button)
	await process_frame
	await process_frame
	check(not is_instance_valid(menu), "Play frees the menu instead of retaining it behind gameplay")
	check(not is_instance_valid(music), "Play frees the menu music player so it cannot overlap gameplay")
	var main := current_scene
	check(main != null and main.scene_file_path == MainMenu.GAMEPLAY_SCENE, "Play loads the existing gameplay scene")
	check(main.has_node("Player") and main.has_node("EnemySpawner"), "Production gameplay runs after Play")
	var deployed_player: Player = main.get_node("Player")
	check(deployed_player.max_health == 50 and deployed_player.get_movement_speed() == 150 and deployed_player.combat_stats.get_armor() == 0 and deployed_player.get_node("Bolter").get_damage() == 25, "Armory inspection/clicks apply no permanent gameplay effects")
	var atmosphere := main.get_node("BackgroundAtmosphere") as AudioStreamPlayer
	await create_timer(0.1).timeout
	check(root.find_children("*", "AudioStreamPlayer", true, false).size() == 1 and not main.has_node("BackgroundMusic"), "Only one ambience player remains across the entire tree after Play")
	check(atmosphere.autoplay and atmosphere.playing, "Gameplay ambience autoplays")
	check(atmosphere.stream.resource_path == "res://assets/audio/Background/background_atmos.wav", "Gameplay retains the existing ambience source")
	check(atmosphere.bus == &"Music" and atmosphere.volume_db == -30.0, "Ambience keeps its Music bus and original gain")
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.63), "Menu volume survives Play")
	main.queue_free()
	await process_frame
	await create_timer(0.15).timeout
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), 0.0)
	print("PASS: ", checks, " main-menu startup / mouse navigation / Escape / audio settings / gameplay transition checks")
	quit(0)
