class_name CampaignCatalog
extends RefCounted

const IDS: Array[String] = ["first_throw", "air_trick", "little_shelter", "glass_bridge", "restless_yard", "last_fort"]
const CHAPTER_BIOMES: Array[StringName] = [&"backyard", &"mountain", &"glacier"]
const CHAPTER_TITLES: Array[String] = ["За домом", "Горные тропы", "Ледяная долина"]
const CHAPTER_DETAILS: Array[String] = ["Дерево и стекло", "Каменные опоры", "Металлические крепости"]
const CHAPTER_COLORS: Array[Color] = [Color("397858"), Color("876344"), Color("3d7195")]
const CHAPTER_TINTS: Array[Color] = [Color("e2ecd4"), Color("eee0ca"), Color("deeff5")]
const LEVELS: Array[LevelDefinition] = [
	preload("res://levels/campaign/01_first_throw.tres"),
	preload("res://levels/campaign/02_air_trick.tres"),
	preload("res://levels/campaign/03_little_shelter.tres"),
	preload("res://levels/campaign/04_glass_bridge.tres"),
	preload("res://levels/campaign/05_restless_yard.tres"),
	preload("res://levels/campaign/06_last_fort.tres"),
]
const NOTES: Array[String] = [
	"Целься в деревянные опоры, чтобы обрушить постройку.",
	"Раздели Тройку в полёте и разбей галерею.",
	"Разрушь опоры и укрытия горной башни.",
	"Расшатай опоры Магнитом и обрушь стеклянный мост.",
	"Заморозь прыгунов перед попаданием Снежка.",
	"Разные укрытия и защитники. Используй весь отряд.",
]


static func is_unlocked(index: int, profile: PlayerProfile) -> bool:
	if index < 0 or index >= LEVELS.size():
		return false
	return index == 0 or profile.stars_for(IDS[index - 1]) > 0


static func chapter_for_level(index: int) -> int:
	return clampi(index / 2, 0, CHAPTER_TITLES.size() - 1)


static func total_stars(profile: PlayerProfile) -> int:
	var total := 0
	for level_id in IDS:
		total += profile.stars_for(level_id)
	return total
