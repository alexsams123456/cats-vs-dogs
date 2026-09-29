class_name DogHouseTypes
extends RefCounted

const IDS: Array[StringName] = [&"classic", &"barrel", &"igloo", &"fortress"]
const LABELS: Array[String] = ["Классическая", "Бочка", "Иглу", "Крепость"]
const DEFINITIONS: Array[DogHouseDefinition] = [
	preload("res://houses/classic.tres"),
	preload("res://houses/barrel.tres"),
	preload("res://houses/igloo.tres"),
	preload("res://houses/fortress.tres"),
]


static func get_definition(id: StringName) -> DogHouseDefinition:
	for definition in DEFINITIONS:
		if definition.id == id:
			return definition
	return DEFINITIONS[0]


static func is_known(id: StringName) -> bool:
	return id in IDS
