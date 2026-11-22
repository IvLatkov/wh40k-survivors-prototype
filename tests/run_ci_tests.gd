extends SceneTree

const TESTS := [
	"res://tests/xp_progression_test.gd",
	"res://tests/armor_test.gd",
	"res://tests/additive_ork_spawning_test.gd",
	"res://tests/combat_optimization_test.gd",
	"res://tests/ultimate_upgrades_test.gd",
	"res://tests/xp_pickup_visual_test.gd",
	"res://tests/terrain_tree_test.gd",
	"res://tests/main_menu_test.gd",
	"res://tests/background_music_test.gd",
]


func _initialize() -> void:
	run_tests.call_deferred()


func run_tests() -> void:
	var godot_executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")

	print("")
	print("========================================")
	print(" WH40K SURVIVORS - CI TEST SUITE")
	print("========================================")
	print("Running %d tests..." % TESTS.size())
	print("")

	var passed := 0

	for test_path in TESTS:
		print("----------------------------------------")
		print("RUNNING: %s" % test_path)
		print("----------------------------------------")

		var output: Array = []

		var exit_code := OS.execute(
			godot_executable,
			[
				"--headless",
				"--path",
				project_path,
				"--script",
				test_path,
			],
			output,
			true
		)

		for line in output:
			print(line)

		if exit_code != 0:
			print("")
			push_error("FAILED: %s" % test_path)
			print("Exit code: %d" % exit_code)
			print("")
			print("========================================")
			print(" CI TEST SUITE FAILED")
			print(" Passed: %d/%d" % [passed, TESTS.size()])
			print(" Failed: %s" % test_path)
			print("========================================")

			quit(1)
			return

		passed += 1
		print("PASSED: %s" % test_path)
		print("")

	print("========================================")
	print(" CI TEST SUITE PASSED")
	print(" Passed: %d/%d" % [passed, TESTS.size()])
	print("========================================")

	quit(0)
