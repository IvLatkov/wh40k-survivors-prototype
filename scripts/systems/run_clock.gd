class_name RunClock
extends Node

signal seconds_changed(elapsed_seconds: int)

var elapsed_time: float = 0.0
var _displayed_seconds: int = 0


func advance_to(seconds: float) -> void:
	# Forward-only time advancement uses the same notification path as a tick.
	_process(maxf(0.0, seconds - elapsed_time))


func _process(delta: float) -> void:
	elapsed_time += delta
	var seconds := floori(elapsed_time)
	if seconds != _displayed_seconds:
		_displayed_seconds = seconds
		seconds_changed.emit(seconds)
