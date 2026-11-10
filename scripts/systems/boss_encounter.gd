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
	# Run-owned flag is set before insertion/signals. Chunk streaming, repeated
	# clock notifications, rebinds or removal of the boss cannot respawn it.
	warboss_spawned = true
	boss = BOSS.instantiate() as Warboss
	boss.position = (get_parent() as Node2D).to_local(_spawner._get_spawn_origin())
	boss.set_target(_player)
	boss.set_spatial_grid(_spawner.spatial_grid)
	boss.defeated.connect(_on_boss_defeated)
	get_parent().add_child(boss)
	# Boss is targetable by the normal weapon grid but does not consume the
	# ordinary 200-enemy budget or change normal spawn cadence/probabilities.
	_spawner.spatial_grid.register_enemy(boss)
	hud.bind_boss(boss)
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
