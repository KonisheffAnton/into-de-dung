extends RefCounted
class_name ProfileAchievements

const MAX_COUNT: int = 1000000000
var counters: Dictionary = {"victories":0, "without_losses":0, "expeditions":0}
var unlocked: Array[String] = []
var total_points: int = 0
var available_points: int = 0

static func definitions() -> Array[ProfileAchievementDefinition]:
	var result: Array[ProfileAchievementDefinition] = []
	for row: Array in [
		["first_victory", "Первая победа", "Победить в одном бою.", "victories", 1, 5],
		["without_losses", "Все вернулись", "Победить без гибели участников отряда.", "without_losses", 1, 5],
		["five_victories", "Опытный отряд", "Одержать пять побед.", "victories", 5, 10],
		["first_expedition", "До самого конца", "Завершить поход победой в финале.", "expeditions", 1, 20]]:
		var definition := ProfileAchievementDefinition.new()
		definition.id = row[0]; definition.title = row[1]; definition.description = row[2]
		definition.counter = row[3]; definition.goal = row[4]; definition.points = row[5]
		result.append(definition)
	return result

func count_for(id: String) -> int:
	for definition: ProfileAchievementDefinition in definitions():
		if definition.id == id: return int(counters[definition.counter])
	return 0

func record(victory: bool, without_losses: bool, completed: bool) -> Array[String]:
	var gained: Array[String] = []
	if not victory: return gained
	counters.victories = mini(MAX_COUNT, int(counters.victories) + 1)
	if without_losses: counters.without_losses = mini(MAX_COUNT, int(counters.without_losses) + 1)
	if completed: counters.expeditions = mini(MAX_COUNT, int(counters.expeditions) + 1)
	for definition: ProfileAchievementDefinition in definitions():
		if unlocked.has(definition.id) or int(counters[definition.counter]) < definition.goal: continue
		unlocked.append(definition.id); gained.append(definition.id)
		total_points += definition.points; available_points += definition.points
	return gained

func to_dict() -> Dictionary:
	return {"schema":1, "counters":counters.duplicate(true), "unlocked":unlocked.duplicate(), "total_points":total_points, "available_points":available_points}

static func from_dict(data: Variant) -> ProfileAchievements:
	if not ItemSimulationSnapshot._shape(data,{"schema":TYPE_INT,"counters":TYPE_DICTIONARY,"unlocked":TYPE_ARRAY,"total_points":TYPE_INT,"available_points":TYPE_INT}): return null
	if data.schema != 1 or not ItemSimulationSnapshot._shape(data.counters,{"victories":TYPE_INT,"without_losses":TYPE_INT,"expeditions":TYPE_INT}): return null
	for value: int in data.counters.values():
		if value < 0 or value > MAX_COUNT: return null
	if data.counters.without_losses > data.counters.victories or data.counters.expeditions > data.counters.victories: return null
	var result := ProfileAchievements.new()
	result.counters = data.counters.duplicate(true)
	var expected: Array[String] = []
	for definition: ProfileAchievementDefinition in definitions():
		if int(result.counters[definition.counter]) >= definition.goal:
			expected.append(definition.id); result.total_points += definition.points
	if data.unlocked.size() != expected.size(): return null
	for id: Variant in data.unlocked:
		if typeof(id) != TYPE_STRING or not expected.has(id) or result.unlocked.has(id): return null
		result.unlocked.append(id)
	# Расходов пока нет: неизвестные открытия мага не создают скрытый способ списания.
	if data.total_points != result.total_points or data.available_points != result.total_points: return null
	result.available_points = result.total_points
	return result
