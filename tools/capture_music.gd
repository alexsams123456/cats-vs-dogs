extends SceneTree
## Проверка реального сигнала на Master в графическом запуске с аудиодрайвером.
## Godot --path . --script res://tools/capture_music.gd

const APP_SCENE := preload("res://scenes/app.tscn")
const SAMPLE_SECONDS: float = 0.8

var _checks: int = 0
var _failures: int = 0
var _recorder: AudioEffectRecord
var _master_bus: int = -1
var _effect_index: int = -1
var _last_position: float = 0.0


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		push_error("Для проверки музыки нужен графический запуск с настоящим аудиодрайвером.")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute("res://.artifacts") != OK:
		push_error("Не удалось создать папку .artifacts.")
		quit(1)
		return
	_master_bus = AudioServer.get_bus_index(&"Master")
	var sfx_bus := AudioServer.get_bus_index(&"SFX")
	var music_bus := AudioServer.get_bus_index(&"Music")
	if _master_bus < 0 or sfx_bus < 0 or music_bus < 0:
		push_error("Для проверки музыки нужны шины Master, SFX и Music.")
		quit(1)
		return
	var original_mute := AudioServer.is_bus_mute(sfx_bus)
	var original_music_mute := AudioServer.is_bus_mute(music_bus)
	var original_music_volume := SoundControls.volume_for(&"Music")
	var original_effects_volume := SoundControls.volume_for(&"SFX")
	SoundToggle.set_muted(false)
	SoundControls.set_volume(&"Music", 1.0)
	SoundControls.set_volume(&"SFX", 1.0)
	_recorder = AudioEffectRecord.new()
	_recorder.format = AudioStreamWAV.FORMAT_16_BITS
	_effect_index = AudioServer.get_bus_effect_count(_master_bus)
	AudioServer.add_bus_effect(_master_bus, _recorder)
	root.size = Vector2i(1280, 720)
	var app := APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await create_timer(2.0).timeout
	var music := app.get_node_or_null("BackgroundMusic") as BackgroundMusic
	_verify(music != null, "Главное меню содержит проигрыватель музыки")
	if music != null:
		await _capture_routes(app, music)
	paused = false
	app.queue_free()
	await create_timer(0.2).timeout
	AudioServer.remove_bus_effect(_master_bus, _effect_index)
	AudioServer.set_bus_mute(sfx_bus, original_mute)
	AudioServer.set_bus_mute(music_bus, original_music_mute)
	SoundControls.set_volume(&"Music", original_music_volume)
	SoundControls.set_volume(&"SFX", original_effects_volume)
	print("Music capture (%s): %d passed, %d failed. WAV: .artifacts/music-*.wav" % [
		AudioServer.get_driver_name(), _checks - _failures, _failures])
	quit(1 if _failures else 0)


func _capture_routes(app: GameApp, music: BackgroundMusic) -> void:
	await _screen_sample(app, music, "menu")
	await _save_image("menu")
	app.campaign.show_page(&"campaign")
	await _screen_sample(app, music, "campaign-map")
	app.campaign.show_page(&"rating")
	await _screen_sample(app, music, "rating")
	_toggle_sound(app.campaign)
	await _sample("menu-muted", false)
	_toggle_sound(app.campaign)
	await _sample("menu-unmuted", true)
	SoundControls.set_volume(&"Music", 0.0)
	await _sample("music-volume-zero", false)
	_verify(is_equal_approx(SoundControls.volume_for(&"SFX"), 1.0), "Нулевая громкость музыки сохраняет громкость эффектов")
	SoundControls.set_volume(&"Music", 1.0)
	SoundControls.set_volume(&"SFX", 0.0)
	await _sample("effects-volume-zero", true)
	SoundControls.set_volume(&"SFX", 1.0)
	app.start_campaign_level(0)
	await _screen_sample(app, music, "campaign-battle")
	_verify(app.game.background_music == music, "Бой кампании использует музыку приложения")
	await _save_image("battle")
	app.game.set_paused(true)
	await _sample("battle-paused", false)
	app.game.set_paused(false)
	await _sample("battle-resumed", true)
	_toggle_sound(app.game)
	await _sample("battle-muted", false)
	_toggle_sound(app.game)
	await _sample("battle-unmuted", true)
	app.game.restart()
	await _screen_sample(app, music, "battle-restarted")
	app.show_sandbox()
	await _screen_sample(app, music, "sandbox")
	app.start_game(&"classic", &"scout")
	await _screen_sample(app, music, "sandbox-battle")
	_verify(app.game.background_music == music, "Свободный бой использует музыку приложения")
	app.show_editor()
	await _screen_sample(app, music, "editor")
	app.editor.request_play()
	await _screen_sample(app, music, "editor-battle")
	_verify(app.game.editor_preview and app.game.background_music == music,
		"Пробный бой использует музыку приложения")
	app.game.set_paused(true)
	app.game.return_to_menu()
	await _screen_sample(app, music, "editor-return")
	app.show_menu()
	await _screen_sample(app, music, "menu-return")
	# Контрольный сегмент исключает другой постоянный звук вместо музыки.
	music.stop()
	await _sample("music-stopped", false)


func _screen_sample(app: GameApp, music: BackgroundMusic, screen: String) -> void:
	await create_timer(0.25).timeout
	_verify(app.get_node_or_null("BackgroundMusic") == music,
		"%s сохраняет тот же проигрыватель" % screen)
	_verify(music.get_playback_position() > _last_position,
		"%s продолжает композицию без перезапуска" % screen)
	await _sample(screen, true)
	_last_position = music.get_playback_position()


func _sample(label: String, audible: bool) -> void:
	# Выходной буфер может содержать хвост до выключения звука или паузы.
	await create_timer(0.2, true).timeout
	_recorder.set_recording_active(true)
	await create_timer(SAMPLE_SECONDS, true).timeout
	_recorder.set_recording_active(false)
	var recording := _recorder.get_recording()
	_verify(recording != null, "%s получил запись Master" % label)
	if recording == null:
		return
	var data := recording.data
	_verify(data.size() >= int(recording.mix_rate * SAMPLE_SECONDS * 2.0),
		"%s содержит достаточное число PCM-отсчётов" % label)
	var peak: float = 0.0
	var energy: float = 0.0
	for offset in range(0, data.size() - 1, 2):
		var value := float(data.decode_s16(offset)) / 32768.0
		peak = maxf(peak, absf(value))
		energy += value * value
	var rms := sqrt(energy / maxf(1.0, data.size() / 2.0))
	if audible:
		_verify(rms > 0.00005, "%s содержит слышимый сигнал музыки" % label)
	else:
		_verify(peak <= 1.0 / 32768.0, "%s содержит тишину" % label)
	var path := "res://.artifacts/music-%s.wav" % label
	_verify(recording.save_to_wav(path) == OK, "%s сохранил WAV" % label)
	print("Music %s: RMS %.6f, peak %.6f" % [label, rms, peak])


func _toggle_sound(screen: Node) -> void:
	for node in screen.find_children("*", "Button", true, false):
		if node is SoundToggle:
			(node as SoundToggle).pressed.emit()
			return
	_verify(false, "Экран содержит кнопку общего звука")


func _save_image(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "res://.artifacts/music-%s.png" % label
	_verify(root.get_texture().get_image().save_png(path) == OK, "Сохранён кадр " + label)


func _verify(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
