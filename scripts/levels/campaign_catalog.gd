class_name CampaignCatalog
extends RefCounted

const IDS: Array[String] = ["first_throw", "air_trick", "little_shelter", "glass_bridge", "restless_yard", "last_fort", "falling_gallery", "double_drop", "weight_cascade", "open_passage", "wind_stairs", "glass_garden", "stone_gate", "magnetic_roof", "high_watch", "frozen_patrol", "shield_line", "ice_roofs", "three_shelters", "last_outpost"]
const CHAPTER_STARTS: Array[int] = [0, 2, 4, 6, 9, 12, 15, 18, 20]
const CHAPTER_BIOMES: Array[StringName] = [&"backyard", &"mountain", &"glacier", &"backyard", &"backyard", &"mountain", &"glacier", &"backyard"]
const CHAPTER_TITLES: Array[String] = ["За домом", "Горные тропы", "Ледяная долина", "Цепные реакции", "Обходные пути", "Верхний удар", "Холодный фронт", "Общий сбор"]
const CHAPTER_DETAILS: Array[String] = ["Дерево и стекло", "Каменные опоры", "Металлические крепости", "Верёвки, грузы и обвалы", "Проходы и широкие атаки", "Крыши и высокий дозор", "Прыгуны, щиты и лёд", "Укрытия и смешанные отряды"]
const CHAPTER_COLORS: Array[Color] = [Color("397858"), Color("876344"), Color("3d7195"), Color("91652c"), Color("397858"), Color("876344"), Color("3d7195"), Color("91652c")]
const CHAPTER_TINTS: Array[Color] = [Color("e2ecd4"), Color("eee0ca"), Color("deeff5"), Color("f3e6c8"), Color("e2ecd4"), Color("eee0ca"), Color("deeff5"), Color("f3e6c8")]
const LEVELS: Array[LevelDefinition] = [
	preload("res://levels/campaign/01_first_throw.tres"),
	preload("res://levels/campaign/02_air_trick.tres"),
	preload("res://levels/campaign/03_little_shelter.tres"),
	preload("res://levels/campaign/04_glass_bridge.tres"),
	preload("res://levels/campaign/05_restless_yard.tres"),
	preload("res://levels/campaign/06_last_fort.tres"),
	preload("res://levels/campaign/07_falling_gallery.tres"),
	preload("res://levels/campaign/08_double_drop.tres"),
	preload("res://levels/campaign/09_weight_cascade.tres"),
	preload("res://levels/campaign/10_open_passage.tres"),
	preload("res://levels/campaign/11_wind_stairs.tres"),
	preload("res://levels/campaign/12_glass_garden.tres"),
	preload("res://levels/campaign/13_stone_gate.tres"),
	preload("res://levels/campaign/14_magnetic_roof.tres"),
	preload("res://levels/campaign/15_high_watch.tres"),
	preload("res://levels/campaign/16_frozen_patrol.tres"),
	preload("res://levels/campaign/17_shield_line.tres"),
	preload("res://levels/campaign/18_ice_roofs.tres"),
	preload("res://levels/campaign/19_three_shelters.tres"),
	preload("res://levels/campaign/20_last_outpost.tres"),
]
const NOTES: Array[String] = [
	"Целься в деревянные опоры, чтобы обрушить постройку.",
	"Раздели Тройку в полёте и разбей галерею.",
	"Разрушь опоры и укрытия горной башни.",
	"Расшатай опоры Магнитом и обрушь стеклянный мост.",
	"Заморозь прыгунов перед попаданием Снежка.",
	"Разные укрытия и защитники. Используй весь отряд.",
	"Перережь верёвку: груз пробьёт два этажа галереи.",
	"Рывок вдоль верёвок уронит грузы на обе конуры.",
	"Сбей верхний груз: он освободит нижний и запустит обвал.",
	"Проведи Тень сквозь опоры к ближней цели.",
	"Подними Ветерком ближнюю арку, затем атакуй верхнюю площадку.",
	"Раздели Тройку перед стеклянными опорами трёх павильонов.",
	"Ударь Валуном сверху: стеклянный пролёт слабее каменных стоек.",
	"Подтяни Магнитом тяжёлые перекрытия и расшатай деревянные опоры.",
	"Сначала обрушь верхний дозор, затем разбери нижние укрытия.",
	"Заморозь ближнего прыгуна перед ударом; дальнего прикрывает навес.",
	"Взрыв снимает щиты; следующий удар поражает защитников.",
	"Выбирай хрупкую крышу вместо прочных стоек.",
	"Разбей ближнюю бочку, пройди под навесом и доберись до дальнего иглу.",
	"Раздели удар между щитом, верхним дозором и подвижной дальней целью.",
]


static func is_unlocked(index: int, profile: PlayerProfile) -> bool:
	if index < 0 or index >= LEVELS.size():
		return false
	return index == 0 or profile.stars_for(IDS[index - 1]) > 0


static func chapter_for_level(index: int) -> int:
	for chapter in range(CHAPTER_TITLES.size() - 1, -1, -1):
		if index >= CHAPTER_STARTS[chapter]:
			return chapter
	return 0


static func total_stars(profile: PlayerProfile) -> int:
	var total := 0
	for level_id in IDS:
		total += profile.stars_for(level_id)
	return total
