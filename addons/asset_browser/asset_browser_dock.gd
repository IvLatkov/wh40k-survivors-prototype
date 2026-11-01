@tool
extends VBoxContainer

const CATALOG_PATH := "res://data/asset_catalog.json"

var assets: Array = []
var filtered_assets: Array = []

var search_box: LineEdit
var category_filter: OptionButton
var result_list: ItemList

var preview: TextureRect
var name_label: Label
var category_label: Label
var path_label: Label
var dimensions_label: Label
var tags_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(700, 350)

	build_ui()
	load_catalog()
	populate_categories()
	refresh_results()


func build_ui() -> void:
	var title := Label.new()
	title.text = "ASSET BROWSER"
	title.add_theme_font_size_override("font_size", 18)
	add_child(title)

	search_box = LineEdit.new()
	search_box.placeholder_text = "Search assets..."
	search_box.text_changed.connect(_on_search_changed)
	add_child(search_box)

	category_filter = OptionButton.new()
	category_filter.item_selected.connect(_on_category_changed)
	add_child(category_filter)

	result_list = ItemList.new()
	result_list.custom_minimum_size = Vector2(0, 220)
	result_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	result_list.item_selected.connect(_on_asset_selected)
	add_child(result_list)

	var separator := HSeparator.new()
	add_child(separator)

	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(220, 180)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(preview)

	name_label = Label.new()
	name_label.text = "Name:"
	add_child(name_label)

	category_label = Label.new()
	category_label.text = "Category:"
	add_child(category_label)

	dimensions_label = Label.new()
	dimensions_label.text = "Dimensions:"
	add_child(dimensions_label)

	path_label = Label.new()
	path_label.text = "Path:"
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(path_label)

	tags_label = Label.new()
	tags_label.text = "Tags:"
	tags_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tags_label)


func load_catalog() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("Asset catalog not found: %s" % CATALOG_PATH)
		return

	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)

	if file == null:
		push_error("Unable to open asset catalog.")
		return

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(text)

	if error != OK:
		push_error(
			"Failed parsing asset catalog: %s" %
			json.get_error_message()
		)
		return

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		push_error("Asset catalog root is not a Dictionary.")
		return

	assets = data.get("assets", [])

	print("Asset Browser loaded %d assets." % assets.size())


func populate_categories() -> void:
	category_filter.clear()

	category_filter.add_item("All")

	var categories: Array[String] = []

	for asset in assets:
		var category := str(asset.get("category", "other"))

		if category not in categories:
			categories.append(category)

	categories.sort()

	for category in categories:
		category_filter.add_item(category.capitalize())


func refresh_results() -> void:
	result_list.clear()
	filtered_assets.clear()

	var search := search_box.text.strip_edges().to_lower()

	var selected_category := "all"

	if category_filter.selected > 0:
		selected_category = (
			category_filter
			.get_item_text(category_filter.selected)
			.to_lower()
		)

	for asset in assets:
		var name := str(asset.get("name", ""))
		var path := str(asset.get("path", ""))
		var category := str(asset.get("category", "other"))
		var tags: Array = asset.get("tags", [])

		if selected_category != "all":
			if category.to_lower() != selected_category:
				continue

		if search != "":
			var searchable := (
				name + " " +
				path + " " +
				category + " " +
				" ".join(tags)
			).to_lower()

			if search not in searchable:
				continue

		filtered_assets.append(asset)
		result_list.add_item(name)


func _on_search_changed(_text: String) -> void:
	refresh_results()


func _on_category_changed(_index: int) -> void:
	refresh_results()


func _on_asset_selected(index: int) -> void:
	if index < 0 or index >= filtered_assets.size():
		return

	var asset: Dictionary = filtered_assets[index]

	show_asset(asset)


func show_asset(asset: Dictionary) -> void:
	var asset_name := str(asset.get("name", "Unknown"))
	var path := str(asset.get("path", ""))
	var category := str(asset.get("category", "other"))
	var width := int(asset.get("width", 0))
	var height := int(asset.get("height", 0))
	var tags: Array = asset.get("tags", [])

	name_label.text = "Name: %s" % asset_name
	category_label.text = "Category: %s" % category
	dimensions_label.text = "Dimensions: %d x %d" % [width, height]
	path_label.text = "Path: %s" % path
	tags_label.text = "Tags: %s" % ", ".join(tags)

	preview.texture = null

	if ResourceLoader.exists(path):
		var resource = load(path)

		if resource is Texture2D:
			preview.texture = resource