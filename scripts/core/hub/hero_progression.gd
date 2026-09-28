extends RefCounted
class_name HeroProgression

const MAX_LEVEL: int = 10
const MAX_XP_TENTHS: int = 1000000000
const ATTRIBUTE_COUNT: int = 4

var id: int = 0
var class_id: StringName = &""
var name: String = ""
var base_attributes: Array[int] = []
var allocated: Array[int] = []
var perk: StringName = &""
var xp_tenths: int = 0
var hp_current: float = 0.0

func level() -> int:
	var remaining := xp_tenths
	var result := 1
	while result < MAX_LEVEL:
		var cost := result * 1000
		if remaining < cost:
			break
		remaining -= cost
		result += 1
	return result

func available_points() -> int:
	return level() - 1 - _sum(allocated)

func attributes() -> Array[int]:
	var result: Array[int] = []
	for index: int in ATTRIBUTE_COUNT:
		result.append(base_attributes[index] + allocated[index])
	if perk == &"force":
		result[0] += 1
	return result

func max_hp() -> int:
	var values := attributes()
	return 20 + 2 * values[2] + (4 if perk == &"hardy" else 0)

func balance_max() -> int:
	var values := attributes()
	return 10 + 2 * values[2] + (2 if perk == &"steady" else 0)

func move_max() -> float:
	var values := attributes()
	return float(3 + floori(float(values[1]) / 3.0) + (1 if perk == &"fleet" else 0))

func fire_resistance() -> int:
	return mini(50, 3 * attributes()[3])

func award_experience_tenths(amount: int) -> bool:
	if amount < 0 or xp_tenths > MAX_XP_TENTHS - amount:
		return false
	xp_tenths += amount
	return true

func apply_allocation(delta: Array[int]) -> bool:
	if delta.size() != ATTRIBUTE_COUNT or hp_current <= 0.0 or _sum(delta) <= 0 or _sum(delta) > available_points():
		return false
	var current := attributes()
	for index: int in ATTRIBUTE_COUNT:
		if delta[index] < 0 or current[index] + delta[index] > 40:
			return false
	for index: int in ATTRIBUTE_COUNT:
		allocated[index] += delta[index]
	# HP прибавляется только за реально вложенную Выносливость и не лечит сверх максимума.
	hp_current = minf(float(max_hp()), hp_current + 2.0 * float(delta[2]))
	return true

func reset_allocations() -> bool:
	if _sum(allocated) <= 0 or hp_current <= 0.0:
		return false
	allocated = [0, 0, 0, 0]
	hp_current = minf(hp_current, float(max_hp()))
	return true

func to_dict() -> Dictionary:
	return {
		"id": id,
		"class_id": String(class_id),
		"name": name,
		"base_attributes": base_attributes.duplicate(),
		"allocated": allocated.duplicate(),
		"perk": String(perk),
		"xp_tenths": xp_tenths,
		"hp_current": hp_current,
	}

static func from_dict(value: Variant) -> HeroProgression:
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var data: Dictionary = value
	if data.size() != 8:
		return null
	var allowed: Array[String] = ["id", "class_id", "name", "base_attributes", "allocated", "perk", "xp_tenths", "hp_current"]
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not String(key) in allowed:
			return null
	if typeof(data["id"]) != TYPE_INT or typeof(data["class_id"]) != TYPE_STRING or typeof(data["name"]) != TYPE_STRING or typeof(data["base_attributes"]) != TYPE_ARRAY or typeof(data["allocated"]) != TYPE_ARRAY or typeof(data["perk"]) != TYPE_STRING or typeof(data["xp_tenths"]) != TYPE_INT or typeof(data["hp_current"]) not in [TYPE_FLOAT, TYPE_INT]:
		return null
	var parsed_class := StringName(data["class_id"])
	var parsed_perk := StringName(data["perk"])
	if HeroCatalog.class_definition(parsed_class) == null or parsed_perk not in HeroCatalog.perk_ids():
		return null
	var base: Array[int] = []
	var alloc: Array[int] = []
	var raw_base: Array = data["base_attributes"]
	var raw_alloc: Array = data["allocated"]
	if raw_base.size() != ATTRIBUTE_COUNT or raw_alloc.size() != ATTRIBUTE_COUNT:
		return null
	for entry: Variant in raw_base:
		if typeof(entry) != TYPE_INT or entry < 1 or entry > 20:
			return null
		base.append(entry)
	for entry: Variant in raw_alloc:
		if typeof(entry) != TYPE_INT or entry < 0 or entry > 9:
			return null
		alloc.append(entry)
	var parsed_id: int = data["id"]
	var parsed_name: String = data["name"]
	var parsed_xp: int = data["xp_tenths"]
	var parsed_hp: float = float(data["hp_current"])
	if parsed_id < 1 or parsed_id > MAX_XP_TENTHS or parsed_name.length() < 1 or parsed_name.length() > 64 or parsed_xp < 0 or parsed_xp > MAX_XP_TENTHS or not is_finite(parsed_hp):
		return null
	var result := HeroProgression.new()
	result.id = parsed_id
	result.class_id = parsed_class
	result.name = parsed_name
	result.base_attributes = base
	result.allocated = alloc
	result.perk = parsed_perk
	result.xp_tenths = parsed_xp
	result.hp_current = parsed_hp
	if _sum(alloc) > result.level() - 1 or result.attributes().any(func(attribute: int) -> bool: return attribute > 40) or parsed_hp <= 0.0 or parsed_hp > float(result.max_hp()):
		return null
	return result

static func _sum(values: Array[int]) -> int:
	var total := 0
	for value: int in values:
		total += value
	return total
