extends RefCounted
class_name MageCardCatalog

const CATALOG_ID: String = "mage-neutral-v1"
const VERSION: int = 1
const IDS: Array[String] = ["card.bleeding","card.burning","card.fire","card.fire_imbue","card.freeze","card.heal","card.raise","card.roots","card.shield","card.stun","card.summon","card.wet"]
const DEFAULT_TYPES: Array[String] = ["card.fire","card.fire","card.heal","card.heal","card.shield","card.shield","card.summon","card.summon","card.wet","card.wet"]

const PRESENTATION: Dictionary = {
	"card.fire": ["Огненный импульс", "Наносит 4 ед. огненного урона одной живой вражеской цели. Мана: 2."],
	"card.heal": ["Лечение", "Восстанавливает союзнику 4 HP, если он ранен. Мана: 1."],
	"card.shield": ["Щит", "Поглощает один положительный пакет урона объёмом до 6 HP. Мана: 1."],
	"card.summon": ["Призыв", "Призывает помощника на допустимую свободную клетку. Мана: 1."],
	"card.raise": ["Поднятие", "Расходует humanoid-тело и призывает помощника. Мана: 1."],
	"card.burning": ["Горение", "Накладывает горение по правилам состояний боя. Мана: 1."],
	"card.wet": ["Мокрота", "Снимает горение и обновляет мокроту до 3 тиков. Мана: 1."],
	"card.freeze": ["Заморозка", "Накладывает или продлевает заморозку по её обычным правилам. Мана: 1."],
	"card.stun": ["Оглушение", "Устанавливает или обновляет оглушение на 1 ход. Мана: 1."],
	"card.roots": ["Путы", "Устанавливает или обновляет путы на 1 ход. Мана: 1."],
	"card.bleeding": ["Кровотечение", "Добавляет стак кровотечения и обновляет срок до 3 тиков. Мана: 1."],
	"card.fire_imbue": ["Огненное усиление", "Обычные атаки наносят +2 огненного урона в этот ход и два следующих. Мана: 1."],
}

static func all() -> Array[MageCardDefinition]:
	var result: Array[MageCardDefinition] = []
	for type_id: String in IDS: result.append(_definition(type_id))
	return result

static func get_card(type_id: String) -> MageCardDefinition:
	return _definition(type_id) if IDS.has(type_id) else null

static func default_base_types() -> Array[String]:
	return DEFAULT_TYPES.duplicate()

static func valid_base(types: Variant) -> bool:
	if typeof(types) != TYPE_ARRAY or types.size() != 10: return false
	var counts: Dictionary = {}
	for type_value: Variant in types:
		if typeof(type_value) != TYPE_STRING or not IDS.has(type_value): return false
		counts[type_value] = int(counts.get(type_value, 0)) + 1
		if counts[type_value] > 2: return false
	return true

static func _definition(type_id: String) -> MageCardDefinition:
	var values: Array = MageCardDefinition.MECHANICS[type_id]
	var result := MageCardDefinition.new()
	var display: Array = PRESENTATION[type_id]
	result.id=type_id; result.name=display[0]
	result.description=display[1]; result.image_key=type_id
	result.mana_cost=values[3]; result.effect=values[0]; result.parameters=values[1].duplicate(true)
	result.target_policy=values[2]
	return result
