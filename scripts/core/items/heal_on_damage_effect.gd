extends TriggeredEffect
class_name HealOnDamageEffect

## Пример конкретного триггерного эффекта (синергия в стиле Isaac/Hades):
## "при получении урона восстановить N HP". Демонстрирует, как наследники
## TriggeredEffect добавляют только _on_triggered(), не занимаясь
## подпиской/жизненным циклом (это делает база).

@export var heal_amount: float = 1.0


func _init() -> void:
	trigger_event = TriggerEvent.UNIT_DAMAGED


func _on_triggered(_context: Dictionary) -> void:
	if _bound_stats == null:
		return
	var hp_stat := _bound_stats.get_stat(StatTypes.StatType.HP)
	hp_stat.set_base_value(hp_stat.get_value() + heal_amount)
	GameEventBus.unit_healed.emit(_bound_stats, heal_amount, self)
