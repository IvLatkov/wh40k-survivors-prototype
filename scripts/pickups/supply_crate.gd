class_name SupplyCrate
extends Area2D

signal collected

var _collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property($Visual, "position:y", -2.0, 1.2)
	bob.tween_property($Visual, "position:y", 0.0, 1.2)


func _on_body_entered(body: Node2D) -> void:
	if _collected or not body is Player or body.current_health <= 0:
		return
	_collected = true
	hide()
	set_deferred(&"monitoring", false)
	# Pause/UI changes and removal happen after the physics query has finished.
	_complete_collection.call_deferred()


func _complete_collection() -> void:
	collected.emit()
	queue_free()


func retire() -> void:
	_collected = true
	hide()
	set_deferred(&"monitoring", false)
	queue_free()
