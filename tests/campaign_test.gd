extends SceneTree
## Прогресс между запусками, ограничения переходов и сохранность рекордов.

const APP_SCENE := preload("res://scenes/app.tscn")
var _checks: int = 0
var _failures: int = 0
var _save_path: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_save_path = "user://campaign_test_%d.json" % Time.get_ticks_usec()
	_test_profile()
	await _test_app()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(_save_path + suffix):
			DirAccess.remove_absolute(_save_path + suffix)
	print("Campaign checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_profile() -> void:
	var profile := PlayerProfile.new(_save_path)
	profile.load_data()
	_check(profile.results.is_empty() and profile.cat_id == &"classic", "Missing profile has defaults")
	_check(CampaignCatalog.is_unlocked(0, profile) and not CampaignCatalog.is_unlocked(1, profile), "Only first yard starts unlocked")
	_check(not CampaignCatalog.is_unlocked(-1, profile) and not CampaignCatalog.is_unlocked(CampaignCatalog.LEVELS.size(), profile), "Invalid campaign indices cannot start")
	profile.cat_id = &"frost"
	profile.dog_id = &"jumper"
	profile.sound_muted = true
	profile.music_volume = 0.35
	profile.effects_volume = 0.7
	_check(profile.record_win(CampaignCatalog.IDS[0], 1, 3) == OK, "Win writes profile")
	_check(profile.record_win(CampaignCatalog.IDS[0], 3, 1) == OK, "Replay writes profile")
	var restored := PlayerProfile.new(_save_path)
	restored.load_data()
	_check(restored.cat_id == &"frost" and restored.dog_id == &"jumper" and restored.sound_muted, "Settings survive new profile instance")
	_check(is_equal_approx(restored.music_volume, 0.35) and is_equal_approx(restored.effects_volume, 0.7), "Music and effects volumes survive a profile reload independently")
	_check(restored.stars_for(CampaignCatalog.IDS[0]) == 3 and restored.best_shots_for(CampaignCatalog.IDS[0]) == 1, "Worse replay preserves best stars and shot count")
	_check(CampaignCatalog.is_unlocked(1, restored) and not CampaignCatalog.is_unlocked(2, restored), "Win unlocks exactly next yard")
	_check(restored.record_win("bad", 30, 5) == ERR_INVALID_PARAMETER, "Invalid records rejected")
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	restored.load_data()
	_check(restored.stars_for(CampaignCatalog.IDS[0]) == 3, "Valid backup recovers interrupted/corrupt save")
	for suffix in ["", ".bak"]:
		DirAccess.remove_absolute(_save_path + suffix)
	file = FileAccess.open(_save_path, FileAccess.WRITE)
	file.store_string('{"version":1,"cat":"unknown","dog":"unknown","results":{"bad":{"stars":"three","shots":[]}}}')
	file.close()
	restored.load_data()
	_check(restored.cat_id == &"classic" and restored.dog_id == &"scout" and restored.results.is_empty(), "Invalid IDs and malformed record use safe defaults")
	_check(restored.music_volume == 1.0 and restored.effects_volume == 1.0, "Legacy profiles retain authored audio levels")
	file = FileAccess.open(_save_path, FileAccess.WRITE)
	file.store_string('{"version":1,"music_volume":"loud","effects_volume":-8}')
	file.close()
	restored.load_data()
	_check(restored.music_volume == 1.0 and restored.effects_volume == 0.0, "Malformed volume uses a default and numeric volume stays in range")
	DirAccess.remove_absolute(_save_path)
	_check(CampaignCatalog.IDS.slice(0, 9) == ["first_throw", "air_trick", "little_shelter", "glass_bridge", "restless_yard", "last_fort", "falling_gallery", "double_drop", "weight_cascade"], "Existing nine saved level IDs retain their order")
	var legacy := PlayerProfile.new("")
	for index in 9:
		legacy.record_win(CampaignCatalog.IDS[index], CampaignCatalog.LEVELS[index].par_shots, 3)
	_check(CampaignCatalog.total_stars(legacy) == 27 and CampaignCatalog.is_unlocked(9, legacy) and not CampaignCatalog.is_unlocked(10, legacy), "Old campaign completion keeps 27 stars and opens only level ten")
	_check(not legacy.rewards.has("campaign_complete") and not legacy.rewards.has("perfect_campaign"), "New completion badges require all twenty results")
	_check(CampaignCatalog.CHAPTER_STARTS.back() == CampaignCatalog.LEVELS.size() and CampaignCatalog.NOTES.size() == CampaignCatalog.LEVELS.size(), "Chapter ranges and hints cover the whole campaign")
	for index in CampaignCatalog.LEVELS.size():
		var level := CampaignCatalog.LEVELS[index]
		_check(StringName(level.biome) == CampaignCatalog.CHAPTER_BIOMES[CampaignCatalog.chapter_for_level(index)], "Campaign chapter matches the environment of level %d" % (index + 1))
		_check(level.is_valid() and level.cat_sequence.size() == level.shots and level.dog_kinds.size() == level.dog_positions.size(), "Campaign yard %d has valid complete loadout" % (index + 1))
		_check(level.cat_sequence.size() > 1 and level.dog_positions.size() > 1, "Campaign yard %d contains multiple cats and dogs" % (index + 1))


func _test_app() -> void:
	var initial_quit_on_go_back := quit_on_go_back
	var app := APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = _save_path
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await _settle()
	_check(app.campaign != null and app.menu == null and app.game == null, "Application starts at main menu")
	_check(not quit_on_go_back, "Main menu intercepts native Back before automatic quit")
	_check(app.campaign.level_buttons.size() == 20, "Campaign includes twenty authored yards")
	_check(app.campaign.chapter_panels.size() == 8, "Campaign has eight complete chapters")
	for chapter in app.campaign.chapter_panels.size():
		var buttons := app.campaign.chapter_panels[chapter].find_children("*", "Button", true, false)
		var start := CampaignCatalog.CHAPTER_STARTS[chapter]
		_check(buttons.size() == CampaignCatalog.CHAPTER_STARTS[chapter + 1] - start, "Chapter contains its complete level range")
		for offset in buttons.size():
			_check(buttons[offset] == app.campaign.level_buttons[start + offset], "Chapter order preserves progression and saved level IDs")
	_check(app.campaign.continue_index == 0 and app.campaign.continue_button.text.begins_with("Играть"), "New profile starts at first yard with Play")
	await _test_menu_navigation(app.campaign)
	await _test_sound_controls(app)
	var sound: SoundToggle
	for node in app.campaign.find_children("*", "Button", true, false):
		if node is SoundToggle:
			sound = node
	_check(sound != null, "Campaign exposes sound toggle")
	if sound != null:
		sound.pressed.emit()
	app.campaign.sandbox_button.pressed.emit()
	await _settle()
	_check(app.menu != null and app.campaign == null, "Hero selection is an optional sandbox")
	app.menu.select_character(&"magnet")
	app.menu.show_species(&"dog")
	app.menu.select_character(&"armored")
	var saved := PlayerProfile.new(_save_path)
	saved.load_data()
	_check(saved.cat_id == &"magnet" and saved.dog_id == &"armored" and saved.sound_muted, "Choosing heroes and muting save immediately")
	root.go_back_requested.emit()
	await _settle()
	_check(app.campaign != null and app.campaign.page == &"home", "Sandbox returns to main menu")
	_check(app.campaign.level_buttons[1].disabled, "Locked yard button is disabled")
	app.start_campaign_level(4)
	await _settle()
	_check(app.game == null, "Locked yard cannot be started through application")
	app.campaign.continue_button.pressed.emit()
	await _settle()
	_check(app.game.campaign_mode and app.game.level.title == CampaignCatalog.LEVELS[0].title, "First campaign yard starts")
	_check(not quit_on_go_back, "Application continues intercepting native Back during a round")
	root.go_back_requested.emit()
	await _settle()
	_check(paused and app.game != null, "System Back pauses a round without leaving it")
	var paused_controls := _sound_controls(app.game)
	_check(paused_controls != null, "Pause exposes independent volume controls")
	if paused_controls != null:
		paused_controls.open_settings()
		root.go_back_requested.emit()
		await _settle()
		_check(not paused_controls.dialog.visible and paused, "Back closes audio settings before resuming a paused round")
	root.go_back_requested.emit()
	await _settle()
	_check(not paused and app.game != null, "Second System Back resumes the same round")
	_check(app.game.slingshot.loaded_projectile.definition.id == &"classic", "Campaign fixed loadout overrides sandbox selection")
	var dog_ids: PackedStringArray = []
	for target in get_nodes_in_group("targets"):
		dog_ids.append(String((target as DogTarget).definition.id))
	_check(dog_ids == CampaignCatalog.LEVELS[0].dog_kinds, "Campaign dogs override sandbox selection too")
	app.game.shots_left = 2
	for target in get_nodes_in_group("targets"):
		(target as DogTarget).destroy()
	await _settle()
	_check(app.game.state == GameRound.RoundState.WON and app.profile.stars_for(CampaignCatalog.IDS[0]) == 3, "Campaign victory records stars")
	app.game.hud.next_requested.emit()
	await _settle()
	_check(app.campaign_index == 1 and app.game.level.title == CampaignCatalog.LEVELS[1].title, "Next button enters newly unlocked yard")
	app.game.restart()
	await _settle()
	_check(app.campaign_index == 1 and app.game.slingshot.loaded_projectile.definition.id == &"splitter", "Restart restores same yard and first cat")
	app.game.return_to_menu()
	await _settle()
	_check(app.campaign != null and not app.campaign.level_buttons[1].disabled, "Return opens campaign with updated unlock")
	_check(app.campaign.continue_index == 1 and app.campaign.continue_button.text.begins_with("Продолжить"), "Continue selects first unlocked unbeaten yard")
	app.campaign.rating_button.pressed.emit()
	await _settle()
	_check_rating(app.campaign)
	app.campaign.back_button.pressed.emit()
	await _settle()
	app.start_game(&"bomb", &"scout")
	await _settle()
	for target in get_nodes_in_group("targets"):
		(target as DogTarget).destroy()
	await _settle()
	_check(app.profile.results.size() == 1, "Sandbox victory awards no campaign credit")
	root.go_back_requested.emit()
	await _settle()
	_check(app.game == null and app.menu != null, "Back from a sandbox result returns to its hero selection")
	app.queue_free()
	await _settle()
	_check(quit_on_go_back == initial_quit_on_go_back, "Removing the application restores native Back policy")
	app = APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = _save_path
	app.editor_recovery_path = ""
	root.add_child(app)
	current_scene = app
	await _settle()
	_check(app.selected_cat_id == &"bomb" and app.profile.stars_for(CampaignCatalog.IDS[0]) == 3, "New app restores latest heroes and campaign progress")
	_check(is_equal_approx(SoundControls.volume_for(&"Music"), 0.35) and is_equal_approx(SoundControls.volume_for(&"SFX"), 0.7), "Relaunch restores both audio bus volumes")
	_check(app.campaign != null and app.menu == null and app.campaign.page == &"home" and app.campaign.continue_index == 1, "Relaunch opens main menu at saved progress")
	app.campaign.continue_button.pressed.emit()
	await _settle()
	_check(app.campaign_index == 1 and app.game.slingshot.loaded_projectile.definition.id == &"splitter", "Continue after relaunch starts next fixed loadout")
	app.game.return_to_menu()
	await _settle()
	for index in 6:
		app.profile.record_win(CampaignCatalog.IDS[index], CampaignCatalog.LEVELS[index].par_shots, 3)
	app.show_campaign()
	await _settle()
	_check(CampaignCatalog.total_stars(app.profile) == 18 and app.campaign.continue_index == 6, "Completed legacy campaign continues into chain reactions with old records intact")
	_check(CampaignCatalog.is_unlocked(6, app.profile) and not CampaignCatalog.is_unlocked(7, app.profile), "Legacy completion unlocks exactly the first new yard")
	app.start_campaign_level(5)
	await _settle()
	_check(app.game.has_next_level, "Former final yard now offers the chain reaction chapter")
	app.game.return_to_menu()
	await _settle()
	for index in CampaignCatalog.LEVELS.size():
		app.profile.record_win(CampaignCatalog.IDS[index], CampaignCatalog.LEVELS[index].par_shots, 3)
	app.start_campaign_level(CampaignCatalog.LEVELS.size() - 1)
	await _settle()
	_check(not app.game.has_next_level, "Last yard has no nonexistent next level")
	app.game.return_to_menu()
	await _settle()
	_check(CampaignCatalog.total_stars(app.profile) == 60, "Completed campaign totals sixty stars")
	_check(app.campaign.continue_button.text.begins_with("Переиграть") and app.campaign.continue_index == 0, "Complete campaign offers replay from first yard")
	app.campaign.show_page(&"rating")
	await _settle()
	_check_rating(app.campaign)
	app.campaign.back_button.pressed.emit()
	await _settle()
	app.campaign.continue_button.pressed.emit()
	await _settle()
	_check(app.campaign_index == 0 and app.game.campaign_mode, "Replay starts completed campaign yard")
	app.game.return_to_menu()
	await _settle()
	app.campaign.editor_button.pressed.emit()
	await _settle()
	_check(app.editor != null and app.editor.visible, "Editor is accessible directly from main menu")
	app.editor._show_library()
	root.go_back_requested.emit()
	await _settle()
	_check(app.editor.visible and app.campaign == null, "Back dismisses an editor dialog without leaving the editor")
	root.go_back_requested.emit()
	await _settle()
	_check(app.campaign != null and app.menu == null and app.campaign.page == &"home", "Editor returns to main menu")
	var music_playback_ref: WeakRef = weakref((app.get_node("BackgroundMusic") as AudioStreamPlayer).get_stream_playback())
	app.queue_free()
	await _settle()
	# Микшер освобождает поток отдельно от быстрых headless-кадров дерева.
	var audio_deadline := Time.get_ticks_msec() + 1000
	while music_playback_ref.get_ref() != null and Time.get_ticks_msec() < audio_deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(music_playback_ref.get_ref() == null, "Closing the campaign releases the application audio playback")
	SoundToggle.set_muted(false)
	SoundControls.set_volume(&"Music", 1.0)
	SoundControls.set_volume(&"SFX", 1.0)


func _test_sound_controls(app: GameApp) -> void:
	var controls := _sound_controls(app.campaign)
	_check(controls != null, "Main menu exposes audio settings")
	if controls == null:
		return
	controls.open_settings()
	await _settle()
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = controls.music_slider.get_global_rect().position + controls.music_slider.size * Vector2(0.6, 0.5)
		touch.pressed = pressed
		controls.dialog.push_input(touch, true)
	_check(controls.music_slider.value > 50.0 and controls.music_slider.value < 70.0, "Music slider accepts native touch without mouse emulation")
	controls.music_slider.value = 35.0
	_check(is_equal_approx(SoundControls.volume_for(&"Music"), 0.35) and is_equal_approx(SoundControls.volume_for(&"SFX"), 1.0), "Music slider leaves effects volume unchanged")
	controls.effects_slider.value = 70.0
	var saved := PlayerProfile.new(_save_path)
	saved.load_data()
	_check(is_equal_approx(saved.music_volume, 0.35) and is_equal_approx(saved.effects_volume, 0.7), "Sliders immediately persist both volume settings")
	controls.music_slider.value = 0.0
	_check(is_zero_approx(SoundControls.volume_for(&"Music")) and is_equal_approx(SoundControls.volume_for(&"SFX"), 0.7), "Music can be silenced while effects remain audible")
	controls.music_slider.value = 35.0
	root.go_back_requested.emit()
	await _settle()
	_check(not controls.dialog.visible and app.campaign.page == &"home", "System Back closes audio settings without quitting the main menu")
	var toggle := controls.get_child(0) as SoundToggle
	toggle.pressed.emit()
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")) and SoundToggle.is_muted(), "General mute affects both independent buses")
	toggle.pressed.emit()
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Music")) and is_equal_approx(SoundControls.volume_for(&"Music"), 0.35), "Unmuting restores the chosen music level")


func _sound_controls(screen: Node) -> SoundControls:
	for node in screen.find_children("*", "HBoxContainer", true, false):
		if node is SoundControls:
			return node as SoundControls
	return null


func _test_menu_navigation(menu: CampaignMenu) -> void:
	_check(menu.page == &"home" and menu.continue_button.is_visible_in_tree(), "Main menu starts with its primary action visible")
	_check(not menu.back_button.is_visible_in_tree() and not menu.level_buttons[0].is_visible_in_tree(), "Home hides page navigation and yard cards")
	menu.campaign_button.pressed.emit()
	await _settle()
	_check(menu.page == &"campaign" and menu.level_buttons[0].is_visible_in_tree() and menu.back_button.is_visible_in_tree(), "Campaign button opens yard selection")
	menu.back_button.pressed.emit()
	await _settle()
	_check(menu.page == &"home" and menu.continue_button.is_visible_in_tree(), "Back from campaign restores main menu")
	menu.rating_button.pressed.emit()
	await _settle()
	_check(menu.page == &"rating" and menu.rating_summary.is_visible_in_tree(), "Rating button opens local records")
	_check_rating(menu)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	escape = escape.duplicate() as InputEventKey
	escape.pressed = false
	root.push_input(escape, true)
	await _settle()
	_check(menu.page == &"home", "Escape from rating restores main menu")
	menu.show_page(&"campaign")
	root.go_back_requested.emit()
	await _settle()
	_check(menu.page == &"home", "System Back from campaign restores main menu")


func _check_rating(menu: CampaignMenu) -> void:
	_check(menu.rating_rows.size() == CampaignCatalog.LEVELS.size(), "Local rating contains one row per prepared yard")
	var summary := menu.rating_summary.text.replace(" ", "")
	_check("%d/%d" % [CampaignCatalog.total_stars(menu.profile), CampaignCatalog.LEVELS.size() * 3] in summary, "Rating summary uses actual profile stars")
	for index in mini(menu.rating_rows.size(), CampaignCatalog.LEVELS.size()):
		var value := menu.rating_rows[index].text
		var stars := menu.profile.stars_for(CampaignCatalog.IDS[index])
		_check(CampaignCatalog.LEVELS[index].title in value, "Rating names yard %d" % (index + 1))
		if stars == 0:
			_check("не пройден" in value.to_lower(), "Unplayed yard %d has no invented score" % (index + 1))
		else:
			_check("★".repeat(stars) in value and "Рекорд: %d" % menu.profile.best_shots_for(CampaignCatalog.IDS[index]) in value, "Rating shows saved stars and best shots for yard %d" % (index + 1))


func _settle() -> void:
	for frame in 5:
		await process_frame
	await create_timer(0.05).timeout


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
