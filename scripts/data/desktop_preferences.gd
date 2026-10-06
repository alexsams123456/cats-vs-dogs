class_name DesktopPreferences
extends RefCounted
## Настройки ПК и физические клавиши, независимые от раскладки.

const ACTIONS: Array[StringName] = [&"ability", &"restart", &"pause", &"camera_reset"]
const TITLES: Array[String] = ["Способность", "Перезапуск", "Пауза", "Весь двор"]
const DEFAULT_KEYS: Array[int] = [KEY_E, KEY_R, KEY_SPACE, KEY_HOME]

var fullscreen: bool = false
var screen_shake: bool = true
var reduced_particles: bool = false
var keys: Array[int] = DEFAULT_KEYS.duplicate()


func load_data(value: Variant) -> void:
	if not value is Dictionary:
		return
	fullscreen = value.get("fullscreen", false) == true
	screen_shake = value.get("screen_shake", true) == true
	reduced_particles = value.get("reduced_particles", false) == true
	var bindings: Variant = value.get("keys", [])
	if not bindings is Array or bindings.size() != ACTIONS.size():
		return
	var validated: Array[int] = []
	for code: Variant in bindings:
		if not (code is int or code is float) or not is_finite(float(code)) or float(code) != floorf(float(code)):
			return
		if not allowed_key(int(code)) or int(code) in validated:
			return
		validated.append(int(code))
	keys = validated


func to_data() -> Dictionary:
	return {"fullscreen": fullscreen, "screen_shake": screen_shake, "reduced_particles": reduced_particles, "keys": keys}


static func allowed_key(code: int) -> bool:
	return (code >= KEY_A and code <= KEY_Z) or (code >= KEY_0 and code <= KEY_9) or code in [KEY_SPACE, KEY_HOME, KEY_END, KEY_INSERT, KEY_DELETE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]


func bind_key(index: int, code: int) -> Error:
	if index < 0 or index >= keys.size() or not allowed_key(code):
		return ERR_INVALID_PARAMETER
	if keys.has(code) and keys[index] != code:
		return ERR_ALREADY_IN_USE
	keys[index] = code
	return OK


func apply_input() -> void:
	for index in ACTIONS.size():
		if not InputMap.has_action(ACTIONS[index]):
			InputMap.add_action(ACTIONS[index])
		InputMap.action_erase_events(ACTIONS[index])
		var event := InputEventKey.new()
		event.physical_keycode = keys[index]
		InputMap.action_add_event(ACTIONS[index], event)
		if ACTIONS[index] == &"pause":
			var escape := InputEventKey.new()
			escape.physical_keycode = KEY_ESCAPE
			InputMap.action_add_event(ACTIONS[index], escape)


func key_name(index: int) -> String:
	return OS.get_keycode_string(keys[index])
