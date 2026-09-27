extends Resource
class_name AbilityDefinition

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
