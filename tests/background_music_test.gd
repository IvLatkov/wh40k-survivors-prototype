extends SceneTree

const MAIN := preload("res://scenes/main.tscn")
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


func count_music_players(node: Node) -> int:
	var count := int(node is AudioStreamPlayer)
	for child in node.get_children():
		count += count_music_players(child)
	return count


func prepare_run() -> Node2D:
	var main := MAIN.instantiate() as Node2D
	root.add_child(main)
	current_scene = main
	main.get_node("RunClock").set_process(false)
	main.get_node("EnemySpawner").set_process(false)
	main.get_node("ChunkManager").set_process(false)
	main.get_node("ChunkManager").set_physics_process(false)
	var player: Player = main.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	return main


func check_playback(main: Node2D, atmosphere: AudioStreamPlayer, stream: AudioStream) -> void:
	check(count_music_players(root) == 1, "Exactly one non-positional ambience player across the tree")
	check(not main.has_node("BackgroundMusic"), "Gameplay never creates menu music")
	check(atmosphere.stream == stream and stream.resource_path == ATMOSPHERE_PATH and atmosphere.volume_db == -30.0, "Same quiet ambience persists throughout the run")
	check(atmosphere.playing or atmosphere.stream_paused, "Ambience remains active or paused without replacement")


func check_paused(atmosphere: AudioStreamPlayer) -> void:
	await create_timer(0.08, true).timeout
	var position := atmosphere.get_playback_position()
	await create_timer(0.12, true).timeout
	check(paused and atmosphere.stream_paused, "Gameplay pause also pauses ambience")
	check(absf(atmosphere.get_playback_position() - position) < 0.03, "Paused ambience retains its playback position")


func run() -> void:
	var main := prepare_run()
	var atmosphere: AudioStreamPlayer = main.get_node("BackgroundAtmosphere")
	var atmosphere_stream := atmosphere.stream as AudioStreamWAV
	await create_timer(0.1).timeout
	check(atmosphere_stream != null and atmosphere_stream.resource_path == ATMOSPHERE_PATH, "Uses the replacement background_atmos.wav source")
	check(atmosphere.autoplay and atmosphere.playing and atmosphere.get_playback_position() > 0.0, "Gameplay ambience starts automatically")
	check(atmosphere.volume_db == -30.0 and is_equal_approx(atmosphere.volume_linear, db_to_linear(-30.0)), "Ambience stays at its original -30 dB")
	check(atmosphere_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and atmosphere_stream.loop_begin == 0 and is_equal_approx(float(atmosphere_stream.loop_end) / atmosphere_stream.mix_rate, atmosphere_stream.get_length()), "Atmosphere WAV loops forwards across its full length")
	print("Atmosphere imported WAV: rate=", atmosphere_stream.mix_rate, " Hz, length=", atmosphere_stream.get_length(), " s, loop_begin=", atmosphere_stream.loop_begin, ", loop_end=", atmosphere_stream.loop_end, ", format=", atmosphere_stream.format)
	check(atmosphere.get_signal_connection_list(&"finished").is_empty(), "Atmosphere uses native WAV looping with no finished restart callback")
	var import_settings := ConfigFile.new()
	check(import_settings.load(ATMOSPHERE_PATH + ".import") == OK and not import_settings.get_value("params", "edit/normalize"), "Atmosphere source is imported without normalization")
	check_playback(main, atmosphere, atmosphere_stream)
	if "--full-atmosphere-loops" in OS.get_cmdline_user_args():
		var playback := atmosphere.get_stream_playback()
		var previous_position := atmosphere.get_playback_position()
		var completed_loops := 0
		var finished_count: Array[int] = [0]
		atmosphere.finished.connect(func(): finished_count[0] += 1)
		var deadline := Time.get_ticks_msec() + int((atmosphere_stream.get_length() * 2.0 + 5.0) * 1000.0)
		print("Monitoring two complete atmosphere loops without seeking (", atmosphere_stream.get_length() * 2.0, " seconds)...")
		while completed_loops < 2 and Time.get_ticks_msec() < deadline:
			await create_timer(0.05).timeout
			var position := atmosphere.get_playback_position()
			check(atmosphere.playing and atmosphere.get_stream_playback() == playback, "Native loop keeps the same active playback")
			if position < previous_position:
				completed_loops += 1
				print("Completed atmosphere loop ", completed_loops, "; position wrapped from ", previous_position, " to ", position)
			previous_position = position
		check(completed_loops == 2 and finished_count[0] == 0, "Two complete loops finish internally without a finished signal or player restart")
	for _cycle in 2:
		atmosphere.seek(atmosphere_stream.get_length() - 0.15)
		var seam_playback := atmosphere.get_stream_playback()
		await create_timer(0.45).timeout
		check(atmosphere.playing and atmosphere.get_playback_position() < 1.0 and atmosphere.get_stream_playback() == seam_playback, "Replacement atmosphere loops internally without replacing playback with no script restart")
	atmosphere.seek(2.0)
	await create_timer(0.1).timeout
	var info = main.get_node("CharacterInfoPanel")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	var player: Player = main.get_node("Player")
	for modal in ["info", "upgrade", "chapter"]:
		var atmosphere_playback := atmosphere.get_stream_playback()
		if modal == "info":
			info.open_panel()
		else:
			if modal == "chapter":
				player.level = main.get_node("ChapterPerkManager").catalog.perks[0].milestone - 1
				player.xp = 0
			player.add_xp(player.get_xp_required() - player.xp)
		if modal == "info":
			await check_paused(atmosphere)
		else:
			var before_atmosphere := atmosphere.get_playback_position()
			await create_timer(0.2, true).timeout
			check(paused and main.get_node("ChapterPerkMenu" if modal == "chapter" else "UpgradeMenu").visible, "Level-up menu still pauses gameplay")
			check(not atmosphere.stream_paused and atmosphere.playing and atmosphere.get_playback_position() > before_atmosphere, "Atmosphere continues during the level-up menu")
		var atmosphere_position := atmosphere.get_playback_position()
		if modal == "info":
			info.close_panel()
		elif modal == "chapter":
			rewards.select_chapter_perk(rewards.chapter_offered[0].id)
		else:
			rewards.select_upgrade(rewards.offered[0].id)
		await create_timer(0.12).timeout
		check(not paused, "Closing a modal resumes gameplay")
		check(not atmosphere.stream_paused and atmosphere.get_playback_position() > atmosphere_position and atmosphere.get_stream_playback() == atmosphere_playback, "Closing a modal resumes the same atmosphere playback without restarting")
		check_playback(main, atmosphere, atmosphere_stream)
	# Several levels from one pickup must keep ambience continuous across menus.
	player.add_xp(player.get_xp_required() - player.xp)
	player.add_xp(player.get_xp_required() - player.xp)
	check(rewards.pending_levels == 2 and paused, "Multiple earned levels queue while gameplay stays paused")
	var queued_atmosphere := atmosphere.get_stream_playback()
	for _selection in 2:
		var before_atmosphere := atmosphere.get_playback_position()
		await create_timer(0.15, true).timeout
		check(atmosphere.get_playback_position() > before_atmosphere, "Ambience continues throughout queued rewards")
		rewards.select_upgrade(rewards.offered[0].id)
		await process_frame
	check(not paused and rewards.pending_levels == 0 and atmosphere.get_stream_playback() == queued_atmosphere, "Finishing a reward queue keeps original audio playback")
	info.open_panel()
	await check_paused(atmosphere)
	info.close_panel()
	await create_timer(0.1).timeout
	var atmosphere_before_boss := atmosphere.get_playback_position()
	var atmosphere_before_skip := atmosphere.get_stream_playback()
	var skip := InputEventKey.new()
	skip.keycode = KEY_F10
	skip.pressed = true
	main._unhandled_key_input(skip)
	var encounter: BossEncounter = main.get_node("BossEncounter")
	check(encounter.warboss_spawned and is_instance_valid(encounter.boss), "F10 spawns the production Warboss")
	encounter.boss.set_physics_process(false)
	main._unhandled_key_input(skip)
	await create_timer(0.12).timeout
	check(atmosphere.get_playback_position() > atmosphere_before_boss and atmosphere.get_stream_playback() == atmosphere_before_skip, "F10 boss spawn and repeat keep the same atmosphere playback")
	check_playback(main, atmosphere, atmosphere_stream)
	# Terminal Victory must override the ambience exception even during an upgrade.
	player.add_xp(player.get_xp_required() - player.xp)
	await create_timer(0.1, true).timeout
	check(paused and atmosphere.playing, "Background audio plays during a pending boss-fight reward")
	encounter.boss.take_damage(encounter.boss.current_health + encounter.boss.armor)
	await check_paused(atmosphere)
	check(encounter.run_ended and encounter.hud.get_node("HUD/Victory").visible, "Victory still pauses the run")
	check_playback(main, atmosphere, atmosphere_stream)
	main.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(atmosphere), "Run teardown removes its ambience player")
	paused = false
	main = prepare_run()
	atmosphere = main.get_node("BackgroundAtmosphere")
	await create_timer(0.1).timeout
	check_playback(main, atmosphere, atmosphere_stream)
	check(not atmosphere.stream_paused and atmosphere.get_playback_position() < 1.0, "New run starts one fresh atmosphere playback")
	var clock: RunClock = main.get_node("RunClock")
	clock._process(599.999)
	check(not main.get_node("BossEncounter").warboss_spawned, "Natural run has no boss before 10:00")
	atmosphere_before_boss = atmosphere.get_playback_position()
	atmosphere_before_skip = atmosphere.get_stream_playback()
	clock._process(0.001)
	encounter = main.get_node("BossEncounter")
	check(encounter.warboss_spawned, "Natural run spawns the boss at 10:00")
	encounter.boss.set_physics_process(false)
	clock.seconds_changed.emit(600)
	await create_timer(0.12).timeout
	check(atmosphere.get_stream_playback() == atmosphere_before_skip and atmosphere.get_playback_position() > atmosphere_before_boss, "Natural 10:00 event and repeated notification preserve atmosphere playback")
	check_playback(main, atmosphere, atmosphere_stream)
	var fresh_player: Player = main.get_node("Player")
	fresh_player.add_xp(fresh_player.get_xp_required())
	await create_timer(0.1, true).timeout
	check(paused and atmosphere.playing, "Background audio continues during a fresh run's reward menu")
	fresh_player.take_damage(1000.0)
	await check_paused(atmosphere)
	check(fresh_player.current_health == 0.0, "Death overrides reward-menu background playback")
	main.queue_free()
	await process_frame
	await process_frame
	# Let the audio mixer release stopped playback before the test exits.
	paused = false
	await create_timer(0.15).timeout
	print("PASS: ", checks, " gameplay ambience startup/loop/volume/modal/boss/Victory/reload checks")
	quit()
