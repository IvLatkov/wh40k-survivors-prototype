extends SceneTree

const MAIN := preload("res://scenes/main.tscn")
const TRACK_PATH := "res://assets/audio/Background/Background foley.wav"
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


func check_playback(main: Node2D, music: AudioStreamPlayer, stream: AudioStream) -> void:
	check(count_music_players(main) == 2, "Exactly two non-positional players per run: music and atmosphere")
	check(music.stream == stream and music.volume_db == -26.0, "Same quiet track persists throughout the run")
	check(music.playing or music.stream_paused, "Music playback remains active or paused without replacement")
	var atmosphere: AudioStreamPlayer = main.get_node("BackgroundAtmosphere")
	check(atmosphere.stream.resource_path == ATMOSPHERE_PATH and atmosphere.volume_db == -30.0, "Same quieter atmosphere persists alongside music")
	check(atmosphere.playing or atmosphere.stream_paused, "Atmosphere playback remains active or paused without replacement")


func check_paused(music: AudioStreamPlayer) -> void:
	var atmosphere: AudioStreamPlayer = music.get_parent().get_node("BackgroundAtmosphere")
	await create_timer(0.08, true).timeout
	var position := music.get_playback_position()
	var atmosphere_position := atmosphere.get_playback_position()
	await create_timer(0.12, true).timeout
	check(paused and music.stream_paused, "Gameplay pause also pauses music")
	check(absf(music.get_playback_position() - position) < 0.03, "Paused music retains its playback position")
	check(atmosphere.stream_paused and absf(atmosphere.get_playback_position() - atmosphere_position) < 0.03, "Atmosphere pauses at its current position together with music")


func run() -> void:
	var main := prepare_run()
	var music: AudioStreamPlayer = main.get_node("BackgroundMusic")
	var stream := music.stream as AudioStreamWAV
	var atmosphere: AudioStreamPlayer = main.get_node("BackgroundAtmosphere")
	var atmosphere_stream := atmosphere.stream as AudioStreamWAV
	await create_timer(0.1).timeout
	check(stream != null and stream.resource_path == TRACK_PATH, "Uses the exact existing Background foley.wav source")
	check(music.autoplay and music.playing and music.get_playback_position() > 0.0, "Music starts automatically with gameplay")
	check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end > 0, "Imported WAV loops forwards across the full track")
	check(is_equal_approx(float(stream.loop_end) / stream.mix_rate, stream.get_length()), "Loop endpoint covers the complete source")
	check(is_equal_approx(music.volume_linear, db_to_linear(-26.0)), "Music amplitude is attenuated to approximately five percent")
	check(atmosphere_stream != null and atmosphere_stream.resource_path == ATMOSPHERE_PATH, "Uses the replacement background_atmos.wav source")
	check(atmosphere.autoplay and atmosphere.playing and atmosphere.get_playback_position() > 0.0 and music.playing, "Atmosphere and existing music start automatically together")
	check(atmosphere.volume_db == -30.0 and atmosphere.volume_linear < music.volume_linear, "Atmosphere gain is lower than the existing background gain")
	check(atmosphere_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and atmosphere_stream.loop_begin == 0 and is_equal_approx(float(atmosphere_stream.loop_end) / atmosphere_stream.mix_rate, atmosphere_stream.get_length()), "Atmosphere WAV loops forwards across its full length")
	print("Atmosphere imported WAV: rate=", atmosphere_stream.mix_rate, " Hz, length=", atmosphere_stream.get_length(), " s, loop_begin=", atmosphere_stream.loop_begin, ", loop_end=", atmosphere_stream.loop_end, ", format=", atmosphere_stream.format)
	check(atmosphere.get_signal_connection_list(&"finished").is_empty(), "Atmosphere uses native WAV looping with no finished restart callback")
	var import_settings := ConfigFile.new()
	check(import_settings.load(ATMOSPHERE_PATH + ".import") == OK and not import_settings.get_value("params", "edit/normalize"), "Atmosphere source is imported without normalization")
	check_playback(main, music, stream)
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
	# Exercise the real loop boundary without waiting the full 23-second track.
	music.seek(stream.get_length() - 0.15)
	await create_timer(0.45).timeout
	check(music.playing and music.get_playback_position() < 1.0, "Music repeats automatically after the end of the track")
	for _cycle in 2:
		atmosphere.seek(atmosphere_stream.get_length() - 0.15)
		var seam_playback := atmosphere.get_stream_playback()
		await create_timer(0.45).timeout
		check(atmosphere.playing and atmosphere.get_playback_position() < 1.0 and music.playing and atmosphere.get_stream_playback() == seam_playback, "Replacement atmosphere loops internally without replacing playback while existing music continues")
	music.seek(2.0)
	atmosphere.seek(2.0)
	await create_timer(0.1).timeout
	var info = main.get_node("CharacterInfoPanel")
	var rewards: UpgradeSystem = main.get_node("UpgradeSystem")
	var player: Player = main.get_node("Player")
	for modal in ["info", "upgrade", "chapter"]:
		var music_playback := music.get_stream_playback()
		var atmosphere_playback := atmosphere.get_stream_playback()
		if modal == "info":
			info.open_panel()
		else:
			if modal == "chapter":
				player.level = main.get_node("ChapterPerkManager").catalog.perks[0].milestone - 1
				player.xp = 0
			player.add_xp(player.get_xp_required() - player.xp)
		if modal == "info":
			await check_paused(music)
		else:
			var before_music := music.get_playback_position()
			var before_atmosphere := atmosphere.get_playback_position()
			await create_timer(0.2, true).timeout
			check(paused and main.get_node("ChapterPerkMenu" if modal == "chapter" else "UpgradeMenu").visible, "Level-up menu still pauses gameplay")
			check(not music.stream_paused and music.playing and music.get_playback_position() > before_music, "Music continues during the level-up menu")
			check(not atmosphere.stream_paused and atmosphere.playing and atmosphere.get_playback_position() > before_atmosphere, "Atmosphere continues during the level-up menu")
		var position := music.get_playback_position()
		var atmosphere_position := atmosphere.get_playback_position()
		if modal == "info":
			info.close_panel()
		elif modal == "chapter":
			rewards.select_chapter_perk(rewards.chapter_offered[0].id)
		else:
			rewards.select_upgrade(rewards.offered[0].id)
		await create_timer(0.12).timeout
		check(not paused and not music.stream_paused and music.get_playback_position() > position, "Closing a modal resumes music without restarting")
		check(not atmosphere.stream_paused and atmosphere.get_playback_position() > atmosphere_position and atmosphere.get_stream_playback() == atmosphere_playback, "Closing a modal resumes the same atmosphere playback without restarting")
		check(music.get_stream_playback() == music_playback, "Menu opening and closing do not restart the music")
		check_playback(main, music, stream)
	# Several levels from one pickup must keep both layers continuous across menus.
	player.add_xp(player.get_xp_required() - player.xp)
	player.add_xp(player.get_xp_required() - player.xp)
	check(rewards.pending_levels == 2 and paused, "Multiple earned levels queue while gameplay stays paused")
	var queued_music := music.get_stream_playback()
	var queued_atmosphere := atmosphere.get_stream_playback()
	for _selection in 2:
		var before_music := music.get_playback_position()
		var before_atmosphere := atmosphere.get_playback_position()
		await create_timer(0.15, true).timeout
		check(music.get_playback_position() > before_music and atmosphere.get_playback_position() > before_atmosphere, "Both layers continue throughout queued level-up choices")
		rewards.select_upgrade(rewards.offered[0].id)
		await process_frame
	check(not paused and rewards.pending_levels == 0 and music.get_stream_playback() == queued_music and atmosphere.get_stream_playback() == queued_atmosphere, "Finishing a reward queue keeps original audio playback")
	info.open_panel()
	await check_paused(music)
	info.close_panel()
	await create_timer(0.1).timeout
	var before_boss := music.get_playback_position()
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
	check(music.get_playback_position() > before_boss, "Boss spawn and repeated F10 preserve continuous playback")
	check(atmosphere.get_playback_position() > atmosphere_before_boss and atmosphere.get_stream_playback() == atmosphere_before_skip, "F10 boss spawn and repeat keep the same atmosphere playback")
	check_playback(main, music, stream)
	# Terminal Victory must override the music exception even during an upgrade.
	player.add_xp(player.get_xp_required() - player.xp)
	await create_timer(0.1, true).timeout
	check(paused and music.playing and atmosphere.playing, "Background audio plays during a pending boss-fight reward")
	encounter.boss.take_damage(encounter.boss.current_health + encounter.boss.armor)
	await check_paused(music)
	check(encounter.run_ended and encounter.hud.get_node("HUD/Victory").visible, "Victory still pauses the run")
	check_playback(main, music, stream)
	main.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(music) and not is_instance_valid(atmosphere), "Run teardown removes both audio players")
	paused = false
	main = prepare_run()
	music = main.get_node("BackgroundMusic")
	atmosphere = main.get_node("BackgroundAtmosphere")
	await create_timer(0.1).timeout
	check_playback(main, music, stream)
	check(not music.stream_paused and music.get_playback_position() < 1.0, "New run starts one fresh music playback")
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
	check_playback(main, music, stream)
	var fresh_player: Player = main.get_node("Player")
	fresh_player.add_xp(fresh_player.get_xp_required())
	await create_timer(0.1, true).timeout
	check(paused and music.playing and atmosphere.playing, "Background audio continues during a fresh run's reward menu")
	fresh_player.take_damage(1000.0)
	await check_paused(music)
	check(fresh_player.current_health == 0.0, "Death overrides reward-menu background playback")
	main.queue_free()
	await process_frame
	await process_frame
	# Let the audio mixer release stopped playback before the test exits.
	paused = false
	await create_timer(0.15).timeout
	print("PASS: ", checks, " background music and atmosphere startup/loop/volume/modal/boss/Victory/reload checks")
	quit()
