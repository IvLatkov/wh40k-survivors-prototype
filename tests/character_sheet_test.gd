extends SceneTree

var checks: int = 0
var system: UpgradeSystem
var all_definitions: Array[UpgradeDefinition]

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize() -> void:
	run.call_deferred()

func definition(id: StringName) -> UpgradeDefinition:
	for value in all_definitions:
		if value.id == id:
			return value
	return null

func select(id: StringName) -> void:
	var choices: Array[UpgradeDefinition] = [definition(id)]
	for value in all_definitions:
		if value.id != id and choices.size() < 3:
			choices.append(value)
	system.definitions = choices
	system.queue_level()
	system.select_upgrade(id)
	system.definitions = all_definitions

func run() -> void:
	root.size = Vector2i(1152, 648)
	var main := preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var player: Player = main.get_node("Player")
	var panel = main.get_node("CharacterInfoPanel")
	system = main.get_node("UpgradeSystem")
	all_definitions = system.definitions.duplicate()
	main.get_node("EnemySpawner").set_process(false)
	player.set_physics_process(false)
	player.get_node("Bolter/FireTimer").stop()
	player.get_node("KnifeAttack").set_physics_process(false)
	var weapons: VBoxContainer = panel.content.get_node("Upgrades/Weapons")
	var generic: VBoxContainer = panel.content.get_node("Upgrades/Generic")
	panel.open_panel()
	check(panel.title.text == "CHARACTER" and panel.chapter_label.text == "Chapter: Ultramarines", "Character and Chapter headings")
	check(panel.visible and paused and panel.can_process(), "Sheet stays active while gameplay pauses")
	check(weapons.get_node("Count").text == "Weapon Upgrades: 0 / 4" and generic.get_node("Count").text == "Generic Upgrades: 0 / 4", "Empty ownership counters")
	for section in [weapons, generic]:
		check(section.get_node("Slots").get_child_count() == 4, "Exactly four slots per section")
		for slot in section.get_node("Slots").get_children():
			check(slot.get_node("Row/Name").text == "Empty" and slot.get_node("Row/Level").text == "", "Empty slots never invent ownership")
	check(panel.content.get_node("ChapterPerks/Owned").text == "None selected", "Unowned perks not displayed")
	var portrait: TextureRect = panel.content.get_node("Body/Portrait")
	check(portrait.texture == player.visual.sprite_frames.get_frame_texture(&"idle_right", 0) and portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and portrait.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Existing right-facing portrait remains sharp and proportional")
	await process_frame
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panel.sheet_panel.get_global_rect()), "Sheet fits current resolution")
	check(panel.content.size.y <= panel.content.get_parent().size.y, "Default sheet needs no vertical scrolling")
	panel.close_panel()
	var weapon_counts := {&"bolter_damage": 4, &"fire_rate": 2, &"knife_damage": 3, &"crit_chance": 1}
	var generic_counts := {&"armor": 2, &"max_health": 1, &"health_regen": 3}
	for id: StringName in weapon_counts:
		for _selection in weapon_counts[id]:
			select(id)
	for id: StringName in generic_counts:
		for _selection in generic_counts[id]:
			select(id)
	panel.open_panel()
	check(weapons.get_node("Count").text == "Weapon Upgrades: 4 / 4" and generic.get_node("Count").text == "Generic Upgrades: 3 / 4", "Actual selected types determine counters")
	for section in [weapons, generic]:
		var counts: Dictionary = weapon_counts if section == weapons else generic_counts
		var index := 0
		for id: StringName in counts:
			var slot: PanelContainer = section.get_node("Slots").get_child(index)
			check(slot.get_node("Row/Name").text == panel._upgrade_display_name(definition(id)), "Owned type shown from upgrade resource")
			check(slot.get_node("Row/Level").text == definition(id).get_level_text(player.combat_stats, counts[id]), "Level reads existing selection count")
			index += 1
	check(generic.get_node("Slots").get_child(3).get_node("Row/Name").text == "Empty", "Fourth Generic slot stays empty")
	check(panel._value_labels["Bolter Fire Rate"].text == "1.60 /s" and panel._value_labels["Knife Attack Rate"].text == "1.25 /s", "Rates use real current cooldowns")
	check(panel._value_labels["Crit Bonus"].text == "+50%" and panel._value_labels["Health Regen"].text == "0.6 HP/s", "Current crit bonus and regen")
	check(panel._value_labels["Knife Range"].text == "55 px", "Knife radius uses live weapon data")
	player.combat_stats.add_modifier(&"knife_range", 0.2)
	check(panel._value_labels["Knife Range"].text == "66 px", "Visible sheet updates real directional radius")
	panel.close_panel()
	# A fifth Weapon type must remain unavailable after four commitments.
	system.queue_level()
	system.offered.append(definition(&"knife_range"))
	system.select_upgrade(&"knife_range")
	check(not system.levels.has(&"knife_range"), "Fifth Weapon type cannot commit")
	system.select_upgrade(system.offered[0].id)
	panel.open_panel()
	check(weapons.get_node("Count").text == "Weapon Upgrades: 4 / 4" and not weapons.get_node("Overflow").visible, "Four Weapon commitments remain visible without a fifth type")
	panel.close_panel()
	var manager: ChapterPerkManager = system.chapter_manager
	var owned_perk: ChapterPerkDefinition = manager.catalog.perks[0]
	manager.apply_perk(owned_perk)
	panel.open_panel()
	check(panel.content.get_node("ChapterPerks/Title").text == "ULTRAMARINES PERKS" and panel.content.get_node("ChapterPerks/Owned").text == owned_perk.display_name.capitalize(), "Only actually owned Chapter perk displayed")
	for size in [Vector2i(1600, 900), Vector2i(800, 600), Vector2i(640, 480)]:
		root.size = size
		await process_frame
		await process_frame
		var rect: Rect2 = panel.sheet_panel.get_global_rect()
		check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(rect), "Sheet stays inside resized viewport")
		check(rect.get_center().is_equal_approx(Vector2(root.size) * 0.5), "Sheet stays centered")
		if size.x < 800:
			check(panel.content.get_node("Upgrades").columns == 1, "Narrow window stacks upgrade sections")
	panel.close_panel()
	check(not paused, "Closing resumes gameplay")
	print("PASS: %d character sheet checks" % checks)
	main.queue_free()
	await process_frame
	quit()
