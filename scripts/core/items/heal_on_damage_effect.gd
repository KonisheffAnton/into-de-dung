extends TriggeredEffect
class_name HealOnDamageEffect

## Определение лечения после получения урона. Core сохраняет только данные;
## временный debug-адаптер выполняет демонстрационную реакцию вне core.

@export var heal_amount: float = 1.0


func _init() -> void:
	trigger_event = TriggerEvent.UNIT_DAMAGED


func create_runtime(owner_id: int, item_id: int, effect_id: int, effect_index: int) -> ItemEffectRuntime:
	if cooldown_turns != 0: return null
	return HealOnDamageEffectRuntime.new(owner_id, item_id, effect_id, effect_index, heal_amount, trigger_event)
