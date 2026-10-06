class_name RewardCatalog
extends RefCounted
## Постоянные значки; условия кампании вычисляются по лучшим результатам.

const IDS: Array[String] = ["first_win", "three_stars", "one_shot", "star_collector", "chapter_0", "chapter_1", "chapter_2", "chapter_3", "campaign_complete", "perfect_campaign", "yard_author", "chapter_4", "chapter_5", "chapter_6", "chapter_7"]
const TITLES: Array[String] = ["Первая победа", "Три звезды", "Один бросок", "Созвездие", "За домом", "Горные тропы", "Ледяная долина", "Цепные реакции", "Большое приключение", "Звёздный мастер", "Испытатель двора", "Обходные пути", "Верхний удар", "Холодный фронт", "Общий сбор"]
const DETAILS: Array[String] = ["Победи в уровне кампании.", "Получи три звезды в уровне кампании.", "Пройди уровень кампании за один бросок.", "Собери 12 звёзд кампании.", "Пройди главу «За домом».", "Пройди главу «Горные тропы».", "Пройди главу «Ледяная долина».", "Пройди главу «Цепные реакции».", "Пройди все уровни кампании.", "Получи три звезды на каждом уровне кампании.", "Победи в пробном бою из редактора.", "Пройди главу «Обходные пути».", "Пройди главу «Верхний удар».", "Пройди главу «Холодный фронт».", "Пройди главу «Общий сбор»."]
const ICONS: Array[StringName] = [&"paw", &"star", &"play", &"star", &"map", &"map", &"map", &"tools", &"trophy", &"trophy", &"tools", &"map", &"map", &"map", &"map"]


static func progress(index: int, profile: PlayerProfile) -> Vector2i:
	var completed: int = 0
	var perfect: int = 0
	var single: int = 0
	for level_id in CampaignCatalog.IDS:
		if profile.stars_for(level_id) > 0:
			completed += 1
			if profile.best_shots_for(level_id) == 1:
				single += 1
		if profile.stars_for(level_id) == 3:
			perfect += 1
	match index:
		0: return Vector2i(mini(completed, 1), 1)
		1: return Vector2i(mini(perfect, 1), 1)
		2: return Vector2i(mini(single, 1), 1)
		3: return Vector2i(mini(CampaignCatalog.total_stars(profile), 12), 12)
		4, 5, 6, 7, 11, 12, 13, 14:
			var chapter := index - 4 if index < 8 else index - 7
			var count: int = 0
			for level_index in range(CampaignCatalog.CHAPTER_STARTS[chapter], CampaignCatalog.CHAPTER_STARTS[chapter + 1]):
				if profile.stars_for(CampaignCatalog.IDS[level_index]) > 0:
					count += 1
			return Vector2i(count, CampaignCatalog.CHAPTER_STARTS[chapter + 1] - CampaignCatalog.CHAPTER_STARTS[chapter])
		8: return Vector2i(completed, CampaignCatalog.IDS.size())
		9: return Vector2i(perfect, CampaignCatalog.IDS.size())
		10: return Vector2i(1 if profile.rewards.has("yard_author") else 0, 1)
	return Vector2i(0, 1)


static func synchronize(profile: PlayerProfile) -> PackedStringArray:
	var unlocked := PackedStringArray()
	for index in IDS.size():
		if IDS[index] == "yard_author":
			continue
		var value := progress(index, profile)
		if value.x >= value.y and not profile.rewards.has(IDS[index]):
			profile.rewards.append(IDS[index])
			unlocked.append(IDS[index])
	return unlocked
