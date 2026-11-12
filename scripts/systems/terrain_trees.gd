class_name TerrainTrees
extends RefCounted

const TEXTURES: Array[Texture2D] = [
	preload("res://assets/art/terrain/trees/olive_tree.png"),
	preload("res://assets/art/terrain/trees/dead_tree.png"),
	preload("res://assets/art/terrain/trees/blasted_tree.png"),
]
const REGION_CHUNKS := Vector2i(3, 2)
const REGION_SALT: int = 0x54524545
const POSITION_SALT: int = 0x574F4F44
const FOOTPRINT := Vector2(160, 160)
const EDGE_GAP: float = 96.0
const PROP_GAP: float = 64.0
const ROAD_GAP: float = 48.0
const START_CLEARANCE: float = 300.0
const PLACEMENT_ATTEMPTS: int = 64


class Placement:
	extends RefCounted
	var position: Vector2
	var variant: int


static func get_region(coordinate: Vector2i) -> Vector2i:
	return Vector2i(floori(float(coordinate.x) / REGION_CHUNKS.x), floori(float(coordinate.y) / REGION_CHUNKS.y))


static func get_region_tree_chunks(region: Vector2i) -> Array[Vector2i]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(region.x, region.y, REGION_SALT))
	var count := rng.randi_range(2, 3)
	var chunks: Array[Vector2i] = []
	for y in REGION_CHUNKS.y:
		for x in REGION_CHUNKS.x:
			chunks.append(region * REGION_CHUNKS + Vector2i(x, y))
	# Use this region's RNG rather than Array.shuffle(), which consumes global RNG.
	for index in range(chunks.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var previous := chunks[index]
		chunks[index] = chunks[other]
		chunks[other] = previous
	chunks.resize(count)
	return chunks


static func get_placements(coordinate: Vector2i, size: int, occupied: Array[Rect2], road_layout: Variant = null) -> Array[Placement]:
	var placements: Array[Placement] = []
	var margin := FOOTPRINT * 0.5 + Vector2.ONE * EDGE_GAP
	if size < margin.x * 2.0 or size < margin.y * 2.0:
		return placements
	if not get_region_tree_chunks(get_region(coordinate)).has(coordinate):
		return placements
	var exclusions: Array[Rect2] = []
	for bounds in occupied:
		exclusions.append(bounds.grow(PROP_GAP))
	var road_cells: Array[Vector3i] = TerrainRoads.get_layout(coordinate, size) if road_layout == null else road_layout
	for cell in road_cells:
		exclusions.append(Rect2(Vector2(cell.x, cell.y) * TerrainRoads.CELL_SIZE, Vector2.ONE * TerrainRoads.CELL_SIZE).grow(ROAD_GAP))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(coordinate.x, coordinate.y, POSITION_SALT))
	var variant := rng.randi_range(0, TEXTURES.size() - 1)
	for _attempt in PLACEMENT_ATTEMPTS:
		var at := Vector2(roundf(rng.randf_range(margin.x, size - margin.x)), roundf(rng.randf_range(margin.y, size - margin.y)))
		var bounds := Rect2(at - FOOTPRINT * 0.5, FOOTPRINT)
		var world_bounds := Rect2(bounds.position + Vector2(coordinate) * size, bounds.size)
		if Vector2.ZERO.clamp(world_bounds.position, world_bounds.end).length_squared() < START_CLEARANCE * START_CLEARANCE:
			continue
		var blocked := false
		for exclusion in exclusions:
			if bounds.intersects(exclusion):
				blocked = true
				break
		if blocked:
			continue
		var placement := Placement.new()
		placement.position = at
		placement.variant = variant
		placements.append(placement)
		break
	# If no safe position exists, leave the chunk clear instead of forcing a tree.
	return placements
