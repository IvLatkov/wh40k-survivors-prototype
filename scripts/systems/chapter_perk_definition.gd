class_name ChapterPerkDefinition
extends Resource

const ChapterTypes = preload("res://scripts/systems/space_marine_chapter.gd")

enum Behavior { NONE, COMBAT_EFFICIENCY, ADAPTIVE_WARFARE, PERFECT_DISCIPLINE }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var chapter: ChapterTypes.Type = ChapterTypes.Type.ULTRAMARINES
@export var milestone: int = 10
@export var modifiers: Dictionary = {}
@export var behavior: Behavior = Behavior.NONE
@export var duration: float = 0.0
@export var bonus: float = 0.0
@export var max_stacks: int = 0
@export var projectile_interval: int = 0
