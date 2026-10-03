extends Resource
class_name MageCardDefinition

const SOURCE_IDS: Dictionary = {
	"card.fire": 13, "card.heal": 14, "card.shield": 15, "card.summon": 16,
	"card.raise": 17, "card.burning": 18, "card.wet": 19, "card.freeze": 20,
	"card.stun": 21, "card.roots": 22, "card.bleeding": 23, "card.fire_imbue": 24,
}
const MECHANICS: Dictionary = {
	"card.fire": ["mage.fire", {"damage": 4}, "enemy_unit", 2],
	"card.heal": ["mage.test_heal", {"amount": 4}, "wounded_ally", 1],
	"card.shield": ["mage.shield", {"amount": 6, "hits": 1}, "ally_unit", 1],
	"card.summon": ["mage.test_summon", {}, "valid_cell", 1],
	"card.raise": ["mage.test_raise", {}, "corpse_cell", 1],
	"card.burning": ["burning", {}, "living_unit", 1],
	"card.wet": ["wet", {}, "living_unit", 1],
	"card.freeze": ["freeze", {}, "living_unit", 1],
	"card.stun": ["stun", {}, "living_unit", 1],
	"card.roots": ["entangle", {}, "living_unit", 1],
	"card.bleeding": ["bleeding", {}, "living_unit", 1],
	"card.fire_imbue": ["fire_imbue", {"bonus": 2, "duration": 2}, "ally_unit", 1],
}

@export var id: String = ""
@export var version: int = 1
@export var name: String = ""
@export_multiline var description: String = ""
@export var image_key: String = ""
@export var mana_cost: int = 0
@export var effect: String = ""
@export var parameters: Dictionary = {}
@export var target_policy: String = ""
@export var cooldown_turns: int = 0

func source_id() -> int:
	return int(SOURCE_IDS.get(id, 0))

func validate() -> StringName:
	if get_script() != MageCardDefinition or not MECHANICS.has(id): return &"mage_card/unknown_id"
	var expected: Array = MECHANICS[id]
	if version != 1 or cooldown_turns != 0: return &"mage_card/invalid_version_or_cooldown"
	if effect != expected[0] or mana_cost != expected[3] or target_policy != expected[2]: return &"mage_card/invalid_mechanics"
	if parameters != expected[1]: return &"mage_card/invalid_parameters"
	for key: Variant in parameters:
		if typeof(key) != TYPE_STRING or typeof(parameters[key]) != TYPE_INT: return &"mage_card/invalid_parameters"
	if name.is_empty() or description.is_empty() or image_key.is_empty(): return &"mage_card/invalid_presentation"
	return &""

func copy() -> MageCardDefinition:
	if validate() != &"": return null
	var result := MageCardDefinition.new()
	result.id = id; result.version = version; result.name = name; result.description = description
	result.image_key = image_key; result.mana_cost = mana_cost; result.effect = effect
	result.parameters = parameters.duplicate(true); result.target_policy = target_policy
	result.cooldown_turns = cooldown_turns
	return result

func to_dict() -> Dictionary:
	if validate() != &"": return {}
	return {"id":id,"version":version,"name":name,"description":description,"image_key":image_key,
		"mana_cost":mana_cost,"effect":effect,"parameters":parameters.duplicate(true),
		"target_policy":target_policy,"cooldown_turns":cooldown_turns}

static func from_dict(value: Variant) -> MageCardDefinition:
	if typeof(value) != TYPE_DICTIONARY: return null
	var fields: Dictionary = {"id":TYPE_STRING,"version":TYPE_INT,"name":TYPE_STRING,"description":TYPE_STRING,
		"image_key":TYPE_STRING,"mana_cost":TYPE_INT,"effect":TYPE_STRING,"parameters":TYPE_DICTIONARY,
		"target_policy":TYPE_STRING,"cooldown_turns":TYPE_INT}
	if not ItemSimulationSnapshot._shape(value, fields): return null
	var result := MageCardDefinition.new()
	result.id=value.id; result.version=value.version; result.name=value.name; result.description=value.description
	result.image_key=value.image_key; result.mana_cost=value.mana_cost; result.effect=value.effect
	result.parameters=value.parameters.duplicate(true); result.target_policy=value.target_policy
	result.cooldown_turns=value.cooldown_turns
	return result if result.validate() == &"" else null
