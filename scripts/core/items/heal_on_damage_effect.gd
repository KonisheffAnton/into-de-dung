extends TriggeredEffect
class_name HealOnDamageEffect

## Пример конкретного триггерного эффекта (синергия в стиле Isaac/Hades):
## "при получении урона восстановить N HP". Демонстрирует, как наследники
## добавляют только `_on_triggered()`, не занимаясь подпиской (это делает
## база). (Сохранено.)
##
## ИСПРАВЛЕНО (C-2). Раньше было:
##     hp_stat.set_base_value(hp_stat.get_value() + heal_amount)
## то есть лечение писалось в БАЗУ стата вместе с модификаторами, наращивая
## её при каждом срабатывании, и не клампилось по HP_MAX (можно было
## вылечиться выше максимума). Теперь через `Vitals.heal()`: кламп есть,
## а база характеристик неприкосновенна (R-2).

@export var heal_amount: float = 1.0


func _init() -> void:
	trigger_event = TriggerEvent.UNIT_DAMAGED


func _on_triggered(_context: Dictionary) -> void:
	if _bound_unit == null or _bound_unit.vitals == null:
		return

	# heal() возвращает ФАКТИЧЕСКИ вылеченное количество (0.0 при полном HP),
	# поэтому событие не эмитится там, где ничего не произошло.
	var healed := _bound_unit.vitals.heal(heal_amount)
	if healed <= 0.0:
		return

	# ⚠️ Прямое обращение к автозагрузке нарушает R-3. Здесь это осознанно
	# оставлено до шага 0.8: эффекты получат инжектированный `EffectContext`
	# со своим `EventSink`. Сейчас у ItemEffect нет канала для инжекции.
	GameEventBus.unit_healed.emit(_bound_unit, healed, self)
