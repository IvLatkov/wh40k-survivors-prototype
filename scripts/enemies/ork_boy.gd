class_name OrkBoy
extends Enemy

enum State { CHASE, ATTACK }

@export var attack_range: float = 65.0
@export var hit_range: float = 75.0
## Cooldown starts with the wind-up, so recovery is part of the 1.25s cycle.
@export var attack_cooldown: float = 1.25
@export_range(0, 3, 1) var hit_frame: int = 2
## The attack sheet draws the same body slightly smaller than the walk sheet.
@export var attack_art_scale: float = 1.12

var state: State = State.CHASE
var attack_damage_applied: bool = false
var _cooldown_remaining: float = 0.0
var _attack_elapsed: float = 0.0
var _attack_timeout: float = 1.25
var _attack_facing: float = 1.0
var _walk_scale: Vector2
var _walk_position: Vector2


func _ready() -> void:
	super._ready()
	_walk_scale = visual.scale
	_walk_position = visual.position
	visual.frame_changed.connect(_on_visual_frame_changed)
	visual.animation_changed.connect(_sync_visual_alignment)
	visual.animation_finished.connect(_on_visual_animation_finished)
	# A watchdog only cancels interrupted/stalled attacks; it never causes damage.
	var frames := visual.sprite_frames
	var duration := 0.0
	for index in frames.get_frame_count(&"attack"):
		duration += frames.get_frame_duration(&"attack", index) / maxf(0.01, frames.get_animation_speed(&"attack"))
	_attack_timeout = maxf(attack_cooldown, duration + 0.2)


func _physics_process(delta: float) -> void:
	if current_health <= 0.0 or is_queued_for_deletion():
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if not is_instance_valid(target):
		_finish_attack()
		velocity = Vector2.ZERO
		visual.pause()
		return
	if state == State.ATTACK:
		velocity = Vector2.ZERO
		_attack_elapsed += delta
		if visual.animation != &"attack" or not visual.is_playing() or _attack_elapsed >= _attack_timeout:
			_finish_attack()
		return
	if target is Player and (target as Player).current_health > 0.0 and _cooldown_remaining <= 0.0 and global_position.distance_squared_to(target.global_position) <= attack_range * attack_range:
		_start_attack()
		return
	# Reuse distance throttling, movement, body collision, and local separation.
	super._physics_process(delta)
	if velocity.is_zero_approx():
		visual.pause()
		visual.frame = 0
	elif _full_simulation_enabled:
		visual.play(&"walk")


func _start_attack() -> void:
	state = State.ATTACK
	velocity = Vector2.ZERO
	attack_damage_applied = false
	_cooldown_remaining = attack_cooldown
	_attack_elapsed = 0.0
	var horizontal := target.global_position.x - global_position.x
	_update_visual_facing(horizontal)
	_attack_facing = -1.0 if visual.flip_h == sprite_faces_right else 1.0
	visual.stop()
	visual.play(&"attack")


func _on_visual_frame_changed() -> void:
	if state != State.ATTACK or visual.animation != &"attack" or visual.frame != hit_frame or attack_damage_applied:
		return
	# Consume the strike even on a miss or invulnerability: never retry a swing.
	attack_damage_applied = true
	if current_health <= 0.0 or is_queued_for_deletion() or not is_instance_valid(target) or not target is Player:
		return
	var player := target as Player
	var offset := player.global_position - global_position
	if offset.length_squared() > hit_range * hit_range or offset.x * _attack_facing < 0.0 or not player.can_take_damage():
		return
	player.take_damage(get_attack_damage())


func _on_visual_animation_finished() -> void:
	if state == State.ATTACK and visual.animation == &"attack":
		_finish_attack()


func _finish_attack() -> void:
	state = State.CHASE
	if visual.animation != &"walk":
		visual.play(&"walk")


func _sync_visual_alignment() -> void:
	var factor := attack_art_scale if visual.animation == &"attack" else 1.0
	visual.scale = _walk_scale * factor
	# Atlas margins put every frame's feet 200 source pixels below its center.
	visual.position = _walk_position - Vector2(0.0, 200.0 * _walk_scale.y * (factor - 1.0))


func die() -> void:
	if is_queued_for_deletion():
		return
	state = State.CHASE
	attack_damage_applied = true
	visual.stop()
	super.die()
