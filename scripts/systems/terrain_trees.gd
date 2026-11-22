class_name TerrainTrees
extends RefCounted

const TEXTURES: Array[Texture2D] = [
	preload("res://assets/art/terrain/trees/olive_tree.png"),
	preload("res://assets/art/terrain/trees/dead_tree.png"),
	preload("res://assets/art/terrain/trees/blasted_tree.png"),
]
const TREES_PER_CHUNK: int = 2
const POSITION_SALT: int = 0x574F4F44
const FOOTPRINT := Vector2(160, 160)
const EDGE_GAP: float = 96.0
const PROP_GAP: float = 64.0
const ROAD_GAP: float = 48.0
const START_CLEARANCE: float = 300.0
const START_PLACEMENT_HALF_SIZE := Vector2(480, 240)
const PLACEMENT_ATTEMPTS: int = 64


class Placement:
	extends RefCounted
	var position: Vector2
	var variant: int


static func get_placements(coordinate: Vector2i, size: int, occupied: Array[Rect2], road_layout: Variant = null) -> Array[Placement]:
	var placements: Array[Placement] = []
	var margin := FOOTPRINT * 0.5 + Vector2.ONE * EDGE_GAP
	if size < margin.x * 2.0 or size < margin.y * 2.0:
		return placements
	var exclusions: Array[Rect2] = []
	for bounds in occupied:
		exclusions.append(bounds.grow(PROP_GAP))
	var road_cells: Array[Vector3i] = TerrainRoads.get_layout(coordinate, size) if road_layout == null else road_layout
	for cell in road_cells:
		exclusions.append(Rect2(Vector2(cell.x, cell.y) * TerrainRoads.CELL_SIZE, Vector2.ONE * TerrainRoads.CELL_SIZE).grow(ROAD_GAP))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(coordinate.x, coordinate.y, POSITION_SALT))
	var variants: Array[int] = [0, 1, 2]
	# Shuffle locally so each chunk uses two different trees without affecting
	# gameplay RNG or depending on the order chunks enter the active grid.
	for index in range(variants.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var previous := variants[index]
		variants[index] = variants[other]
		variants[other] = previous
	# Try positions inside the opening landscape view first, while retaining
	# the clear spawn disk. Fall back to the full chunk if that area is blocked.
	var origin := Vector2(coordinate) * size
	var nearby_min := margin.max(-START_PLACEMENT_HALF_SIZE - origin)
	var nearby_max := (Vector2.ONE * size - margin).min(START_PLACEMENT_HALF_SIZE - origin)
	var near_start := nearby_min.x <= nearby_max.x and nearby_min.y <= nearby_max.y
	var attempts := PLACEMENT_ATTEMPTS * 2 if near_start else PLACEMENT_ATTEMPTS
	for tree_index in TREES_PER_CHUNK:
		for attempt in attempts:
			var first := nearby_min if near_start and attempt < PLACEMENT_ATTEMPTS else margin
			var last := nearby_max if near_start and attempt < PLACEMENT_ATTEMPTS else Vector2.ONE * size - margin
			var at := Vector2(roundf(rng.randf_range(first.x, last.x)), roundf(rng.randf_range(first.y, last.y)))
			var bounds := Rect2(at - FOOTPRINT * 0.5, FOOTPRINT)
			var world_bounds := Rect2(bounds.position + origin, bounds.size)
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
			placement.variant = variants[tree_index]
			placements.append(placement)
			exclusions.append(bounds.grow(PROP_GAP))
			break
	# Never force either tree onto a road or another obstacle when space is tight.
	return placements
