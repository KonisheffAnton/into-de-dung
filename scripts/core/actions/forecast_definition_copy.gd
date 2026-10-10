extends RefCounted
class_name ForecastDefinitionCopy

const MAX_DEPTH: int = 32
const MAX_VISITS: int = 50000

class Result extends RefCounted:
	var reason: StringName = &""
	var definitions: Dictionary = {}

## Вызывать сразу после успешного capture: формы/поля уже проверены, metadata
## не входит в DTO и требует отдельной границы перед глубоким копированием.
static func copy_catalog(state: ItemSimulationState) -> Result:
	var result := Result.new()
	if state == null:
		result.reason = &"preview/unsupported_definition_metadata"
		return result
	var roots: Array[Resource] = []
	var budget := {"visits": 0}
	for owner: ItemOwnerState in state.get_owners():
		if owner == null:
			return _rejected()
		for key: Variant in owner._definitions:
			var candidate: Variant = owner._definitions[key]
			if typeof(key) != TYPE_STRING_NAME or not (candidate is ItemDef): return _rejected()
			var definition := candidate as ItemDef
			if definition.get_script() not in [ItemDef, Item]: return _rejected()
			roots.append(definition)
			for effect: ItemEffect in definition.effects:
				if effect == null or (effect.get_script() != StatModifierEffect and effect.get_script() != HealOnDamageEffect): return _rejected()
				roots.append(effect)
			if definition.summon_definition != null:
				if definition.summon_definition.get_script() != SummonDefinition: return _rejected()
				roots.append(definition.summon_definition)
	# Проверяем каждый экземпляр до копирования: повторяющийся id не должен скрыть
	# неподдерживаемые данные предыдущего владельца.
	for root: Resource in roots:
		if not _metadata_safe(root, budget): return _rejected()
	for owner: ItemOwnerState in state.get_owners():
		for id: StringName in owner._definitions:
			var definition := owner._definitions[id] as ItemDef
			result.definitions[id] = definition.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as ItemDef
	return result

static func _rejected() -> Result:
	var result := Result.new()
	result.reason = &"preview/unsupported_definition_metadata"
	return result

static func _metadata_safe(root: Resource, budget: Dictionary) -> bool:
	var active: Array = []
	for meta_key: StringName in root.get_meta_list():
		if not _walk(meta_key, 0, active, budget) or not _walk(root.get_meta(meta_key), 0, active, budget): return false
	return true

static func _walk(value: Variant, depth: int, active: Array, budget: Dictionary) -> bool:
	budget["visits"] = int(budget["visits"]) + 1
	if int(budget["visits"]) > MAX_VISITS or depth > MAX_DEPTH: return false
	var kind: int = typeof(value)
	if kind == TYPE_OBJECT or kind == TYPE_CALLABLE or kind == TYPE_SIGNAL or kind == TYPE_RID: return false
	if kind == TYPE_ARRAY:
		var array_value: Array = value
		for container: Variant in active:
			if is_same(container, array_value): return false
		active.append(array_value)
		for child: Variant in array_value:
			if not _walk(child, depth + 1, active, budget): return false
		active.pop_back()
	elif kind == TYPE_DICTIONARY:
		var dictionary_value: Dictionary = value
		for container: Variant in active:
			if is_same(container, dictionary_value): return false
		active.append(dictionary_value)
		for key: Variant in dictionary_value:
			if not _walk(key, depth + 1, active, budget) or not _walk(dictionary_value[key], depth + 1, active, budget): return false
		active.pop_back()
	return true
