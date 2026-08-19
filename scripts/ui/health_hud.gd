class_name HealthHud
extends CanvasLayer

@onready var health_label: Label = $HUD/HealthDisplay/HealthLabel
@onready var health_bar: ProgressBar = $HUD/HealthDisplay/HealthBar
@onready var death_label: Label = $HUD/DeathLabel
@onready var performance_label: Label = $HUD/PerformanceLabel
@onready var performance_update_timer: Timer = $PerformanceUpdateTimer

@export var show_performance_counters: bool = true

var _enemy_spawner: EnemySpawner


func bind_player(player: Player) -> void:
	player.health_changed.connect(_on_player_health_changed)
	player.health_depleted.connect(_on_player_health_depleted)
	_on_player_health_changed(player.current_health, player.max_health)


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
	health_label.text = "HP %d / %d" % [roundi(current_health), roundi(max_health)]


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
