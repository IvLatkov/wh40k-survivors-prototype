extends SceneTree

const ASSET_ROOT := "res://assets"
const OUTPUT_FILE := "res://data/asset_catalog.json"

const IMAGE_EXTENSIONS := [
	"png",
	"jpg",
	"jpeg",
	"webp"
]

var assets: Array = []


func _initialize() -> void:
	print("Scanning assets...")
	scan_directory(ASSET_ROOT)

	assets.sort_custom(func(a, b):
		return a["path"] < b["path"]
	)

	var catalog := {
		"generated_by": "build_asset_catalog.gd",
		"asset_count": assets.size(),
		"assets": assets
	}

	var file := FileAccess.open(OUTPUT_FILE, FileAccess.WRITE)

	if file == null:
		push_error("Could not create asset catalog.")
		quit(1)
		return

	file.store_string(JSON.stringify(catalog, "\t"))
	file.close()

	print("")
	print("========================================")
	print(" ASSET CATALOG GENERATED")
	print(" Assets found: %d" % assets.size())
	print(" Output: %s" % OUTPUT_FILE)
	print("========================================")

	quit(0)


func scan_directory(path: String) -> void:
	var directory := DirAccess.open(path)

	if directory == null:
		push_error("Unable to open directory: %s" % path)
		return

	directory.list_dir_begin()

	var file_name := directory.get_next()

	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = directory.get_next()
			continue

		var full_path := path.path_join(file_name)

		if directory.current_is_dir():
			scan_directory(full_path)
		else:
			process_file(full_path)

		file_name = directory.get_next()

	directory.list_dir_end()


func process_file(path: String) -> void:
	var extension := path.get_extension().to_lower()

	if extension not in IMAGE_EXTENSIONS:
		return

	var image := Image.new()

	var absolute_path := ProjectSettings.globalize_path(path)
	var error := image.load(absolute_path)

	if error != OK:
		push_warning("Could not inspect image: %s" % path)
		return

	var entry := {
		"id": create_asset_id(path),
		"name": path.get_file().get_basename(),
		"path": path,
		"type": "image",
		"category": detect_category(path),
		"extension": extension,
		"width": image.get_width(),
		"height": image.get_height(),
		"tags": create_tags(path)
	}

	assets.append(entry)


func create_asset_id(path: String) -> String:
	var id := path.trim_prefix("res://assets/")
	id = id.get_basename()
	id = id.replace("/", "_")
	id = id.replace("\\", "_")
	id = id.replace(" ", "_")

	return id.to_lower()


func detect_category(path: String) -> String:
	var lower := path.to_lower()

	if "/enemy/" in lower or "/enemies/" in lower:
		return "enemy"

	if "/player/" in lower:
		return "player"

	if "/terrain/" in lower:
		return "terrain"

	if "/xp/" in lower:
		return "xp"

	if "/weapon/" in lower or "/weapons/" in lower:
		return "weapon"

	if "/ui/" in lower:
		return "ui"

	if "/effects/" in lower:
		return "effect"

	return "other"


func create_tags(path: String) -> Array:
	var tags: Array = []

	var clean_path := path.trim_prefix("res://assets/")
	var parts := clean_path.split("/")

	for part in parts:
		var tag := String(part).get_basename().to_lower()

		if tag != "" and tag not in tags:
			tags.append(tag)

	return tags