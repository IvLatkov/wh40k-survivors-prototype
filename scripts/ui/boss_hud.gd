extends CanvasLayer

@onready var display: VBoxContainer = $HUD/BossDisplay
@onready var bar: ProgressBar = $HUD/BossDisplay/HealthBar
@onready var health_label: Label = $HUD/BossDisplay/HealthLabel
@onready var victory_overlay: ColorRect = $HUD/Victory


func _ready() -> void:
	display.hide()
	victory_overlay.hide()


func bind_boss(boss: Warboss) -> void:
	boss.health_changed.connect(_update_health)
	_update_health(boss.current_health, boss.max_health)
	display.show()


func _update_health(health: float, maximum: float) -> void:
	bar.max_value = maximum
	bar.value = health
	health_label.text = "%d / %d" % [ceili(health), ceili(maximum)]


func show_victory() -> void:
	display.hide()
	victory_overlay.show()
