class_name TerrainChunk
extends Node2D

const TILE_SIZE: int = 32
const TANK_TEXTURE: Texture2D = preload("res://assets/art/effects/terrain/tanks/tank1.png")
const TANK_CHANCE: float = 0.35
const TANK_SCALE: float = 2.0
const TANK_EDGE_MARGIN: float = 192.0
const TANK_START_CLEARANCE: float = 250.0
const TANK_RNG_SALT: int = 0x54414E4B
const GROUND_ATLAS: Texture2D = preload("res://assets/art/effects/terrain/battlefield_biome/prepared/battlefield_ground_atlas.png")
const DECORATION_FOLDER: String = "res://assets/art/effects/terrain/decorations/"
# Explicit visually inspected sprites: rubble, bone fragments, stains, rocks,
# craters, ash and industrial scrap. The opaque presentation sheet is excluded.
const DECORATION_FILES: Array[String] = [
	"dark_dirt_ash_tile.png", "dark_dirt_ash_tile_2.png",
	"dark_dirt_ash_tile_3.png", "dark_dirt_ash_tile_4.png",
	"dark_dirt_ash_tile_5.png", "dark_dirt_ash_tile_6.png",
	"dark_dirt_ash_tile_11.png", "dark_dirt_ash_tile_12.png",
]
# Keep the historical scale and all other per-cell chances unchanged.
# Tile 4 is reduced 65%; total decoration probability is now 4.92815534%.
const DECORATION_NORMALIZATION: float = 0.0705 / 0.0515
const DECORATION_CHANCES: Array[float] = [
	0.004 * DECORATION_NORMALIZATION, 0.004 * DECORATION_NORMALIZATION,
	0.005 * DECORATION_NORMALIZATION, 0.007 * DECORATION_NORMALIZATION,
	0.003 * DECORATION_NORMALIZATION, 0.003 * DECORATION_NORMALIZATION,
	0.005 * DECORATION_NORMALIZATION, 0.005 * DECORATION_NORMALIZATION,
]

@export_range(32, 8192, 32) var chunk_size: int = 1024
var chunk_coordinate: Vector2i = Vector2i.ZERO
var chunk_seed: int = 0
var profile_generation: bool = false
var ground_population_usec: int = 0
var decoration_population_usec: int = 0
var _has_generated: bool = false
var _prepared_data: ChunkData
static var _ground_tiles: TileSet
static var _decoration_tiles: TileSet

@onready var large_props: Node2D = $LargeProps

@onready var ground: TileMapLayer = $Ground
@onready var decorations: TileMapLayer = $Decorations


func configure(coordinate: Vector2i, size: int, data: ChunkData = null) -> void:
	_prepared_data = data
	chunk_coordinate = coordinate
	chunk_size = size
	chunk_seed = hash(chunk_coordinate)
	position = Vector2(chunk_coordinate) * chunk_size
	if is_node_ready():
		_generate()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_prepare_tiles()
	_generate()


static func _prepare_tiles() -> void:
	if _ground_tiles != null:
		return
	_ground_tiles = TileSet.new()
	_ground_tiles.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = GROUND_ATLAS
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for y in 4:
		for x in 24:
			atlas.create_tile(Vector2i(x, y))
	_ground_tiles.add_source(atlas, 0)
	_decoration_tiles = TileSet.new()
	_decoration_tiles.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for index in DECORATION_FILES.size():
		var source := TileSetAtlasSource.new()
		source.texture = load(DECORATION_FOLDER + DECORATION_FILES[index]) as Texture2D
		source.texture_region_size = Vector2i(48, 48)
		source.create_tile(Vector2i.ZERO)
		_decoration_tiles.add_source(source, index)


# Jittered world-space regions give coherent ~5-cell patches that continue
# across chunk borders. Each region owns its RNG, independent of load order.
static func _ground_variant(world_cell: Vector2i, patches: Dictionary[Vector2i, Vector3]) -> int:
	var region := Vector2i(floori(world_cell.x / 5.0), floori(world_cell.y / 5.0))
	var nearest_distance: float = INF
	var variant: int = 0
	for y in range(-1, 2):
		for x in range(-1, 2):
			var patch := patches[region + Vector2i(x, y)]
			var distance := Vector2(patch.x, patch.y).distance_squared_to(Vector2(world_cell) + Vector2(0.5, 0.5))
			if distance < nearest_distance:
				nearest_distance = distance
				variant = int(patch.z)
	return variant


static func _prepare_patches(cells: int, chunk_position: Vector2i) -> Dictionary[Vector2i, Vector3]:
	var patches: Dictionary[Vector2i, Vector3] = {}
	var start := chunk_position * cells
	var first := Vector2i(floori(start.x / 5.0), floori(start.y / 5.0)) - Vector2i.ONE
	var last := Vector2i(floori((start.x + cells - 1) / 5.0), floori((start.y + cells - 1) / 5.0)) + Vector2i.ONE
	var rng := RandomNumberGenerator.new()
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var coordinate := Vector2i(x, y)
			rng.seed = hash(coordinate)
			var center := Vector2(coordinate) * 5.0 + Vector2(rng.randf_range(0.5, 4.5), rng.randf_range(0.5, 4.5))
			var roll := rng.randf()
			var variant: int
			# Common dirt 65%, secondary ash 22%, cracks 10%, rocky 3%.
			if roll < 0.40:
				variant = 0
			elif roll < 0.65:
				variant = 3
			elif roll < 0.87:
				variant = 1
			elif roll < 0.94:
				variant = 4
			elif roll < 0.97:
				variant = 5
			else:
				variant = 2
			patches[coordinate] = Vector3(center.x, center.y, variant)
	return patches

# Only values are cached. No TileMapLayer, scene or mutable TileSet is touched
# while preparing a chunk. Keep row/cell iteration and all RNG calls identical.
class ChunkData:
	extends RefCounted
	var ground_cells: Array[Vector2i] = []
	var decoration_cells: Array[Vector4i] = []


class Generation:
	extends RefCounted
	var coordinate: Vector2i
	var cells: int
	var row: int = 0
	var data := ChunkData.new()
	var rng := RandomNumberGenerator.new()
	var patches: Dictionary[Vector2i, Vector3]
	var profile_enabled: bool = false
	var ground_usec: int = 0
	var decoration_usec: int = 0

	func _init(chunk_position: Vector2i, size: int) -> void:
		coordinate = chunk_position
		cells = floori(float(size) / TILE_SIZE)
		rng.seed = hash(coordinate)
		patches = TerrainChunk._prepare_patches(cells, coordinate)

	func generate_row() -> void:
		var y := row
		for x in cells:
			var started := Time.get_ticks_usec() if profile_enabled else 0
			var world_cell := coordinate * cells + Vector2i(x, y)
			var variant := TerrainChunk._ground_variant(world_cell, patches)
			data.ground_cells.append(Vector2i(variant * 4 + posmod(world_cell.x, 4), posmod(world_cell.y, 4)))
			if profile_enabled:
				ground_usec += Time.get_ticks_usec() - started
				started = Time.get_ticks_usec()
			var roll := rng.randf()
			var threshold: float = 0.0
			for index in DECORATION_FILES.size():
				threshold += DECORATION_CHANCES[index]
				if roll >= threshold:
					continue
				var transform: int = 0
				if rng.randf() < 0.5:
					transform |= TileSetAtlasSource.TRANSFORM_FLIP_H
				if rng.randf() < 0.5:
					transform |= TileSetAtlasSource.TRANSFORM_FLIP_V
				if rng.randf() < 0.5:
					transform |= TileSetAtlasSource.TRANSFORM_TRANSPOSE
				data.decoration_cells.append(Vector4i(x, y, index, transform))
				break
			if profile_enabled:
				decoration_usec += Time.get_ticks_usec() - started
		row += 1

	func is_complete() -> bool:
		return row == cells


static func generate_data(coordinate: Vector2i, size: int) -> ChunkData:
	var generation := Generation.new(coordinate, size)
	while not generation.is_complete():
		generation.generate_row()
	return generation.data


func _generate() -> void:
	ground.tile_set = _ground_tiles
	decorations.tile_set = _decoration_tiles
	var data := _prepared_data
	if data == null:
		data = generate_data(chunk_coordinate, chunk_size)
	_prepared_data = null
	# Fresh chunk layers are empty; clear only when reconfiguring a live chunk.
	if _has_generated:
		ground.clear()
		decorations.clear()
	_has_generated = true
	var cells := floori(float(chunk_size) / TILE_SIZE)
	# set_cell queues internal TileMap updates; do not force rebuilds in this loop.
	var started := Time.get_ticks_usec() if profile_generation else 0
	for y in cells:
		for x in cells:
			ground.set_cell(Vector2i(x, y), 0, data.ground_cells[y * cells + x])
	ground_population_usec = Time.get_ticks_usec() - started if profile_generation else 0
	started = Time.get_ticks_usec() if profile_generation else 0
	for cell in data.decoration_cells:
		decorations.set_cell(Vector2i(cell.x, cell.y), cell.z, Vector2i.ZERO, cell.w)
	decoration_population_usec = Time.get_ticks_usec() - started if profile_generation else 0

	_populate_large_props()


static func get_tank_position(coordinate: Vector2i, size: int) -> Vector2:
	# Own stream: no ground, decoration or gameplay RNG is consumed.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(coordinate.x, coordinate.y, TANK_RNG_SALT))
	if rng.randf() >= TANK_CHANCE:
		return Vector2.INF
	# Native texture shared by every sprite; scale is an integer pixel-art zoom.
	var half_size := TANK_TEXTURE.get_size() * TANK_SCALE * 0.5
	var margin := half_size + Vector2.ONE * TILE_SIZE
	margin = margin.max(Vector2.ONE * TANK_EDGE_MARGIN)
	if margin.x * 2.0 > size or margin.y * 2.0 > size:
		return Vector2.INF
	var local_position := Vector2(
		roundf(rng.randf_range(margin.x, size - margin.x)),
		roundf(rng.randf_range(margin.y, size - margin.y))
	)
	# The real run starts at terrain origin. Keep the entire prop footprint
	# clear of its 250px disk, including neighboring chunks; never reroll.
	var world_position := Vector2(coordinate) * size + local_position
	var nearest_to_start := Vector2.ZERO.clamp(world_position - half_size, world_position + half_size)
	if nearest_to_start.length_squared() < TANK_START_CLEARANCE * TANK_START_CLEARANCE:
		return Vector2.INF
	return local_position


func _populate_large_props() -> void:
	# Reconfiguration must replace the old prop immediately, without duplicates.
	for child in large_props.get_children():
		child.free()
	var at := get_tank_position(chunk_coordinate, chunk_size)
	if at == Vector2.INF:
		return
	var tank := Sprite2D.new()
	tank.name = "TankWreck"
	tank.texture = TANK_TEXTURE
	tank.position = at
	tank.scale = Vector2.ONE * TANK_SCALE
	large_props.add_child(tank)
