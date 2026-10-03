extends Resource
class_name AbilityDefinition

## Дополнительный каталог нового тестового боя; старые снимки его не требуют.
const TEST_EFFECTS: Dictionary = {
	&"mage.test_burning": &"burning", &"mage.test_wet": &"wet",
	&"mage.test_freeze": &"freeze", &"mage.test_stun": &"stun",
	&"mage.test_roots": &"entangle", &"mage.test_bleeding": &"bleeding",
}
const TEST_SUPPORT_EFFECTS: Dictionary = {
	&"mage.test_heal": &"heal", &"mage.test_summon": &"summon", &"mage.test_raise": &"raise",
}

static func is_cell_spell(id: StringName) -> bool:
	return id in [&"mage.test_summon", &"mage.test_raise"]

static func mage_source_id(id: StringName) -> int:
	match id:
		&"mage.fire": return 1
		&"mage.heal": return 2
		&"mage.test_burning": return 3
		&"mage.test_wet": return 4
		&"mage.test_freeze": return 5
		&"mage.test_stun": return 6
		&"mage.test_roots": return 7
		&"mage.test_bleeding": return 8
		&"mage.test_heal": return 9
		&"mage.test_summon": return 10
		&"mage.test_raise": return 11
	return 0

@export var ability_id: StringName = &""
@export var cooldown_turns: int = 0
@export var mana_cost: int = 0
@export var effect: StringName = &""
@export var amount: int = 0

func validate() -> StringName:
	if get_script() != AbilityDefinition or ability_id == &"" or String(ability_id).to_utf8_buffer().size() > 128 or cooldown_turns < 0 or mana_cost < 0 or amount < 0:
		return &"ability/invalid_definition"
	if ability_id == &"mage.fire":
		if effect != &"fire" or mana_cost != 2 or amount != 4:
			return &"ability/invalid_mage_fire"
		return &""
	if ability_id == &"mage.heal":
		if effect != &"heal" or mana_cost != 3 or amount != 4:
			return &"ability/invalid_mage_heal"
		return &""
	if TEST_EFFECTS.has(ability_id):
		return &"" if effect == TEST_EFFECTS[ability_id] and mana_cost == 1 and cooldown_turns == 0 and amount == 1 else &"ability/invalid_test_spell"
	if TEST_SUPPORT_EFFECTS.has(ability_id):
		return &"" if effect == TEST_SUPPORT_EFFECTS[ability_id] and mana_cost == 1 and cooldown_turns == 0 and amount == (4 if ability_id == &"mage.test_heal" else 1) else &"ability/invalid_test_spell"
	if String(ability_id).begins_with("mage.") or effect != &"":
		return &"ability/unsupported_effect"
	if cooldown_turns != 0:
		return &"ability/unsupported_cooldown"
	if mana_cost != 0 or amount != 0:
		return &"ability/invalid_effect_values"
	return &""

func copy() -> AbilityDefinition:
	if validate() != &"": return null
	var result := AbilityDefinition.new()
	result.ability_id = ability_id
	result.cooldown_turns = cooldown_turns
	result.mana_cost = mana_cost
	result.effect = effect
	result.amount = amount
	return result

func to_dict() -> Dictionary:
	if validate() != &"": return {}
	return {"ability_id": String(ability_id), "cooldown_turns": cooldown_turns, "mana_cost": mana_cost, "effect": String(effect), "amount": amount}

static func from_dict(value: Variant) -> AbilityDefinition:
	if typeof(value) != TYPE_DICTIONARY: return null
	var data: Dictionary = value
	if data.size() != 5: return null
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or key not in ["ability_id", "cooldown_turns", "mana_cost", "effect", "amount"]: return null
	if typeof(data["ability_id"]) != TYPE_STRING or typeof(data["cooldown_turns"]) != TYPE_INT or typeof(data["mana_cost"]) != TYPE_INT or typeof(data["effect"]) != TYPE_STRING or typeof(data["amount"]) != TYPE_INT: return null
	var result := AbilityDefinition.new()
	result.ability_id = StringName(data["ability_id"])
	result.cooldown_turns = data["cooldown_turns"]
	result.mana_cost = data["mana_cost"]
	result.effect = StringName(data["effect"])
	result.amount = data["amount"]
	return result if result.validate() == &"" else null
