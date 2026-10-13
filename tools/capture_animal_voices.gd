extends SceneTree
## Прослушивание трёх мяу и трёх гав: запись реального выхода Master.

const CAT_SCENE := preload("res://scenes/actors/cat_projectile.tscn")
const DOG_SCENE := preload("res://scenes/actors/dog_target.tscn")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		push_error("Нужен графический запуск с настоящим аудиодрайвером.")
		quit(1)
		return
	var world := Node2D.new()
	root.add_child(world)
	var master_bus := AudioServer.get_bus_index(&"Master")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	var original_mute := AudioServer.is_bus_mute(sfx_bus)
	AudioServer.set_bus_mute(sfx_bus, false)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var effect_index := AudioServer.get_bus_effect_count(master_bus)
	AudioServer.add_bus_effect(master_bus, recorder)
	await create_timer(0.2).timeout
	recorder.set_recording_active(true)
	await create_timer(0.15).timeout
	for index in 3:
		var cat := CAT_SCENE.instantiate() as CatProjectile
		cat.definition = CharacterCatalog.CATS[index]
		cat.freeze = true
		world.add_child(cat)
		(cat.get_node("Voice") as CatVoice).play_meow()
		await create_timer(0.85).timeout
		cat.queue_free()
	for index in 3:
		var dog := DOG_SCENE.instantiate() as DogTarget
		dog.definition = CharacterCatalog.DOGS[index]
		dog.freeze = true
		world.add_child(dog)
		dog.set_process(false)
		(dog.get_node("Voice") as DogVoice).play_bark()
		await create_timer(0.85).timeout
		dog.queue_free()
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	var result := recording.save_to_wav("res://.artifacts/animal-voices-preview.wav")
	AudioServer.remove_bus_effect(master_bus, effect_index)
	AudioServer.set_bus_mute(sfx_bus, original_mute)
	world.queue_free()
	await create_timer(0.3).timeout
	print("Animal voice preview (%s): %s" % [AudioServer.get_driver_name(), error_string(result)])
	quit(0 if result == OK else 1)
