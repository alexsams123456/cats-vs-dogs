class_name CatVoice
extends AudioStreamPlayer
## One bounded voice per projectile; inherited pause also pauses playback.

const MEOW_CLASSIC := preload("res://assets/audio/meow_classic.wav")
const MEOW_BOMB := preload("res://assets/audio/meow_bomb.wav")
const MEOW_ZIGZAG := preload("res://assets/audio/meow_zigzag.wav")

var play_count: int = 0


func _ready() -> void:
	bus = &"SFX"
	volume_db = -12.0
	max_polyphony = 1
	var cat := get_parent() as CatProjectile
	if cat == null:
		return
	var kind: StringName = cat.definition.id if cat.definition != null else &"classic"
	match kind:
		&"bomb", &"heavy", &"magnet": stream = MEOW_BOMB
		&"zigzag", &"splitter", &"wind", &"frost": stream = MEOW_ZIGZAG
		_: stream = MEOW_CLASSIC
	match kind:
		&"splitter": pitch_scale = 1.12
		&"heavy": pitch_scale = 0.82
		&"wind": pitch_scale = 1.06
		&"magnet": pitch_scale = 0.95
		&"frost": pitch_scale = 0.92
		&"ghost": pitch_scale = 0.86
		&"homing": pitch_scale = 1.08
	cat.meow_requested.connect(play_meow)


func play_meow() -> void:
	if not is_inside_tree() or get_tree().paused:
		return
	var bus_index := AudioServer.get_bus_index(bus)
	if bus_index >= 0 and AudioServer.is_bus_mute(bus_index):
		return
	play_count += 1
	play()
