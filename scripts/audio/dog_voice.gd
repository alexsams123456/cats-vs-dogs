class_name DogVoice
extends AudioStreamPlayer
## Голос собаки; общий предел голосов защищает звук больших пользовательских уровней.

signal bark_started(duration: float)

const BARK_SCOUT := preload("res://assets/audio/bark_scout.wav")
const BARK_ARMORED := preload("res://assets/audio/bark_armored.wav")
const BARK_JUMPER := preload("res://assets/audio/bark_jumper.wav")
const MAX_VOICES := 2
const VOICE_GROUP := &"dog_voices"
const IDLE_PACK_INTERVAL: float = 4.0

var play_count: int = 0
var _dog: DogTarget
var _idle_pack_cooldown_left: float = 0.0


func _ready() -> void:
	bus = &"SFX"
	volume_db = -6.0
	max_polyphony = 1
	add_to_group(VOICE_GROUP)
	_dog = get_parent() as DogTarget
	if _dog == null:
		return
	var kind: StringName = _dog.definition.id if _dog.definition != null else &"scout"
	match kind:
		&"armored": stream = BARK_ARMORED
		&"jumper": stream = BARK_JUMPER
		_: stream = BARK_SCOUT
	_dog.bark_requested.connect(play_bark)
	_dog.idle_bark_requested.connect(play_idle_bark)
	_dog.bark_interrupted.connect(stop)
	bark_started.connect(_dog.show_bark)


func _process(delta: float) -> void:
	_idle_pack_cooldown_left = maxf(0.0, _idle_pack_cooldown_left - delta)


func play_idle_bark() -> void:
	if not is_inside_tree():
		return
	# В покое отвечает одна собака; отклонённые голоса не ждут в очереди.
	# Лай на подлёте кота проходит напрямую и имеет приоритет над этим интервалом.
	for voice: Node in get_tree().get_nodes_in_group(VOICE_GROUP):
		if voice is DogVoice and (voice.playing or voice._idle_pack_cooldown_left > 0.0):
			return
	play_bark()


func play_bark() -> void:
	if not is_inside_tree() or not can_process() or playing:
		return
	if not is_instance_valid(_dog) or _dog.is_destroyed or _dog.is_queued_for_deletion():
		return
	if _dog.frost_time_left > 0.0:
		return
	var bus_index := AudioServer.get_bus_index(bus)
	if bus_index >= 0 and AudioServer.is_bus_mute(bus_index):
		return
	var active_voices := 0
	for voice: Node in get_tree().get_nodes_in_group(VOICE_GROUP):
		if voice is AudioStreamPlayer and voice.playing:
			active_voices += 1
			if active_voices >= MAX_VOICES:
				return
	play_count += 1
	_idle_pack_cooldown_left = IDLE_PACK_INTERVAL
	play()
	bark_started.emit(stream.get_length())
