class_name LevelExchangeDialog
extends AcceptDialog
## Обмен кодом или файлом; импорт передаётся редактору только после предпросмотра.

signal import_requested(level: LevelDefinition)
signal play_requested

var code_edit: TextEdit
var summary: Label
var completion_label: Label
var review_label: Label
var thumbnail: LevelThumbnail
var test_button: Button
var message: Label
var share_button: Button
var import_button: Button
var copy_button: Button
var paste_button: Button
var save_button: Button
var open_button: Button
var add_button: Button
var file_dialog: FileDialog
var _source: LevelDefinition
var _incoming: LevelDefinition
var _sharing: bool = true


func _ready() -> void:
	title = "Обмен уровнями"
	ok_button_text = "Закрыть"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 350)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	var modes := HFlowContainer.new()
	column.add_child(modes)
	share_button = _button("Поделиться", _show_share)
	import_button = _button("Импортировать", _show_import)
	modes.add_child(share_button)
	modes.add_child(import_button)
	var hint := Label.new()
	hint.text = "Отправь код или файл другу. Полученный уровень добавится в «Мои уровни»."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	column.add_child(hint)
	var preview := HBoxContainer.new()
	preview.add_theme_constant_override("separation", 12)
	column.add_child(preview)
	thumbnail = LevelThumbnail.new()
	preview.add_child(thumbnail)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_child(details)
	summary = Label.new()
	summary.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", 16)
	details.add_child(summary)
	completion_label = Label.new()
	completion_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	completion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	completion_label.add_theme_font_size_override("font_size", 16)
	details.add_child(completion_label)
	review_label = Label.new()
	review_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	review_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	review_label.add_theme_font_size_override("font_size", 16)
	column.add_child(review_label)
	code_edit = TextEdit.new()
	code_edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	code_edit.placeholder_text = tr("Вставь код уровня CVD1:…")
	code_edit.custom_minimum_size = Vector2(0, 80)
	code_edit.add_theme_font_size_override("font_size", 16)
	code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_edit.text_direction = Control.TEXT_DIRECTION_LTR
	code_edit.text_changed.connect(_validate_code)
	column.add_child(code_edit)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	column.add_child(actions)
	copy_button = _button("Копировать код", _copy_code)
	paste_button = _button("Вставить код", _paste_code)
	save_button = _button("Сохранить файл", _save_file)
	open_button = _button("Открыть файл", _open_file)
	add_button = _button("Добавить в мои уровни", _request_import)
	test_button = _button("Испытать уровень", _request_play)
	for button: Button in [copy_button, paste_button, save_button, open_button, add_button, test_button]:
		actions.add_child(button)
	message = Label.new()
	message.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.add_filter("*.cvdlevel", tr("Уровень «Кошки против собак»"), "application/json")
	file_dialog.file_selected.connect(_file_selected)
	add_child(file_dialog)
	get_ok_button().custom_minimum_size.y = 48
	close_requested.connect(hide)
	copy_button.disabled = not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	paste_button.disabled = copy_button.disabled


func show_exchange(level: LevelDefinition) -> void:
	_source = level.duplicate(true) as LevelDefinition
	_show_share() if level.is_valid() else _show_import()
	var available: Vector2 = (get_parent() as Control).get_viewport_rect().size
	popup_centered(Vector2i(minf(760, available.x - 40), minf(600, available.y - 40)))


func _set_mode(sharing: bool) -> void:
	_sharing = sharing
	share_button.disabled = sharing
	import_button.disabled = not sharing
	code_edit.editable = not sharing
	copy_button.visible = sharing
	save_button.visible = sharing
	paste_button.visible = not sharing
	open_button.visible = not sharing
	add_button.visible = not sharing
	test_button.visible = sharing
	message.text = ""
	code_edit.placeholder_text = tr("Вставь код уровня CVD1:…")


func _show_share() -> void:
	_set_mode(true)
	code_edit.text = LevelExchange.encode(_source)
	_summary(_source if not code_edit.text.is_empty() else null)
	save_button.disabled = code_edit.text.is_empty()
	test_button.disabled = code_edit.text.is_empty()
	copy_button.disabled = code_edit.text.is_empty() or not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	if code_edit.text.is_empty():
		message.text = tr("Для обмена укажи название и добавь хотя бы одну собаку.")


func _show_import() -> void:
	_set_mode(false)
	code_edit.text = ""
	_validate_code()
	code_edit.grab_focus()


func _validate_code() -> void:
	if _sharing:
		return
	_incoming = LevelExchange.decode(code_edit.text)
	_summary(_incoming)
	add_button.disabled = _incoming == null
	message.text = tr("Код повреждён или создан другой версией игры.") if _incoming == null and not code_edit.text.strip_edges().is_empty() else ""


func _summary(level: LevelDefinition) -> void:
	if level == null:
		summary.text = ""
		completion_label.text = ""
		review_label.text = ""
		thumbnail.hide()
		return
	summary.text = tr("%s · собак: %d · блоков: %d · грузов: %d · выстрелов: %d") % [level.title, level.dog_positions.size(), level.block_positions.size(), level.weight_positions.size(), level.shots]
	thumbnail.draft = level
	thumbnail.show()
	thumbnail.queue_redraw()
	completion_label.text = tr("Пройден автором · бросков: %d") % int(level.author_completion.shots) if level.is_author_completed() else tr("Нет отметки прохождения")
	if _sharing and not level.is_author_completed():
		completion_label.text += "\n" + tr("Победи в пробном бою, чтобы получить отметку.")
	var issues := LevelLayoutReview.inspect(level)
	review_label.text = "" if issues.is_empty() else tr("Подсказок по постройке: %d. Подробнее — в редакторе, «Проверить двор».") % issues.size()


func _copy_code() -> void:
	if copy_button.disabled:
		return
	DisplayServer.clipboard_set(code_edit.text)
	message.text = tr("Код скопирован. Отправь его другу в сообщении.")


func _paste_code() -> void:
	if paste_button.disabled:
		return
	code_edit.text = DisplayServer.clipboard_get()
	_validate_code()


func _save_file() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.current_file = "level.cvdlevel"
	file_dialog.title = tr("Сохранить файл")
	file_dialog.popup_file_dialog()


func _open_file() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.current_file = ""
	file_dialog.title = tr("Открыть файл")
	file_dialog.popup_file_dialog()


func _file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		# Записываем ровно выбранный путь: подтверждение перезаписи принадлежит диалогу.
		message.text = tr("Файл готов. Отправь его другу.") if LevelExchange.write_file(_source, path) == OK else tr("Не удалось сохранить файл. Выбери другую папку.")
	else:
		var level := LevelExchange.read_file(path)
		code_edit.text = LevelExchange.encode(level) if level != null else ""
		_validate_code()
		if level == null:
			message.text = tr("Не удалось открыть уровень. Файл отсутствует или содержит ошибки.")


func _request_import() -> void:
	if _incoming == null:
		return
	hide()
	import_requested.emit(_incoming.duplicate(true) as LevelDefinition)


func _request_play() -> void:
	if test_button.disabled:
		return
	hide()
	play_requested.emit()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.pressed.connect(action)
	return button
