extends RefCounted
class_name AbilityCatalog

static func defaults() -> Array[AbilityDefinition]:
	var result: Array[AbilityDefinition] = []
	for id: StringName in [&"move", &"safe_retreat", &"guard:default", &"guard:opportunist", &"guard:cover", &"guard:counterattack", &"restore_armor", &"raise_corpse", &"elemental:burning", &"elemental:wet", &"elemental:freeze", &"perk:sneak_attack", &"perk:tank_reactions", &"perk:stunning_strike", &"perk:stun_immune", &"perk:entangle_immune", &"perk:counterattack", &"perk:burning_bypass_hp_gate", &"immunity:stun", &"immunity:entangle", &"immunity:bleeding", &"immunity:freeze", &"team.end_turn"]:
		result.append(_definition(id))
	var fire := _definition(&"mage.fire")
	fire.effect = &"fire"; fire.amount = 4; fire.mana_cost = 2; fire.cooldown_turns = 2
	result.append(fire)
	var heal := _definition(&"mage.heal")
	heal.effect = &"heal"; heal.amount = 4; heal.mana_cost = 3; heal.cooldown_turns = 2
	result.append(heal)
	return result

static func build(attack_rules: AttackRules, item_definitions: Dictionary, include_test_spells: bool = false) -> Array[AbilityDefinition]:
	var result := defaults()
	if include_test_spells:
		for id: StringName in AbilityDefinition.TEST_EFFECTS:
			var spell := _definition(id)
			spell.effect = AbilityDefinition.TEST_EFFECTS[id]
			spell.amount = 1; spell.mana_cost = 1
			result.append(spell)
	if attack_rules == null or attack_rules.validate() != &"": return []
	for attack: AttackDefinition in attack_rules.get_definitions():
		var descriptor := attack.get_ability_definition()
		if descriptor == null or descriptor.validate() != &"": return []
		result.append(descriptor)
	for key: Variant in item_definitions:
		var definition: Variant = item_definitions[key]
		if typeof(key) != TYPE_STRING_NAME or not definition is ItemDef or (definition as ItemDef).get_script() not in [ItemDef, Item]: return []
		var item: ItemDef = definition
		if item.id == &"" or item.id != key or item.cooldown_turns != 0: return []
		if item.use_summon:
			var use_descriptor := item.get_ability_definition(&"summon_adjacent")
			if ItemUseAction.from_definition(item) == null or use_descriptor == null or use_descriptor.validate() != &"": return []
			result.append(use_descriptor)
		elif item.use_heal_amount > 0.0:
			var use_descriptor := item.get_ability_definition(&"heal_self")
			if ItemUseAction.from_definition(item) == null or use_descriptor == null or use_descriptor.validate() != &"": return []
			result.append(use_descriptor)
		for index: int in item.effects.size():
			var effect_definition: ItemEffect = item.effects[index]
			if effect_definition == null: return []
			var effect_descriptor := effect_definition.get_ability_definition(item.id, index)
			if effect_descriptor == null or effect_descriptor.validate() != &"": return []
			result.append(effect_descriptor)
	var ids: Dictionary = {}
	for descriptor: AbilityDefinition in result:
		if descriptor == null or descriptor.validate() != &"" or ids.has(descriptor.ability_id): return []
		ids[descriptor.ability_id] = true
	return result

static func _definition(id: StringName) -> AbilityDefinition:
	var value := AbilityDefinition.new(); value.ability_id = id
	return value

## AttackRules передаются отдельно от снимка доски: проверяем все ссылки до root.
static func attack_references_valid(context: ActionContext) -> bool:
	var abilities := context.get_state().abilities
	if abilities == null: return true
	var rules := context.get_attack_rules()
	if rules == null or rules.validate() != &"": return false
	var expected: Dictionary = {}
	for attack: AttackDefinition in rules.get_definitions():
		var descriptor := attack.get_ability_definition()
		if descriptor == null: return false
		expected[descriptor.ability_id] = descriptor.to_dict()
	for descriptor: AbilityDefinition in abilities.catalog:
		if descriptor == null: return false
		if not String(descriptor.ability_id).begins_with("attack:"): continue
		if expected.get(descriptor.ability_id) != descriptor.to_dict(): return false
		expected.erase(descriptor.ability_id)
	return expected.is_empty()

## Команды и BT читают один адаптер; последствия не получают собственную способность.
static func for_command(command: Command, context: ActionContext) -> AbilityDefinition:
	if command == null or context == null: return null
	var id: StringName = &""
	if command is AttackCommand:
		var rules := context.get_attack_rules()
		var attack := rules.get_definition((command as AttackCommand).get_attack_definition_id()) if rules != null else null
		return attack.get_ability_definition() if attack != null else null
	if command is MoveCommand: id = &"safe_retreat" if (command as MoveCommand)._movement_kind == &"safe_retreat" else &"move"
	elif command is GuardCommand:
		var mode := (command as GuardCommand)._mode
		id = &"guard:opportunist" if mode == CombatPerksState.Mode.OPPORTUNIST else &"guard:cover" if mode == CombatPerksState.Mode.COVER else &"guard:counterattack" if mode == CombatPerksState.Mode.COUNTERATTACK else &"guard:default"
	elif command is RestoreArmorCommand: id = &"restore_armor"
	elif command is RaiseCorpseCommand: id = &"raise_corpse"
	elif command is ElementalCastCommand: id = StringName("elemental:" + String((command as ElementalCastCommand)._effect))
	elif command is MageCastCommand: id = (command as MageCastCommand).spell_id
	elif command is UseHealingItemCommand or command is UseSummoningItemCommand:
		var owner := context.get_state().get_owner(command.get("_actor_id"))
		var item: ItemInstance = owner._items.get(command.get("_item_id")) if owner != null else null
		var action := item.get_use_action() if item != null else null
		return action.get_ability_definition() if action != null else null
	if id == &"": return null
	if context.get_state().abilities != null:
		var found := context.get_state().abilities.definition(id)
		return found.copy() if found != null else null
	for descriptor: AbilityDefinition in defaults():
		if descriptor.ability_id == id and descriptor.cooldown_turns == 0: return descriptor
	return null
