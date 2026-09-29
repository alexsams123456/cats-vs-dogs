class_name LevelEditor
extends Control
## Черновик, история правок и интерфейс встроенной мастерской.

signal play_requested(level: LevelDefinition)
signal menu_requested

const INK := Color("254b4b")
const CREAM := Color("fff7df")
const TEAL := Color("387c73")
const ORANGE := Color("efa05a")
const DEFAULT_LEVEL := preload("res://levels/level_01.tres")
const HISTORY_LIMIT := 60
const DRAFT_STORE := preload("res://scripts/levels/editor_draft_store.gd")
const AUTOSAVE_DELAY: float = 0.6

var draft: LevelDefinition
var current_path: String = ""
## Пустой путь отключает восстановление; проверки используют отдельный файл.
var recovery_path: String = DRAFT_STORE.DEFAULT_PATH
var canvas: LevelCanvas
var title_edit: LineEdit
var shots_input: SpinBox
var material_picker: OptionButton
var house_type_picker: OptionButton
var dog_kind_picker: OptionButton
var rules_button: Button
var biome_picker: OptionButton
var par_input: SpinBox
var cat_roster_toggle: CheckButton
var dog_roster_toggle: CheckButton
var cat_pickers: Array[OptionButton] = []
var tool_buttons: Array[Button] = []
var save_button: Button
var play_button: Button
var undo_button: Button
var redo_button: Button
var _status: Label
var _selection_label: Label
var _house_description: Label
var _fields: Array[SpinBox] = []
var _delete_button: Button
var _rotate_button: Button
var _undo_stack: Array[LevelDefinition] = []
var _redo_stack: Array[LevelDefinition] = []
var _before: LevelDefinition
var _saved_state: String = ""
var _syncing: bool = false
var _confirm: ConfirmationDialog
var _pending_replace: Callable
var _library_dialog: AcceptDialog
var _library_list: VBoxContainer
var _rules_dialog: AcceptDialog
var _cat_rows: VBoxContainer
var _dog_properties: VBoxContainer
var _margin: MarginContainer
var _draft_store: EditorDraftStore
var _autosave_timer: Timer
var _recovery_ready: bool = false
var _recovered: bool = false
var _recovery_failed: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var editor_theme := Theme.new()
	editor_theme.default_font_size = 18
	editor_theme.set_color("font_color", "Label", INK)
	theme = editor_theme
	var background := ColorRect.new()
	background.color = CREAM
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_margin.add_child(column)
	_build_header(column)
	_build_metadata(column)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	_build_sidebar(body)
	var field_column := VBoxContainer.new()
	field_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(field_column)
	canvas = LevelCanvas.new()
	canvas.custom_minimum_size = Vector2(320, 220)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_column.add_child(canvas)
	canvas.edit_started.connect(_begin_edit)
	canvas.edit_finished.connect(_finish_edit)
	canvas.selection_changed.connect(_update_selection)
	canvas.tool_changed.connect(_update_tools)
	_build_inspector(field_column)
	var hint := _label("Выбери объект слева и нажми на поле. Перетаскивай мышью или пальцем.", 17)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field_column.add_child(hint)
	_status = _label("", 17)
	_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_build_dialogs()
	resized.connect(_update_margins)
	_update_margins()
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DELAY
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)
	_draft_store = DRAFT_STORE.new(recovery_path)
	var recovered: Dictionary = _draft_store.load_draft()
	if recovered.is_empty():
		var initial_level := DEFAULT_LEVEL.duplicate(true) as LevelDefinition
		initial_level.title = tr(initial_level.title)
		_replace_draft(initial_level, "")
	else:
		_replace_draft(recovered.level, recovered.current_path)
		if recovered.dirty:
			_saved_state = ""
		_recovered = true
		_update_actions()
	_recovery_ready = true
	visibility_changed.connect(_on_visibility_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _recovery_ready:
		_refresh_translations()
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		flush_recovery()


func _refresh_translations() -> void:
	title_edit.placeholder_text = tr("Название двора")
	for index in BlockMaterials.LABELS.size():
		material_picker.set_item_text(index, tr(BlockMaterials.LABELS[index]))
	for index in DogHouseTypes.LABELS.size():
		house_type_picker.set_item_text(index, tr(DogHouseTypes.LABELS[index]))
	_refresh_rules()
	_update_actions()
	_update_selection()


func _exit_tree() -> void:
	flush_recovery()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		flush_recovery()


func _queue_recovery() -> void:
	if _recovery_ready and _autosave_timer.is_inside_tree():
		_autosave_timer.start()


func flush_recovery() -> void:
	if not _recovery_ready:
		return
	canvas.cancel_drag()
	_finish_edit()
	_autosave_timer.stop()
	_write_recovery()


func _on_autosave_timeout() -> void:
	if canvas._pointer != LevelCanvas.NO_POINTER:
		_queue_recovery()
		return
	_write_recovery()


func _write_recovery() -> void:
	var error: Error = _draft_store.save_draft(draft, current_path, is_dirty())
	var previous_failure := _recovery_failed
	_recovery_failed = error != OK
	if _recovery_failed or previous_failure:
		_update_actions()


func _request_menu() -> void:
	flush_recovery()
	menu_requested.emit()


func _build_header(column: VBoxContainer) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	column.add_child(row)
	var heading := _label("Редактор уровней", 28)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	row.add_child(_button("Меню", _request_menu))
	row.add_child(_button("Новый", func() -> void: _confirm_replace(new_level)))
	row.add_child(_button("Открыть", _show_library))
	save_button = _button("Сохранить", save_level)
	row.add_child(save_button)
	row.add_child(_button("Копия", save_level.bind(true)))
	play_button = _button("Испытать  →", request_play, ORANGE)
	row.add_child(play_button)


func _build_metadata(column: VBoxContainer) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 8)
	column.add_child(row)
	var title_row := HBoxContainer.new()
	title_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_row)
	title_row.add_child(_label("Название", 18))
	title_edit = LineEdit.new()
	title_edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_edit.placeholder_text = tr("Название двора")
	title_edit.max_length = 48
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.custom_minimum_size = Vector2(160, 48)
	_style_input(title_edit)
	title_edit.text_changed.connect(_on_title_changed)
	title_edit.focus_exited.connect(_finish_edit)
	title_row.add_child(title_edit)
	var shots_row := HBoxContainer.new()
	row.add_child(shots_row)
	shots_row.add_child(_label("Выстрелы", 18))
	shots_input = _spin(1, 20)
	shots_input.value_changed.connect(_on_shots_changed)
	shots_row.add_child(shots_input)
	undo_button = _button("Отменить", undo)
	undo_button.tooltip_text = "Ctrl+Z"
	row.add_child(undo_button)
	redo_button = _button("Вернуть", redo)
	redo_button.tooltip_text = "Ctrl+Y / Ctrl+Shift+Z"
	row.add_child(redo_button)


func _build_sidebar(body: HBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 224
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)
	rules_button = _button("Правила двора", _show_rules, ORANGE)
	column.add_child(rules_button)
	column.add_child(_label("МАТЕРИАЛ", 16))
	material_picker = TouchOptionButton.new()
	_style_picker(material_picker)
	material_picker.tooltip_text = "Материал новых блоков и будок; меняет материал выбранного строения"
	for index in BlockMaterials.IDS.size():
		material_picker.add_item(tr(BlockMaterials.LABELS[index]))
	material_picker.item_selected.connect(_on_material_selected)
	column.add_child(material_picker)
	column.add_child(_label("ВИД КОНУРЫ", 16))
	house_type_picker = TouchOptionButton.new()
	_style_picker(house_type_picker)
	house_type_picker.tooltip_text = "Вид новой конуры; меняет выбранную конуру вместе с её размерами и прочностью"
	for index in DogHouseTypes.IDS.size():
		house_type_picker.add_item(tr(DogHouseTypes.LABELS[index]))
	house_type_picker.item_selected.connect(_on_house_type_selected)
	column.add_child(house_type_picker)
	_house_description = _label("", 16)
	_house_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_house_description)
	column.add_child(_label("ОБЪЕКТЫ", 16))
	var names: Array[String] = ["Выбрать / двигать", "+ Собака", "+ Стойка", "+ Перекладина", "+ Ящик", "+ Собака в будке", "+ Башня"]
	for index in names.size():
		var button := _button(names[index], _choose_tool.bind(index))
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = names[index]
		button.toggle_mode = true
		column.add_child(button)
		tool_buttons.append(button)
	var grid := CheckButton.new()
	grid.text = "Сетка · шаг 10"
	grid.add_theme_color_override("font_color", INK)
	grid.add_theme_color_override("font_hover_color", TEAL)
	grid.add_theme_color_override("font_pressed_color", INK)
	grid.add_theme_color_override("font_hover_pressed_color", TEAL)
	grid.button_pressed = true
	grid.custom_minimum_size.y = 48
	grid.toggled.connect(func(value: bool) -> void:
		canvas.grid_enabled = value
		canvas.queue_redraw()
	)
	column.add_child(grid)
	_selection_label = _label("Ничего не выбрано", 17)
	_selection_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_selection_label)
	_dog_properties = VBoxContainer.new()
	column.add_child(_dog_properties)
	column.move_child(_dog_properties, 1)
	var dog_label := _label("Вид выбранной собаки", 16)
	dog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dog_properties.add_child(dog_label)
	dog_kind_picker = TouchOptionButton.new()
	_style_picker(dog_kind_picker)
	dog_kind_picker.fit_to_longest_item = false
	dog_kind_picker.add_item(tr("Из песочницы"))
	dog_kind_picker.set_item_disabled(0, true)
	for dog in CharacterCatalog.DOGS:
		dog_kind_picker.add_item(tr(dog.display_name))
	dog_kind_picker.item_selected.connect(_on_dog_kind_selected)
	_dog_properties.add_child(dog_kind_picker)


func _build_inspector(column: VBoxContainer) -> void:
	var property_grid := HFlowContainer.new()
	property_grid.add_theme_constant_override("h_separation", 8)
	property_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(property_grid)
	for index in 4:
		var field_row := HBoxContainer.new()
		property_grid.add_child(field_row)
		field_row.add_child(_label(["X", "Y", "Ш", "В"][index], 16))
		var field := _spin(0 if index < 2 else 10, 1280 if index < 2 else 400)
		field.custom_minimum_size.x = 88
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.tooltip_text = ["Положение по горизонтали", "Положение по вертикали", "Ширина блока", "Высота блока"][index]
		field.value_changed.connect(_on_property_changed.bind(index))
		field_row.add_child(field)
		_fields.append(field)
	_rotate_button = _button("Повернуть", func() -> void: canvas.rotate_selected())
	property_grid.add_child(_rotate_button)
	_delete_button = _button("Удалить", func() -> void: canvas.delete_selected())
	_delete_button.tooltip_text = "Delete"
	property_grid.add_child(_delete_button)


func _build_dialogs() -> void:
	var dialog_theme := Theme.new()
	dialog_theme.default_font_size = 20
	dialog_theme.set_color("font_color", "Label", CREAM)
	_confirm = ConfirmationDialog.new()
	_confirm.theme = dialog_theme
	_confirm.title = "Заменить черновик?"
	_confirm.dialog_text = "Несохранённые изменения будут потеряны."
	_confirm.ok_button_text = "Заменить"
	_confirm.cancel_button_text = "Продолжить правки"
	_confirm.confirmed.connect(func() -> void:
		if _pending_replace.is_valid():
			_pending_replace.call()
	)
	add_child(_confirm)
	_library_dialog = AcceptDialog.new()
	_library_dialog.theme = dialog_theme
	_library_dialog.title = "Мои уровни"
	_library_dialog.ok_button_text = "Закрыть"
	add_child(_library_dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_library_dialog.add_child(scroll)
	_library_list = VBoxContainer.new()
	_library_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_library_list)
	_build_rules_dialog()


func _build_rules_dialog() -> void:
	_rules_dialog = AcceptDialog.new()
	_rules_dialog.theme = _library_dialog.theme.duplicate() as Theme
	_rules_dialog.theme.set_constant("buttons_min_width", "AcceptDialog", 160)
	_rules_dialog.theme.set_constant("buttons_min_height", "AcceptDialog", 56)
	_rules_dialog.title = "Правила двора"
	_rules_dialog.ok_button_text = "Закрыть"
	add_child(_rules_dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_rules_dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	column.add_child(_label("Окружение", 18))
	biome_picker = TouchOptionButton.new()
	_style_picker(biome_picker)
	for label: String in ["За домом", "Горные тропы", "Ледяная долина"]:
		biome_picker.add_item(tr(label))
	biome_picker.item_selected.connect(_on_biome_selected)
	column.add_child(biome_picker)
	var stars_row := HBoxContainer.new()
	column.add_child(stars_row)
	var stars_label := _label("Лимит на три звезды", 18)
	stars_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stars_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stars_row.add_child(stars_label)
	par_input = _spin(0, 20)
	par_input.value_changed.connect(_on_par_changed)
	stars_row.add_child(par_input)
	var stars_hint := _label("0 — без звёзд. Лимит не больше числа выстрелов.", 16)
	stars_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(stars_hint)
	cat_roster_toggle = CheckButton.new()
	cat_roster_toggle.text = "Задать порядок котов"
	cat_roster_toggle.custom_minimum_size.y = 48
	cat_roster_toggle.toggled.connect(_on_cat_roster_toggled)
	column.add_child(cat_roster_toggle)
	var roster_hint := _label("Без своего состава используются герои песочницы.", 16)
	roster_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(roster_hint)
	_cat_rows = VBoxContainer.new()
	_cat_rows.add_theme_constant_override("separation", 8)
	column.add_child(_cat_rows)
	dog_roster_toggle = CheckButton.new()
	dog_roster_toggle.text = "Задать виды собак"
	dog_roster_toggle.custom_minimum_size.y = 48
	dog_roster_toggle.toggled.connect(_on_dog_roster_toggled)
	column.add_child(dog_roster_toggle)
	var dog_hint := _label("Выбери собаку на поле, затем её вид в панели слева.", 16)
	dog_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(dog_hint)


func _show_rules() -> void:
	canvas.cancel_drag()
	_finish_edit()
	_refresh_rules()
	_rules_dialog.popup_centered(Vector2i(620, 550))


func _refresh_rules() -> void:
	if draft == null or _rules_dialog == null:
		return
	var previous_syncing := _syncing
	_syncing = true
	for index in 3:
		biome_picker.set_item_text(index, tr(["За домом", "Горные тропы", "Ледяная долина"][index]))
	biome_picker.select(LevelDefinition.BIOMES.find(StringName(draft.biome)))
	par_input.max_value = draft.shots
	par_input.set_value_no_signal(draft.par_shots)
	cat_roster_toggle.set_pressed_no_signal(not draft.cat_sequence.is_empty())
	dog_roster_toggle.set_pressed_no_signal(not draft.dog_kinds.is_empty())
	dog_roster_toggle.disabled = draft.dog_positions.is_empty()
	_cat_rows.visible = not draft.cat_sequence.is_empty()
	if cat_pickers.size() != draft.shots:
		for child in _cat_rows.get_children():
			_cat_rows.remove_child(child)
			child.queue_free()
		cat_pickers.clear()
		for slot in draft.shots:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			_cat_rows.add_child(row)
			var label := _label("", 18)
			label.custom_minimum_size.x = 120
			row.add_child(label)
			var picker := TouchOptionButton.new()
			_style_picker(picker)
			picker.fit_to_longest_item = false
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for cat in CharacterCatalog.CATS:
				picker.add_item(tr(cat.display_name))
			picker.item_selected.connect(_on_cat_selected.bind(slot))
			row.add_child(picker)
			cat_pickers.append(picker)
	for slot in cat_pickers.size():
		var picker := cat_pickers[slot]
		(picker.get_parent().get_child(0) as Label).text = tr("Бросок %d") % (slot + 1)
		for index in CharacterCatalog.CATS.size():
			picker.set_item_text(index, tr(CharacterCatalog.CATS[index].display_name))
		var cat := CharacterCatalog.find_cat(StringName(draft.cat_sequence[slot]) if not draft.cat_sequence.is_empty() else &"classic")
		picker.select(CharacterCatalog.CATS.find(cat))
		picker.tooltip_text = tr(cat.ability_hint)
	dog_kind_picker.set_item_text(0, tr("Из песочницы"))
	for index in CharacterCatalog.DOGS.size():
		dog_kind_picker.set_item_text(index + 1, tr(CharacterCatalog.DOGS[index].display_name))
	_syncing = previous_syncing


func _on_biome_selected(index: int) -> void:
	_begin_edit()
	draft.biome = String(LevelDefinition.BIOMES[index])
	canvas.draft = draft
	_finish_edit()


func _on_par_changed(value: float) -> void:
	if _syncing:
		return
	_begin_edit()
	draft.par_shots = int(value)
	_finish_edit()


func _on_cat_roster_toggled(enabled: bool) -> void:
	_begin_edit()
	draft.cat_sequence.clear()
	if enabled:
		draft.cat_sequence.resize(draft.shots)
		draft.cat_sequence.fill("classic")
	_finish_edit()


func _on_cat_selected(index: int, slot: int) -> void:
	_begin_edit()
	draft.cat_sequence[slot] = String(CharacterCatalog.CATS[index].id)
	_finish_edit()


func _on_dog_roster_toggled(enabled: bool) -> void:
	_begin_edit()
	draft.dog_kinds.clear()
	if enabled:
		draft.dog_kinds.resize(draft.dog_positions.size())
		draft.dog_kinds.fill("scout")
	_finish_edit()


func _on_dog_kind_selected(index: int) -> void:
	if canvas.selected_kind != 0 or index == 0:
		return
	_begin_edit()
	if draft.dog_kinds.is_empty():
		draft.dog_kinds.resize(draft.dog_positions.size())
		draft.dog_kinds.fill("scout")
	draft.dog_kinds[canvas.selected_index] = String(CharacterCatalog.DOGS[index - 1].id)
	_finish_edit()


func _show_library() -> void:
	_finish_edit()
	for child in _library_list.get_children():
		_library_list.remove_child(child)
		child.queue_free()
	_library_list.add_child(_button("Первый двор · шаблон", _choose_saved.bind("res://levels/level_01.tres")))
	_library_list.add_child(_button("Двор конур · шаблон", _choose_saved.bind("res://levels/kennel_yard.tres")))
	var entries := LevelLibrary.list_levels()
	for entry in entries:
		var button := _button(entry.title, _choose_saved.bind(String(entry.path)))
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = entry.path
		_library_list.add_child(button)
	if entries.is_empty():
		_library_list.add_child(_label("Здесь появятся сохранённые уровни.", 18))
	_library_dialog.popup_centered()


func _choose_saved(path: String) -> void:
	_library_dialog.hide()
	_confirm_replace(open_level.bind(path))


func _confirm_replace(action: Callable) -> void:
	_finish_edit()
	if is_dirty():
		_pending_replace = action
		_confirm.popup_centered()
	else:
		action.call()


func new_level() -> void:
	var empty := LevelDefinition.new()
	empty.title = tr("Новый двор")
	_replace_draft(empty, "")


func open_level(path: String) -> void:
	var loaded := LevelLibrary.load_level(path)
	if loaded == null:
		_status.text = tr("Не удалось открыть уровень. Файл отсутствует или содержит ошибки.")
		return
	if path.begins_with("res://levels/"):
		loaded.title = tr(loaded.title)
	_replace_draft(loaded, path if path.begins_with("user://") else "")


func save_level(as_copy: bool = false) -> void:
	_finish_edit()
	if not draft.is_valid():
		_status.text = tr("Для сохранения нужны название, хотя бы одна собака и 1–20 выстрелов.")
		return
	var result := LevelLibrary.save_level(draft, "" if as_copy else current_path)
	if result.error != OK:
		_status.text = tr("Не удалось сохранить уровень: ошибка %d. Черновик остаётся здесь.") % result.error
		return
	current_path = result.path
	_saved_state = _signature(draft)
	_recovered = false
	flush_recovery()
	_refresh()
	_status.text = tr("Сохранено на устройстве · %s") % draft.title


func request_play() -> void:
	_finish_edit()
	if draft.is_valid():
		canvas.cancel_drag()
		flush_recovery()
		play_requested.emit(draft.duplicate(true) as LevelDefinition)
	else:
		_status.text = tr("Добавь собаку и название, чтобы испытать уровень.")


func is_dirty() -> bool:
	return draft != null and _signature(draft) != _saved_state


func _replace_draft(value: LevelDefinition, path: String) -> void:
	canvas.cancel_drag()
	draft = value
	draft.normalize_materials()
	current_path = path
	_recovered = false
	_saved_state = _signature(draft)
	_undo_stack.clear()
	_redo_stack.clear()
	_before = null
	canvas.draft = draft
	canvas.clear_selection()
	canvas.set_tool(LevelCanvas.Tool.SELECT)
	_refresh()
	flush_recovery()


func _begin_edit() -> void:
	if _before == null:
		_before = draft.duplicate(true) as LevelDefinition


func _finish_edit() -> void:
	if _before == null:
		return
	if not draft.cat_sequence.is_empty():
		var previous_size := draft.cat_sequence.size()
		draft.cat_sequence.resize(draft.shots)
		for slot in range(previous_size, draft.shots):
			draft.cat_sequence[slot] = "classic"
	draft.par_shots = mini(draft.par_shots, draft.shots)
	if _signature(_before) != _signature(draft):
		_undo_stack.append(_before)
		if _undo_stack.size() > HISTORY_LIMIT:
			_undo_stack.pop_front()
		_redo_stack.clear()
		_queue_recovery()
	_before = null
	_refresh()


func undo() -> void:
	canvas.cancel_drag()
	_finish_edit()
	if _undo_stack.is_empty():
		return
	_redo_stack.append(draft.duplicate(true) as LevelDefinition)
	draft = _undo_stack.pop_back()
	_restore_history()


func redo() -> void:
	canvas.cancel_drag()
	_finish_edit()
	if _redo_stack.is_empty():
		return
	_undo_stack.append(draft.duplicate(true) as LevelDefinition)
	draft = _redo_stack.pop_back()
	_restore_history()


func _restore_history() -> void:
	canvas.draft = draft
	canvas.clear_selection()
	_refresh()
	_queue_recovery()


func _signature(value: LevelDefinition) -> String:
	return var_to_str([value.title, value.biome, value.shots, value.dog_positions, value.dog_house_materials, value.dog_house_types, value.block_positions, value.block_sizes, value.block_materials, value.cat_sequence, value.dog_kinds, value.tutorial, value.par_shots])


func _on_title_changed(value: String) -> void:
	if _syncing:
		return
	_begin_edit()
	draft.title = value
	_update_actions()
	_queue_recovery()


func _on_shots_changed(value: float) -> void:
	if _syncing:
		return
	_begin_edit()
	draft.shots = int(value)
	_finish_edit()


func _on_property_changed(value: float, index: int) -> void:
	if _syncing or canvas.selected_kind < 0:
		return
	_begin_edit()
	var point := canvas.selected_position()
	if index == 0:
		point.x = value
	elif index == 1:
		point.y = value
	elif canvas.selected_kind == 1:
		var dimensions := canvas.selected_size()
		if index == 2:
			dimensions.x = value
		else:
			dimensions.y = value
		draft.block_sizes[canvas.selected_index] = dimensions
	canvas.move_selected(point)
	_finish_edit()


func _choose_tool(index: int) -> void:
	canvas.set_tool(index as LevelCanvas.Tool)
	if index != LevelCanvas.Tool.SELECT:
		canvas.clear_selection()


func _on_material_selected(index: int) -> void:
	if _syncing:
		return
	canvas.material_id = BlockMaterials.IDS[index]
	canvas.set_selected_material(canvas.material_id)


func _on_house_type_selected(index: int) -> void:
	if _syncing:
		return
	canvas.house_type = DogHouseTypes.IDS[index]
	canvas.set_selected_house_type(canvas.house_type)
	_update_house_description()


func _update_house_description() -> void:
	_house_description.text = tr(DogHouseTypes.get_definition(canvas.house_type).description)


func _update_tools() -> void:
	for index in tool_buttons.size():
		tool_buttons[index].set_pressed_no_signal(index == canvas.tool)


func _refresh() -> void:
	_syncing = true
	title_edit.text = draft.title
	shots_input.set_value_no_signal(draft.shots)
	_refresh_rules()
	_syncing = false
	_update_actions()
	_update_selection()
	canvas.queue_redraw()


func _update_actions() -> void:
	play_button.disabled = not draft.is_valid()
	save_button.disabled = not draft.is_valid()
	undo_button.disabled = _undo_stack.is_empty() and _before == null
	redo_button.disabled = _redo_stack.is_empty()
	var state := tr("Есть изменения") if is_dirty() else (tr("Сохранено") if not current_path.is_empty() else tr("Черновик"))
	var hint := ""
	if draft.title.strip_edges().is_empty():
		hint = tr(" · Укажи название")
	elif draft.dog_positions.is_empty():
		hint = tr(" · Добавь хотя бы одну собаку")
	var house_count := 0
	for index in draft.dog_positions.size():
		if not draft.dog_house_material_at(index).is_empty():
			house_count += 1
	_status.text = tr("%s · собак: %d · будок: %d · блоков: %d%s") % [state, draft.dog_positions.size(), house_count, draft.block_positions.size(), hint]
	if _recovered:
		_status.text = tr("Черновик восстановлен · ") + _status.text
	if _recovery_failed:
		_status.text = tr("Не удалось автоматически сохранить черновик · ") + _status.text


func _update_selection() -> void:
	_syncing = true
	var selected := canvas.selected_kind >= 0
	_dog_properties.visible = canvas.selected_kind == 0
	if canvas.selected_kind == 0:
		var kind_index := 0
		if not draft.dog_kinds.is_empty():
			var dog := CharacterCatalog.find_dog(StringName(draft.dog_kinds[canvas.selected_index]))
			kind_index = CharacterCatalog.DOGS.find(dog) + 1
			dog_kind_picker.tooltip_text = tr(dog.description)
		else:
			dog_kind_picker.tooltip_text = tr("Без своего состава используются герои песочницы.")
		dog_kind_picker.select(kind_index)
	_selection_label.text = (tr("Собака") if canvas.selected_kind == 0 else tr("Блок")) if selected else tr("Ничего не выбрано")
	var selected_material := canvas.selected_material()
	if not selected_material.is_empty():
		var material_index := BlockMaterials.IDS.find(selected_material)
		material_picker.select(material_index)
		canvas.material_id = selected_material
		_selection_label.text = (tr("Собака в будке") if canvas.selected_kind == 0 else tr("Блок")) + " · " + tr(BlockMaterials.LABELS[material_index])
	var selected_type := canvas.selected_house_type()
	if not selected_type.is_empty():
		var type_index := DogHouseTypes.IDS.find(selected_type)
		house_type_picker.select(type_index)
		canvas.house_type = selected_type
		_selection_label.text += " · " + tr(DogHouseTypes.LABELS[type_index])
	_update_house_description()
	var point := canvas.selected_position()
	var dimensions := canvas.selected_size()
	for index in _fields.size():
		_fields[index].editable = selected and (index < 2 or canvas.selected_kind == 1)
		_fields[index].set_value_no_signal([point.x, point.y, dimensions.x, dimensions.y][index])
	_delete_button.disabled = not selected
	_rotate_button.disabled = canvas.selected_kind != 1
	_syncing = false


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		if event.shift_pressed:
			redo()
		else:
			undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		redo()
	elif event.ctrl_pressed and event.keycode == KEY_S:
		save_level()
	elif event.keycode == KEY_DELETE:
		canvas.delete_selected()
	else:
		return
	get_viewport().set_input_as_handled()


func _update_margins() -> void:
	var margins := Vector4(20, 18, 20, 18)
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		if screen.x > 0 and screen.y > 0 and safe.has_area():
			var ratio := size / Vector2(screen)
			margins += Vector4(safe.position.x * ratio.x, safe.position.y * ratio.y, (screen.x - safe.end.x) * ratio.x, (screen.y - safe.end.y) * ratio.y)
	for entry in [["left", margins.x], ["top", margins.y], ["right", margins.z], ["bottom", margins.w]]:
		_margin.add_theme_constant_override("margin_" + entry[0], int(entry[1]))


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _spin(minimum: float, maximum: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.custom_minimum_size = Vector2(104, 48)
	_style_input(spin.get_line_edit())
	return spin


func _style_input(field: LineEdit) -> void:
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_uneditable_color", Color("87968a"))
	field.add_theme_color_override("caret_color", TEAL)
	for state in ["normal", "read_only", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fffdf5") if state != "read_only" else Color("e8ebdc")
		style.set_corner_radius_all(8)
		style.set_border_width_all(2 if state == "focus" else 1)
		style.border_color = ORANGE if state == "focus" else Color("c3cdb9")
		style.content_margin_left = 10
		style.content_margin_right = 10
		field.add_theme_stylebox_override(state, style)


func _style_picker(picker: OptionButton) -> void:
	picker.custom_minimum_size.y = 48
	picker.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fffdf5")
		style.set_corner_radius_all(8)
		style.set_border_width_all(2 if state == "focus" else 1)
		style.border_color = ORANGE if state == "focus" else Color("c3cdb9")
		style.content_margin_left = 12
		style.content_margin_right = 28
		picker.add_theme_stylebox_override(state, style)
		if state != "focus":
			var mirrored := style.duplicate() as StyleBoxFlat
			mirrored.content_margin_left = 28
			mirrored.content_margin_right = 12
			picker.add_theme_stylebox_override(state + "_mirrored", mirrored)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		picker.add_theme_color_override(state, INK)


func _button(text: String, action: Callable, color: Color = TEAL) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color
		if state == "hover":
			style.bg_color = color.lightened(0.12)
		elif state == "pressed" or state == "hover_pressed":
			style.bg_color = color.darkened(0.22)
		elif state == "disabled":
			style.bg_color = Color("dbe1ce")
		style.set_corner_radius_all(12)
		style.content_margin_left = 14
		style.content_margin_right = 14
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), INK if color == ORANGE or state == "disabled" else CREAM)
	button.pressed.connect(action)
	return button
