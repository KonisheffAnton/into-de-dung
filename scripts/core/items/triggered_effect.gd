extends ItemEffect
class_name TriggeredEffect

## Эффект-реакция на событие GameEventBus (синергии, перки в стиле Isaac/
## Hades). Подписывается на выбранный сигнал при экипировке, отписывается
## при снятии. Конкретное действие-реакция переопределяется в наследниках
## через _on_triggered(), базовый класс отвечает только за подписку/жизненный
## цикл — большинство "триггерных" предметов будет наследоваться от этого
## класса и переопределять только _on_triggered().

enum TriggerEvent {
	UNIT_DAMAGED,
	UNIT_HEALED,
	UNIT_BALANCE_BROKEN,
	TURN_STARTED,
	TURN_ENDED,
}

@export var trigger_event: TriggerEvent = TriggerEvent.UNIT_DAMAGED

## Заполняется владельцем Item (см. StatModifierEffect) — используется
## наследниками для идентификации источника вторичных эффектов (например
## HoT/лечения), если потребуется.
var item_id: StringName = &""

## Кэшируем владельца/статы на время действия подписки, чтобы обработчик
## сигнала знал, реагировать ли (эффект должен реагировать только на
## СВОЕГО владельца, а не на любой юнит в игре).
var _bound_owner: Node
var _bound_stats: StatsComponent


func on_equip(owner: Node, stats: StatsComponent) -> void:
	_bound_owner = owner
	_bound_stats = stats
	_connect_signal()


func on_unequip(_owner: Node, _stats: StatsComponent) -> void:
	_disconnect_signal()
	_bound_owner = null
	_bound_stats = null


func _connect_signal() -> void:
	match trigger_event:
		TriggerEvent.UNIT_DAMAGED:
			GameEventBus.unit_damaged.connect(_on_unit_damaged)
		TriggerEvent.UNIT_HEALED:
			GameEventBus.unit_healed.connect(_on_unit_healed)
		TriggerEvent.UNIT_BALANCE_BROKEN:
			GameEventBus.unit_balance_broken.connect(_on_unit_balance_broken)
		TriggerEvent.TURN_STARTED:
			GameEventBus.turn_started.connect(_on_turn_started)
		TriggerEvent.TURN_ENDED:
			GameEventBus.turn_ended.connect(_on_turn_ended)


func _disconnect_signal() -> void:
	match trigger_event:
		TriggerEvent.UNIT_DAMAGED:
			if GameEventBus.unit_damaged.is_connected(_on_unit_damaged):
				GameEventBus.unit_damaged.disconnect(_on_unit_damaged)
		TriggerEvent.UNIT_HEALED:
			if GameEventBus.unit_healed.is_connected(_on_unit_healed):
				GameEventBus.unit_healed.disconnect(_on_unit_healed)
		TriggerEvent.UNIT_BALANCE_BROKEN:
			if GameEventBus.unit_balance_broken.is_connected(_on_unit_balance_broken):
				GameEventBus.unit_balance_broken.disconnect(_on_unit_balance_broken)
		TriggerEvent.TURN_STARTED:
			if GameEventBus.turn_started.is_connected(_on_turn_started):
				GameEventBus.turn_started.disconnect(_on_turn_started)
		TriggerEvent.TURN_ENDED:
			if GameEventBus.turn_ended.is_connected(_on_turn_ended):
				GameEventBus.turn_ended.disconnect(_on_turn_ended)


func _on_unit_damaged(unit: StatsComponent, amount: float, source: Variant) -> void:
	if unit != _bound_stats:
		return
	_on_triggered({"amount": amount, "source": source})


func _on_unit_healed(unit: StatsComponent, amount: float, source: Variant) -> void:
	if unit != _bound_stats:
		return
	_on_triggered({"amount": amount, "source": source})


func _on_unit_balance_broken(unit: StatsComponent) -> void:
	if unit != _bound_stats:
		return
	_on_triggered({})


func _on_turn_started(unit: StatsComponent) -> void:
	if unit != _bound_stats:
		return
	_on_triggered({})


func _on_turn_ended(unit: StatsComponent) -> void:
	if unit != _bound_stats:
		return
	_on_triggered({})


## Переопределяется в наследниках — конкретная реакция на триггер.
## context — Dictionary с деталями события (например "amount", "source").
func _on_triggered(_context: Dictionary) -> void:
	pass # virtual
