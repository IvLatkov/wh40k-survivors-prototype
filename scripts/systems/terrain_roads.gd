class_name TerrainRoads
extends Node2D

# World-space 256px cells. Compact, independently seeded 16x16-cell route
# clusters cross ordinary chunk borders but terminate inside their own region.
# No global RNG, persistent layout cache, physics or per-frame processing.
const CELL_SIZE: int = 256
const REGION_CELLS: int = 16
const REGION_CHANCE: float = 0.65
const BRANCH_CHANCE: float = 0.55
const RNG_SALT: int = 0x524F4144
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const TEXTURES: Array[Texture2D] = [
	null,
	preload("res://assets/art/effects/terrain/roads/prepared/road_01.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_02.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_03.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_04.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_05.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_06.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_07.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_08.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_09.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_10.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_11.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_12.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_13.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_14.png"),
	preload("res://assets/art/effects/terrain/roads/prepared/road_15.png"),
]


static func _region_path(region: Vector2i) -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(region.x, region.y, RNG_SALT))
	if rng.randf() >= REGION_CHANCE:
		return cells
	var first_y := rng.randi_range(3, 12)
	var last_y := rng.randi_range(3, 12)
	var bend_x := rng.randi_range(6, 9)
	for x in range(1, bend_x + 1):
		cells[Vector2i(x, first_y)] = true
	for y in range(mini(first_y, last_y), maxi(first_y, last_y) + 1):
		cells[Vector2i(bend_x, y)] = true
	for x in range(bend_x, 15):
		cells[Vector2i(x, last_y)] = true
	if rng.randf() < BRANCH_CHANCE:
		var branch_x := rng.randi_range(3, 12)
		for y in range(1, 15):
			cells[Vector2i(branch_x, y)] = true
	return cells


# x/y are chunk-local cell coordinates, z is the four-direction port mask.
static func get_layout(coordinate: Vector2i, size: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	if size < CELL_SIZE or size % CELL_SIZE != 0:
		return result
	var width := size / CELL_SIZE
	var origin := coordinate * width
	var regions: Dictionary[Vector2i, Dictionary] = {}
	for y in width:
		for x in width:
			var world := origin + Vector2i(x, y)
			var region := Vector2i(floori(float(world.x) / REGION_CELLS), floori(float(world.y) / REGION_CELLS))
			if not regions.has(region):
				regions[region] = _region_path(region)
			var path: Dictionary = regions[region]
			var local := world - region * REGION_CELLS
			if not path.has(local):
				continue
			var mask := 0
			for direction in 4:
				if path.has(local + DIRECTIONS[direction]):
					mask |= 1 << direction
			result.append(Vector3i(x, y, mask))
	return result


func populate(coordinate: Vector2i, size: int) -> void:
	for child in get_children():
		child.free()
	for cell in get_layout(coordinate, size):
		var piece := Sprite2D.new()
		piece.texture = TEXTURES[cell.z]
		piece.centered = false
		piece.position = Vector2(cell.x, cell.y) * CELL_SIZE
		add_child(piece)
