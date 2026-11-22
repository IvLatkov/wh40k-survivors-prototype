extends SceneTree

const MENU := preload("res://scenes/ui/main_menu.tscn")
const MAIN := preload("res://scenes/main.tscn")
const MUSIC_PATH := "res://assets/audio/Background/Background foley.wav"
const ATMOSPHERE_PATH := "res://assets/audio/Background/background_atmos.wav"
var checks: int = 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)


func _initialize() -> void:
	run.call_deferred()


func check_no_background(main: Node) -> void:
	check(not main.has_node("BackgroundMusic") and not main.has_node("BackgroundAtmosphere"), "Gameplay owns neither menu layer")
	for node in root.find_children("*", "AudioStreamPlayer", true, false):
		var audio := node as AudioStreamPlayer
		check(audio.stream == null or audio.stream.resource_path not in [MUSIC_PATH, ATMOSPHERE_PATH], "No menu track is retained or recreated during gameplay")


func prepare_run(main: Node2D) -> void:
	main.get_node("RunClock").set_process(false)
	main.get_node("EnemySpawner").set_process(false)
	main.get_node("ChunkManager").set_process(false)
	main.get_node("ChunkManager").set_physics_process(false)
	var player: Player = main.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)


func run() -> void:
	root.size = Vector2i(1152, 648)
	var menu := MENU.instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.1).timeout
	var layers: Array[AudioStreamPlayer] = [menu.get_node("BackgroundMusic"), menu.get_node("BackgroundAtmosphere")]
	var playbacks: Array[AudioStreamPlayback] = []
	for index in 2:
		var audio := layers[index]
		var stream := audio.stream as AudioStreamWAV
		check(stream != null and stream.resource_path == [MUSIC_PATH, ATMOSPHERE_PATH][index], "Uses the exact existing background stream")
		check(audio.autoplay and audio.playing and audio.get_playback_position() > 0, "Both scene-owned layers start automatically together")
		check(audio.volume_db == [-26.0, -34.0][index] and audio.bus == &"Music", "Music/atmosphere preserve the intended gain and Music routing")
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and is_equal_approx(float(stream.loop_end) / stream.mix_rate, stream.get_length()), "Native looping covers the complete WAV")
		check(audio.get_signal_connection_list(&"finished").is_empty(), "No finished-to-play restart callback exists")
		var import_settings := ConfigFile.new()
		check(import_settings.load(stream.resource_path + ".import") == OK and not import_settings.get_value("params", "edit/normalize"), "Existing unnormalized source import is preserved")
		playbacks.append(audio.get_stream_playback())
		print("MENU_LAYER name=%s stream=%s db=%.1f seconds=%.3f native_loop=%d" % [audio.name, stream.resource_path, audio.volume_db, stream.get_length(), stream.loop_mode])
	check(layers[1].volume_linear < layers[0].volume_linear, "Atmosphere has lower configured gain than the primary music")
	check(menu.find_children("*", "AudioStreamPlayer2D", true, false).is_empty(), "Menu backgrounds use non-positional players")
	# Retain the old full-loop invocation as an alias for the new menu ownership.
	if "--full-background-loops" in OS.get_cmdline_user_args() or "--full-atmosphere-loops" in OS.get_cmdline_user_args():
		var wraps: Array[int] = [0, 0]
		var previous: Array[float] = [layers[0].get_playback_position(), layers[1].get_playback_position()]
		var seconds := maxf(layers[0].stream.get_length(), layers[1].stream.get_length()) * 2 + 5
		var deadline := Time.get_ticks_msec() + int(seconds * 1000)
		print("Monitoring two natural loops of BOTH menu layers (deadline %.1f seconds)..." % seconds)
		while (wraps[0] < 2 or wraps[1] < 2) and Time.get_ticks_msec() < deadline:
			await create_timer(0.1).timeout
			for index in 2:
				var position := layers[index].get_playback_position()
				check(layers[index].playing and layers[index].get_stream_playback() == playbacks[index], "Natural loop retains the same active playback")
				if position < previous[index]:
					wraps[index] += 1
					print("NATURAL_LOOP layer=%s count=%d" % [layers[index].name, wraps[index]])
				previous[index] = position
		check(wraps[0] >= 2 and wraps[1] >= 2, "Both tracks complete two natural loops without seeking or restarting")
	for _cycle in 2:
		var seam_playbacks: Array[AudioStreamPlayback] = []
		for audio in layers:
			audio.seek(audio.stream.get_length() - 0.15)
			seam_playbacks.append(audio.get_stream_playback())
		await create_timer(0.45).timeout
		for index in 2:
			check(layers[index].playing and layers[index].get_playback_position() < 1 and layers[index].get_stream_playback() == seam_playbacks[index], "Each loop boundary wraps internally without playback replacement")
	playbacks = [layers[0].get_stream_playback(), layers[1].get_stream_playback()]
	for page: MainMenu.Page in [MainMenu.Page.CHARACTER, MainMenu.Page.MAP, MainMenu.Page.UPGRADES, MainMenu.Page.COLLECTION, MainMenu.Page.SETTINGS, MainMenu.Page.MAIN]:
		menu.show_page(page)
		var positions: Array[float] = [layers[0].get_playback_position(), layers[1].get_playback_position()]
		await create_timer(0.25).timeout
		check(root.find_children("*", "AudioStreamPlayer", true, false).size() == 2, "Navigation keeps exactly two players, with no duplicate copies")
		for index in 2:
			check(layers[index].playing and layers[index].get_stream_playback() == playbacks[index] and layers[index].get_playback_position() > positions[index], "Page transitions keep both original playbacks advancing")
	menu.show_page(MainMenu.Page.SETTINGS)
	var slider := menu.pages[MainMenu.Page.SETTINGS].get_node("Music/Slider") as HSlider
	slider.value = 0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) and layers[0].playing and layers[1].playing, "Music setting mutes both routed layers without stopping playback")
	slider.value = 63
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Music setting restores both layers without restarting")
	menu.show_page(MainMenu.Page.MAIN)
	menu.get_node("%Deploy").pressed.emit()
	await process_frame
	await process_frame
	check(not is_instance_valid(menu) and not is_instance_valid(layers[0]) and not is_instance_valid(layers[1]), "Production DEPLOY unloads both menu players")
	var main := current_scene as Node2D
	check(main != null and main.scene_file_path == "res://scenes/main.tscn", "DEPLOY uses the existing gameplay scene")
	prepare_run(main)
	check_no_background(main)
	var info = main.get_node("CharacterInfoPanel")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	var player: Player = main.get_node("Player")
	for modal in ["info", "upgrade", "chapter"]:
		if modal == "info":
			info.open_panel()
		else:
			if modal == "chapter":
				player.level = main.get_node("ChapterPerkManager").catalog.perks[0].milestone - 1
				player.xp = 0
			player.add_xp(player.get_xp_required() - player.xp)
		await create_timer(0.1, true).timeout
		check(paused, "Gameplay modal pause is unchanged after removing background-only hooks")
		check_no_background(main)
		if modal == "info":
			info.close_panel()
		elif modal == "chapter":
			rewards.select_chapter_perk(rewards.chapter_offered[0].id)
		else:
			rewards.select_upgrade(rewards.offered[0].id)
		check(not paused, "Closing the gameplay modal still resumes the run")
	player.add_xp(player.get_xp_required() - player.xp)
	player.add_xp(player.get_xp_required() - player.xp)
	check(rewards.pending_levels == 2 and paused, "Queued rewards still pause gameplay")
	for _selection in 2:
		check_no_background(main)
		rewards.select_upgrade(rewards.offered[0].id)
		await process_frame
	check(not paused and rewards.pending_levels == 0, "Finishing queued rewards resumes gameplay")
	var skip := InputEventKey.new()
	skip.keycode = KEY_F10
	skip.pressed = true
	main._unhandled_key_input(skip)
	main._unhandled_key_input(skip)
	var encounter: BossEncounter = main.get_node("BossEncounter")
	check(encounter.warboss_spawned and is_instance_valid(encounter.boss), "F10 uses the real Warboss encounter")
	encounter.boss.set_physics_process(false)
	check_no_background(main)
	player.add_xp(player.get_xp_required() - player.xp)
	encounter.boss.take_damage(100000)
	check(paused and encounter.run_ended, "Real Warboss defeat still triggers terminal Victory during rewards")
	check_no_background(main)
	main.queue_free()
	await process_frame
	await process_frame
	paused = false
	main = MAIN.instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	prepare_run(main)
	var clock: RunClock = main.get_node("RunClock")
	clock._process(599.999)
	check(not main.get_node("BossEncounter").warboss_spawned, "Natural encounter still waits for 10:00")
	clock._process(0.001)
	encounter = main.get_node("BossEncounter")
	check(encounter.warboss_spawned, "Natural 10:00 encounter still works")
	encounter.boss.set_physics_process(false)
	clock.seconds_changed.emit(600)
	check_no_background(main)
	var fresh_player: Player = main.get_node("Player")
	fresh_player.add_xp(fresh_player.get_xp_required())
	fresh_player.take_damage(1000)
	check(paused and fresh_player.current_health == 0, "Death still pauses/ends gameplay during rewards")
	check_no_background(main)
	main.queue_free()
	await process_frame
	await process_frame
	paused = false
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), 0)
	await create_timer(0.15).timeout
	print("PASS: ", checks, " dual-menu background / native loops / navigation / clean gameplay / modal / boss / Victory checks")
	quit(0)
