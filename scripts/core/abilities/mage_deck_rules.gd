class_name MageDeckRules
extends RefCounted

static func live_valid(state: ItemSimulationState) -> bool:
	if state.deck == null and state.card_effects == null: return state.abilities == null or state.abilities.to_dict().get("ruleset_id") == ""
	if state.deck == null or state.card_effects == null or state.abilities == null or state.artifacts != null: return false
	if state.deck.get_script() != BattleDeckState or state.card_effects.get_script() != BattleCardEffectState or state.deck.draw_rng == null or state.deck.draw_rng.get_script() != CombatRng: return false
	if not state.deck.valid() or not state.card_effects.valid() or state.abilities.to_dict().get("ruleset_id") != "u14-deck-v1": return false
	var units: Array = []
	for unit: UnitState in state.get_board().get_all_units(): units.append(unit.to_reference_dict())
	return _references(state.deck,state.card_effects,state.abilities.to_dict(),units,state.get_summons())

static func snapshot_valid(data: Dictionary) -> bool:
	if not BattleAbilityState.valid(data.abilities) or data.abilities.get("ruleset_id") != "u14-deck-v1" or data.has("artifacts"): return false
	var deck := BattleDeckState.from_dict(data.deck)
	var effects := BattleCardEffectState.from_dict(data.card_effects)
	if deck == null or effects == null: return false
	return _references(deck,effects,data.abilities,data.board_snapshot.board.units,data.summons)

## В v1 factory присваивает персональный default ID; остальные бойцы и helpers
## используют demo_strike. Codec выводит привязку из каталога, а admission сверяет
## сам каталог с AttackRules, поэтому произвольный существующий ID не становится default.
static func hero_attack_id(unit_id: int) -> StringName:
	return StringName("hero_attack_%d" % unit_id)

static func default_attack_id(unit_id: int, ability: Dictionary) -> String:
	var personal := String(hero_attack_id(unit_id))
	for descriptor: Dictionary in ability.catalog:
		if descriptor.ability_id == "attack:" + personal: return personal
	return "demo_strike"

static func _references(deck: BattleDeckState, effects: BattleCardEffectState, ability: Dictionary, units: Array, summons: Array) -> bool:
	if not deck.mulligan_done and ability.stage != "setup": return false
	if deck.replaced_serial > ability.serials[0]: return false
	var by_id: Dictionary = {}
	for unit: Dictionary in units: by_id[unit.id] = unit
	var bound: Dictionary = {}
	for record: Dictionary in effects.ordinary_attacks:
		if not by_id.has(record.unit_id) or record.attack_id != default_attack_id(record.unit_id,ability): return false
		bound[record.unit_id] = true
	if bound.size() != by_id.size(): return false
	var pending: Dictionary = {}
	for summon: Dictionary in summons:
		if typeof(summon.get("pending")) != TYPE_BOOL or typeof(summon.get("unit_id")) != TYPE_INT: return false
		if summon.pending: pending[summon.unit_id] = true
	for effect: Dictionary in effects.fire_imbues:
		if not by_id.has(effect.unit_id): return false
		var unit: Dictionary = by_id[effect.unit_id]
		var card := deck.card(effect.source_card_id)
		if unit.faction != Faction.Type.PLAYER or not unit.vitals.is_alive or pending.has(unit.id): return false
		if card.get("type_id") != "card.fire_imbue" or not deck.spent_ids.has(effect.source_card_id): return false
		if effect.applied_team_serial > ability.serials[unit.faction]: return false
		if effect.expires_after_serial <= ability.ended[unit.faction]: return false
	return true

static func references_valid(context: ActionContext) -> bool:
	var state := context.get_state()
	if state.deck == null: return state.card_effects == null and (state.abilities == null or state.abilities.ruleset_id == "")
	if not live_valid(state) or context._attack_rules == null: return false
	for record: Dictionary in state.card_effects.ordinary_attacks:
		if context._attack_rules.get_definition(StringName(record.attack_id)) == null: return false
	return true

static func ordinary_bonus(state: ItemSimulationState, unit_id: int, attack_id: StringName) -> bool:
	if state.card_effects == null: return false
	var ordinary := false
	for binding: Dictionary in state.card_effects.ordinary_attacks:
		if binding.unit_id == unit_id and binding.attack_id == String(attack_id): ordinary = true
	if not ordinary: return false
	for effect: Dictionary in state.card_effects.fire_imbues:
		if effect.unit_id == unit_id: return true
	return false
