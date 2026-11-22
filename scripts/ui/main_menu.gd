class_name MainMenu
extends Control

const GAMEPLAY_SCENE: String = "res://scenes/main.tscn"
const SelectionData := preload("res://scripts/ui/menu_selection_data.gd")
enum Page { MAIN, CHARACTER, MAP, UPGRADES, SETTINGS, COLLECTION }

# Display-only until a real currency system is introduced.
@export var displayed_currency: int = 0

var current_page: Page = Page.MAIN
var _starting_game: bool = false
var selection_data := SelectionData.new()

@onready var panel: PanelContainer = %MenuPanel
@onready var pages: Dictionary[int, Control] = {
	Page.MAIN: %Main,
	Page.CHARACTER: %Character,
	Page.MAP: %Map,
	Page.UPGRADES: %Upgrades,
	Page.SETTINGS: %Settings,
	Page.COLLECTION: %Collection,
}


func _ready() -> void:
	_refresh_selection()
	%UltramarineCard.pressed.connect(_refresh_selection)
	%BattlefieldAlphaCard.pressed.connect(_refresh_selection)
	%CharacterPanel.gui_input.connect(_open_selection_card.bind(Page.CHARACTER))
	%MissionPanel.gui_input.connect(_open_selection_card.bind(Page.MAP))
	%Deploy.pressed.connect(_play)
	%CharacterSelect.pressed.connect(show_page.bind(Page.CHARACTER))
	%MapSelect.pressed.connect(show_page.bind(Page.MAP))
	%OpenUpgrades.pressed.connect(show_page.bind(Page.UPGRADES))
	%OpenSettings.pressed.connect(show_page.bind(Page.SETTINGS))
	%OpenCollection.pressed.connect(show_page.bind(Page.COLLECTION))
	%CurrencyDisplay.text = "Currency: %d" % displayed_currency
	%Upgrades.set_displayed_currency(displayed_currency)
	%Quit.visible = not OS.has_feature("web") and (OS.has_feature("windows") or OS.has_feature("linux") or OS.has_feature("macos"))
	%Quit.pressed.connect(_quit)
	for page: int in pages:
		if page != Page.MAIN:
			(pages[page].get_node("Back") as Button).pressed.connect(show_page.bind(Page.MAIN))
	for bus: String in ["Master", "Music", "SFX"]:
		var row := %Settings.get_node(bus)
		var slider := row.get_node("Slider") as HSlider
		var index := AudioServer.get_bus_index(bus)
		slider.editable = index >= 0
		var volume := 0.0 if index < 0 or AudioServer.is_bus_mute(index) else db_to_linear(AudioServer.get_bus_volume_db(index)) * 100.0
		slider.set_value_no_signal(volume)
		_update_volume_label(bus, slider.value)
		slider.value_changed.connect(_set_volume.bind(bus))
	get_viewport().size_changed.connect(_resize_panel)
	_resize_panel()
	show_page(Page.MAIN)


func show_page(page: Page) -> void:
	current_page = page
	for key: int in pages:
		pages[key].visible = key == page
	%SubmenuCenter.visible = page != Page.MAIN
	_resize_panel()
	if page == Page.MAIN:
		%Deploy.grab_focus()
	elif page == Page.UPGRADES:
		%UpgradeGrid.get_child(0).grab_focus()
		%Scroll.set_deferred(&"scroll_vertical", 0)
	else:
		(pages[page].get_node("Back") as Button).grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and current_page != Page.MAIN:
		show_page(Page.MAIN)
		get_viewport().set_input_as_handled()


func _resize_panel() -> void:
	# Stack the dashboard on narrow windows; the scroll keeps every control reachable.
	var compact := size.x < 900.0
	%MainContent.columns = 1 if compact else 3
	%BottomNavigation.columns = 2 if compact else 4
	%TopBar.columns = 1 if size.x < 600.0 else 2
	%GameTitle.add_theme_font_size_override("font_size", 24 if compact else 30)
	var margin := 16 if compact else 28
	%Margin.add_theme_constant_override("margin_left", margin)
	%Margin.add_theme_constant_override("margin_right", margin)
	# Reserve space for a vertical scrollbar on short windows.
	var selection_page := current_page in [Page.CHARACTER, Page.MAP, Page.UPGRADES]
	for edge: String in ["left", "right", "top", "bottom"]:
		panel.get_node("Padding").add_theme_constant_override("margin_" + edge, 16 if selection_page else 24)
	panel.custom_minimum_size.x = minf(920.0 if selection_page else 460.0, maxf(0.0, size.x - margin * 2.0 - 16.0))
	%Upgrades.set_compact(size.x < 700.0)
	%CharacterSelection.columns = 1 if size.x < 800.0 else 2
	%MapSelection.columns = 1 if size.x < 800.0 else 2


func _open_selection_card(event: InputEvent, page: Page) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		show_page(page)
		get_viewport().set_input_as_handled()


func _refresh_selection() -> void:
	var character := selection_data.character
	var mission := selection_data.mission
	%CharacterName.text = str(character.name).to_upper()
	%Chapter.text = "Chapter: " + character.chapter
	%StartingWeapon.text = "Starting Weapon: " + character.starting_weapon
	%Portrait.texture = character.portrait
	%MissionName.text = str(mission.name).to_upper()
	%Duration.text = "Duration: " + selection_data.duration_text()
	%Boss.text = "Boss: " + mission.boss
	%BattlefieldPreview.texture = mission.portrait
	%Summary.text = "%s\n%s\n%s\n%02d:%02d Mission" % [character.name, character.starting_weapon, mission.name, int(mission.duration_seconds) / 60, int(mission.duration_seconds) % 60]
	%UltramarineCard.configure(character, "Chapter: %s\nStarting Weapon: %s" % [character.chapter, character.starting_weapon])
	%BattlefieldAlphaCard.configure(mission, "Duration: %s\nEnemy Types: %s\nDifficulty: %s\nBoss: %s" % [selection_data.duration_text(), ", ".join(mission.enemies), mission.difficulty, selection_data.boss_text()])
	var details := %CharacterDetails.get_node("Padding/Content")
	details.get_node("Name").text = str(character.name).to_upper()
	details.get_node("Chapter").text = "Chapter: " + character.chapter
	details.get_node("StartingWeapon").text = "Starting Weapon: " + character.starting_weapon
	details.get_node("Stats").text = "Max HP: %s\nMovement Speed: %s px/s\nArmor: %d\nCrit Chance: %s%%" % [str(character.max_hp), str(character.movement_speed), character.armor, str(float(character.crit_chance) * 100.0)]
	details.get_node("PassiveBonus").text = "Passive Bonus: " + character.passive_bonus
	details.get_node("UnlockState").text = "Unlocked · Selected"
	details = %MissionDetails.get_node("Padding/Content")
	details.get_node("Name").text = str(mission.name).to_upper()
	details.get_node("Duration").text = "Duration: " + selection_data.duration_text()
	details.get_node("EnemyTypes").text = "Enemy Types:\n" + "\n".join(mission.enemies)
	details.get_node("Difficulty").text = "Difficulty: " + mission.difficulty
	details.get_node("Boss").text = "Boss: " + selection_data.boss_text()
	details.get_node("UnlockState").text = "Unlocked · Selected"


func _set_volume(value: float, bus: String) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, value <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value / 100.0, 0.001)))
	_update_volume_label(bus, value)


func _update_volume_label(bus: String, value: float) -> void:
	(%Settings.get_node(bus + "/Header/Value") as Label).text = "%d%%" % roundi(value)


func _play() -> void:
	if _starting_game:
		return
	_starting_game = true
	%Deploy.disabled = true
	var error := get_tree().change_scene_to_file(GAMEPLAY_SCENE)
	if error != OK:
		_starting_game = false
		%Deploy.disabled = false
		%PlayError.show()
		push_error("Could not open gameplay scene: %s" % error_string(error))


func _quit() -> void:
	if %Quit.visible:
		get_tree().quit()
