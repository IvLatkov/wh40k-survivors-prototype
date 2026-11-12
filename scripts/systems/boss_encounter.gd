class_name BossEncounter
extends Node

signal boss_spawned(boss: Warboss)
signal victory

const BOSS := preload("res://scenes/enemies/warboss.tscn")
const SPAWN_SECONDS: int = 600

var warboss_spawned: bool = false
var run_ended: bool = false
var boss: Warboss
var _player: Player
var _spawner: EnemySpawner
var _rewards: UpgradeSystem
var _info: CanvasLayer
var _menus: Array[CanvasLayer] = []
var _bound: bool = false

@onready var hud: CanvasLayer = $BossHUD


func bind_run(clock: RunClock, player: Player, spawner: EnemySpawner, rewards: UpgradeSystem, info: CanvasLayer, menus: Array[CanvasLayer]) -> void:
	if _bound:
		return
	_bound = true
	_player = player
	_spawner = spawner
	_rewards = rewards
	_info = info
	_menus = menus
	clock.seconds_changed.connect(_on_seconds_changed)
	_on_seconds_changed(floori(clock.elapsed_time))


func _on_seconds_changed(seconds: int) -> void:
	if seconds < SPAWN_SECONDS or warboss_spawned or run_ended or _player.current_health <= 0.0:
		return
	# Resolve placement before committing the encounter. A completely blocked
	# area retries on a later clock tick instead of losing or duplicating the boss.
	boss = BOSS.instantiate() as Warboss
	var safe_position := _spawner.find_clear_spawn_position(_spawner._get_spawn_origin(), boss)
	if safe_position == Vector2.INF:
		boss.free()
		boss = null
		return
	# The run-owned flag is set before insertion/signals and never resets on death.
	warboss_spawned = true
	_spawner.stop_normal_spawning()
	boss.position = (get_parent() as Node2D).to_local(safe_position)
	boss.set_target(_player)
	boss.set_spatial_grid(_spawner.spatial_grid)
	boss.defeated.connect(_on_boss_defeated)
	get_parent().add_child(boss)
	# Boss is targetable by the normal weapon grid but does not consume the
	# ordinary enemy budget. Only the pre-encounter survivors remain alongside it.
	_spawner.spatial_grid.register_enemy(boss)
	boss_spawned.emit(boss)


func _on_boss_defeated() -> void:
	if run_ended:
		return
	run_ended = true
	_spawner.set_process(false)
	_info.end_run()
	_rewards.end_run()
	for menu in _menus:
		menu.end_run()
	hud.show_victory()
	# Terminal pause wins over informational/reward pause ownership. Explicit
	# always-processing menus are also disabled, so stale UI cannot resume play.
	# Defeated may originate inside Area2D.body_entered. Changing a subtree's
	# process mode removes CollisionObjects; defer that until queries finish.
	get_parent().set_deferred(&"process_mode", Node.PROCESS_MODE_DISABLED)
	get_tree().paused = true
	victory.emit()
