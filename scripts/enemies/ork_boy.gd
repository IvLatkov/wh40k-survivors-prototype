class_name OrkBoy
extends Enemy

enum State { CHASE, WINDUP, SWING, RECOVERY }

const SLASH_SCENE := preload("res://scenes/effects/knife_slash.tscn")

@export var attack_range: float = 65.0
@export var hit_range: float = 75.0
## Measured from wind-up start; the next preparation overlaps its last 0.3s.
@export var attack_cooldown: float = 1.25
@export_range(0, 3, 1) var hit_frame: int = 2
@export var attack_delay_min: float = 0.10
@export var attack_delay_max: float = 0.30
@export var preparation_cancel_range: float = 85.0
@export var impact_pause_duration: float = 0.05
@export var hit_flash_duration: float = 0.08
@export var telegraph_tint: Color = Color(1.15, 1.10, 1.02)
@export var hit_flash_tint: Color = Color(1.7, 1.7, 1.7)
@export var slash_offset: Vector2 = Vector2(32.0, -12.0)
@export var slash_scale: float = 0.75
## The attack sheet draws the same body slightly smaller than the walk sheet.
@export var attack_art_scale: float = 1.12

var state: State = State.CHASE
var attack_damage_applied: bool = false
var _cooldown_remaining: float = 0.0
var _pre_attack_remaining: float = -1.0
var _attack_elapsed: float = 0.0
var _attack_timeout: float = 1.25
var _attack_facing: float = 1.0
var _impact_pause_remaining: float = 0.0
var _hit_flash_remaining: float = 0.0
var _attack_rng := RandomNumberGenerator.new()
var _walk_scale: Vector2
var _walk_position: Vector2
var _base_tint: Color


func _ready() -> void:
	super._ready()
	_attack_rng.randomize()
	_walk_scale = visual.scale
	_walk_position = visual.position
	_base_tint = visual.self_modulate
	damage_received.connect(_on_damage_received)
	visual.frame_changed.connect(_on_visual_frame_changed)
	visual.animation_changed.connect(_sync_visual_alignment)
	visual.animation_finished.connect(_on_visual_animation_finished)
	# A watchdog only cancels interrupted/stalled attacks; it never causes damage.
	var frames := visual.sprite_frames
	var duration := 0.0
	for index in frames.get_frame_count(&"attack"):
		duration += frames.get_frame_duration(&"attack", index) / maxf(0.01, frames.get_animation_speed(&"attack"))
	_attack_timeout = maxf(attack_cooldown, duration + impact_pause_duration + 0.2)


func _physics_process(delta: float) -> void:
	if current_health <= 0.0 or is_queued_for_deletion():
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	_hit_flash_remaining = maxf(0.0, _hit_flash_remaining - delta)
	_update_tint()
	if not is_instance_valid(target) or (target is Player and (target as Player).current_health <= 0.0):
		_finish_attack()
		velocity = Vector2.ZERO
		visual.pause()
		return
	if state != State.CHASE:
		velocity = Vector2.ZERO
		_attack_elapsed += delta
		if _impact_pause_remaining > 0.0:
			_impact_pause_remaining = maxf(0.0, _impact_pause_remaining - delta)
			if _impact_pause_remaining <= 0.000001:
				_impact_pause_remaining = 0.0
				visual.play()
			else:
				return
		if visual.animation != &"attack" or not visual.is_playing() or _attack_elapsed >= _attack_timeout:
			_finish_attack()
		return
	var distance_squared := global_position.distance_squared_to(target.global_position)
	if _pre_attack_remaining >= 0.0:
		if distance_squared > preparation_cancel_range * preparation_cancel_range:
			_pre_attack_remaining = -1.0
		else:
			_pre_attack_remaining = maxf(0.0, _pre_attack_remaining - delta)
			if _pre_attack_remaining <= 0.0:
				_start_attack()
			else:
				_move_preparing(delta)
			return
	if target is Player and _cooldown_remaining <= attack_delay_max and distance_squared <= attack_range * attack_range:
		# Draw once per eligibility, using an independent RNG. During sustained
		# attacks this delay overlaps cooldown instead of extending every cycle.
		_pre_attack_remaining = maxf(_cooldown_remaining, _attack_rng.randf_range(attack_delay_min, attack_delay_max))
		_move_preparing(delta)
		return
	# Reuse distance throttling, movement, body collision, and local separation.
	super._physics_process(delta)
	_update_walk_animation()


func _move_preparing(delta: float) -> void:
	# No forward pressure while waiting; preserve the same local separation.
	velocity = _get_separation_direction(delta) * separation_strength * _individual_movement_speed
	move_and_slide()
	_update_visual_facing(target.global_position.x - global_position.x)
	_update_walk_animation()


func _update_walk_animation() -> void:
	if velocity.is_zero_approx():
		visual.pause()
		visual.frame = 0
	elif _full_simulation_enabled:
		visual.play(&"walk")


func _start_attack() -> void:
	if current_health <= 0.0 or is_queued_for_deletion() or not is_instance_valid(target):
		return
	state = State.WINDUP
	_pre_attack_remaining = -1.0
	velocity = Vector2.ZERO
	attack_damage_applied = false
	_cooldown_remaining = attack_cooldown
	_attack_elapsed = 0.0
	_impact_pause_remaining = 0.0
	_update_visual_facing(target.global_position.x - global_position.x)
	_attack_facing = -1.0 if visual.flip_h == sprite_faces_right else 1.0
	visual.stop()
	visual.play(&"attack")
	_update_tint()


func _on_visual_frame_changed() -> void:
	if state == State.CHASE or visual.animation != &"attack":
		return
	if current_health <= 0.0 or is_queued_for_deletion():
		return
	if visual.frame > hit_frame:
		state = State.RECOVERY
		_update_tint()
		return
	if visual.frame != hit_frame or attack_damage_applied:
		return
	state = State.SWING
	_update_tint()
	# Consume the strike even on a miss or invulnerability: never retry a swing.
	attack_damage_applied = true
	_spawn_slash()
	if not is_instance_valid(target) or not target is Player:
		return
	var player := target as Player
	var offset := player.global_position - global_position
	# A broad horizontal half-plane matches the art's two facing directions.
	if offset.length_squared() > hit_range * hit_range or offset.x * _attack_facing < 0.0 or not player.can_take_damage():
		return
	var previous_health := player.current_health
	player.take_damage(get_attack_damage())
	if player.current_health < previous_health:
		# Only this Ork pauses; dodge and misses do not trigger impact feedback.
		_impact_pause_remaining = impact_pause_duration
		visual.pause()


func _spawn_slash() -> void:
	var effect := SLASH_SCENE.instantiate() as KnifeSlashEffect
	var effect_parent := get_parent() as Node2D
	effect.position = effect_parent.to_local(global_position + Vector2(slash_offset.x * _attack_facing, slash_offset.y))
	effect.scale = Vector2.ONE * slash_scale
	effect.modulate = Color(1.0, 0.75, 0.55, 0.7)
	effect.set_direction(Vector2(_attack_facing, 0.0))
	effect_parent.add_child(effect)
	effect.animated_sprite.speed_scale = 1.5


func _on_damage_received(_amount: float, _critical: bool) -> void:
	_hit_flash_remaining = hit_flash_duration
	_update_tint()


func _update_tint() -> void:
	var tint := Color.WHITE
	if _hit_flash_remaining > 0.0:
		tint = hit_flash_tint
	elif state == State.WINDUP:
		tint = telegraph_tint
	visual.self_modulate = _base_tint * tint


func _on_visual_animation_finished() -> void:
	if state != State.CHASE and visual.animation == &"attack":
		_finish_attack()


func _finish_attack() -> void:
	state = State.CHASE
	_pre_attack_remaining = -1.0
	_impact_pause_remaining = 0.0
	if visual.animation != &"walk":
		visual.play(&"walk")
	visual.pause()
	visual.frame = 0
	_update_tint()


func _sync_visual_alignment() -> void:
	var factor := attack_art_scale if visual.animation == &"attack" else 1.0
	visual.scale = _walk_scale * factor
	# Atlas margins put every frame's feet 200 source pixels below its center.
	visual.position = _walk_position - Vector2(0.0, 200.0 * _walk_scale.y * (factor - 1.0))


func die() -> void:
	if is_queued_for_deletion():
		return
	state = State.CHASE
	_pre_attack_remaining = -1.0
	_impact_pause_remaining = 0.0
	attack_damage_applied = true
	visual.stop()
	super.die()
