extends SceneTree
## Условия, миграция профиля, сохранение и доступность коллекции.

const APP_SCENE := preload("res://scenes/app.tscn")
var _checks: int = 0
var _failures: int = 0
var _path: String
var _capture: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture = "--capture-rewards" in OS.get_cmdline_user_args()
	_path = "user://rewards_test_%d.json" % Time.get_ticks_usec()
	_test_conditions()
	_test_storage()
	await _test_app()
	await _test_collection()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(_path + suffix):
			DirAccess.remove_absolute(_path + suffix)
	GameLocalization.apply_locale("ru")
	print("Rewards checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_conditions() -> void:
	var profile := PlayerProfile.new("")
	_check(RewardCatalog.synchronize(profile).is_empty(), "New profile has no rewards")
	profile.record_win("custom_level", 1, 3)
	_check(profile.rewards.is_empty(), "Unknown level cannot earn campaign rewards")
	profile.record_win(CampaignCatalog.IDS[0], 2, 2)
	_check(profile.rewards == PackedStringArray(["first_win"]), "First victory grants only its badge")
	profile.record_win(CampaignCatalog.IDS[0], 1, 3)
	_check(profile.rewards.has("three_stars") and profile.rewards.has("one_shot"), "Three stars and one shot grant independent badges")
	profile.record_win(CampaignCatalog.IDS[0], 3, 1)
	_check(profile.rewards.size() == 3 and RewardCatalog.synchronize(profile).is_empty(), "Worse replays never revoke or duplicate rewards")
	profile.record_win(CampaignCatalog.IDS[1], 2, 3)
	_check(profile.rewards.has("chapter_0") and not profile.rewards.has("chapter_1"), "Chapter requires its own complete set of levels")
	profile.record_win(CampaignCatalog.IDS[2], 2, 3)
	_check(not profile.rewards.has("star_collector"), "Nine stars do not grant constellation")
	profile.record_win(CampaignCatalog.IDS[3], 2, 3)
	_check(profile.rewards.has("star_collector") and profile.rewards.has("chapter_1"), "Twelve stars and second chapter unlock at their boundaries")
	for index in range(4, CampaignCatalog.IDS.size()):
		profile.record_win(CampaignCatalog.IDS[index], 2, 2)
	_check(profile.rewards.has("chapter_2") and profile.rewards.has("chapter_3") and profile.rewards.has("campaign_complete"), "Final victory completes all chapter badges and campaign badge")
	for chapter in range(4, CampaignCatalog.CHAPTER_TITLES.size()):
		_check(profile.rewards.has("chapter_%d" % chapter), "New chapter %d grants its permanent badge" % chapter)
	_check(not profile.rewards.has("perfect_campaign") and not profile.rewards.has("yard_author"), "Campaign completion does not invent perfect results or editor victories")
	for index in range(4, CampaignCatalog.IDS.size()):
		profile.record_win(CampaignCatalog.IDS[index], 2, 3)
	_check(profile.rewards.has("perfect_campaign"), "Every campaign level needs three stars for the master badge")
	profile.record_editor_win()
	profile.record_editor_win()
	_check(profile.rewards.size() == RewardCatalog.IDS.size(), "Editor reward is persistent and idempotent")
	var zero := PlayerProfile.new("")
	zero.record_win(CampaignCatalog.IDS[0], 0, 3)
	_check(not zero.rewards.has("one_shot"), "Zero shots does not count as a one-shot victory")


func _test_storage() -> void:
	_write({"version": 1, "cat": "frost", "locale": "de", "results": {"first_throw": {"stars": 3, "shots": 1}}})
	var profile := PlayerProfile.new(_path)
	profile.load_data()
	_check(profile.rewards.size() == 3 and profile.locale == "de" and profile.cat_id == &"frost", "Legacy progress earns retrospective badges without resetting preferences")
	_check(profile.record_editor_win() == OK, "Editor badge saves together with migrated progress")
	var restored := PlayerProfile.new(_path)
	restored.load_data()
	_check(restored.rewards == profile.rewards and restored.stars_for("first_throw") == 3, "All badges and best results survive reload")
	_write({"version": 1, "rewards": ["yard_author", "yard_author", "unknown", 5, {}]})
	restored.load_data()
	_check(restored.rewards == PackedStringArray(["yard_author"]), "Unknown/malformed IDs ignored and duplicates removed")
	_write({"version": 1, "rewards": "yard_author"})
	restored.load_data()
	_check(restored.rewards.is_empty(), "Malformed reward collection uses an empty default")
	_write({"version": 1, "rewards": ["campaign_complete", "perfect_campaign"], "results": {"first_throw": {"stars": 3, "shots": 2}}})
	restored.load_data()
	_check(restored.rewards.has("campaign_complete") and restored.rewards.has("perfect_campaign"), "Earned legacy completion badges stay permanent after campaign expansion")
	var failed := PlayerProfile.new("user://missing_rewards_directory_%d/profile.json" % Time.get_ticks_usec())
	_check(failed.record_editor_win() != OK and failed.rewards.has("yard_author"), "Save failure reported while session reward remains available")


func _write(data: Dictionary) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _test_app() -> void:
	var app := APP_SCENE.instantiate() as GameApp
	app.animate_screen_changes = false
	app.profile_path = ""
	app.editor_recovery_path = ""
	root.add_child(app)
	await _settle()
	app.start_game(&"classic", &"scout")
	await _settle()
	app.game._complete_round(false)
	_check(app.profile.rewards.is_empty(), "Defeat cannot earn a badge")
	app.game._complete_round(true)
	_check(app.profile.rewards.is_empty(), "Sandbox win cannot earn campaign/editor badges")
	app.show_campaign()
	await _settle()
	app.start_campaign_level(0)
	await _settle()
	app.game.shots_left = app.game.level.shots - 1
	app.game._complete_round(true)
	_check(app.profile.rewards.size() == 3 and app.game.hud._reward_notice.visible, "Campaign result shows newly earned badges")
	if _capture:
		await _shot("victory")
	app._restart_round()
	await _settle()
	app.game.shots_left = app.game.level.shots - 1
	app.game._complete_round(true)
	_check(not app.game.hud._reward_notice.visible, "Replay shows no duplicate announcement")
	app.show_editor()
	await _settle()
	app.start_editor_game(app.editor.draft)
	await _settle()
	app.game.shots_left = app.game.level.shots - 1
	app.game._complete_round(true)
	_check(app.profile.rewards.has("yard_author") and app.game.hud._reward_notice.visible, "Editor completion earns its badge through application")
	app.queue_free()
	await _settle()


func _test_collection() -> void:
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(960, 720)]:
		root.size = dimensions
		for state in 3:
			var profile := PlayerProfile.new("")
			if state > 0:
				profile.record_win(CampaignCatalog.IDS[0], 1, 3)
			if state == 2:
				for level_id in CampaignCatalog.IDS:
					profile.record_win(level_id, 1, 3)
				profile.record_editor_win()
			var menu := CampaignMenu.new()
			menu.profile = profile
			root.add_child(menu)
			await _settle()
			_check(root.get_visible_rect().encloses(menu.rewards_button.get_global_rect()), "Rewards entry fits main menu")
			_check(root.get_visible_rect().encloses(menu._home_panel.get_global_rect()), "Whole home panel fits viewport after adding rewards")
			_click(menu.rewards_button, state != 0)
			await _settle()
			_check(menu.page == &"rewards" and menu.reward_collection.cards.size() == RewardCatalog.IDS.size(), "Mouse/touch opens every reward card")
			for card in menu.reward_collection.cards:
				menu.reward_collection.scroll.ensure_control_visible(card)
				await _settle()
				_check(root.get_visible_rect().encloses(card.get_global_rect()), "Every reward card is reachable within viewport")
			menu.reward_collection.scroll.scroll_vertical = 0
			if _capture:
				await _shot("%dx%d-state%d" % [dimensions.x, dimensions.y, state])
			_click(menu.back_button, true)
			await _settle()
			_check(menu.page == &"home" and menu.continue_button.has_focus(), "Back restores home and keyboard focus")
			if _capture:
				await _shot("home-%dx%d-state%d" % [dimensions.x, dimensions.y, state])
			menu.queue_free()
			await _settle()
	if _capture:
		for locale in GameLocalization.SUPPORTED_LOCALES:
			GameLocalization.apply_locale(locale)
			var menu := CampaignMenu.new()
			root.add_child(menu)
			await _settle()
			menu.show_page(&"rewards")
			await _settle()
			await _shot(locale)
			menu.queue_free()
			await _settle()


func _click(button: BaseButton, touch: bool) -> void:
	for pressed: bool in [true, false]:
		if touch:
			var event := InputEventScreenTouch.new()
			event.position = button.get_global_rect().get_center()
			event.pressed = pressed
			root.push_input(event, true)
		else:
			var event := InputEventMouseButton.new()
			event.position = button.get_global_rect().get_center()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			root.push_input(event, true)


func _settle() -> void:
	for frame in 5:
		await process_frame
	await create_timer(0.05).timeout


func _shot(label: String) -> void:
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.artifacts/rewards-%s.png" % label) == OK, "Reward screenshot saved")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
