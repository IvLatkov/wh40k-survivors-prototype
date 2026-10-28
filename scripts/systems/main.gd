extends Node2D

@onready var player: Player = $Player
@onready var health_hud: HealthHud = $HealthHUD
@onready var enemy_spawner: EnemySpawner = $EnemySpawner


func _ready() -> void:
	var blood_pool := BloodBurstPool.new()
	blood_pool.name = "BloodBurstPool"
	add_child(blood_pool)
	var number_pool := DamageNumberPool.new()
	number_pool.name = "DamageNumberPool"
	add_child(number_pool)
	health_hud.bind_run_clock($RunClock)
	enemy_spawner.bind_run_clock($RunClock)
	health_hud.bind_player(player)
	health_hud.bind_enemy_spawner(enemy_spawner)
	$UpgradeSystem.choices_ready.connect($UpgradeMenu.show_choices)
	$UpgradeSystem.selection_finished.connect($UpgradeMenu.hide)
	$UpgradeMenu.upgrade_selected.connect($UpgradeSystem.select_upgrade)
	$ChapterPerkManager.bind_player(player)
	$UpgradeSystem.chapter_manager = $ChapterPerkManager
	$UpgradeMenu.stats = player.combat_stats
	$UpgradeSystem.chapter_choices_ready.connect($ChapterPerkMenu.show_chapter_choices)
	$UpgradeSystem.selection_finished.connect($ChapterPerkMenu.hide)
	$ChapterPerkMenu.upgrade_selected.connect($UpgradeSystem.select_chapter_perk)
	$UpgradeSystem.ultimate_selected.connect(player.get_node("Bolter").activate_ultimate)
	$UpgradeSystem.ultimate_selected.connect(player.get_node("KnifeAttack").activate_ultimate)
	$UpgradeSystem.bind_player(player)
	var reward_menus: Array[CanvasLayer] = [$UpgradeMenu, $ChapterPerkMenu]
	$CharacterInfoPanel.bind_player(player, $UpgradeSystem, reward_menus)
