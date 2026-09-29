extends SceneTree
## Графический бой, мышь/касания и запись фактического выхода Master.
## Посторонние эффекты направляются во временную тихую шину только в этом прогоне.

var _checks: int = 0
var _failures: int = 0
var _barks_heard: int = 0
var _sheltered_heard: int = 0
var _recorder: AudioEffectRecord
var _master_bus: int
var _effect_index: int
var _silent_bus: int


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		push_error("Нужен графический запуск с настоящим аудиодрайвером.")
		quit(1)
		return
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	var original_mute := AudioServer.is_bus_mute(sfx_bus)
	AudioServer.set_bus_mute(sfx_bus, false)
	_master_bus = AudioServer.get_bus_index(&"Master")
	_recorder = AudioEffectRecord.new()
	_recorder.format = AudioStreamWAV.FORMAT_16_BITS
	_effect_index = AudioServer.get_bus_effect_count(_master_bus)
	AudioServer.add_bus_effect(_master_bus, _recorder)
	_silent_bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(_silent_bus, &"BarkPreviewMuted")
	AudioServer.set_bus_mute(_silent_bus, true)
	root.size = Vector2i(1280, 720)
	var app := load("res://scenes/app.tscn").instantiate() as GameApp
	app.editor_recovery_path = ""
	app.profile_path = ""
	root.add_child(app)
	current_scene = app
	DirAccess.make_dir_recursive_absolute("res://.artifacts")
	await create_timer(0.3).timeout
	for kind: StringName in [&"scout", &"armored", &"jumper"]:
		app.start_game(&"classic", kind)
		await create_timer(0.2).timeout
		_prepare_audio(app)
		var before := _barks_heard
		await _record_interval("%s-idle" % kind, 2.3)
		_verify(_barks_heard == before + 1, "%s: до выстрела слышна одна собака" % kind)
		before = _barks_heard
		_recorder.set_recording_active(true)
		var anchor := app.game.slingshot.get_global_transform_with_canvas().origin
		_pointer(anchor, true, kind == &"armored")
		_pointer(anchor + Vector2(-95, 32), false, kind == &"armored")
		_verify(app.game.state == GameRound.RoundState.FLYING, "%s: мышь/касание запустило кота" % kind)
		var deadline := Time.get_ticks_msec() + 1600
		while _barks_heard == before and Time.get_ticks_msec() < deadline:
			await process_frame
		_verify(_barks_heard > before, "%s: лай реагирует на настоящий подлёт кота" % kind)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.artifacts/bark-%s.png" % kind)
		await create_timer(0.55).timeout
		_finish_recording("%s-shot" % kind, true)
	app.profile.record_win(CampaignCatalog.IDS[1], 1, 3)
	app.start_campaign_level(2)
	await create_timer(0.2).timeout
	_verify(app.game.campaign_mode and app.campaign_index == 2, "Открыт настоящий третий двор кампании с конурами")
	_prepare_audio(app)
	# Проверяем реального жителя конуры: остальные не мешают его первому ответу.
	for dog: DogTarget in get_nodes_in_group("targets"):
		if not dog.is_sheltered():
			dog._idle_bark_delay_left = 3.0
	var sheltered_before := _sheltered_heard
	await _record_interval("campaign-kennel", 2.3)
	_verify(_sheltered_heard > sheltered_before, "В кампании собака гавкает из целой будки")
	var dog := get_nodes_in_group("targets")[0] as DogTarget
	AudioServer.set_bus_mute(sfx_bus, true)
	await create_timer(0.2).timeout
	var muted_count := _barks_heard
	dog.bark_requested.emit()
	await _record_interval("muted", 0.5, false)
	_verify(_barks_heard == muted_count, "Выключенный звук отклоняет запрос лая без мимики")
	AudioServer.set_bus_mute(sfx_bus, false)
	dog.bark_requested.emit()
	await create_timer(0.04).timeout
	app.game.set_paused(true)
	await create_timer(0.2, true).timeout
	await _record_interval("paused", 0.5, false)
	app.game.set_paused(false)
	await _record_interval("resumed", 0.6)
	app.show_menu()
	await create_timer(0.3).timeout
	app.queue_free()
	await create_timer(0.3).timeout
	AudioServer.remove_bus_effect(_master_bus, _effect_index)
	AudioServer.remove_bus(_silent_bus)
	AudioServer.set_bus_mute(sfx_bus, original_mute)
	print("Bark capture (%s): %d passed, %d failed; WAV: .artifacts/bark-*.wav" % [AudioServer.get_driver_name(), _checks - _failures, _failures])
	quit(1 if _failures else 0)


func _prepare_audio(app: GameApp) -> void:
	for player: Node in app.find_children("*", "AudioStreamPlayer", true, false):
		if player is DogVoice:
			(player as DogVoice).bark_started.connect(_on_bark_started.bind(player.get_parent()))
		else:
			(player as AudioStreamPlayer).bus = &"BarkPreviewMuted"


func _on_bark_started(_duration: float, dog: DogTarget) -> void:
	_barks_heard += 1
	if dog.is_sheltered():
		_sheltered_heard += 1


func _record_interval(label: String, seconds: float, audible: bool = true) -> void:
	_recorder.set_recording_active(true)
	await create_timer(seconds, true).timeout
	_finish_recording(label, audible)


func _finish_recording(label: String, audible: bool) -> void:
	_recorder.set_recording_active(false)
	var recording := _recorder.get_recording()
	_verify(recording != null and not recording.data.is_empty(), label + ": микшер записал PCM")
	if recording == null or recording.data.is_empty():
		return
	var peak := 0.0
	var energy := 0.0
	var data := recording.data
	for offset in range(0, data.size() - 1, 2):
		var value := float(data.decode_s16(offset)) / 32768.0
		peak = maxf(peak, absf(value))
		energy += value * value
	var rms := sqrt(energy / maxf(1.0, data.size() / 2.0))
	_verify(peak > 0.1 and rms > 0.015 if audible else peak <= 1.0 / 32768.0, label + ": слышимый лай/тишина на выходе Master")
	_verify(recording.save_to_wav("res://.artifacts/bark-%s.wav" % label) == OK, label + ": WAV сохранён")
	print("Bark %s: RMS %.6f, peak %.6f" % [label, rms, peak])


func _verify(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)


func _pointer(position: Vector2, pressed: bool, touch: bool) -> void:
	if touch:
		var event := InputEventScreenTouch.new()
		event.index = 0
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.pressed = pressed
		root.push_input(event, true)
