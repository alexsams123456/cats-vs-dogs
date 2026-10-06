class_name CampaignMenu
extends Control
## Живой стартовый двор, карта кампании и личные рекорды из профиля.

signal level_requested(index: int)
signal sandbox_requested
signal editor_requested
signal language_requested(locale: String)

const INK := Color("285448")
const CREAM := Color("fff9e9")
const TEAL := Color("347b62")
const GOLD := Color("f7bc55")
const MUTED := Color("75846a")
const MENU_FONT := preload("res://assets/fonts/interface_font.tres")

var profile: PlayerProfile
var handles_native_back: bool = true
var page: StringName = &"home"
var level_buttons: Array[Button] = []
var chapter_panels: Array[PanelContainer] = []
var continue_button: Button
var campaign_button: Button
var rating_button: Button
var rewards_button: Button
var sandbox_button: Button
var editor_button: Button
var back_button: Button
var language_picker: OptionButton
var rating_summary: Label
var rating_rows: Array[Label] = []
var continue_index: int = 0
var _completed: bool = false
var _backdrop: MenuBackdrop
var _margin: MarginContainer
var _home: Control
var _title: VBoxContainer
var _title_cats: Label
var _title_dogs: Label
var _home_panel: PanelContainer
var _home_note: Label
var _campaign_page: VBoxContainer
var _rating_page: VBoxContainer
var reward_collection: RewardCollection
var _grid: GridContainer
var _chapter_grids: Array[GridContainer] = []
var _chapter_contents: Array[GridContainer] = []
var _chapter_headings: Array[HBoxContainer] = []
var _page_title: Label
var _transition: Tween
var _bold_font: FontVariation
var _button_tweens: Dictionary = {}
var _previous_quit_on_go_back: bool = true
var _menu_windows: Array[Window] = []
var _startup_progress: float = 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if handles_native_back:
		_previous_quit_on_go_back = get_tree().quit_on_go_back
		get_tree().quit_on_go_back = false
		get_tree().root.go_back_requested.connect(_go_back)
	if profile == null:
		profile = PlayerProfile.new("")
	_bold_font = FontVariation.new()
	_bold_font.base_font = MENU_FONT
	_bold_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 900.0}
	var regular_font := FontVariation.new()
	regular_font.base_font = MENU_FONT
	regular_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 600.0}
	var ui_theme := Theme.new()
	ui_theme.default_font = regular_font
	ui_theme.default_font_size = 20
	ui_theme.set_color("font_color", "Label", INK)
	theme = ui_theme
	_find_continue()
	RewardCatalog.synchronize(profile)
	_backdrop = MenuBackdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	_margin.add_child(column)
	_build_header(column)
	var pages := Control.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pages)
	_build_home(pages)
	_build_campaign(pages)
	_build_rating(pages)
	reward_collection = RewardCollection.new()
	reward_collection.profile = profile
	pages.add_child(reward_collection)
	for node in find_children("*", "Window", true, false):
		var window := node as Window
		_menu_windows.append(window)
		window.about_to_popup.connect(_backdrop.reset_interactions)
	resized.connect(_update_layout)
	_home.resized.connect(_layout_home)
	_home_panel.minimum_size_changed.connect(_layout_home)
	_update_layout()
	show_page(&"home")


func _find_continue() -> void:
	_completed = true
	for index in CampaignCatalog.LEVELS.size():
		if profile.stars_for(CampaignCatalog.IDS[index]) == 0 and CampaignCatalog.is_unlocked(index, profile):
			continue_index = index
			_completed = false
			break


func _build_header(column: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	back_button = _button("‹  В меню", true)
	back_button.pressed.connect(func() -> void: show_page(&"home"))
	header.add_child(back_button)
	var paw := MenuIcon.new()
	paw.kind = &"paw"
	paw.custom_minimum_size = Vector2(38, 38)
	paw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(paw)
	_page_title = _label("БОЛЬШОЕ ПРИКЛЮЧЕНИЕ В МАЛЕНЬКОМ ДВОРЕ", 16, true)
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_page_title)
	var stars := _label("★  %d / %d" % [CampaignCatalog.total_stars(profile), CampaignCatalog.LEVELS.size() * 3], 22, true)
	stars.autowrap_mode = TextServer.AUTOWRAP_OFF
	stars.text_direction = Control.TEXT_DIRECTION_LTR
	stars.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stars.tooltip_text = "Звёзды кампании"
	header.add_child(stars)
	language_picker = TouchOptionButton.new()
	language_picker.name = "LanguagePicker"
	language_picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language_picker.custom_minimum_size = Vector2(180, 46)
	language_picker.fit_to_longest_item = false
	language_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	language_picker.add_theme_font_size_override("font_size", 18)
	language_picker.tooltip_text = tr("Язык / Language")
	language_picker.add_theme_stylebox_override("normal", _style(Color("e3ecdb"), 10, 14))
	language_picker.add_theme_stylebox_override("hover", _style(Color("d3e3ca"), 10, 14))
	language_picker.add_theme_stylebox_override("pressed", _style(Color("d3e3ca"), 10, 14))
	language_picker.add_theme_stylebox_override("hover_pressed", _style(Color("d3e3ca"), 10, 14))
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		language_picker.add_theme_stylebox_override(state + "_mirrored", language_picker.get_theme_stylebox(state))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		language_picker.add_theme_color_override(state, INK)
	var popup := language_picker.get_popup()
	popup.add_theme_stylebox_override("panel", _style(CREAM, 10, 14))
	popup.add_theme_stylebox_override("hover", _style(Color("d3e3ca"), 4, 8))
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", INK)
	for index in GameLocalization.SUPPORTED_LOCALES.size():
		language_picker.add_item(GameLocalization.LANGUAGE_NAMES[index])
		language_picker.set_item_metadata(index, GameLocalization.SUPPORTED_LOCALES[index])
	language_picker.select(GameLocalization.SUPPORTED_LOCALES.find(GameLocalization.normalize_locale(TranslationServer.get_locale())))
	language_picker.item_selected.connect(func(index: int) -> void:
		language_requested.emit(GameLocalization.SUPPORTED_LOCALES[index])
	)
	header.add_child(language_picker)
	header.add_child(SoundControls.new())


func _build_home(parent: Control) -> void:
	_home = Control.new()
	_home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(_home)
	_title = VBoxContainer.new()
	_title.add_theme_constant_override("separation", -8)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(_title)
	var eyebrow := _label("РОГАТКА. КОТЫ. НЕМНОГО ХАОСА.", 18, true)
	eyebrow.add_theme_color_override("font_color", Color("7b8650"))
	_title.add_child(eyebrow)
	_title_cats = _label("КОШКИ", 88, true)
	_title_cats.add_theme_color_override("font_color", INK)
	_title.add_child(_title_cats)
	var versus := _label("     П Р О Т И В", 22, true)
	versus.add_theme_color_override("font_color", Color("9a6644"))
	_title.add_child(versus)
	_title_dogs = _label("СОБАК", 88, true)
	_title_dogs.add_theme_color_override("font_color", Color("d07a3e"))
	_title.add_child(_title_dogs)
	for label: Label in [_title_cats, _title_dogs]:
		label.add_theme_color_override("font_shadow_color", Color("fff9e9"))
		label.add_theme_constant_override("shadow_offset_y", 4)
		label.add_theme_constant_override("shadow_offset_x", 0)
	var subtitle := _label("Маленькие лапы. Большие разборки.", 21)
	_title.add_child(subtitle)
	_home_panel = PanelContainer.new()
	var panel_style := _style(CREAM, 26, 28)
	panel_style.border_color = Color("ffffffb0")
	panel_style.set_border_width_all(2)
	panel_style.shadow_color = Color("264d4020")
	panel_style.shadow_size = 16
	panel_style.shadow_offset = Vector2(0, 8)
	_home_panel.add_theme_stylebox_override("panel", panel_style)
	_home.add_child(_home_panel)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	_home_panel.add_child(menu)
	menu.add_child(_label("ДВОР ЗОВЁТ!", 16, true))
	menu.add_child(_label("Вперёд, команда", 31, true))
	var next := tr("Все %d уровней пройдены — собери %d звёзд!") % [CampaignCatalog.LEVELS.size(), CampaignCatalog.LEVELS.size() * 3] if _completed else tr("Уровень %d · %s") % [continue_index + 1, tr(CampaignCatalog.LEVELS[continue_index].title)]
	var next_label := _label(next, 16)
	next_label.add_theme_color_override("font_color", MUTED)
	menu.add_child(next_label)
	continue_button = _button(_continue_text())
	continue_button.custom_minimum_size.y = 66
	continue_button.add_theme_font_size_override("font_size", 25)
	continue_button.pressed.connect(func() -> void: level_requested.emit(continue_index))
	menu.add_child(continue_button)
	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", _line_style())
	divider.custom_minimum_size.y = 8
	menu.add_child(divider)
	campaign_button = _navigation_button("Кампания", tr("%d глав · %d уровней") % [CampaignCatalog.CHAPTER_TITLES.size(), CampaignCatalog.LEVELS.size()], &"map", Color("e6edd6"))
	campaign_button.pressed.connect(func() -> void: show_page(&"campaign"))
	menu.add_child(campaign_button)
	rating_button = _navigation_button("Рейтинг", "Твои звёзды и лучшие броски", &"trophy", Color("f9e8b6"))
	rating_button.pressed.connect(func() -> void: show_page(&"rating"))
	menu.add_child(rating_button)
	rewards_button = _button(tr("Награды: %d / %d").replace("%d / %d", "\u2066%d / %d\u2069") % [profile.rewards.size(), RewardCatalog.IDS.size()], true)
	rewards_button.pressed.connect(func() -> void: show_page(&"rewards"))
	menu.add_child(rewards_button)
	editor_button = _navigation_button("Редактор", "Построй свой идеальный двор", &"tools", Color("e3e9e8"))
	editor_button.pressed.connect(editor_requested.emit)
	menu.add_child(editor_button)
	sandbox_button = _button("Песочница  ·  Выбрать героев  ›", true)
	sandbox_button.add_theme_font_size_override("font_size", 17)
	sandbox_button.pressed.connect(sandbox_requested.emit)
	menu.add_child(sandbox_button)
	_home_note = _label("Потяни рогатку. Отпусти кота. Спаси этот двор от скуки.", 16, true)
	_home_note.add_theme_color_override("font_color", INK)
	_home_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(_home_note)


func _build_campaign(parent: Control) -> void:
	_campaign_page = VBoxContainer.new()
	_campaign_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_campaign_page.add_theme_constant_override("separation", 14)
	parent.add_child(_campaign_page)
	var heading := HBoxContainer.new()
	_campaign_page.add_child(heading)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(titles)
	titles.add_child(_label("От тёплого двора до ледяных крепостей", 28, true))
	titles.add_child(_label("Верёвки, грузы и обвалы", 17))
	var play := _button(_continue_text())
	play.custom_minimum_size.x = 220
	play.pressed.connect(func() -> void: level_requested.emit(continue_index))
	heading.add_child(play)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_campaign_page.add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(_grid)
	for chapter in CampaignCatalog.CHAPTER_TITLES.size():
		_add_chapter(chapter)


func _add_chapter(chapter: int) -> void:
	var panel := PanelContainer.new()
	panel.name = "Chapter%d" % (chapter + 1)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(CampaignCatalog.CHAPTER_TINTS[chapter], 10, 22))
	_grid.add_child(panel)
	chapter_panels.append(panel)
	var column := GridContainer.new()
	column.add_theme_constant_override("h_separation", 12)
	column.add_theme_constant_override("v_separation", 8)
	panel.add_child(column)
	_chapter_contents.append(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_child(heading)
	_chapter_headings.append(heading)
	var landscape := CampaignBiomeIcon.new()
	landscape.biome = CampaignCatalog.CHAPTER_BIOMES[chapter]
	landscape.custom_minimum_size = Vector2(62, 62)
	heading.add_child(landscape)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -3)
	heading.add_child(titles)
	var title := _label("%02d  %s" % [chapter + 1, tr(CampaignCatalog.CHAPTER_TITLES[chapter])], 22, true)
	title.add_theme_color_override("font_color", CampaignCatalog.CHAPTER_COLORS[chapter])
	titles.add_child(title)
	titles.add_child(_label(CampaignCatalog.CHAPTER_DETAILS[chapter], 14))
	var difficulty := _label(tr("Сложность: %d / %d") % [chapter + 1, CampaignCatalog.CHAPTER_TITLES.size()], 13, true)
	difficulty.add_theme_color_override("font_color", CampaignCatalog.CHAPTER_COLORS[chapter])
	titles.add_child(difficulty)
	var levels := GridContainer.new()
	levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	levels.add_theme_constant_override("h_separation", 10)
	levels.add_theme_constant_override("v_separation", 8)
	column.add_child(levels)
	_chapter_grids.append(levels)
	for index in range(CampaignCatalog.CHAPTER_STARTS[chapter], CampaignCatalog.CHAPTER_STARTS[chapter + 1]):
		_add_level(index, levels)


func _add_level(index: int, parent: GridContainer) -> void:
	var level := CampaignCatalog.LEVELS[index]
	var unlocked := CampaignCatalog.is_unlocked(index, profile)
	var chapter := CampaignCatalog.chapter_for_level(index)
	var accent := CampaignCatalog.CHAPTER_COLORS[chapter]
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(280, 0)
	var card_style := _style(CREAM if unlocked else CREAM.lerp(CampaignCatalog.CHAPTER_TINTS[chapter], 0.6), 10, 15)
	card_style.shadow_color = Color("2a533016")
	card_style.shadow_size = 5
	card_style.shadow_offset = Vector2(0, 4)
	if unlocked and index == continue_index:
		card_style.set_border_width_all(2)
		card_style.border_color = accent
	card.add_theme_stylebox_override("panel", card_style)
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	card.add_child(content)
	var label := _label(tr("УРОВЕНЬ %02d%s") % [index + 1, tr("  ·  ТВОЙ СЛЕДУЮЩИЙ") if unlocked and index == continue_index else ""], 12, true)
	label.add_theme_color_override("font_color", accent if unlocked else MUTED)
	content.add_child(label)
	content.add_child(_label(level.title, 20, true))
	var stars := profile.stars_for(CampaignCatalog.IDS[index])
	var best := profile.best_shots_for(CampaignCatalog.IDS[index])
	var stars_label := _label("★".repeat(stars) + "☆".repeat(3 - stars) + (tr("  ·  Рекорд: %d выстр.") % best if best >= 0 else tr("  ·  3★ за %d выстр.") % level.par_shots), 15, true)
	stars_label.add_theme_color_override("font_color", Color("98672a"))
	content.add_child(stars_label)
	content.add_child(_label(tr("Котов: %d  ·  Собак: %d") % [level.cat_sequence.size(), level.dog_positions.size()], 14))
	var queue := HBoxContainer.new()
	queue.add_theme_constant_override("separation", 2)
	content.add_child(queue)
	for cat_index in level.cat_sequence.size():
		var portrait := CharacterPortrait.new()
		portrait.definition = CharacterCatalog.find_cat(StringName(level.cat_sequence[cat_index]))
		portrait.custom_minimum_size = Vector2(32, 32)
		portrait.tooltip_text = "%d. %s" % [cat_index + 1, tr(portrait.definition.display_name)]
		queue.add_child(portrait)
	var start := _button(("Переиграть  ›" if stars > 0 else "На уровень  ›") if unlocked else tr("Пройди уровень %d") % index, not unlocked)
	start.tooltip_text = CampaignCatalog.NOTES[index]
	start.disabled = not unlocked
	start.pressed.connect(func() -> void: level_requested.emit(index))
	content.add_child(start)
	level_buttons.append(start)


func _build_rating(parent: Control) -> void:
	_rating_page = VBoxContainer.new()
	_rating_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rating_page.add_theme_constant_override("separation", 10)
	parent.add_child(_rating_page)
	_rating_page.add_child(_label("Твои лучшие броски", 34, true))
	_rating_page.add_child(_label("Личный рейтинг на этом устройстве. Каждый уровень — ещё один шанс стать лучше.", 18))
	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", _style(TEAL, 14, 22))
	_rating_page.add_child(summary)
	var summary_row := HBoxContainer.new()
	summary_row.add_theme_constant_override("separation", 22)
	summary.add_child(summary_row)
	var trophy := MenuIcon.new()
	trophy.kind = &"trophy"
	trophy.color = GOLD
	trophy.custom_minimum_size = Vector2(48, 48)
	summary_row.add_child(trophy)
	var total := CampaignCatalog.total_stars(profile)
	var completed_count := 0
	for level_id in CampaignCatalog.IDS:
		if profile.stars_for(level_id) > 0:
			completed_count += 1
	rating_summary = _label(tr("★  %d / %d     ·     Уровней пройдено: %d / %d") % [total, CampaignCatalog.LEVELS.size() * 3, completed_count, CampaignCatalog.LEVELS.size()], 26, true)
	rating_summary.add_theme_color_override("font_color", CREAM)
	rating_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(rating_summary)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rating_page.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	for index in CampaignCatalog.LEVELS.size():
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _style(CREAM, 8, 16))
		rows.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		panel.add_child(row)
		var level := CampaignCatalog.LEVELS[index]
		var stars := profile.stars_for(CampaignCatalog.IDS[index])
		var best := profile.best_shots_for(CampaignCatalog.IDS[index])
		var record := tr("Не пройден") if stars == 0 else tr("Рекорд: %d выстр.") % best
		var label := _label("%02d   %s     ·     %s%s     ·     %s" % [index + 1, tr(level.title), "★".repeat(stars), "☆".repeat(3 - stars), record], 21, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		rating_rows.append(label)
		var replay := _button("На уровень  ›", true)
		replay.disabled = not CampaignCatalog.is_unlocked(index, profile)
		replay.pressed.connect(func() -> void: level_requested.emit(index))
		row.add_child(replay)


func show_page(page_id: StringName) -> void:
	if page_id not in [&"home", &"campaign", &"rating", &"rewards"]:
		return
	page = page_id
	if _transition != null:
		_transition.kill()
	_home.visible = page == &"home"
	_campaign_page.visible = page == &"campaign"
	_rating_page.visible = page == &"rating"
	reward_collection.visible = page == &"rewards"
	back_button.visible = page != &"home"
	_backdrop.showcase_visible = page == &"home"
	_page_title.text = {&"home": "БОЛЬШОЕ ПРИКЛЮЧЕНИЕ В МАЛЕНЬКОМ ДВОРЕ", &"campaign": "КАМПАНИЯ  /  ТРИ МИРА", &"rating": "РЕЙТИНГ  /  ЛИЧНЫЕ РЕКОРДЫ", &"rewards": "Коллекция наград"}[page]
	var target: Control = _home if page == &"home" else (_campaign_page if page == &"campaign" else _rating_page)
	if page == &"rewards":
		target = reward_collection
	target.modulate.a = 0.0
	_transition = create_tween()
	_transition.tween_property(target, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_SINE)
	# Фокус не остаётся на скрытой кнопке предыдущей страницы.
	if page == &"home":
		continue_button.grab_focus()
	else:
		back_button.grab_focus()


func prepare_startup_entrance() -> void:
	if _transition != null:
		_transition.kill()
	_home.modulate.a = 1.0
	set_startup_progress(0.0)


func set_startup_progress(progress: float) -> void:
	_startup_progress = clampf(progress, 0.0, 1.0)
	_margin.modulate.a = smoothstep(0.2, 1.0, _startup_progress)
	_layout_home()


func _input(event: InputEvent) -> void:
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		var blocked: bool = page != &"home" or not is_visible_in_tree()
		for window in _menu_windows:
			blocked = blocked or window.visible
		var point: Vector2 = event.position
		blocked = blocked or _home_panel.get_global_rect().has_point(point)
		if _backdrop.handle_pointer_event(event, blocked):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and page != &"home":
		show_page(&"home")
		get_viewport().set_input_as_handled()


func _go_back() -> void:
	for node in find_children("*", "Window", true, false):
		var dialog := node as Window
		if dialog.visible and (dialog is AcceptDialog or dialog is PopupMenu):
			dialog.hide()
			return
	if page != &"home":
		show_page(&"home")
	elif _previous_quit_on_go_back:
		get_tree().quit()


func _exit_tree() -> void:
	if handles_native_back:
		get_tree().root.go_back_requested.disconnect(_go_back)
		get_tree().quit_on_go_back = _previous_quit_on_go_back


func _update_layout() -> void:
	var wide := size.x >= size.y * 1.6
	_grid.columns = 2 if wide else 1
	for levels in _chapter_grids:
		levels.columns = 1 if wide else 2
	for content in _chapter_contents:
		content.columns = 1 if wide else 2
	for heading in _chapter_headings:
		heading.custom_minimum_size.x = 0 if wide else 270
	var margins := Vector4(38, 20, 38, 22)
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		if screen.x > 0 and screen.y > 0 and safe.has_area():
			var ratio := size / Vector2(screen)
			margins.x += safe.position.x * ratio.x
			margins.y += safe.position.y * ratio.y
			margins.z += (screen.x - safe.end.x) * ratio.x
			margins.w += (screen.y - safe.end.y) * ratio.y
	for entry in [["left", margins.x], ["top", margins.y], ["right", margins.z], ["bottom", margins.w]]:
		_margin.add_theme_constant_override("margin_" + entry[0], int(entry[1]))
	_layout_home()


func _layout_home() -> void:
	if _home_panel == null:
		return
	var panel_width := clampf(_home.size.x * 0.35, 390.0, 440.0)
	var panel_height := _home_panel.get_combined_minimum_size().y
	_home_panel.size = Vector2(panel_width, panel_height)
	_home_panel.position = Vector2(_home.size.x - panel_width - 12, maxf(8, (_home.size.y - panel_height) * 0.34))
	var title_width := _home.size.x - panel_width - 90
	_title.position = Vector2(34, maxf(10, _home.size.y * 0.02))
	_title.size = Vector2(title_width, 0)
	var entrance_offset := (1.0 - _startup_progress) * 22.0
	_title.position.y += entrance_offset
	_home_panel.position.y += entrance_offset
	var font_size := int(clampf(title_width * 0.14, 70, 86))
	_title_cats.add_theme_font_size_override("font_size", font_size)
	_title_dogs.add_theme_font_size_override("font_size", font_size)
	_home_note.position = Vector2(15, _home.size.y - 36)
	_home_note.size = Vector2(title_width + 38, 36)


func _continue_text() -> String:
	return "Переиграть  ›" if _completed else ("Продолжить  ›" if CampaignCatalog.total_stars(profile) > 0 else "Играть  ›")


func _navigation_button(title: String, subtitle: String, icon_kind: StringName, tint: Color) -> Button:
	var button := _button("", true)
	button.custom_minimum_size.y = 68
	button.tooltip_text = tr(title) + ". " + tr(subtitle)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var icon_panel := PanelContainer.new()
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_panel.add_theme_stylebox_override("panel", _style(tint, 5, 12))
	icon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_panel)
	var icon := MenuIcon.new()
	icon.kind = icon_kind
	icon.custom_minimum_size = Vector2(36, 36)
	icon_panel.add_child(icon)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_constant_override("separation", -1)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(copy)
	copy.add_child(_label(title, 22, true))
	var caption := _label(subtitle, 14)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_theme_color_override("font_color", MUTED)
	copy.add_child(caption)
	row.add_child(_label("›", 28, true))
	return button


func _label(value: String, font_size: int, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	if bold:
		label.add_theme_font_override("font", _bold_font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(value: String, secondary: bool = false) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(148, 46)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", _bold_font)
	button.add_theme_color_override("font_focus_color", INK)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color := Color("f8f2df") if secondary else GOLD
		if state == "hover":
			color = Color("ecebd4") if secondary else Color("ffcc70")
		elif state == "pressed":
			color = Color("e4e4cc") if secondary else Color("e9a843")
		elif state == "disabled":
			color = Color("dbe1cc")
		var style := _style(color, 10, 15)
		if not secondary and state != "pressed":
			style.shadow_color = Color("b98135")
			style.shadow_offset = Vector2(0, 4)
			style.shadow_size = 1
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_" + state + "_color" if state != "normal" else "font_color", MUTED if state == "disabled" else INK)
	var focus := _style(Color.TRANSPARENT, 0, 15)
	focus.border_color = Color("347b6299")
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.mouse_entered.connect(func() -> void: _animate_button(button, 1.018))
	button.mouse_exited.connect(func() -> void: _animate_button(button, 1.0))
	button.button_down.connect(func() -> void: _animate_button(button, 0.985))
	button.button_up.connect(func() -> void: _animate_button(button, 1.0))
	button.resized.connect(func() -> void: button.pivot_offset = button.size * 0.5)
	return button


func _animate_button(button: Button, target_scale: float) -> void:
	if button.disabled:
		return
	var previous: Tween = _button_tweens.get(button.get_instance_id())
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * target_scale, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_button_tweens[button.get_instance_id()] = tween


func _style(color: Color, padding: int, radius: int = 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _line_style() -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = Color("e4e4ce")
	line.thickness = 1
	return line
