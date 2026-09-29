class_name BlockMaterials
extends RefCounted

const IDS: Array[StringName] = [&"wood", &"glass", &"stone", &"metal"]
const LABELS: Array[String] = ["Дерево", "Стекло", "Камень", "Металл"]
const DEFINITIONS: Array[BlockMaterialDefinition] = [
	preload("res://materials/wood.tres"),
	preload("res://materials/glass.tres"),
	preload("res://materials/stone.tres"),
	preload("res://materials/metal.tres"),
]


static func get_definition(id: StringName) -> BlockMaterialDefinition:
	for definition in DEFINITIONS:
		if definition.id == id:
			return definition
	return DEFINITIONS[0]


static func is_known(id: StringName) -> bool:
	return id in IDS
