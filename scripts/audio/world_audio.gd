class_name WorldAudio
extends Node
## Короткие звуки раунда: тела удаляются независимо от хвостов своих звуков.

signal effect_played(effect_id: StringName)

const TENSION := preload("res://assets/audio/sfx_tension.wav")
const RELEASE := preload("res://assets/audio/sfx_release.wav")
const FLIGHT := preload("res://assets/audio/sfx_flight.wav")
const WOOD := preload("res://assets/audio/sfx_wood.wav")
const GLASS := preload("res://assets/audio/sfx_glass.wav")
const STONE := preload("res://assets/audio/sfx_stone.wav")
const METAL := preload("res://assets/audio/sfx_metal.wav")
const VICTORY := preload("res://assets/audio/sfx_victory.wav")
const MAX_VOICES := 6
const MATERIAL_INTERVAL := 0.08

var play_count: int = 0
var _players: Array[AudioStreamPlayer] = []
var _cooldowns: Dictionary[StringName, float] = {}
var _victory_played: bool = false


func _ready() -> void:
	for index in MAX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Effect%d" % index
		player.bus = &"SFX"
		player.max_polyphony = 1
		add_child(player)
		_players.append(player)
	get_tree().node_added.connect(_on_node_added)
	# Родитель может создать тела позже, в собственном _ready().
	_bind_branch.call_deferred(get_parent())


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _process(delta: float) -> void:
	for key: StringName in _cooldowns:
		_cooldowns[key] = maxf(0.0, _cooldowns[key] - delta)


func play_victory() -> void:
	if _victory_played or not _can_play():
		return
	_victory_played = true
	# Победа слышна даже в момент обрушения большой башни.
	_play(&"victory", VICTORY, -12.0, true)


func _on_node_added(node: Node) -> void:
	if node is Slingshot or node is WoodenBlock:
		_bind_node.call_deferred(node)


func _bind_branch(node: Node) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	_bind_node(node)
	for child in node.get_children():
		_bind_branch(child)


func _bind_node(node: Node) -> void:
	if not is_instance_valid(node) or not is_inside_tree() or node.is_queued_for_deletion():
		return
	if not get_parent().is_ancestor_of(node):
		return
	if node is Slingshot:
		if not node.tension_started.is_connected(_on_tension):
			node.tension_started.connect(_on_tension)
			node.launched.connect(_on_launched)
	elif node is WoodenBlock:
		if not node.material_hit.is_connected(_on_material_hit):
			node.material_hit.connect(_on_material_hit)
			node.destroyed.connect(_on_material_destroyed.bind(node.material_id))


func _on_tension() -> void:
	if _cooldowns.get(&"tension", 0.0) > 0.0 or not _can_play():
		return
	_cooldowns[&"tension"] = 0.18
	_play(&"tension", TENSION, -21.0)


func _on_launched(_projectile: CatProjectile) -> void:
	_play(&"release", RELEASE, -15.0)
	_play(&"flight", FLIGHT, -20.0)


func _on_material_hit(material_id: StringName) -> void:
	_play_material(material_id, -21.0)


func _on_material_destroyed(material_id: StringName) -> void:
	_play_material(material_id, -16.0)


func _play_material(material_id: StringName, volume: float) -> void:
	if _cooldowns.get(material_id, 0.0) > 0.0 or not _can_play():
		return
	_cooldowns[material_id] = MATERIAL_INTERVAL
	var sound: AudioStreamWAV = WOOD
	match material_id:
		&"glass": sound = GLASS
		&"stone": sound = STONE
		&"metal": sound = METAL
	_play(material_id, sound, volume)


func _can_play() -> bool:
	if not is_inside_tree() or not can_process() or is_queued_for_deletion():
		return false
	var bus_index := AudioServer.get_bus_index(&"SFX")
	return bus_index >= 0 and not AudioServer.is_bus_mute(bus_index)


func _play(effect_id: StringName, sound: AudioStreamWAV, volume: float, priority: bool = false) -> void:
	if not _can_play():
		return
	var available: AudioStreamPlayer
	for player in _players:
		if not player.playing:
			available = player
			break
	if available == null:
		if not priority:
			return
		available = _players[0]
		available.stop()
	available.stream = sound
	available.volume_db = volume
	available.play()
	play_count += 1
	effect_played.emit(effect_id)
