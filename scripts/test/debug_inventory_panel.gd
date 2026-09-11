extends Label

## Демонстрация Модуля 5: создаёт тестового юнита с StatsComponent +
## InventoryComponent, выдаёт 2 предмета (StatModifierEffect + TriggeredEffect)
## и по клику эмитит unit_damaged через GameEventBus, показывая, что оба
## эффекта реагируют независимо друг от друга (синергия без прямой связи).
## Не является частью финальной архитектуры.

@export var item_a: Item
@export var item_b: Item

var _stats: StatsComponent
var _inventory: InventoryComponent
var _damage_tick: int = 0


func _ready() -> void:
	if item_a == null:
		item_a = load("res://resources/items/item_a_strength_boost.tres")
	if item_b == null:
		item_b = load("res://resources/items/item_b_heal_on_damage.tres")

	_stats = StatsComponent.new()
	add_child(_stats)
	_stats.set_base_value(StatTypes.StatType.HP, 10.0)
	_stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)

	_inventory = InventoryComponent.new()
	_inventory.owner_node = self
	_inventory.stats = _stats
	add_child(_inventory)

	_inventory.add_item(item_a)
	_inventory.add_item(item_b)

	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_refresh_text()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_damage_tick += 1
		GameEventBus.unit_damaged.emit(_stats, 2.0, "debug_click")
		_refresh_text()


func _refresh_text() -> void:
	var hp := _stats.get_value(StatTypes.StatType.HP)
	var strength := _stats.get_value(StatTypes.StatType.STRENGTH)
	text = (
		"=== Inventory & Synergy Demo (click = emit unit_damaged event) ===\n" +
		"HP: %.1f (base 10, +1 per click via item_b synergy)\n" % hp +
		"STRENGTH: %.1f (base 3 + 2 from item_a)\n" % strength +
		"Damage events emitted: %d\n" % _damage_tick +
		"(Note: actual damage subtraction is Module 6 - not built yet.\n" +
		"This demo only proves item_b's TriggeredEffect reacts to the event.)"
	)
