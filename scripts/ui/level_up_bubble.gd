extends Control

const BATTLE_CRIES: Array[String] = [
	"FOR THE EMPEROR!",
	"COURAGE AND HONOUR!",
	"NO FEAR!",
	"GLORY TO THE IMPERIUM!",
	"THE EMPEROR PROTECTS!",
	"VICTORY OR DEATH!",
	"HONOUR AND DUTY!",
	"BY THE EMPEROR'S WILL!",
]

@export var display_duration: float = 1.0
@export var fade_duration: float = 0.4

var _fade_tween: Tween
var _last_cry_index: int = -1

@onready var message: Label = $Panel/Message


func show_message() -> void:
	var cry_index := randi_range(0, BATTLE_CRIES.size() - 1)
	if _last_cry_index >= 0:
		# Choose uniformly from every line except the previous one.
		cry_index = randi_range(0, BATTLE_CRIES.size() - 2)
		if cry_index >= _last_cry_index:
			cry_index += 1
	_last_cry_index = cry_index
	message.text = BATTLE_CRIES[cry_index]
	if _fade_tween != null:
		_fade_tween.kill()
	modulate.a = 1.0
	show()
	_fade_tween = create_tween()
	_fade_tween.tween_interval(display_duration)
	_fade_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	_fade_tween.tween_callback(hide)
