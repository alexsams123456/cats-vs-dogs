class_name GameLocalization
extends RefCounted
## Поддерживаемые языки; переводы загружает штатный TranslationServer.

const SUPPORTED_LOCALES: Array[String] = ["ru", "en", "zh_CN", "hi", "es", "fr", "ar", "pt", "bn", "ur", "id", "de", "ja"]
const LANGUAGE_NAMES: Array[String] = ["Русский", "English", "简体中文", "हिन्दी", "Español", "Français", "العربية", "Português", "বাংলা", "اردو", "Bahasa Indonesia", "Deutsch", "日本語"]


static func normalize_locale(value: String) -> String:
	var normalized := value.strip_edges().replace("-", "_").to_lower()
	var language := normalized.get_slice("_", 0)
	if language == "zh":
		return "zh_CN"
	if language in SUPPORTED_LOCALES:
		return language
	return "en"


static func apply_locale(value: String) -> String:
	var locale := normalize_locale(value)
	TranslationServer.set_locale(locale)
	return locale
