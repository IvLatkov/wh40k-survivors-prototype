extends Node2D

# Local testing only. Release exports also reject this shortcut below.
const DEBUG_BOSS_SKIP_ENABLED: bool = true

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
	$BossEncounter.bind_run($RunClock, player, enemy_spawner, $UpgradeSystem, $CharacterInfoPanel, reward_menus)


func _unhandled_key_input(event: InputEvent) -> void:
	if not DEBUG_BOSS_SKIP_ENABLED or not OS.is_debug_build() or Engine.is_editor_hint():
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode != KEY_F10 and event.physical_keycode != KEY_F10:
		return
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed:
		return
	if get_tree().paused or player.current_health <= 0.0 or $BossEncounter.run_ended or $BossEncounter.warboss_spawned:
		return
	if $CharacterInfoPanel.visible or $UpgradeMenu.visible or $ChapterPerkMenu.visible or $UpgradeSystem.pending_levels > 0:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	get_viewport().set_input_as_handled()
	print("DEBUG: Jumping run clock to 10:00 for Warboss test.")
	$RunClock.advance_to(BossEncounter.SPAWN_SECONDS)
