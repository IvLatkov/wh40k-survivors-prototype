class_name BloodBurstPool
extends Node

# Only blood is pooled: profiling showed CPUParticles2D construction dominates
# mass deaths. Idle nodes remain owned by this scene and are freed with it.
const BURST := preload("res://scenes/effects/blood_burst.tscn")
const PREWARM := 64
const MAX_IDLE := 128
var _idle: Array[CPUParticles2D] = []

func _ready() -> void:
	for index in PREWARM:
		var effect := _create()
		effect.emitting = false
		effect.visible = false
		effect.get_node("CleanupTimer").stop()
		_idle.append(effect)

func _create() -> CPUParticles2D:
	var effect := BURST.instantiate() as CPUParticles2D
	var timer := effect.get_node("CleanupTimer") as Timer
	timer.timeout.disconnect(effect.queue_free)
	timer.timeout.connect(_release.bind(effect))
	add_child(effect)
	return effect

func spawn(at: Vector2) -> void:
	# Enemy deaths may occur during physics callbacks; preserve deferred insertion.
	_activate.call_deferred(at)

func _activate(at: Vector2) -> void:
	var profile_start := Time.get_ticks_usec() if CombatProfile.enabled else 0
	var effect := _idle.pop_back() as CPUParticles2D if not _idle.is_empty() else _create()
	effect.global_position = at
	effect.visible = true
	effect.restart()
	(effect.get_node("CleanupTimer") as Timer).start()
	CombatProfile.finish(&"blood_activation", profile_start)
	CombatProfile.count_event(&"blood_activated")
	CombatProfile.count_event(&"vfx_spawned_pooled")

func _release(effect: CPUParticles2D) -> void:
	effect.emitting = false
	effect.visible = false
	if _idle.size() < MAX_IDLE:
		_idle.append(effect)
	else:
		effect.queue_free()
