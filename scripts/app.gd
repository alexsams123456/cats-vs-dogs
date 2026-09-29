class_name GameApp
extends Node
## Переходы экранов, локальные настройки и прогресс кампании.

const MENU_SCENE := preload("res://scenes/ui/roster_menu.tscn")
const GAME_SCENE := preload("res://scenes/main.tscn")
const EDITOR_SCENE := preload("res://scenes/editor/level_editor.tscn")

var selected_cat_id: StringName = &"classic"
var selected_dog_id: StringName = &"scout"
var menu: RosterMenu
var game: GameRound
var editor: LevelEditor
var campaign: CampaignMenu
var profile_path: String = PlayerProfile.DEFAULT_PATH
var editor_recovery_path: String = "user://editor_draft.json"
var profile: PlayerProfile
var campaign_index: int = -1
var _world_audio: WorldAudio
var _preview_level: LevelDefinition
var _transition_pending: bool = false
var _previous_quit_on_go_back: bool = true


func _ready() -> void:
	_previous_quit_on_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	get_tree().root.go_back_requested.connect(_go_back)
	profile = PlayerProfile.new(profile_path)
	profile.load_data()
	GameLocalization.apply_locale(profile.locale)
	get_window().title = tr("Кошки против собак")
	selected_cat_id = profile.cat_id
	selected_dog_id = profile.dog_id
	if not profile_path.is_empty():
		SoundToggle.set_muted(profile.sound_muted)
		SoundControls.set_volume(&"Music", profile.music_volume)
		SoundControls.set_volume(&"SFX", profile.effects_volume)
	_open_campaign()


func _exit_tree() -> void:
	get_tree().root.go_back_requested.disconnect(_go_back)
	get_tree().quit_on_go_back = _previous_quit_on_go_back


func _go_back() -> void:
	if _transition_pending:
		return
	# Закрытие дочернего окна не должно заодно снимать паузу или покидать редактор.
	for node in find_children("*", "Window", true, false):
		var dialog := node as Window
		if dialog.visible and (dialog is AcceptDialog or dialog is PopupMenu):
			dialog.hide()
			return
	if is_instance_valid(game):
		if game.state in [GameRound.RoundState.READY, GameRound.RoundState.FLYING]:
			game.toggle_pause()
		else:
			game.return_to_menu()
	elif is_instance_valid(campaign):
		if campaign.page != &"home":
			campaign.show_page(&"home")
		elif _previous_quit_on_go_back:
			get_tree().quit()
	else:
		show_menu()


func start_game(cat_id: StringName, dog_id: StringName) -> void:
	if _transition_pending:
		return
	selected_cat_id = CharacterCatalog.find_cat(cat_id).id
	selected_dog_id = CharacterCatalog.find_dog(dog_id).id
	_save_profile()
	campaign_index = -1
	_preview_level = null
	_transition_pending = true
	_open_game.call_deferred()


func start_editor_game(level: LevelDefinition) -> void:
	if _transition_pending or level == null or not level.is_valid():
		return
	_preview_level = level.duplicate(true) as LevelDefinition
	campaign_index = -1
	_transition_pending = true
	_open_game.call_deferred()


func show_editor() -> void:
	if _transition_pending:
		return
	if is_instance_valid(menu):
		selected_cat_id = menu.selected_cat_id
		selected_dog_id = menu.selected_dog_id
	_save_profile()
	campaign_index = -1
	_transition_pending = true
	_open_editor.call_deferred()


func show_menu() -> void:
	show_campaign()


func show_sandbox() -> void:
	if _transition_pending:
		return
	_transition_pending = true
	_open_sandbox.call_deferred()


func _clear_screen() -> void:
	get_tree().paused = false
	if is_instance_valid(game):
		remove_child(game)
		game.queue_free()
		game = null
	if is_instance_valid(menu):
		remove_child(menu)
		menu.queue_free()
		menu = null
	if is_instance_valid(campaign):
		remove_child(campaign)
		campaign.queue_free()
		campaign = null
	if is_instance_valid(editor):
		editor.hide()
		editor.process_mode = Node.PROCESS_MODE_DISABLED


func _open_sandbox() -> void:
	_clear_screen()
	_preview_level = null
	campaign_index = -1
	menu = MENU_SCENE.instantiate() as RosterMenu
	menu.set_selection(selected_cat_id, selected_dog_id)
	menu.play_requested.connect(start_game)
	menu.editor_requested.connect(show_editor)
	menu.campaign_requested.connect(show_campaign)
	menu.selection_changed.connect(_on_selection_changed)
	add_child(menu)
	_connect_sound_setting(menu)
	_transition_pending = false


func _open_editor() -> void:
	_clear_screen()
	_preview_level = null
	if not is_instance_valid(editor):
		editor = EDITOR_SCENE.instantiate() as LevelEditor
		editor.recovery_path = editor_recovery_path
		editor.play_requested.connect(start_editor_game)
		editor.menu_requested.connect(show_menu)
		add_child(editor)
	editor.process_mode = Node.PROCESS_MODE_INHERIT
	editor.show()
	_transition_pending = false


func _open_game() -> void:
	_clear_screen()
	game = GAME_SCENE.instantiate() as GameRound
	game.background_music = $BackgroundMusic
	if _preview_level != null:
		game.level = _preview_level.duplicate(true) as LevelDefinition
		game.editor_preview = true
	elif campaign_index >= 0:
		game.level = CampaignCatalog.LEVELS[campaign_index].duplicate(true) as LevelDefinition
		game.campaign_mode = true
		game.has_next_level = campaign_index + 1 < CampaignCatalog.LEVELS.size()
	game.cat_definition = CharacterCatalog.find_cat(selected_cat_id)
	game.dog_definition = CharacterCatalog.find_dog(selected_dog_id)
	game.restart_requested.connect(_restart_round)
	if game.editor_preview:
		game.menu_requested.connect(show_editor)
	elif game.campaign_mode:
		game.menu_requested.connect(show_campaign)
	else:
		game.menu_requested.connect(show_sandbox)
	game.round_completed.connect(_on_round_completed)
	game.next_requested.connect(_next_campaign_level)
	add_child(game)
	_world_audio = WorldAudio.new()
	game.add_child(_world_audio)
	_connect_sound_setting(game)
	_transition_pending = false


func _restart_round() -> void:
	if _transition_pending:
		return
	_transition_pending = true
	_open_game.call_deferred()


func show_campaign() -> void:
	if _transition_pending:
		return
	_save_profile()
	_transition_pending = true
	_open_campaign.call_deferred()


func start_campaign_level(index: int) -> void:
	if _transition_pending or not CampaignCatalog.is_unlocked(index, profile):
		return
	campaign_index = index
	_preview_level = null
	_transition_pending = true
	_open_game.call_deferred()


func _open_campaign() -> void:
	_clear_screen()
	_preview_level = null
	campaign_index = -1
	campaign = CampaignMenu.new()
	campaign.handles_native_back = false
	campaign.profile = profile
	campaign.level_requested.connect(start_campaign_level)
	campaign.sandbox_requested.connect(show_sandbox)
	campaign.editor_requested.connect(show_editor)
	campaign.language_requested.connect(_on_language_requested)
	add_child(campaign)
	_connect_sound_setting(campaign)
	_transition_pending = false


func _on_language_requested(locale: String) -> void:
	if _transition_pending:
		return
	_transition_pending = true
	profile.locale = GameLocalization.apply_locale(locale)
	get_window().title = tr("Кошки против собак")
	_save_profile()
	_refresh_language.call_deferred(campaign.page)


func _refresh_language(page: StringName) -> void:
	_open_campaign()
	campaign.show_page(page)
	campaign.language_picker.grab_focus()


func _next_campaign_level() -> void:
	if campaign_index < 0 or not is_instance_valid(game) or game.state != GameRound.RoundState.WON:
		return
	start_campaign_level(campaign_index + 1)


func _on_round_completed(won: bool, shots_used: int, stars: int) -> void:
	if not won:
		return
	if is_instance_valid(_world_audio):
		_world_audio.play_victory()
	if campaign_index >= 0:
		profile.sound_muted = _sound_muted()
		if profile.record_win(CampaignCatalog.IDS[campaign_index], shots_used, stars) != OK:
			game.hud.set_save_warning()


func _on_selection_changed(cat_id: StringName, dog_id: StringName) -> void:
	selected_cat_id = cat_id
	selected_dog_id = dog_id
	_save_profile()


func _connect_sound_setting(screen: Node) -> void:
	for node in screen.find_children("*", "", true, false):
		if node is SoundControls:
			node.settings_changed.connect(_save_profile)
		elif node is SoundToggle and not node.get_parent() is SoundControls:
			node.pressed.connect(_save_profile)


func _sound_muted() -> bool:
	return SoundToggle.is_muted()


func _save_profile() -> void:
	if profile == null:
		return
	profile.cat_id = selected_cat_id
	profile.dog_id = selected_dog_id
	profile.sound_muted = _sound_muted()
	profile.music_volume = SoundControls.volume_for(&"Music")
	profile.effects_volume = SoundControls.volume_for(&"SFX")
	if profile.save_data() != OK:
		push_warning("Не удалось сохранить настройки игры: %s" % error_string(profile.last_error))
