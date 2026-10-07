extends Resource
class_name HeroCatalog

static func class_ids(catalog_version: int = 1) -> Array[StringName]:
	match catalog_version:
		1: return [&"warrior", &"archer", &"rogue", &"mage"]
		2: return [&"shieldbearer", &"archer", &"rogue", &"mage"]
		_: return []

static func class_definition(id: StringName) -> HeroClassDefinition:
	var definition := HeroClassDefinition.new()
	definition.id = id
	match id:
		&"warrior":
			definition.display_name = "Воин"
			definition.base_attributes = [3, 2, 3, 1]
			definition.attack_range = 1
			definition.weapon_damage = 4
			definition.armor_max = 40
			definition.abilities_text = "Удар, оглушающий удар, реакционные стойки."
			definition.equipment_text = "Броня воина и оружие ближнего боя."
		&"shieldbearer":
			definition.display_name = "Щитоносец"
			definition.base_attributes = [3, 2, 3, 1]
			definition.attack_range = 1
			definition.weapon_damage = 4
			definition.armor_max = 40
			definition.abilities_text = "Оппортунист (пассивный); Поднять щиты: 90% первой атаки, 1 основное действие, перезарядка 1."
			definition.equipment_text = "Броня Щитоносца и оружие ближнего боя."
		&"archer":
			definition.display_name = "Стрелок"
			definition.base_attributes = [3, 3, 2, 1]
			definition.attack_range = 4
			definition.weapon_damage = 4
			definition.armor_max = 20
			definition.abilities_text = "Дальний выстрел, опутывающий выстрел."
			definition.equipment_text = "Лёгкая броня и дальнобойное оружие."
		&"rogue":
			definition.display_name = "Разбойник"
			definition.base_attributes = [3, 3, 2, 1]
			definition.attack_range = 1
			definition.weapon_damage = 3
			definition.armor_max = 25
			definition.abilities_text = "Пробивание, скрытая атака, общий отход."
			definition.equipment_text = "Лёгкая броня и оружие для быстрых атак."
		&"mage":
			definition.display_name = "Маг"
			definition.base_attributes = [3, 2, 2, 2]
			definition.attack_range = 3
			definition.weapon_damage = 4
			definition.armor_max = 15
			definition.abilities_text = "Огненный удар, поджечь, облить, заморозить."
			definition.equipment_text = "Мантия мага и магическое оружие."
		_:
			return null
	return definition

static func perk_ids() -> Array[StringName]:
	return [&"hardy", &"steady", &"fleet", &"force"]

static func perk_text(id: StringName) -> String:
	match id:
		&"hardy": return "Закалённый: +4 к максимуму HP."
		&"steady": return "Устойчивый: +2 к порогу равновесия."
		&"fleet": return "Проворный: +1 к движению."
		&"force": return "Сильный: +1 к Мощи."
		_: return ""

static func make_hero(id: int, class_id: StringName, rng: RandomNumberGenerator) -> HeroProgression:
	var definition := class_definition(class_id)
	if definition == null or rng == null or id < 1 or id > HeroProgression.MAX_XP_TENTHS:
		return null
	var hero := HeroProgression.new()
	hero.id = id
	hero.class_id = class_id
	hero.name = "%s %d" % [definition.display_name, id]
	hero.base_attributes = definition.base_attributes.duplicate()
	hero.allocated = [0, 0, 0, 0]
	hero.perk = perk_ids()[rng.randi_range(0, 3)]
	# Число стартовых очков и их раскладка задаются одним внедрённым RNG для повторяемости профиля.
	var bonus_points := rng.randi_range(0, 2)
	for index: int in bonus_points:
		hero.base_attributes[rng.randi_range(0, 3)] += 1
	hero.hp_current = float(hero.max_hp())
	return hero
