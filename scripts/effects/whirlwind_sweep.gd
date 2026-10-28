extends Node2D

var radius: float = 55.0
var _remaining: float = 0.18


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		queue_free()
	else:
		modulate.a = _remaining / 0.18
		queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.85, 0.9, 1.0), 3.0, true)
