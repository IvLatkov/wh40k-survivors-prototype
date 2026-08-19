extends Node2D

@onready var player: Player = $Player
@onready var health_hud: HealthHud = $HealthHUD
@onready var enemy_spawner: EnemySpawner = $EnemySpawner


func _ready() -> void:
	health_hud.bind_player(player)
	health_hud.bind_enemy_spawner(enemy_spawner)
