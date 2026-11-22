class_name MainMenu
extends Control

const GAMEPLAY_SCENE: String = "res://scenes/main.tscn"
enum Page { MAIN, CHARACTER, MAP, UPGRADES, SETTINGS, COLLECTION }

# Display-only until a real currency system is introduced.
@export var displayed_currency: int = 0

var current_page: Page = Page.MAIN
var _starting_game: bool = false

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
	%Deploy.pressed.connect(_play)
	%CharacterSelect.pressed.connect(show_page.bind(Page.CHARACTER))
	%MapSelect.pressed.connect(show_page.bind(Page.MAP))
	%OpenUpgrades.pressed.connect(show_page.bind(Page.UPGRADES))
	%OpenSettings.pressed.connect(show_page.bind(Page.SETTINGS))
	%OpenCollection.pressed.connect(show_page.bind(Page.COLLECTION))
	%CurrencyDisplay.text = "Currency: %d" % displayed_currency
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
	if page == Page.MAIN:
		%Deploy.grab_focus()
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
	panel.custom_minimum_size.x = minf(460.0, maxf(0.0, size.x - margin * 2.0 - 16.0))


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
