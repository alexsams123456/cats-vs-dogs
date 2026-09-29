class_name CharacterCatalog
extends RefCounted

const CATS: Array[CharacterDefinition] = [
	preload("res://characters/cats/classic.tres"),
	preload("res://characters/cats/bomb.tres"),
	preload("res://characters/cats/zigzag.tres"),
	preload("res://characters/cats/splitter.tres"),
	preload("res://characters/cats/heavy.tres"),
	preload("res://characters/cats/wind.tres"),
	preload("res://characters/cats/magnet.tres"),
	preload("res://characters/cats/frost.tres"),
	preload("res://characters/cats/ghost.tres"),
	preload("res://characters/cats/homing.tres"),
]
const DOGS: Array[CharacterDefinition] = [
	preload("res://characters/dogs/scout.tres"),
	preload("res://characters/dogs/armored.tres"),
	preload("res://characters/dogs/jumper.tres"),
]


static func find_cat(id: StringName) -> CharacterDefinition:
	return _find(CATS, id)


static func find_dog(id: StringName) -> CharacterDefinition:
	return _find(DOGS, id)


static func _find(roster: Array[CharacterDefinition], id: StringName) -> CharacterDefinition:
	for definition in roster:
		if definition.id == id:
			return definition
	return roster[0]
