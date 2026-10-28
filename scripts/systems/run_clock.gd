class_name RunClock
extends Node

signal seconds_changed(elapsed_seconds: int)

var elapsed_time: float = 0.0
var _displayed_seconds: int = 0


func _process(delta: float) -> void:
	elapsed_time += delta
	var seconds := floori(elapsed_time)
	if seconds != _displayed_seconds:
		_displayed_seconds = seconds
		seconds_changed.emit(seconds)
