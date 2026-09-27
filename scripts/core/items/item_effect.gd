extends Resource
class_name ItemEffect

@export var cooldown_turns: int = 0

func get_ability_definition(item_id: StringName, effect_index: int) -> AbilityDefinition:
	if cooldown_turns != 0 or item_id == &"" or effect_index < 0: return null
	var result := AbilityDefinition.new()
	result.ability_id = StringName("item_effect:%s:%d" % [String(item_id), effect_index])
	return result

## Определение эффекта. Runtime создаётся владельцем, поэтому Resource остаётся
## неизменяемым и безопасно разделяется между предметами.
func create_runtime(owner_id: int, item_id: int, effect_id: int, effect_index: int) -> ItemEffectRuntime:
	if cooldown_turns != 0: return null
	return null
