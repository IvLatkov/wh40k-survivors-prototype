class_name WarbossProjectile
extends BoltProjectile


func _ready() -> void:
	splash_enabled = false
	can_fork = false
	super._ready()


func _on_body_entered(body: Node2D) -> void:
	if _has_impacted or not body is Player:
		return
	_has_impacted = true
	(body as Player).take_damage(damage)
	set_deferred(&"monitoring", false)
	queue_free()
