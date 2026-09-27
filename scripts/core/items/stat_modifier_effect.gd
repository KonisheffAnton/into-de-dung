extends ItemEffect
class_name StatModifierEffect

## Определение пассивного модификатора.

@export var stat_type: StatTypes.StatType = StatTypes.StatType.STRENGTH
@export var operation: StatModifier.Operation = StatModifier.Operation.ADD_FLAT
@export var value: float = 0.0

func create_runtime(owner_id: int, item_id: int, effect_id: int, effect_index: int) -> ItemEffectRuntime:
	if cooldown_turns != 0: return null
	return StatModifierEffectRuntime.new(owner_id, item_id, effect_id, effect_index, stat_type, operation, value)
