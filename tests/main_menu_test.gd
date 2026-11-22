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


func click_button(button: Button) -> void:
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
	check((menu.panel.get_node("Padding/Content/Title") as Label).text == "WH40K SURVIVOR", "Menu displays the game title")
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
	var buttons: Array[String] = ["CharacterSelect", "MapSelect", "OpenUpgrades", "OpenSettings"]
	var pages: Array[MainMenu.Page] = [MainMenu.Page.CHARACTER, MainMenu.Page.MAP, MainMenu.Page.UPGRADES, MainMenu.Page.SETTINGS]
	for index in buttons.size():
		await click_button(menu.get_node("%" + buttons[index]) as Button)
		check_page(menu, pages[index])
		var page: Control = menu.pages[pages[index]]
		await click_button(page.get_node("Back") as Button)
		check_page(menu, MainMenu.Page.MAIN)
		await click_button(menu.get_node("%" + buttons[index]) as Button)
		await escape()
		check_page(menu, MainMenu.Page.MAIN)
	await escape()
	check_page(menu, MainMenu.Page.MAIN)
	check(menu.pages[MainMenu.Page.CHARACTER].get_node("Description").text == "Ultramarine", "Current character is shown")
	check(menu.pages[MainMenu.Page.MAP].get_node("Description").text == "Current Battlefield", "Current battlefield is shown")
	check(menu.pages[MainMenu.Page.UPGRADES].get_node("Description").text == "Coming soon", "Permanent upgrades remain a placeholder")
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
	root.size = Vector2i(360, 480)
	await process_frame
	await process_frame
	check(menu.panel.get_global_rect().position.x >= 0.0 and menu.panel.get_global_rect().end.x <= 360.0, "Menu fits a narrow window without horizontal clipping")
	await click_button(menu.get_node("%CharacterSelect") as Button)
	check_page(menu, MainMenu.Page.CHARACTER)
	await click_button(menu.pages[MainMenu.Page.CHARACTER].get_node("Back") as Button)
	check_page(menu, MainMenu.Page.MAIN)
	root.size = Vector2i(1152, 648)
	await process_frame
	await process_frame
	check(music.playing and music.get_stream_playback() == menu_playback, "Navigation and settings keep the same menu playback")
	await click_button(menu.get_node("%Play") as Button)
	await process_frame
	await process_frame
	check(not is_instance_valid(menu), "Play frees the menu instead of retaining it behind gameplay")
	check(not is_instance_valid(music), "Play frees the menu music player so it cannot overlap gameplay")
	var main := current_scene
	check(main != null and main.scene_file_path == MainMenu.GAMEPLAY_SCENE, "Play loads the existing gameplay scene")
	check(main.has_node("Player") and main.has_node("EnemySpawner"), "Production gameplay runs after Play")
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
