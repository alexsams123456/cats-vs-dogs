extends SceneTree
## Один музыкальный фон сопровождает все экраны, сохраняет фразу и подчиняется общему звуку.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const APP_SCENE := preload("res://scenes/app.tscn")

var _checks: int = 0
var _failures: int = 0
var _save_path: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_save_path = "user://background_music_test_%d.json" % Time.get_ticks_usec()
	var bus_index := AudioServer.get_bus_index(&"Music")
	_check(bus_index >= 0 and bus_index != AudioServer.get_bus_index(&"SFX"), "Music uses a separate bus from sound effects")
	if bus_index < 0:
		quit(1)
		return
	var initially_muted := AudioServer.is_bus_mute(bus_index)
	AudioServer.set_bus_mute(bus_index, false)
	await _test_playback(bus_index)
	await _test_screens(bus_index)
	AudioServer.set_bus_mute(bus_index, initially_muted)
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(_save_path + suffix):
			DirAccess.remove_absolute(_save_path + suffix)
	# Даём аудиодрайверу освободить удалённые потоки перед завершением процесса.
	await create_timer(0.3).timeout
	print("Background music checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_playback(bus_index: int) -> void:
	var game := MAIN_SCENE.instantiate() as GameRound
	root.add_child(game)
	current_scene = game
	var music := game.get_node_or_null("BackgroundMusic") as BackgroundMusic
	_check(music != null, "Direct round supplies its own music without the application")
	if music == null:
		game.queue_free()
		await _settle()
		return
	_check(game.background_music == music, "Direct round exposes its fallback music")
	_check(_music_count() == 1 and music.playing, "Direct round starts exactly one music player")
	_check(is_zero_approx(music.volume_linear), "Direct round enters with a silent fade")
	_check(AudioServer.get_bus_index(music.bus) == bus_index, "Music uses the bus controlled by the sound button")
	var stream := music.stream as AudioStreamWAV
	_check(stream != null and not stream.data.is_empty(), "Music contains imported audio samples")
	if stream != null:
		_check(stream.get_length() >= 40.0 and stream.get_length() <= 90.0, "Music has a long phrase rather than a short repeated effect")
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Imported music repeats continuously")
	await create_timer(0.25).timeout
	_check(music.volume_linear > 0.0, "Music rises gradually during the opening")
	game.set_paused(true)
	await create_timer(0.08, true).timeout
	var paused_volume := music.volume_linear
	var paused_position := music.get_playback_position()
	await create_timer(0.2, true).timeout
	_check(music.stream_paused, "Round pause suspends music playback")
	_check(is_equal_approx(music.volume_linear, paused_volume), "Opening fade freezes during pause")
	_check(absf(music.get_playback_position() - paused_position) < 0.03, "Paused music holds its playback position")
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(paused and music.stream_paused, "Regaining application focus preserves an explicit round pause")
	game.set_paused(false)
	await create_timer(0.15).timeout
	_check(not music.stream_paused and music.get_playback_position() > paused_position, "Resume continues the same musical phrase")
	_check(music.volume_linear > paused_volume, "Opening fade continues after resume")
	await create_timer(music.fade_in_seconds).timeout
	_check(music.volume_db >= -24.0 and music.volume_db <= -12.0, "Opening reaches an audible background level below the sound effects")
	if stream != null:
		music.seek(stream.get_length() - 0.15)
		await create_timer(0.4).timeout
		_check(music.playing and music.get_playback_position() < 2.0, "Playback crosses the loop boundary without stopping")
	for target in get_nodes_in_group("targets"):
		(target as DogTarget).destroy()
	await _settle()
	_check(game.state == GameRound.RoundState.WON and not paused, "Result screen keeps its scene tree active")
	await _test_focus(game, music, "Direct round result")
	var music_ref: WeakRef = weakref(music)
	game.queue_free()
	await _settle()
	_check(music_ref.get_ref() == null and _music_count() == 0, "Removing a direct round also removes its music")


func _test_screens(bus_index: int) -> void:
	var profile := PlayerProfile.new(_save_path)
	profile.sound_muted = true
	_check(profile.save_data() == OK, "Test uses an isolated muted profile")
	var app := _new_app()
	var music := app.get_node_or_null("BackgroundMusic") as BackgroundMusic
	_check(music != null, "Application owns music before creating any screen")
	if music == null:
		app.free()
		return
	var target_volume := music.volume_linear
	root.add_child(app)
	current_scene = app
	_check(AudioServer.is_bus_mute(bus_index) and music.playing, "Saved mute applies as the main menu begins playback")
	_check(is_zero_approx(music.volume_linear), "Application starts music with a silent fade")
	await _settle()
	_check(app.campaign != null and app.campaign.page == &"home", "Application begins on the main menu")
	_check_shared_music(app, music, 0.0, "Main menu")
	_check(music.volume_linear > 0.0 and music.volume_linear < target_volume, "Main menu gradually fades in the music")
	await _test_focus(app, music, "Main menu during fade")
	var toggle := _sound_toggle(app.campaign)
	_check(toggle != null, "Main menu exposes the shared sound button")
	if toggle != null:
		toggle.pressed.emit()
		_check(not AudioServer.is_bus_mute(bus_index) and music.playing, "Main menu sound button makes the existing music audible")
		_check_saved_mute(false, "Main menu saves enabled sound immediately")
	await create_timer(music.fade_in_seconds).timeout
	_check(is_equal_approx(music.volume_linear, target_volume), "Main menu fade reaches its authored volume")
	# Запас позиции позволяет заметить перезапуск записи даже при сохранении самого узла.
	music.seek(10.0)
	await _settle()
	for page in [&"campaign", &"rating", &"home"]:
		var page_position := music.get_playback_position()
		app.campaign.show_page(page)
		await _settle()
		_check(app.campaign.page == page, "Menu opens the %s page" % page)
		_check_shared_music(app, music, page_position, "Menu page %s" % page)
	var position := music.get_playback_position()
	app.campaign.continue_button.pressed.emit()
	await _settle()
	_check_round(app, music, position, "Campaign")
	toggle = _sound_toggle(app.game)
	_check(toggle != null, "Round exposes the shared sound button")
	if toggle != null:
		toggle.pressed.emit()
		_check(AudioServer.is_bus_mute(bus_index) and music.playing, "Round sound button mutes music together with effects")
		_check_saved_mute(true, "Round saves disabled sound immediately")
	await _test_active_round_focus(app, music)
	app.game.set_paused(true)
	await create_timer(0.08, true).timeout
	position = music.get_playback_position()
	await create_timer(0.15, true).timeout
	_check(music.stream_paused and absf(music.get_playback_position() - position) < 0.03, "Round pause also suspends the application music")
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(paused and music.stream_paused, "Application focus cannot override the round's explicit pause")
	app.game.restart()
	await _settle()
	_check_round(app, music, position, "Restarted campaign")
	_check(not paused and not music.stream_paused, "Restart from pause resumes the shared musical timeline")
	_check(AudioServer.is_bus_mute(bus_index), "Restart preserves the shared mute setting")
	await _test_campaign_rounds(app, music)
	position = music.get_playback_position()
	app.game.return_to_menu()
	await _settle()
	_check(app.campaign != null, "Leaving campaign returns to main menu")
	_check_shared_music(app, music, position, "Return from campaign")
	position = music.get_playback_position()
	app.campaign.sandbox_button.pressed.emit()
	await _settle()
	_check(app.menu != null, "Sandbox opens hero selection")
	_check_shared_music(app, music, position, "Hero selection")
	position = music.get_playback_position()
	app.menu.play_requested.emit(&"classic", &"scout")
	await _settle()
	_check_round(app, music, position, "Sandbox round")
	position = music.get_playback_position()
	app.game.return_to_menu()
	await _settle()
	_check(app.menu != null, "Leaving sandbox returns to hero selection")
	_check_shared_music(app, music, position, "Return from sandbox")
	position = music.get_playback_position()
	app.show_editor()
	await _settle()
	_check(app.editor != null, "Editor opens without a round")
	_check_shared_music(app, music, position, "Level editor")
	await _test_focus(app, music, "Level editor")
	position = music.get_playback_position()
	app.editor.play_button.pressed.emit()
	await _settle()
	_check_round(app, music, position, "Editor preview")
	_check(app.game.editor_preview, "Music also accompanies the editor's playable preview")
	position = music.get_playback_position()
	app.game.return_to_menu()
	await _settle()
	_check(app.editor.visible, "Leaving preview returns to the editor")
	_check_shared_music(app, music, position, "Return to editor")
	var music_ref: WeakRef = weakref(music)
	app.queue_free()
	await _settle()
	_check(music_ref.get_ref() == null and _music_count() == 0, "Closing application frees the shared player")
	AudioServer.set_bus_mute(bus_index, false)
	app = _new_app()
	root.add_child(app)
	current_scene = app
	await _settle()
	music = app.get_node("BackgroundMusic") as BackgroundMusic
	_check(AudioServer.is_bus_mute(bus_index) and music.playing and _music_count() == 1, "New application restores saved mute while starting one music player")
	app.queue_free()
	await _settle()
	_check(_music_count() == 0, "Repeated application lifetime leaves no music players")


func _test_campaign_rounds(app: GameApp, music: BackgroundMusic) -> void:
	for index in CampaignCatalog.LEVELS.size():
		_check(app.campaign_index == index, "Music accompanies campaign level %d" % (index + 1))
		var position := music.get_playback_position()
		for target in get_nodes_in_group("targets"):
			(target as DogTarget).destroy()
		await _settle()
		_check(app.game.state == GameRound.RoundState.WON, "Campaign level %d reaches its result screen" % (index + 1))
		_check_shared_music(app, music, position, "Campaign result %d" % (index + 1))
		if index + 1 < CampaignCatalog.LEVELS.size():
			position = music.get_playback_position()
			app.game.hud.next_requested.emit()
			await _settle()
			_check_round(app, music, position, "Next campaign level %d" % (index + 2))


func _test_active_round_focus(app: GameApp, music: BackgroundMusic) -> void:
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.08, true).timeout
	var position := music.get_playback_position()
	_check(paused and music.stream_paused, "Losing focus in an active round pauses both gameplay and shared music")
	app.game.set_paused(false)
	await create_timer(0.15, true).timeout
	_check(not paused and music.stream_paused and absf(music.get_playback_position() - position) < 0.03, "Removing gameplay pause while unfocused keeps the music suspended")
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.15, true).timeout
	_check(not paused and not music.stream_paused and music.get_playback_position() > position, "Music resumes after both focus loss and gameplay pause are cleared")


func _test_focus(screen: Node, music: BackgroundMusic, description: String) -> void:
	screen.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await create_timer(0.08, true).timeout
	var position := music.get_playback_position()
	var volume := music.volume_linear
	await create_timer(0.15, true).timeout
	_check(music.stream_paused and absf(music.get_playback_position() - position) < 0.03, description + " suspends music when focus is lost")
	_check(is_equal_approx(music.volume_linear, volume), description + " also holds the fade while unfocused")
	screen.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.15, true).timeout
	_check(not music.stream_paused and music.get_playback_position() > position, description + " resumes the same phrase after regaining focus")


func _new_app() -> GameApp:
	var app := APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = _save_path
	app.editor_recovery_path = ""
	return app


func _check_shared_music(app: GameApp, music: BackgroundMusic, position: float, description: String) -> void:
	_check(app.get_node("BackgroundMusic") == music and _music_count() == 1 and music.playing and not music.stream_paused, description + " retains the only active music player")
	_check(music.get_playback_position() >= position - 0.03, description + " continues without restarting the phrase")


func _check_round(app: GameApp, music: BackgroundMusic, position: float, description: String) -> void:
	_check(app.game.background_music == music, description + " uses the application's player")
	_check_shared_music(app, music, position, description)


func _check_saved_mute(expected: bool, description: String) -> void:
	var restored := PlayerProfile.new(_save_path)
	restored.load_data()
	_check(restored.sound_muted == expected, description)


func _music_count() -> int:
	var count := 0
	for node in root.find_children("*", "AudioStreamPlayer", true, false):
		if node is BackgroundMusic:
			count += 1
	return count


func _sound_toggle(screen: Node) -> SoundToggle:
	for node in screen.find_children("*", "Button", true, false):
		if node is SoundToggle:
			return node as SoundToggle
	return null


func _settle() -> void:
	for frame in 5:
		await process_frame
	await create_timer(0.05).timeout


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
