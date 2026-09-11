extends Label

## Демонстрация системы предметов и синергий: юнит получает 2 предмета
## (StatModifierEffect + TriggeredEffect), по клику ему наносится РЕАЛЬНЫЙ
## урон, и item_b реагирует лечением. Не финальная архитектура.
##
## ОБНОВЛЕНО ПОСЛЕ АУДИТА:
##  - урон теперь НАСТОЯЩИЙ (через Vitals), а не просто эмит события: раньше
##    панель эмитила `unit_damaged` вручную без вычитания HP, поэтому дефект
##    C-2 (порча base_value при уроне) физически не мог проявиться в демо —
##    именно так он и уехал в статус "Done";
##  - виден результат синергии: урон 4 -> лечение +1 -> итог -3 HP за клик;
##  - HP клампится по HP_MAX (раньше лечение уходило за максимум).

@export var item_a: Item
@export var item_b: Item

var _unit: UnitState
var _inventory: InventoryState
var _sink: EventSink
var _clicks: int = 0


func _ready() -> void:
	if item_a == null:
		item_a = load("res://resources/items/item_a_strength_boost.tres")
	if item_b == null:
		item_b = load("res://resources/items/item_b_heal_on_damage.tres")

	var stats := StatsBag.new()
	stats.set_base_value(StatTypes.StatType.HP_MAX, 10.0)
	stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)

	_unit = UnitState.create(Faction.Type.PLAYER, Vector2i.ZERO, stats, "ItemCarrier")
	_sink = GameEventBusSink.new()

	_inventory = InventoryState.new(_unit)
	_inventory.add_item(item_a)
	_inventory.add_item(item_b)

	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_refresh_text()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_clicks += 1
		_apply_debug_damage()
		_refresh_text()


## Наносит урон "от лица" фиктивного атакующего, чтобы пройти весь настоящий
## путь: DamageCalculator -> Vitals -> событие -> реакция item_b.
func _apply_debug_damage() -> void:
	if not _unit.is_alive():
		return

	var dummy_stats := StatsBag.new()
	dummy_stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	var dummy := UnitState.create(Faction.Type.ENEMY, Vector2i(-1, -1), dummy_stats, "DebugSource")

	var info := DamageCalculator.calculate(
		dummy, _unit,
		dummy.cell, _unit.cell,
		1.0, 0.0,
		GridDataProvider.new(), 1
	)
	DamageCalculator.apply(info, _sink)


func _refresh_text() -> void:
	var hp := _unit.vitals.get_hp()
	var hp_max := _unit.vitals.get_hp_max()
	var strength := _unit.get_stat(StatTypes.StatType.STRENGTH)
	var status := "ALIVE" if _unit.is_alive() else "DEAD"

	text = (
		"=== Items & Synergy Demo (click = take real damage) ===\n" +
		"HP: %.1f / %.1f   [%s]\n" % [hp, hp_max, status] +
		"STRENGTH: %.1f (base 3 + 2 from item_a)\n" % strength +
		"Clicks: %d\n" % _clicks +
		"Each click: -4 dmg (1 base + 3 STR), then item_b heals +1 => net -3.\n" +
		"item_a copies carried: %d" % _inventory.count_of(item_a.id)
	)
