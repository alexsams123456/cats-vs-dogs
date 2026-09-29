class_name TouchOptionButton
extends OptionButton
## PopupMenu получает явные касания без общей эмуляции мыши в игре.

class PopupTouchInput extends Node:
	var popup: PopupMenu
	var touch_index: int = -1

	func _ready() -> void:
		popup = get_parent() as PopupMenu
		popup.visibility_changed.connect(_reset)

	func _input(event: InputEvent) -> void:
		if not popup.visible:
			return
		if event is InputEventScreenTouch:
			if event.pressed and not event.canceled and touch_index < 0:
				touch_index = event.index
			if event.index == touch_index:
				if event.canceled:
					popup.hide()
				else:
					_forward_button(event.position, event.pressed)
				if not event.pressed or event.canceled:
					touch_index = -1
			popup.set_input_as_handled()
		elif event is InputEventScreenDrag:
			if event.index == touch_index:
				var motion := InputEventMouseMotion.new()
				motion.position = event.position
				motion.relative = event.relative
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				_forward(motion)
			popup.set_input_as_handled()

	func _forward_button(point: Vector2, pressed: bool) -> void:
		var button := InputEventMouseButton.new()
		button.position = point
		button.button_index = MOUSE_BUTTON_LEFT
		button.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		button.pressed = pressed
		_forward(button)

	func _forward(event: InputEventMouse) -> void:
		# Встроенные окна проекта используют координаты корневого viewport.
		# push_input сохраняет настоящую мышь: глобальную маску кнопок не меняем.
		event.device = -1
		event.position += Vector2(popup.position)
		event.global_position = event.position
		get_tree().root.push_input(event, true)

	func _reset() -> void:
		touch_index = -1

	func _notification(what: int) -> void:
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(popup):
			popup.hide()
			_reset()


func _ready() -> void:
	get_popup().add_child(PopupTouchInput.new())
