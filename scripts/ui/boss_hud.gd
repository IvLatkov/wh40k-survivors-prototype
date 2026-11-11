extends CanvasLayer

@onready var victory_overlay: ColorRect = $HUD/Victory


func _ready() -> void:
	victory_overlay.hide()


func show_victory() -> void:
	victory_overlay.show()
