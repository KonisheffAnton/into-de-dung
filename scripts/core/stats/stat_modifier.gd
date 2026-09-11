extends Resource
class_name StatModifier

## Модификатор характеристики от предмета/перка/статуса. Хранит источник
## (source_id), чтобы можно было снять все модификаторы конкретного
## предмета при его потере, без необходимости отдельно "запоминать",
## что именно он менял (Inventory/Equipment/Perks — Модуль 5).

## Стадия конвейера в Stat._recompute_value():
##     (base + Σ ADD_FLAT) * (1 + Σ ADD_PERCENT) * Π MULTIPLY
## ВАЖНО (R-4): значения enum попадают в сейвы/.tres — только append.
enum Operation {
	ADD_FLAT,     ## Слагаемое к базе: +2 STRENGTH
	ADD_PERCENT,  ## Доля от базы: value=0.2 => +20%
	MULTIPLY,     ## Множитель итога: value=1.5 => x1.5
}

## Идентификатор источника модификатора (ID предмета/перка/статуса).
## Используется для массового снятия модификаторов при потере источника.
@export var source_id: StringName = &""

@export var operation: Operation = Operation.ADD_FLAT
@export var value: float = 0.0


func _init(
	p_source_id: StringName = &"",
	p_operation: Operation = Operation.ADD_FLAT,
	p_value: float = 0.0
) -> void:
	source_id = p_source_id
	operation = p_operation
	value = p_value


## `priority` УДАЛЁН (D-4.1): при фиксированном конвейере стадий порядок
## применения задан формулой, а не полем, поэтому приоритет ничего не решал,
## но создавал иллюзию управляемости и делал результат зависимым от порядка
## добавления модификаторов (ломало воспроизводимость после загрузки сейва).


## --- Сериализация (R-4) ----------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"source_id": String(source_id),
		"operation": int(operation),
		"value": value,
	}


static func from_dict(data: Dictionary) -> StatModifier:
	var source_id_str: String = data.get("source_id", "")
	var operation_int: int = data.get("operation", int(Operation.ADD_FLAT))
	var value_float: float = data.get("value", 0.0)
	return StatModifier.new(StringName(source_id_str), operation_int as Operation, value_float)
