class_name HealthHud
extends CanvasLayer

const RunClockScript = preload("res://scripts/systems/run_clock.gd")

@onready var run_timer_label: Label = $HUD/RunTimerLabel
@onready var health_label: Label = $HUD/HealthDisplay/HealthLabel
@onready var health_bar: ProgressBar = $HUD/HealthDisplay/HealthBar
@onready var xp_label: Label = $HUD/XPDisplay/XPLabel
@onready var xp_bar: ProgressBar = $HUD/XPDisplay/XPBar
@onready var death_label: Label = $HUD/DeathLabel
@onready var performance_label: Label = $HUD/PerformanceLabel
@onready var performance_update_timer: Timer = $PerformanceUpdateTimer

@export var show_performance_counters: bool = true

var _enemy_spawner: EnemySpawner


func bind_run_clock(clock: RunClockScript) -> void:
	clock.seconds_changed.connect(_on_run_seconds_changed)
	_on_run_seconds_changed(floori(clock.elapsed_time))


func _on_run_seconds_changed(seconds: int) -> void:
	run_timer_label.text = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


func bind_player(player: Player) -> void:
	player.health_changed.connect(_on_player_health_changed)
	player.health_depleted.connect(_on_player_health_depleted)
	_on_player_health_changed(player.current_health, player.max_health)
	player.xp_changed.connect(_on_player_xp_changed)
	_on_player_xp_changed(player.xp, player.get_xp_required(), player.level)


func _on_player_xp_changed(current_xp: float, required_xp: int, current_level: int) -> void:
	xp_bar.max_value = required_xp
	xp_bar.value = current_xp
	xp_label.text = "LEVEL %d    XP %d / %d" % [current_level, floori(current_xp + Player.XP_COMPARISON_EPSILON), required_xp]


func bind_enemy_spawner(enemy_spawner: EnemySpawner) -> void:
	_enemy_spawner = enemy_spawner
	performance_label.visible = show_performance_counters
	if not show_performance_counters:
		return

	performance_update_timer.timeout.connect(_update_performance_counters)
	performance_update_timer.start()
	_update_performance_counters()


func _on_player_health_changed(current_health: float, max_health: float) -> void:
	health_bar.max_value = max_health
	health_bar.value = current_health
	health_label.text = "HP %d / %d" % [roundi(current_health + Player.HEALTH_ROUNDING_EPSILON), roundi(max_health + Player.HEALTH_ROUNDING_EPSILON)]


func _on_player_health_depleted() -> void:
	death_label.show()
	get_tree().paused = true


func _update_performance_counters() -> void:
	if not is_instance_valid(_enemy_spawner):
		return

	performance_label.text = "FPS: %d\nEnemies: %d / %d" % [
		Engine.get_frames_per_second(),
		_enemy_spawner.get_active_enemy_count(),
		_enemy_spawner.get_target_enemy_count(),
	]
