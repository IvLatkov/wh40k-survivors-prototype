extends SceneTree

const MENU := preload("res://scenes/ui/main_menu.tscn")
const SAMPLE_FRAMES := 600


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	root.size = Vector2i(1152, 648)
	# Alternate order to expose warm-up/order noise; no captures inside measurement.
	for enabled: bool in [false, true, true, false]:
		var menu := MENU.instantiate() as MainMenu
		(menu.get_node("MenuPolish") as MainMenuPolish).enabled = enabled
		root.add_child(menu)
		current_scene = menu
		for _frame in 180:
			await process_frame
		var samples: Array[float] = []
		var draw_calls := 0.0
		var start := Time.get_ticks_usec()
		for _frame in SAMPLE_FRAMES:
			await process_frame
			samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		var total := 0.0
		for sample in samples:
			total += sample
		samples.sort()
		print("MENU_POLISH_PERF enabled=%s frames=%d process_mean_ms=%.4f process_p95_ms=%.4f wall_frame_ms=%.4f draw_calls_mean=%.1f active_tweens=%d" % [enabled, SAMPLE_FRAMES, total / SAMPLE_FRAMES, samples[int(SAMPLE_FRAMES * 0.95)], elapsed / SAMPLE_FRAMES, draw_calls / SAMPLE_FRAMES, get_processed_tweens().size()])
		if enabled:
			var tweens := get_processed_tweens()
			var update_start := Time.get_ticks_usec()
			for _step in 10000:
				for tween in tweens:
					tween.custom_step(1.0 / 120.0)
			print("MENU_POLISH_UPDATE_ONLY steps=10000 tweens=%d mean_usec=%.3f (manual tween updates, excludes rendering)" % [tweens.size(), (Time.get_ticks_usec() - update_start) / 10000.0])
		menu.queue_free()
		await process_frame
		await process_frame
	quit(0)
