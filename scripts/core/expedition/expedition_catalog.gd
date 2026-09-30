class_name ExpeditionCatalog
extends RefCounted

# Менять версию при изменении семантики; value-манифест также ловит правки чисел без bump.
const CONTENT_VERSION: int = 1
const SPARK_DAMAGE: int = 2
const HARVEST_HEAL: int = 4
const FORMATION_REPAIR: int = 4
const CACHE_GOLD: int = 40
const RICH_CACHE_GOLD: int = 80
const SERVICE_PERCENT: int = 25
const BOOSTED_SERVICE_PERCENT: int = 50
const COPY_ESSENCE: int = 10
const FINAL_ESSENCE: int = 10
const FINAL_GOLD: int = 100
const SPIKE_DAMAGE: int = 8

static func artifact_ids() -> Array[String]:
	return ["spark", "blood", "ember", "ice", "formation", "harvest"]

static func artifact(id: String) -> ExpeditionArtifactDefinition:
	var definitions: Dictionary = {
		"spark": ["Искра", "+2 огненного урона обычной атаке за копию, кроме мага. До 3 постоянных стаков; объединённые копии нельзя разделить.", 3],
		"blood": ["Кровавая руна", "Обычная атака с физическим уроном HP даёт 1 стак кровотечения. Иммунитет и горение препятствуют наложению.", 1],
		"ember": ["Угольная печать", "Обычная атака с огненным уроном HP пытается дать 1 стак поджога и +1 тик. Мокрый гасит попытку; поджог снимает кровотечение.", 1],
		"ice": ["Ледяная игла", "Обычная атака замораживает мокрую цель или продлевает заморозку на 1 тик, если броня до удара ниже 50%. Иммунитет сохраняется.", 1],
		"formation": ["Печать строя", "После тиков в начале своего командного хода: ремонт 4 брони при соседнем постоянном союзнике на том же уровне, до максимума.", 1],
		"harvest": ["Печать жатвы", "Прямое убийство обычной атакой лечит живому владельцу 4 HP. Маг, падение, тики, реакции и заклинания не учитываются.", 1]
	}
	if not definitions.has(id):
		return null
	var values: Array = definitions[id]
	var result := ExpeditionArtifactDefinition.new()
	result.id = id
	result.version = 1
	result.title = values[0]
	result.description = values[1]
	result.max_stacks = values[2]
	return result

static func room(kind: String) -> ExpeditionRoomDefinition:
	var definitions: Dictionary = {
		"battle": ["Обычный бой", 100, 40],
		"rest": ["Привал", 0, 0],
		"cache": ["Тайник", 0, 0],
		"elite": ["Усиленный бой", 150, 60],
		"camp": ["Безопасная точка", 0, 0],
		"final": ["Финальный бой", 200, 80]
	}
	if not definitions.has(kind):
		return null
	var values: Array = definitions[kind]
	var result := ExpeditionRoomDefinition.new()
	result.id = kind
	result.version = 1
	result.title = values[0]
	result.xp = values[1]
	result.gold = values[2]
	return result

static func artifact_name(id: String) -> String:
	var definition := artifact(id)
	return "" if definition == null else definition.title

static func room_name(kind: String) -> String:
	var definition := room(kind)
	return "" if definition == null else definition.title

static func encounter(kind: String, variant: int) -> ExpeditionEncounterDefinition:
	var result := ExpeditionEncounterDefinition.new()
	result.kind = kind; result.variant = variant
	result.enemy_hp = 24 if kind == "battle" else 30 if kind == "elite" else 36
	result.enemy_strength = 3 if kind == "battle" else 4
	for index: int in (3 if kind == "battle" else 4):
		result.enemy_cells.append(Vector2i(5 + index % 2,1 + index * 2) if variant == 1 else Vector2i(6 - index % 2,index * 3) if variant == 2 else Vector2i(6,1 + index * 2))
	return result if result.valid() else null

static func content_values() -> Dictionary:
	var rooms: Array[Dictionary] = []
	for kind: String in ["battle", "elite", "final", "rest", "camp", "cache"]:
		var value := room(kind)
		rooms.append({"id":value.id,"version":value.version,"title":value.title,"xp":value.xp,"gold":value.gold})
	var artifacts: Array[Dictionary] = []
	for id: String in artifact_ids():
		var value := artifact(id)
		artifacts.append({"id":id,"version":value.version,"title":value.title,"description":value.description,"max_stacks":value.max_stacks})
	var encounters: Array[Dictionary] = []
	for kind: String in ["battle", "elite", "final"]:
		for variant: int in (3 if kind == "battle" else 2): encounters.append(encounter(kind,variant).to_values())
	return {"version":CONTENT_VERSION,"rooms":rooms,"artifacts":artifacts,"encounters":encounters,
		"rules":{"spark_damage":SPARK_DAMAGE,"harvest_heal":HARVEST_HEAL,"formation_repair":FORMATION_REPAIR,
		"cache_gold":CACHE_GOLD,"rich_cache_gold":RICH_CACHE_GOLD,"service_percent":SERVICE_PERCENT,
		"boosted_service_percent":BOOSTED_SERVICE_PERCENT,"copy_essence":COPY_ESSENCE,
		"final_essence":FINAL_ESSENCE,"final_gold":FINAL_GOLD,"spike_damage":SPIKE_DAMAGE}}

static func matches_content(value: Variant) -> bool:
	return _same_values(value, content_values())

static func _same_values(value: Variant, expected: Variant) -> bool:
	if typeof(value) != typeof(expected): return false
	if value is Dictionary:
		if value.size() != expected.size(): return false
		for key: Variant in expected:
			if not value.has(key) or not _same_values(value[key],expected[key]): return false
		return true
	if value is Array:
		if value.size() != expected.size(): return false
		for index: int in value.size():
			if not _same_values(value[index],expected[index]): return false
		return true
	return value == expected
