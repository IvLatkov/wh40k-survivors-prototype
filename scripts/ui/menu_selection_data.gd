class_name MenuSelectionData
extends RefCounted

# Menu-only display data. Player defaults are inspected off-tree, never run.
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHAPTER := preload("res://resources/chapters/ultramarines.tres")
const MISSION_PREVIEW := preload("res://assets/art/effects/terrain/buildings/imperial_ruin_3.1.png")

var character: Dictionary
var mission: Dictionary


func _init() -> void:
	character = read_character(PLAYER_SCENE)
	mission = {
		"id": &"battlefield_alpha",
		"name": "Battlefield Alpha",
		"portrait": MISSION_PREVIEW,
		"duration_seconds": BossEncounter.SPAWN_SECONDS,
		"enemies": ["Squigs", "Orks", "Ork Warboss"],
		"difficulty": "Normal",
		"boss": "Ork Warboss",
		"unlocked": true,
	}


static func read_character(scene: PackedScene) -> Dictionary:
	var player := scene.instantiate() as Player
	var visual := player.get_node("Visual") as AnimatedSprite2D
	var data := {
		"id": &"ultramarine",
		"name": "Ultramarine",
		"chapter": CHAPTER.display_name.capitalize(),
		"starting_weapon": str(player.get_node("Bolter").name),
		"portrait": visual.sprite_frames.get_frame_texture(&"idle_right", 0),
		"max_hp": player.max_health,
		"movement_speed": player.get_movement_speed(),
		"armor": player.combat_stats.get_armor(),
		"crit_chance": player.combat_stats.get_crit_chance(),
		# ChapterPerkManager grants chosen milestone perks, not a starting passive.
		"passive_bonus": "None",
		"unlocked": true,
	}
	player.free()
	return data


func duration_text() -> String:
	return "%d Minutes" % (int(mission.duration_seconds) / 60)


func deploy_summary_text() -> String:
	var seconds := int(mission.duration_seconds)
	return "%s\n%s\n%s\n%02d:%02d Mission\n%s Difficulty" % [character.name, character.starting_weapon, mission.name, seconds / 60, seconds % 60, mission.difficulty]


func boss_text() -> String:
	var seconds := int(mission.duration_seconds)
	return "%s — %d:%02d" % [mission.boss, seconds / 60, seconds % 60]
