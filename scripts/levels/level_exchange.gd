class_name LevelExchange
extends RefCounted
## Переносимые данные без путей, ресурсов и исполняемых объектов.

const FORMAT: String = "cats-vs-dogs-level"
const VERSION: int = 1
const PREFIX: String = "CVD1:"
const MAX_BYTES: int = 128 * 1024
const MAX_CODE_LENGTH: int = 192 * 1024
const EXTENSION: String = "cvdlevel"


static func document(level: LevelDefinition) -> String:
	if level == null or not level.is_valid():
		return ""
	var text := JSON.stringify({"format": FORMAT, "version": VERSION, "level": LevelData.to_dictionary(level)}, "", true, true)
	return text if text.to_utf8_buffer().size() <= MAX_BYTES else ""


static func encode(level: LevelDefinition) -> String:
	var text := document(level)
	if text.is_empty():
		return ""
	return PREFIX + Marshalls.raw_to_base64(text.to_utf8_buffer())


static func decode(code: String) -> LevelDefinition:
	if code.length() > MAX_CODE_LENGTH:
		return null
	var text := code.strip_edges()
	if not text.begins_with(PREFIX):
		return null
	var payload := text.substr(PREFIX.length()).replace("\n", "").replace("\r", "").replace(" ", "").replace("\t", "")
	if payload.is_empty() or payload.length() % 4 != 0:
		return null
	# Проверяем алфавит до декодирования: повреждённый ввод не пишет ошибки движка.
	var alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	var padding := 0
	for character in payload:
		if character == "=":
			padding += 1
		elif padding > 0 or not alphabet.contains(character):
			return null
	if padding > 2:
		return null
	var bytes := Marshalls.base64_to_raw(payload)
	return parse_document(bytes.get_string_from_utf8()) if bytes.size() <= MAX_BYTES and _is_utf8(bytes) else null


static func parse_document(text: String) -> LevelDefinition:
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return null
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return null
	var data: Dictionary = parser.data
	if not data.get("format") is String or not LevelData._is_integer(data.get("version")):
		return null
	if data.format != FORMAT or int(data.version) != VERSION or not data.get("level") is Dictionary:
		return null
	for key: Variant in data:
		if key not in ["format", "version", "level"]:
			return null
	var fields: Dictionary = data.level
	# Внешний файл не может назначать script, пути или произвольные свойства.
	for key: Variant in fields:
		if key not in ["title", "shots", "biome", "dog_positions", "block_positions", "weight_positions", "block_sizes", "block_materials", "dog_house_materials", "dog_house_types", "cat_sequence", "dog_kinds", "tutorial", "par_shots", "author_completion"]:
			return null
	return LevelData.from_dictionary(fields)


static func read_file(path: String) -> LevelDefinition:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	if file.get_length() > MAX_BYTES:
		file.close()
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return parse_document(bytes.get_string_from_utf8()) if _is_utf8(bytes) else null


static func write_file(level: LevelDefinition, path: String) -> Error:
	var text := document(level)
	if text.is_empty():
		return ERR_INVALID_DATA
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	return error


static func _is_utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var first: int = bytes[index]
		index += 1
		if first < 0x80:
			continue
		var count := 1 if first >= 0xc2 and first <= 0xdf else (2 if first >= 0xe0 and first <= 0xef else (3 if first >= 0xf0 and first <= 0xf4 else 0))
		if count == 0 or index + count > bytes.size():
			return false
		var codepoint: int = first & (0x7f >> (count + 1))
		for offset in count:
			var next: int = bytes[index + offset]
			if next < 0x80 or next > 0xbf:
				return false
			codepoint = (codepoint << 6) | (next & 0x3f)
		if codepoint < [0, 0x80, 0x800, 0x10000][count] or codepoint > 0x10ffff or (codepoint >= 0xd800 and codepoint <= 0xdfff):
			return false
		index += count
	return true
