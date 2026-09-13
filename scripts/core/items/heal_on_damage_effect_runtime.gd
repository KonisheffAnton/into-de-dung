extends ItemEffectRuntime
class_name HealOnDamageEffectRuntime

var _heal_amount: float
var _trigger_event: TriggeredEffect.TriggerEvent

func _init(owner_id: int, item_id: int, effect_id: int, effect_index: int, amount: float, trigger: TriggeredEffect.TriggerEvent) -> void:
	super(owner_id, item_id, effect_id, effect_index)
	_heal_amount = amount
	_trigger_event = trigger

func get_heal_amount() -> float: return _heal_amount
func get_trigger_event() -> TriggeredEffect.TriggerEvent: return _trigger_event
