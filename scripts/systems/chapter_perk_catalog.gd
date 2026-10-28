class_name ChapterPerkCatalog
extends Resource

const ChapterTypes = preload("res://scripts/systems/space_marine_chapter.gd")

@export var chapter: ChapterTypes.Type = ChapterTypes.Type.ULTRAMARINES
@export var display_name: String = "ULTRAMARINES"
@export var perks: Array[ChapterPerkDefinition] = []

func has_milestone(level: int) -> bool:
	for perk in perks:
		if perk.chapter == chapter and perk.milestone == level:
			return true
	return false
