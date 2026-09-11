extends ItemEffect
class_name TriggeredEffect

## Эффект-реакция на событие `GameEventBus` (синергии, перки в стиле
## Isaac/Hades). Подписывается при экипировке, отписывается при снятии.
## Наследники переопределяют только `_on_triggered()`. (Решение модуля 5.)
##
## ⚠️⚠️ ЭТОТ КЛАСС СОДЕРЖИТ ДЕФЕКТ C-3 И БУДЕТ ПЕРЕПИСАН НА ШАГЕ 0.8.
##
## СУТЬ ДЕФЕКТА (нарушение R-1). `Resource` кэшируется `ResourceLoader`, то
## есть один `.tres`-эффект — ОДИН объект на всю игру. Но `_bound_unit` —
## состояние КОНКРЕТНОГО владельца. Выдача одного предмета двум юнитам:
##   1) юнит A: `_bound_unit = A`, подписка;
##   2) юнит B: `_bound_unit = B` — ПЕРЕЗАТЁРЛО A, а повторный connect того
##      же Callable даёт hard error Godot;
##   3) A теряет предмет -> отписка снимает подписку и у B.
## Итог: система предметов работоспособна только при ОДНОМ экземпляре
## предмета в игре — для роглайка это блокер.
##
## ЧТО СДЕЛАНО СЕЙЧАС (временная мера, не исправление): добавлены проверки
## `is_connected` перед connect и явный `push_error` при попытке привязать
## эффект ко второму владельцу. Это превращает тихую порчу данных в громкую
## ошибку — чтобы дефект нельзя было случайно не заметить, пока не дошли до
## шага 0.8.
##
## ЦЕЛЕВАЯ МОДЕЛЬ: `TriggeredEffectDef : Resource` (какой сигнал, параметры)
## -> `TriggeredEffectRuntime : RefCounted` (своя подписка на каждого
## владельца), плюс реакции порождают `Command` в очередь вместо немедленной
## мутации состояния (дефект S-5: синхронная реентрантность).

enum TriggerEvent {
	UNIT_DAMAGED,
	UNIT_HEALED,
	UNIT_BALANCE_BROKEN,
	UNIT_DIED,
	TURN_STARTED,
	TURN_ENDED,
}

@export var trigger_event: TriggerEvent = TriggerEvent.UNIT_DAMAGED

## Заполняется владельцем `Item`. ⚠️ мутация разделяемого Resource (C-3).
var item_id: StringName = &""

## Владелец эффекта. Реакция срабатывает ТОЛЬКО на события своего владельца,
## события других юнитов игнорируются. (Сохранено.)
var _bound_unit: UnitState = null


func on_equip(unit: UnitState) -> void:
	if unit == null:
		return

	# Защита от дефекта C-3: громкая ошибка вместо тихого перезатирания.
	if _bound_unit != null and _bound_unit != unit:
		push_error(
			"TriggeredEffect '%s' уже привязан к юниту '%s' и не может быть выдан '%s'. " % [
				item_id, _bound_unit.debug_name, unit.debug_name
			]
			+ "Это дефект C-3 (состояние владельца внутри разделяемого Resource, нарушение R-1). "
			+ "До шага 0.8 давайте один .tres-предмет только ОДНОМУ юниту."
		)
		return

	_bound_unit = unit
	_connect_signal()


func on_unequip(_unit: UnitState) -> void:
	_disconnect_signal()
	_bound_unit = null


func _connect_signal() -> void:
	var target_signal := _signal_for_event()
	if target_signal == null:
		return
	# is_connected-проверка: повторный connect того же Callable в Godot 4 —
	# hard error, а не no-op.
	if not target_signal.is_connected(_on_event):
		target_signal.connect(_on_event)


func _disconnect_signal() -> void:
	var target_signal := _signal_for_event()
	if target_signal == null:
		return
	if target_signal.is_connected(_on_event):
		target_signal.disconnect(_on_event)


## Один обработчик на все типы событий: сигналы имеют разные сигнатуры,
## поэтому используется variadic-приём через массив аргументов. Это проще,
## чем шесть почти одинаковых методов, как было раньше.
func _signal_for_event() -> Signal:
	match trigger_event:
		TriggerEvent.UNIT_DAMAGED: return GameEventBus.unit_damaged
		TriggerEvent.UNIT_HEALED: return GameEventBus.unit_healed
		TriggerEvent.UNIT_BALANCE_BROKEN: return GameEventBus.unit_balance_broken
		TriggerEvent.UNIT_DIED: return GameEventBus.unit_died
		TriggerEvent.TURN_STARTED: return GameEventBus.turn_started
		TriggerEvent.TURN_ENDED: return GameEventBus.turn_ended
	return GameEventBus.unit_damaged


## Сигналы шины имеют разную арность, поэтому принимаем до трёх аргументов
## с дефолтами — Godot вызовет с тем количеством, которое объявлено в сигнале.
func _on_event(unit: UnitState, arg1: Variant = null, arg2: Variant = null) -> void:
	if unit == null or unit != _bound_unit:
		return
	_on_triggered({"amount": arg1, "source": arg2})


## Переопределяется в наследниках — конкретная реакция на триггер.
func _on_triggered(_context: Dictionary) -> void:
	pass # virtual
