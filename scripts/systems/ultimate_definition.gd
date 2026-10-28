class_name UltimateDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
## Required selection levels, keyed by normal upgrade ID.
@export var prerequisites: Dictionary = {}
## These prerequisites also accept a selected upgrade's actual functional cap.
@export var accept_functional_cap: Array[StringName] = []
