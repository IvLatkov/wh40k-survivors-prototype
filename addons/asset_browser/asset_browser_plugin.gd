@tool
extends EditorPlugin

var browser: Control


func _enter_tree() -> void:
	browser = preload(
		"res://addons/asset_browser/asset_browser_dock.gd"
	).new()

	add_control_to_bottom_panel(browser, "Asset Browser")


func _exit_tree() -> void:
	if browser:
		remove_control_from_bottom_panel(browser)
		browser.queue_free()
		browser = null