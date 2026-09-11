extends Resource
class_name StatModifier

## Модификатор характеристики от предмета/перка/статуса. Хранит источник
## (source_id), чтобы можно было снять все модификаторы конкретного
## предмета при его потере, без необходимости отдельно "запоминать",
## что именно он менял (Inventory/Equipment/Perks — Модуль 5).

enum Operation {
	ADD_FLAT,     ## base + value
	ADD_PERCENT,  ## base + base * value (value=0.2 => +20%)
	MULTIPLY,     ## base * value
}

## Идентификатор источника модификатора (например ID предмета/перка/статуса).
## Используется для массового снятия модификаторов при потере источника.
@export var source_id: StringName = &""

@export var operation: Operation = Operation.ADD_FLAT
@export var value: float = 0.0

## Приоритет применения при нескольких модификаторах одного stat'а.
## Меньшее значение применяется раньше. ADD_FLAT обычно применяют первыми,
## затем ADD_PERCENT, затем MULTIPLY — см. Stat._recompute_value().
@export var priority: int = 0


func _init(
	p_source_id: StringName = &"",
	p_operation: Operation = Operation.ADD_FLAT,
	p_value: float = 0.0,
	p_priority: int = 0
) -> void:
	source_id = p_source_id
	operation = p_operation
	value = p_value
	priority = p_priority
