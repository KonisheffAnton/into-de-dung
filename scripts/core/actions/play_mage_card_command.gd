extends Command
class_name PlayMageCardCommand

var card_instance_id: int
var target_id: int
var target_cell: Vector2i
var revision: int

func _init(instance_id: int = 0, target: int = 0, cell: Vector2i = Vector2i(-1, -1), rev: int = 0) -> void:
	card_instance_id = instance_id; target_id = target; target_cell = cell; revision = rev

func get_kind() -> StringName: return &"mage_card_play"
func copy_for_queue() -> Command: return PlayMageCardCommand.new(card_instance_id, target_id, target_cell, revision)

func projected_after(context: ActionContext) -> Dictionary:
	return _prepare(context).get("paid", {})

func projected_deck(context: ActionContext) -> Dictionary:
	return _prepare(context).get("deck_after", {})

func projected_effects(context: ActionContext) -> Dictionary:
	return _prepare(context).get("effects_after", {})

func validate(context: ActionContext) -> StringName: return _prepare(context).get("reason", &"mage_card/invalid_context")

func _prepare(context: ActionContext) -> Dictionary:
	if context == null or context.is_faulted() or context.get_state() == null or revision != context.get_revision() or revision < 0 or revision >= ActionContext.MAX_ID - 1:
		return {"reason": &"mage_card/invalid_context"}
	var state := context.get_state()
	if not MageDeckRules.references_valid(context): return {"reason": &"mage_card/capability_required"}
	var ability := state.abilities
	if ability == null or ability.schema_version != 2 or not ability.mage_allowed or ability.team != Faction.Type.PLAYER or ability.stage != "active": return {"reason": &"mage_card/window_closed"}
	if card_instance_id <= 0 or card_instance_id >= ActionContext.MAX_ID or not state.deck.hand_ids.has(card_instance_id): return {"reason": &"mage_card/not_in_hand"}
	var card_value := state.deck.card(card_instance_id)
	var definition := MageCardCatalog.get_card(String(card_value.get("type_id", "")))
	if definition == null or definition.validate() != &"": return {"reason": &"mage_card/unknown_type"}
	if ability.mana < definition.mana_cost: return {"reason": &"mage_card/insufficient_mana"}
	var teams: Array[bool] = [false, false]
	for unit: UnitState in state.get_board().get_all_units():
		if unit.is_alive() and unit.faction in [Faction.Type.PLAYER, Faction.Type.ENEMY]: teams[unit.faction] = true
	if not teams[0] or not teams[1]: return {"reason": &"mage_card/terminal"}
	var deck_plan := state.deck.play(card_instance_id)
	if deck_plan.is_empty(): return {"reason": &"mage_card/not_in_hand"}
	var paid := ability.to_dict()
	paid["mana"] = ability.mana - definition.mana_cost
	if not BattleAbilityState.valid(paid): return {"reason": &"mage_card/invalid_payment"}
	var deck_after: Dictionary = deck_plan.after
	var effects_after: Dictionary = state.card_effects.to_dict()
	var source := DamageSource.new(&"mage", definition.source_id(), Vector2i(-1, -1), 0, 0)
	var amount: int = int(definition.parameters.get("damage", definition.parameters.get("amount", 0)))
	var hits: int = int(definition.parameters.get("hits", 0))
	var plan := MageEffectExecutor.prepare(context, target_id, target_cell, StringName(definition.effect), amount, hits, source, paid, StringName(definition.id), card_instance_id, deck_after, effects_after)
	if plan.get("reason", &"") != &"": return plan
	if not plan.get("effects_after", {}).is_empty(): effects_after = plan.effects_after
	if context._next_event_seq > ActionContext.MAX_ID - 8: return {"reason": &"sequence_exhausted"}
	plan["card_type_id"] = definition.id
	plan["deck_after"] = deck_after
	plan["effects_after"] = effects_after
	return plan

func execute(context: ActionContext) -> CommandStepResult:
	var plan := _prepare(context)
	if plan.get("reason", &"") != &"": return CommandStepResult.faulted(plan.reason)
	var seal: Array = [card_instance_id, target_id, target_cell, revision]
	var state := context.get_state()
	var ability := state.abilities
	var deck := state.deck
	var payment_effects: Dictionary = state.card_effects.to_dict() if plan.has("summon_plan") else plan.effects_after
	var guard: SpatialRules.Guard = plan.guard.ability_phase(plan.paid).deck_phase(plan.deck_after, payment_effects)
	var mana_before: int = ability.mana
	var deck_before: Dictionary = deck.to_dict()
	# Обе стоимости публикуются до первого callback; при ошибке эффект видит оплаченный prefix.
	ability.apply_values(plan.paid)
	deck.apply_values(plan.deck_after)
	if plan.effect == &"fire_imbue": state.card_effects.apply_values(plan.effects_after)
	var source: DamageSource = plan.source
	var played := {"kind": &"mage_card_played", "type_id": String(plan.card_type_id), "card_instance_id": card_instance_id,
		"actor_unit_id": 0, "target_unit_id": target_id, "target_cell": target_cell, "source": source.to_dict(),
		"mana_before": mana_before, "mana_after": ability.mana}
	var result := CommandStepResult.applied([played, MageDeckChangeCommand.changed(deck_before, plan.deck_after, "play")], [], [], null, true)
	if not guard.check(context) or [card_instance_id, target_id, target_cell, revision] != seal:
		result.status = &"FAULTED"; result.reason = &"mage_card/checkpoint"; return result
	var effect_result := MageEffectExecutor.apply(context, plan, guard, func() -> bool: return [card_instance_id, target_id, target_cell, revision] == seal)
	result.events.append_array(effect_result.events); result.status = effect_result.status; result.reason = effect_result.reason
	return result

static func valid_draft(draft: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "type_id": TYPE_STRING, "card_instance_id": TYPE_INT,
		"actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "target_cell": TYPE_VECTOR2I, "source": TYPE_DICTIONARY,
		"mana_before": TYPE_INT, "mana_after": TYPE_INT}): return false
	var definition := MageCardCatalog.get_card(draft.type_id)
	if draft.kind != &"mage_card_played" or definition == null or draft.actor_unit_id != 0 or draft.card_instance_id <= 0 or draft.card_instance_id >= ActionContext.MAX_ID: return false
	if draft.target_unit_id < 0 or draft.target_unit_id >= ActionContext.MAX_ID: return false
	if definition.target_policy in ["valid_cell", "corpse_cell"]:
		if draft.target_cell.x < 0 or draft.target_cell.y < 0: return false
	elif draft.target_unit_id == 0: return false
	if draft.mana_before < definition.mana_cost or draft.mana_before > 9 or draft.mana_after != draft.mana_before - definition.mana_cost: return false
	return draft.source == DamageSource.new(&"mage", definition.source_id(), Vector2i(-1, -1), 0, 0).to_dict()
