extends SceneTree
## Языки, локальные шрифты, сохранение настройки и смена экранов без потери черновика.

const APP_SCENE := preload("res://scenes/app.tscn")
const INTERFACE_FONT := preload("res://assets/fonts/interface_font.tres")

var _checks: int = 0
var _failures: int = 0
var _save_path: String
var _recovery_path: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_locale := TranslationServer.get_locale()
	var stamp := Time.get_ticks_usec()
	_save_path = "user://localization_test_%d.json" % stamp
	_recovery_path = "user://localization_draft_test_%d.json" % stamp
	_test_locales()
	_test_fonts()
	_test_profile()
	_test_catalogs()
	await _test_language_selection()
	TranslationServer.set_locale(original_locale)
	for path: String in [_save_path, _recovery_path]:
		for suffix: String in ["", ".tmp", ".bak"]:
			if FileAccess.file_exists(path + suffix):
				DirAccess.remove_absolute(path + suffix)
	print("Localization checks: %d passed, %d failed" % [_checks - _failures, _failures])
	quit(1 if _failures else 0)


func _test_locales() -> void:
	_check(GameLocalization.SUPPORTED_LOCALES.size() == 13, "Thirteen supported languages are exposed")
	_check(GameLocalization.LANGUAGE_NAMES.size() == GameLocalization.SUPPORTED_LOCALES.size(), "Every language has a native name")
	for locale: String in GameLocalization.SUPPORTED_LOCALES:
		_check(GameLocalization.normalize_locale(locale) == locale, "Supported locale stays canonical: " + locale)
		_check(GameLocalization.apply_locale(locale) == locale and GameLocalization.normalize_locale(TranslationServer.get_locale()) == locale, "Locale applies to TranslationServer: " + locale)
	_check(GameLocalization.normalize_locale("  EN-us ") == "en", "Locale normalization handles case, region and whitespace")
	_check(GameLocalization.normalize_locale("pt-BR") == "pt", "Portuguese regions use the Portuguese catalog")
	_check(GameLocalization.normalize_locale("zh-Hans-CN") == "zh_CN", "Chinese script tags use the simplified Chinese catalog")
	_check(GameLocalization.normalize_locale("unsupported") == "en", "Unsupported language has an English fallback")
	_check(GameLocalization.normalize_locale("") == "en", "Empty language has an English fallback")


func _test_fonts() -> void:
	var original_font := load("res://assets/fonts/Nunito.ttf") as Font
	_check(INTERFACE_FONT.get_height(20) <= original_font.get_height(20) * 1.15, "Fallback metrics retain compact interface rows")
	var body_width := INTERFACE_FONT.get_string_size("LEVEL EDITOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var thin_width := original_font.get_string_size("LEVEL EDITOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_check(body_width > thin_width, "Interface applies the readable font weight instead of Nunito ExtraLight")
	for native_name: String in GameLocalization.LANGUAGE_NAMES:
		_check(_font_covers(native_name), "Bundled fonts cover native language name: " + native_name)
	var bold_font := FontVariation.new()
	bold_font.base_font = INTERFACE_FONT
	bold_font.variation_opentype = {2003265652: 900.0}
	_check(bold_font.has_char("猫".unicode_at(0)) and bold_font.has_char("ह".unicode_at(0)), "Menu bold font retains multilingual fallbacks")
	_check(_font_covers("★☆≤✓×←→"), "Bundled fonts cover interface symbols")


func _test_profile() -> void:
	var profile := PlayerProfile.new(_save_path)
	profile.load_data()
	_check(profile.locale == "ru", "Missing profile retains the existing Russian default")
	_write_profile({"version": 1, "cat": "frost", "muted": true})
	profile.load_data()
	_check(profile.locale == "ru" and profile.cat_id == &"frost" and profile.sound_muted, "Old profile without language keeps settings and Russian")
	_write_profile({"version": 1, "locale": 17})
	profile.load_data()
	_check(profile.locale == "ru", "Malformed language value uses a safe default")
	_write_profile({"version": 1, "locale": "not-a-language"})
	profile.load_data()
	_check(profile.locale == "en", "Unknown saved language uses English")
	_write_profile({"version": 1, "locale": "zh-Hans-CN"})
	profile.load_data()
	_check(profile.locale == "zh_CN", "Saved regional locale is normalized")
	profile.locale = "ja"
	profile.cat_id = &"magnet"
	profile.dog_id = &"armored"
	profile.sound_muted = true
	_check(profile.record_win(CampaignCatalog.IDS[0], 2, 3) == OK, "Language and progress save together")
	var restored := PlayerProfile.new(_save_path)
	restored.load_data()
	_check(restored.locale == "ja" and restored.cat_id == &"magnet" and restored.dog_id == &"armored" and restored.sound_muted, "Language and other preferences survive a new profile")
	_check(restored.stars_for(CampaignCatalog.IDS[0]) == 3, "Language persistence retains campaign records")
	restored.locale = "ru"
	restored.save_data()


func _test_catalogs() -> void:
	var messages: Dictionary = {}
	var seen_keys: Dictionary = {}
	var placeholder_pattern := RegEx.new()
	placeholder_pattern.compile("%(?:[-+0 #]*[0-9]*(?:\\.[0-9]+)?)[sdif]")
	for locale: String in GameLocalization.SUPPORTED_LOCALES:
		messages[locale] = {}
	for path: String in ["res://translations/core.csv", "res://translations/gameplay.csv", "res://translations/editor.csv"]:
		var file := FileAccess.open(path, FileAccess.READ)
		_check(file != null, "Translation source opens: " + path)
		if file == null:
			continue
		var headers := file.get_csv_line()
		_check(headers.size() == GameLocalization.SUPPORTED_LOCALES.size() + 1, "Catalog exposes every supported language: " + path)
		while file.get_position() < file.get_length():
			var row := file.get_csv_line()
			if row.size() == 1 and row[0].is_empty():
				continue
			_check(row.size() == headers.size(), "Catalog row has all language columns: " + row[0])
			if row.size() != headers.size():
				continue
			var key := row[0]
			_check(not seen_keys.has(key), "Translation key is defined once: " + key)
			seen_keys[key] = true
			for index in range(1, headers.size()):
				var locale := headers[index]
				if not messages.has(locale):
					_check(false, "Unsupported catalog locale: " + locale)
					continue
				var translated := row[index]
				messages[locale][key] = translated
				_check(not translated.strip_edges().is_empty(), "%s has a translation for %s" % [locale, key])
				_check(_font_covers(translated), "%s translation uses bundled glyphs: %s" % [locale, key])
				_check(_placeholders(key, placeholder_pattern) == _placeholders(translated, placeholder_pattern), "%s preserves formatting arguments for %s" % [locale, key])
	for locale: String in GameLocalization.SUPPORTED_LOCALES:
		GameLocalization.apply_locale(locale)
		var localized: Dictionary = messages[locale]
		_check(not localized.is_empty(), "Language has translated messages: " + locale)
		for key: String in localized:
			_check(String(TranslationServer.translate(key)) == localized[key], "%s translation is registered: %s" % [locale, key])


func _test_language_selection() -> void:
	var app := APP_SCENE.instantiate() as GameApp
	app.profile_path = _save_path
	app.editor_recovery_path = _recovery_path
	root.add_child(app)
	current_scene = app
	await _settle()
	_check(app.campaign.language_picker.item_count == 13, "Main menu offers all languages")
	for index in GameLocalization.LANGUAGE_NAMES.size():
		_check(app.campaign.language_picker.get_item_text(index) == GameLocalization.LANGUAGE_NAMES[index], "Language choices retain their native names")
	app.campaign.show_page(&"campaign")
	await _select_locale(app, "en")
	_check(app.campaign.page == &"campaign", "Switching language preserves the open campaign page")
	_check(app.campaign.continue_button.tr(app.campaign.continue_button.text).contains("Continue"), "Dynamic Continue label updates immediately")
	var restored := PlayerProfile.new(_save_path)
	restored.load_data()
	_check(restored.locale == "en" and restored.stars_for(CampaignCatalog.IDS[0]) == 3, "Language selection immediately saves without losing progress")
	app.show_sandbox()
	await _settle()
	_check(app.menu != null and app.selected_cat_id == &"magnet", "Sandbox opens with translated UI and existing selection")
	app.show_editor()
	await _settle()
	_check(app.editor.draft.title == TranslationServer.translate(LevelEditor.DEFAULT_LEVEL.title), "First editor draft uses the translated built-in template title")
	var saved_editor := app.editor
	var custom_title := "Мой двор / 私の庭 / ساحتي"
	app.editor.title_edit.text = custom_title
	app.editor.title_edit.text_changed.emit(custom_title)
	app.editor._finish_edit()
	var original_positions := app.editor.draft.dog_positions.duplicate()
	var history_size := app.editor._undo_stack.size()
	app.show_campaign()
	await _settle()
	await _select_locale(app, "ar")
	_check(app.campaign.is_layout_rtl(), "Arabic activates right-to-left menu layout")
	app.show_editor()
	await _settle()
	_check(app.editor == saved_editor, "Changing language preserves the editor instance")
	_check(app.editor.draft.title == custom_title and app.editor.title_edit.text == custom_title, "User-written level title is not translated")
	_check(app.editor.draft.dog_positions == original_positions and app.editor._undo_stack.size() == history_size, "Changing language preserves editor content and undo history")
	_check(app.editor.material_picker.get_item_text(0) == TranslationServer.translate(BlockMaterials.LABELS[0]), "Hidden editor refreshes material names when reopened")
	app.show_campaign()
	await _settle()
	await _select_locale(app, "zh_CN")
	app.campaign.continue_button.pressed.emit()
	await _settle()
	_check(app.game != null and app.game.campaign_mode, "Campaign starts after changing to Chinese")
	app.queue_free()
	await _settle()
	app = APP_SCENE.instantiate() as GameApp
	app.profile_path = _save_path
	app.editor_recovery_path = _recovery_path
	root.add_child(app)
	current_scene = app
	await _settle()
	_check(GameLocalization.normalize_locale(TranslationServer.get_locale()) == "zh_CN", "A new app instance restores the chosen language")
	_check(app.campaign.language_picker.get_selected_metadata() == "zh_CN", "Language picker matches the restored profile")
	var music_playback_ref: WeakRef = weakref((app.get_node("BackgroundMusic") as AudioStreamPlayer).get_stream_playback())
	app.queue_free()
	await _settle()
	# Микшер освобождает поток отдельно от быстрых headless-кадров дерева.
	var audio_deadline := Time.get_ticks_msec() + 1000
	while music_playback_ref.get_ref() != null and Time.get_ticks_msec() < audio_deadline:
		await create_timer(0.025, true, false, true).timeout
	_check(music_playback_ref.get_ref() == null, "Closing the localized app releases its audio playback")


func _select_locale(app: GameApp, locale: String) -> void:
	var index := GameLocalization.SUPPORTED_LOCALES.find(locale)
	app.campaign.language_picker.select(index)
	app.campaign.language_picker.item_selected.emit(index)
	await _settle()
	_check(GameLocalization.normalize_locale(TranslationServer.get_locale()) == locale and app.profile.locale == locale, "Selecting a language updates the app: " + locale)


func _font_covers(value: String) -> bool:
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint > 32 and codepoint not in [0x200C, 0x200D, 0x200E, 0x200F, 0x2066, 0x2067, 0x2068, 0x2069] and not INTERFACE_FONT.has_char(codepoint):
			return false
	return true


func _placeholders(value: String, pattern: RegEx) -> PackedStringArray:
	var placeholders := PackedStringArray()
	for result: RegExMatch in pattern.search_all(value.replace("%%", "")):
		placeholders.append(result.get_string())
	return placeholders


func _write_profile(data: Dictionary) -> void:
	var file := FileAccess.open(_save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _settle() -> void:
	for frame in 5:
		await process_frame
	await create_timer(0.04).timeout


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
