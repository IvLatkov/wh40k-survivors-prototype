class_name Warboss
extends Enemy

signal defeated
signal state_changed(next_state: State)
signal shot_fired(projectile: BoltProjectile)

enum State { CHASE, CLAW_WINDUP, CLAW_SWING, CLAW_RECOVERY, GUN_WINDUP, GUN_BURST, GUN_RECOVERY, DEAD }

const SHOT := preload("res://scenes/projectiles/warboss_projectile.tscn")
const SLASH := preload("res://scenes/effects/knife_slash.tscn")

@export var armor: float = 5.0
@export var claw_trigger_range: float = 90.0
@export var claw_hit_range: float = 105.0
@export var claw_damage: float = 12.0
@export var claw_windup: float = 0.55
@export var claw_recovery: float = 0.45
@export var claw_cooldown: float = 1.8
@export var gun_range: float = 550.0
@export var gun_windup: float = 0.45
@export var gun_shot_interval: float = 0.18
@export var gun_cooldown: float = 3.5
@export var gun_recovery: float = 0.35

@onready var phase_timer: Timer = $PhaseTimer
@onready var claw_timer: Timer = $ClawCooldown
@onready var gun_timer: Timer = $GunCooldown
@onready var flash_timer: Timer = $HitFlashTimer

var state: State = State.CHASE
var attack_direction: Vector2 = Vector2.RIGHT
var claw_damage_applied: bool = false
var shots_fired: int = 0


func _ready() -> void:
	super._ready()
	phase_timer.timeout.connect(_on_phase_timeout)
	flash_timer.timeout.connect(_update_tint)
	damage_received.connect(_on_hit)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if not is_instance_valid(target) or (target is Player and target.current_health <= 0.0):
		phase_timer.stop()
		_set_state(State.CHASE)
		velocity = Vector2.ZERO
		return
	if state != State.CHASE:
		velocity = Vector2.ZERO
		return
	var distance := global_position.distance_to(target.global_position)
	if distance <= claw_trigger_range and claw_timer.is_stopped():
		claw_damage_applied = false
		_lock_direction()
		_start_phase(State.CLAW_WINDUP, claw_windup)
	elif distance > claw_trigger_range and distance <= gun_range and gun_timer.is_stopped():
		shots_fired = 0
		_lock_direction()
		_start_phase(State.GUN_WINDUP, gun_windup)
	else:
		# Reuse the existing bounded spatial-grid separation and chase movement.
		super._physics_process(delta)


func _lock_direction() -> void:
	attack_direction = global_position.direction_to(target.global_position)
	if attack_direction.is_zero_approx():
		attack_direction = Vector2.RIGHT
	_update_visual_facing(attack_direction.x)
	velocity = Vector2.ZERO


func _set_state(value: State) -> void:
	state = value
	_update_tint()
	queue_redraw()
	state_changed.emit(state)


func _start_phase(value: State, duration: float) -> void:
	_set_state(value)
	phase_timer.start(duration)


func _on_phase_timeout() -> void:
	if state == State.DEAD:
		return
	match state:
		State.CLAW_WINDUP:
			_set_state(State.CLAW_SWING)
			_apply_claw_hit()
			_spawn_slash()
			# A completed swing owns a real cooldown, including on misses.
			claw_timer.start(claw_cooldown)
			_start_phase(State.CLAW_RECOVERY, claw_recovery)
		State.GUN_WINDUP, State.GUN_BURST:
			_fire_shot()
		State.CLAW_RECOVERY, State.GUN_RECOVERY:
			_set_state(State.CHASE)


func _apply_claw_hit() -> void:
	if claw_damage_applied or state != State.CLAW_SWING:
		return
	claw_damage_applied = true
	if not is_instance_valid(target) or not target is Player:
		return
	var offset := target.global_position - global_position
	if offset.length_squared() <= claw_hit_range * claw_hit_range and offset.dot(attack_direction) >= 0.0:
		# Dodge, reduction, armor and i-frames remain entirely player-owned.
		(target as Player).take_damage(claw_damage)


func _fire_shot() -> void:
	if state == State.DEAD:
		return
	if not is_instance_valid(target):
		_set_state(State.CHASE)
		return
	_set_state(State.GUN_BURST)
	var projectile := SHOT.instantiate() as BoltProjectile
	var direction := attack_direction.rotated((shots_fired - 1) * 0.035)
	projectile.position = (get_parent() as Node2D).to_local(global_position + direction * 48.0)
	projectile.set_direction(direction)
	get_parent().add_child.call_deferred(projectile)
	shots_fired += 1
	shot_fired.emit(projectile)
	if shots_fired < 3:
		phase_timer.start(gun_shot_interval)
	else:
		gun_timer.start(gun_cooldown)
		_start_phase(State.GUN_RECOVERY, gun_recovery)


func _spawn_slash() -> void:
	var slash := SLASH.instantiate() as KnifeSlashEffect
	slash.position = (get_parent() as Node2D).to_local(global_position + attack_direction * 45.0)
	slash.scale = Vector2.ONE * 1.3
	slash.modulate = Color(1.0, 0.6, 0.25, 0.8)
	slash.set_direction(attack_direction)
	get_parent().add_child(slash)


func take_damage(amount: float, critical: bool = false, attacker_stats: CombatStats = null, source: StringName = &"") -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	# Weapon/crit calculations already happened at the source. Every weapon
	# reaches this override through the existing Enemy damage entry point.
	super.take_damage(maxf(1.0, amount - armor), critical, attacker_stats, source)


func _on_hit(_amount: float, _critical: bool) -> void:
	flash_timer.start(0.08)
	_update_tint()


func _update_tint() -> void:
	visual.self_modulate = Color(1.7, 1.7, 1.7) if not flash_timer.is_stopped() else (Color(1.15, 0.85, 0.55) if state in [State.CLAW_WINDUP, State.GUN_WINDUP] else Color.WHITE)


func _draw() -> void:
	if state == State.CLAW_WINDUP:
		var angle := attack_direction.angle()
		var points := PackedVector2Array([Vector2.ZERO])
		for index in 25:
			points.append(Vector2.from_angle(angle - PI * 0.5 + PI * index / 24.0) * claw_hit_range)
		draw_colored_polygon(points, Color(1.0, 0.35, 0.05, 0.15))
		draw_arc(Vector2.ZERO, claw_hit_range, angle - PI * 0.5, angle + PI * 0.5, 32, Color(1, 0.55, 0.1, 0.9), 3.0)
	elif state == State.GUN_WINDUP:
		draw_line(attack_direction * 48.0, attack_direction * gun_range, Color(1.0, 0.25, 0.05, 0.6), 2.0)


func die() -> void:
	if state == State.DEAD:
		return
	_set_state(State.DEAD)
	phase_timer.stop()
	claw_timer.stop()
	gun_timer.stop()
	flash_timer.stop()
	velocity = Vector2.ZERO
	set_physics_process(false)
	defeated.emit()
	# Deliberately bypass Enemy.die(): no XP drop and no reward queue.
	queue_free()
