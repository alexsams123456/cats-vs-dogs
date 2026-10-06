class_name PlayerProfile
extends RefCounted
## Локальный прогресс; JSON не загружает скрипты и ресурсы из сохранения.

const DEFAULT_PATH := "user://profile.json"

var path: String = DEFAULT_PATH
var cat_id: StringName = &"classic"
var dog_id: StringName = &"scout"
var sound_muted: bool = false
var music_volume: float = 1.0
var effects_volume: float = 1.0
var locale: String = "ru"
var results: Dictionary = {}
var rewards: PackedStringArray = PackedStringArray()
var desktop: DesktopPreferences = DesktopPreferences.new()
var last_error: Error = OK


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path


func load_data() -> void:
	cat_id = &"classic"
	dog_id = &"scout"
	sound_muted = false
	music_volume = 1.0
	effects_volume = 1.0
	locale = "ru"
	results.clear()
	rewards.clear()
	desktop = DesktopPreferences.new()
	if path.is_empty():
		return
	var data := _read(path)
	if data.is_empty():
		data = _read(path + ".bak")
	if data.is_empty():
		return
	var saved_cat := StringName(str(data.get("cat", "classic")))
	var saved_dog := StringName(str(data.get("dog", "scout")))
	cat_id = CharacterCatalog.find_cat(saved_cat).id
	dog_id = CharacterCatalog.find_dog(saved_dog).id
	sound_muted = data.get("muted", false) == true
	music_volume = _volume_from(data.get("music_volume", 1.0))
	effects_volume = _volume_from(data.get("effects_volume", 1.0))
	var saved_locale: Variant = data.get("locale", "ru")
	locale = GameLocalization.normalize_locale(saved_locale) if saved_locale is String else "ru"
	desktop.load_data(data.get("desktop", {}))
	var saved_rewards: Variant = data.get("rewards", [])
	if saved_rewards is Array:
		for reward: Variant in saved_rewards:
			if reward is String and reward in RewardCatalog.IDS and not rewards.has(reward):
				rewards.append(reward)
	var records: Variant = data.get("results", {})
	if not records is Dictionary:
		return
	for level_id: String in records:
		var entry: Variant = records[level_id]
		if not entry is Dictionary:
			continue
		var stars: Variant = entry.get("stars", 0)
		var shots: Variant = entry.get("shots", 0)
		if not (stars is float or stars is int) or not (shots is float or shots is int):
			continue
		if not is_finite(float(stars)) or not is_finite(float(shots)):
			continue
		if float(stars) != floorf(float(stars)) or float(shots) != floorf(float(shots)):
			continue
		if stars >= 1 and stars <= 3 and shots >= 0 and shots <= 20:
			results[level_id] = {"stars": int(stars), "shots": int(shots)}
	RewardCatalog.synchronize(self)


func stars_for(level_id: String) -> int:
	return int(results.get(level_id, {}).get("stars", 0))


func best_shots_for(level_id: String) -> int:
	return int(results.get(level_id, {}).get("shots", -1))


func record_win(level_id: String, shots: int, stars: int) -> Error:
	if level_id.is_empty() or shots < 0 or shots > 20 or stars < 1 or stars > 3:
		return ERR_INVALID_PARAMETER
	var previous := best_shots_for(level_id)
	results[level_id] = {
		"stars": maxi(stars, stars_for(level_id)),
		"shots": shots if previous < 0 else mini(shots, previous),
	}
	RewardCatalog.synchronize(self)
	return save_data()


func record_editor_win() -> Error:
	if not rewards.has("yard_author"):
		rewards.append("yard_author")
	return save_data()


func save_data() -> Error:
	last_error = OK
	if path.is_empty():
		return OK
	var data := {"version": 1, "cat": String(cat_id), "dog": String(dog_id), "muted": sound_muted, "music_volume": _volume_from(music_volume), "effects_volume": _volume_from(effects_volume), "locale": locale, "results": results, "rewards": rewards, "desktop": desktop.to_data()}
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = FileAccess.get_open_error()
		return last_error
	file.store_string(JSON.stringify(data))
	file.flush()
	last_error = file.get_error()
	file.close()
	if last_error != OK:
		return last_error
	# Keep the last valid file until its replacement has been written completely.
	if FileAccess.file_exists(path) and not _read(path).is_empty():
		last_error = DirAccess.copy_absolute(path, path + ".bak")
		if last_error != OK:
			return last_error
	last_error = DirAccess.rename_absolute(temporary, path)
	return last_error


func _volume_from(value: Variant) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), 0.0, 1.0)
	return 1.0


func _read(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var data: Variant = parser.data
	if not data is Dictionary or data.get("version", 0) != 1:
		return {}
	return data
