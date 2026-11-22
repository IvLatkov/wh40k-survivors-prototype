class_name SupplyCrateEncounter
extends Node

const CRATE := preload("res://scenes/pickups/supply_crate.tscn")
const SPAWN_SECONDS := 300
const CLEARANCE_RADIUS := 28.0

var supply_crate_spawned: bool = false
var milestone_closed: bool = false
var crate: SupplyCrate
var _player: Player
var _chunks: ChunkManager
var _rewards: UpgradeSystem
var _boss: BossEncounter
var _bound: bool = false


func bind_run(clock: RunClock, player: Player, chunks: ChunkManager, rewards: UpgradeSystem, boss: BossEncounter) -> void:
	if _bound:
		return
	_bound = true
	_player = player
	_chunks = chunks
	_rewards = rewards
	_boss = boss
	clock.seconds_changed.connect(_on_seconds_changed)
	boss.boss_spawned.connect(_on_boss_spawned)
	player.health_depleted.connect(close_milestone)
	_on_seconds_changed(floori(clock.elapsed_time))


func _on_seconds_changed(seconds: int) -> void:
	# A direct F10 jump to 600 closes this window without producing a stale crate.
	if seconds >= BossEncounter.SPAWN_SECONDS:
		close_milestone()
		return
	if seconds < SPAWN_SECONDS or supply_crate_spawned or milestone_closed or _rewards.run_ended or _player.current_health <= 0:
		return
	var position := find_spawn_position()
	if position == Vector2.INF:
		return # Retry on a later clock tick if the nearby area is completely blocked.
	supply_crate_spawned = true
	crate = CRATE.instantiate() as SupplyCrate
	crate.position = (get_parent() as Node2D).to_local(position)
	crate.collected.connect(_on_collected)
	get_parent().add_child(crate)


func find_spawn_position() -> Vector2:
	var space := _player.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = CLEARANCE_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.collision_mask = TerrainObstacles.COLLISION_LAYER | 2
	query.collide_with_areas = false
	for distance: float in [320.0, 380.0, 260.0]:
		for direction in 16:
			# Use the existing obstacle layer/clearance query, but keep the bounded
			# search inside this nearby annulus rather than expanding distant rings.
			var candidate := _player.global_position + Vector2.from_angle(direction * TAU / 16.0) * distance
			if not _is_loaded(candidate):
				continue
			query.transform = Transform2D(0, candidate)
			if not space.intersect_shape(query, 1).is_empty():
				continue
			# A swept player-sized circle requires a direct clear approach; no pathfinder.
			var route := PhysicsShapeQueryParameters2D.new()
			var body := CircleShape2D.new()
			body.radius = 16.0
			route.shape = body
			route.collision_mask = TerrainObstacles.COLLISION_LAYER
			route.transform = Transform2D(0, _player.global_position)
			route.motion = candidate - _player.global_position
			if space.cast_motion(route)[0] >= 1.0:
				return candidate
	return Vector2.INF


func _is_loaded(position: Vector2) -> bool:
	for offset: Vector2 in [Vector2(-28, -28), Vector2(28, -28), Vector2(-28, 28), Vector2(28, 28)]:
		if not _chunks.active_chunks.has(_chunks.get_chunk_coordinate(position + offset)):
			return false
	return true


func _on_collected() -> void:
	if milestone_closed or _boss.warboss_spawned or _rewards.run_ended or _player.current_health <= 0:
		return
	_rewards.queue_supply_reward()


func _on_boss_spawned(_value: Warboss) -> void:
	close_milestone()


func close_milestone() -> void:
	milestone_closed = true
	if is_instance_valid(crate):
		crate.retire()
