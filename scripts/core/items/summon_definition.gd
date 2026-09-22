extends Resource
class_name SummonDefinition

## Resource описывает только неизменяемый шаблон помощника; runtime создаётся
## отдельно, чтобы один предмет не разделял состояние между владельцами.
const DEFAULT_SCHEMA_VERSION: int = 1
const DEFAULT_HP_MAX: float = 16.0
const DEFAULT_ARMOR: float = 0.0
const DEFAULT_STRENGTH: float = 4.0
const DEFAULT_WEAPON_DAMAGE: float = 2.0
const DEFAULT_IMPACT_POWER: float = 3.0
const DEFAULT_BALANCE_MAX: float = 5.0
const DEFAULT_MOVE_RANGE: float = 4.0
const DEFAULT_MAIN_ACTIONS_MAX: float = 1.0
const DEFAULT_BONUS_ACTIONS_MAX: float = 1.0
const DEFAULT_ATTACK_RANGE: float = 1.0
const DEFAULT_NAME_PREFIX: String = "Помощник · "
const DEFAULT_APPEND_OWNER_NAME: bool = true

const DEFAULT_VALUES: Dictionary = {
	"schema_version": DEFAULT_SCHEMA_VERSION,
	"hp_max": DEFAULT_HP_MAX,
	"armor": DEFAULT_ARMOR,
	"strength": DEFAULT_STRENGTH,
	"weapon_damage": DEFAULT_WEAPON_DAMAGE,
	"impact_power": DEFAULT_IMPACT_POWER,
	"balance_max": DEFAULT_BALANCE_MAX,
	"move_range": DEFAULT_MOVE_RANGE,
	"main_actions_max": DEFAULT_MAIN_ACTIONS_MAX,
	"bonus_actions_max": DEFAULT_BONUS_ACTIONS_MAX,
	"attack_range": DEFAULT_ATTACK_RANGE,
	"name_prefix": DEFAULT_NAME_PREFIX,
	"append_owner_name": DEFAULT_APPEND_OWNER_NAME,
}

@export var hp_max: float = DEFAULT_HP_MAX
@export var armor: float = DEFAULT_ARMOR
@export var strength: float = DEFAULT_STRENGTH
@export var weapon_damage: float = DEFAULT_WEAPON_DAMAGE
@export var impact_power: float = DEFAULT_IMPACT_POWER
@export var balance_max: float = DEFAULT_BALANCE_MAX
@export var move_range: float = DEFAULT_MOVE_RANGE
@export var main_actions_max: float = DEFAULT_MAIN_ACTIONS_MAX
@export var bonus_actions_max: float = DEFAULT_BONUS_ACTIONS_MAX
@export var attack_range: float = DEFAULT_ATTACK_RANGE
@export var name_prefix: String = DEFAULT_NAME_PREFIX
@export var append_owner_name: bool = DEFAULT_APPEND_OWNER_NAME

func to_dict() -> Dictionary:
	return {
		"schema_version": DEFAULT_SCHEMA_VERSION,
		"hp_max": hp_max, "armor": armor, "strength": strength,
		"weapon_damage": weapon_damage, "impact_power": impact_power,
		"balance_max": balance_max, "move_range": move_range,
		"main_actions_max": main_actions_max, "bonus_actions_max": bonus_actions_max,
		"attack_range": attack_range, "name_prefix": name_prefix,
		"append_owner_name": append_owner_name,
	}

static func valid_data(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var value: Dictionary = data
	if value.keys().size() != DEFAULT_VALUES.keys().size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING: return false
	for key in DEFAULT_VALUES.keys():
		if not value.has(key):
			return false
	if typeof(value["schema_version"]) != TYPE_INT or value["schema_version"] != DEFAULT_SCHEMA_VERSION:
		return false
	for key in ["hp_max", "armor", "strength", "weapon_damage", "impact_power", "balance_max", "move_range", "main_actions_max", "bonus_actions_max", "attack_range"]:
		if typeof(value[key]) != TYPE_FLOAT or not is_finite(value[key]) or value[key] < 0.0 or value[key] > 4096.0:
			return false
	if value["hp_max"] <= 0.0 or value["balance_max"] <= 0.0 or value["attack_range"] < 1.0:
		return false
	if value["main_actions_max"] != floorf(value["main_actions_max"]) or value["bonus_actions_max"] != floorf(value["bonus_actions_max"]):
		return false
	if typeof(value["name_prefix"]) != TYPE_STRING or value["name_prefix"].is_empty() or value["name_prefix"].to_utf8_buffer().size() > 256:
		return false
	return typeof(value["append_owner_name"]) == TYPE_BOOL

func validate() -> bool:
	return valid_definition(self)

static func valid_definition(definition: SummonDefinition) -> bool:
	# Проверка capability должна предшествовать любому виртуальному вызову Resource.
	return definition != null and definition.get_script() == SummonDefinition and valid_data(definition.to_dict())

static func default_values() -> Dictionary:
	return DEFAULT_VALUES.duplicate(true)

func is_default() -> bool:
	return to_dict() == DEFAULT_VALUES

func base_values() -> Dictionary:
	return {
		StatTypes.StatType.HP_MAX: hp_max,
		StatTypes.StatType.ARMOR: armor,
		StatTypes.StatType.STRENGTH: strength,
		StatTypes.StatType.WEAPON_DAMAGE: weapon_damage,
		StatTypes.StatType.IMPACT_POWER: impact_power,
		StatTypes.StatType.BALANCE_MAX: balance_max,
		StatTypes.StatType.MOVE_RANGE: move_range,
		StatTypes.StatType.MAIN_ACTIONS_MAX: main_actions_max,
		StatTypes.StatType.BONUS_ACTIONS_MAX: bonus_actions_max,
		StatTypes.StatType.ATTACK_RANGE: attack_range,
	}

func make_name(owner_name: String) -> String:
	return name_prefix + owner_name if append_owner_name else name_prefix

func name_valid(owner_name: String) -> bool:
	var result := make_name(owner_name)
	return valid_definition(self) and result.to_utf8_buffer().size() <= 4096
