extends RefCounted
class_name ActionEventValidator

const MAX_ID: int = 9223372036854775807

# Статический валидатор не удерживает состояние очереди и проверяет только DTO события.
static func valid_draft(draft: Dictionary, context: ActionContext = null) -> bool:
	if draft.get("kind") in [&"raised_shields", &"raised_shield_used"]:
		var fields := {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "before": TYPE_DICTIONARY, "after": TYPE_DICTIONARY}
		if draft.kind == &"raised_shields": fields.merge({"main_before": TYPE_INT, "main_after": TYPE_INT})
		if not ItemSimulationSnapshot._shape(draft, fields) or draft.actor_unit_id < 0 or draft.actor_unit_id >= MAX_ID or draft.target_unit_id < 1 or draft.target_unit_id >= MAX_ID or not RaisedShield.valid(draft.before) or not RaisedShield.valid(draft.after): return false
		if draft.kind == &"raised_shields":
			return draft.actor_unit_id == draft.target_unit_id and draft.main_before > 0 and draft.main_after == draft.main_before - 1 and not draft.before.active and draft.after.active and draft.after.ready_turn >= 3
		return draft.before.active and not draft.after.active and draft.before.ready_turn == draft.after.ready_turn and draft.after.blocked_root > 0 and draft.after.blocked_group > 0
	if draft.get("kind") == &"shield_changed": return SpellShield.valid_event(draft)
	if draft.get("kind") == &"mage_cast": return MageCastCommand.valid_draft(draft)
	if draft.get("kind") == &"mage_card_played": return PlayMageCardCommand.valid_draft(draft)
	if draft.get("kind") == &"deck_changed": return MageDeckChangeCommand.valid_draft(draft)
	if draft.get("kind") == &"mage_summoned": return MageSummonEffect.valid_draft(draft)
	if draft.get("kind") == &"chain_link": return PushChainCommand.valid_draft(draft)
	if draft.get("kind") in [&"environment_turn", &"support_collapsed"]: return CollapsePhaseCommand.valid_draft(draft)
	if draft.get("kind") == &"reaction_used":
		if draft.has("bonus_before"):
			return ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "mode": TYPE_INT, "bonus_before": TYPE_INT, "bonus_after": TYPE_INT, "bonus_cost": TYPE_INT}) and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["actor_unit_id"] != draft["target_unit_id"] and draft["mode"] in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COVER, CombatPerksState.Mode.COUNTERATTACK] and draft["bonus_before"] >= 1 and draft["bonus_before"] <= ActionResources.MAX_COUNTER and draft["bonus_after"] == draft["bonus_before"] - 1 and draft["bonus_cost"] == 1
		return ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "mode": TYPE_INT, "charge_before": TYPE_INT, "charge_after": TYPE_INT}) and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["actor_unit_id"] != draft["target_unit_id"] and draft["mode"] in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COVER, CombatPerksState.Mode.COUNTERATTACK] and draft["charge_before"] == 1 and draft["charge_after"] == 0
	if draft.get("kind") == &"guarded" and draft.has("reaction_mode"):
		if typeof(draft.get("reaction_mode")) != TYPE_INT or typeof(draft.get("cover_target_id")) != TYPE_INT: return false
		if draft["reaction_mode"] not in [0, 1, 2, 3] or draft["cover_target_id"] < 0 or draft["cover_target_id"] >= MAX_ID: return false
		if (draft["reaction_mode"] == 2) != (draft["cover_target_id"] > 0) or draft["cover_target_id"] == draft.get("actor_unit_id"): return false
		var guarded := draft.duplicate(true)
		guarded.erase("reaction_mode"); guarded.erase("cover_target_id")
		return valid_draft(guarded, context)
	if draft.get("kind") in [&"opportunity_attacked", &"counterattacked"] and not draft.has("modifiers"):
		if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "attack_definition_id": TYPE_STRING_NAME, "actor_cell": TYPE_VECTOR2I, "target_cell": TYPE_VECTOR2I, "main_cost": TYPE_INT, "main_before": TYPE_INT, "main_after": TYPE_INT}): return false
		if context == null: return false
		var reaction_def := context.get_attack_rules().get_definition(draft["attack_definition_id"])
		return reaction_def != null and reaction_def.reaction_strike and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["actor_unit_id"] != draft["target_unit_id"] and draft["main_cost"] == 0 and draft["main_before"] >= 0 and draft["main_before"] <= 4096 and draft["main_after"] == draft["main_before"]
	if draft.get("kind") == &"corpse_created": return EnvironmentRules.valid_draft(draft)
	if draft.get("kind") == &"corpse_raised": return RaiseCorpseCommand.valid_draft(draft)
	if draft.get("kind") == &"bleeding_changed": return _valid_bleeding_draft(draft)
	if draft.get("kind") == &"control_changed": return _valid_control_draft(draft)
	if draft.get("kind") in [&"trap_armed", &"trap_fired"]: return BattleHazards.valid_event(draft)
	if draft.get("kind") in [&"elemental_changed", &"elemental_cast"]: return _valid_elemental_draft(draft)
	if draft.get("kind") in [&"attacked", &"opportunity_attacked", &"counterattacked"] and draft.has("modifiers"):
		if typeof(draft["modifiers"]) != TYPE_DICTIONARY: return false
		if draft["modifiers"].has("sneak_percent"):
			var modifiers: Dictionary = draft["modifiers"]
			if not ItemSimulationSnapshot._shape(modifiers, {"backstab_percent": TYPE_INT, "critical": TYPE_BOOL, "sneak_percent": TYPE_INT, "threat_ids": TYPE_ARRAY}): return false
			if context == null: return false
			var sneak_def := context.get_attack_rules().get_definition(draft.get("attack_definition_id", &""))
			if sneak_def == null or not sneak_def.sneak_attack_enabled or modifiers["sneak_percent"] not in [0, 50]: return false
			var last_id: int = 0
			for id: Variant in modifiers["threat_ids"]:
				if typeof(id) != TYPE_INT or id <= last_id or id >= MAX_ID: return false
				last_id = id
			if modifiers["sneak_percent"] == 50 and modifiers["threat_ids"].size() < 2: return false
			var reduced := draft.duplicate(true)
			reduced["modifiers"].erase("sneak_percent"); reduced["modifiers"].erase("threat_ids")
			return valid_draft(reduced, context)
		if not ItemSimulationSnapshot._shape(draft["modifiers"], {"backstab_percent": TYPE_INT, "critical": TYPE_BOOL}): return false
		var clean := draft.duplicate(true)
		clean.erase("modifiers")
		if not valid_draft(clean, context): return false
		var definition := context.get_attack_rules().get_definition(draft["attack_definition_id"])
		return definition != null and (definition.backstab_bonus_percent > 0 or definition.critical_on_control or definition.sneak_attack_enabled or ElementalRules.is_frozen(context.get_state().get_board().get_unit_by_id(draft["target_unit_id"]))) and draft["modifiers"]["backstab_percent"] in [0, definition.backstab_bonus_percent] and (definition.critical_on_control or ElementalRules.is_frozen(context.get_state().get_board().get_unit_by_id(draft["target_unit_id"])) or not draft["modifiers"]["critical"])
	if draft.has("transit_path"):
		return _valid_transit_draft(draft, context)
	if draft.get("kind") in [&"armor_changed", &"hit_resolved"]:
		return _valid_armor_draft(draft)
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "item_instance_id": TYPE_INT, "cell": TYPE_VECTOR2I}):
		return draft["kind"] == &"summoned" and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["target_unit_id"] != draft["actor_unit_id"] and draft["item_instance_id"] > 0 and draft["item_instance_id"] < MAX_ID
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "item_instance_id": TYPE_INT, "main_cost": TYPE_INT, "main_before": TYPE_INT, "main_after": TYPE_INT, "charges_before": TYPE_INT, "charges_after": TYPE_INT}):
		return draft["kind"] == &"item_used" and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] == draft["actor_unit_id"] and draft["item_instance_id"] > 0 and draft["item_instance_id"] < MAX_ID and draft["main_cost"] == 1 and draft["main_before"] >= 1 and draft["main_before"] <= 4096 and draft["main_after"] == draft["main_before"] - 1 and draft["charges_before"] >= 1 and draft["charges_before"] <= 4096 and draft["charges_after"] == draft["charges_before"] - 1
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "main_cost": TYPE_INT, "main_before": TYPE_INT, "main_after": TYPE_INT}):
		return draft["kind"] == &"guarded" and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] == draft["actor_unit_id"] and draft["main_cost"] == 1 and draft["main_before"] >= 1 and draft["main_before"] <= 4096 and draft["main_after"] == draft["main_before"] - 1
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "balance_before": TYPE_FLOAT, "balance_after": TYPE_FLOAT, "balance_max": TYPE_FLOAT, "impact": TYPE_FLOAT, "broke": TYPE_BOOL}):
		var before: float = draft["balance_before"]; var after: float = draft["balance_after"]; var maximum: float = draft["balance_max"]; var impact: float = draft["impact"]
		if draft["actor_unit_id"] <= 0 or draft["actor_unit_id"] >= MAX_ID or draft["target_unit_id"] <= 0 or draft["target_unit_id"] >= MAX_ID or draft["actor_unit_id"] == draft["target_unit_id"] or before < 0.0 or after < 0.0 or maximum <= 0.0 or impact <= 0.0 or not is_finite(before) or not is_finite(after) or not is_finite(maximum) or not is_finite(impact): return false
		var sum := before + impact
		if not is_finite(sum): return false
		if draft["kind"] == &"balance_changed": return after != before and ((draft["broke"] and after == 0.0 and sum >= maximum) or (not draft["broke"] and after == sum and sum < maximum))
		return draft["kind"] == &"balance_broken" and draft["broke"] and after == 0.0 and sum >= maximum
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "from_cell": TYPE_VECTOR2I, "attempted_cell": TYPE_VECTOR2I, "reason": TYPE_STRING_NAME}):
		var dx: int = int(draft["attempted_cell"].x) - int(draft["from_cell"].x); var dy: int = int(draft["attempted_cell"].y) - int(draft["from_cell"].y)
		return draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["actor_unit_id"] != draft["target_unit_id"] and absi(dx) + absi(dy) == 1 and ((draft["kind"] == &"push_blocked" and draft["reason"] in [&"wall", &"height"]) or (draft["kind"] == &"fell" and draft["reason"] == &"bounds"))
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "from_cell": TYPE_VECTOR2I, "attempted_cell": TYPE_VECTOR2I, "blocker_unit_id": TYPE_INT}):
		var cdx: int = int(draft["attempted_cell"].x) - int(draft["from_cell"].x); var cdy: int = int(draft["attempted_cell"].y) - int(draft["from_cell"].y)
		return draft["kind"] == &"collision" and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["actor_unit_id"] != draft["target_unit_id"] and draft["blocker_unit_id"] > 0 and draft["blocker_unit_id"] < MAX_ID and draft["blocker_unit_id"] != draft["actor_unit_id"] and draft["blocker_unit_id"] != draft["target_unit_id"] and absi(cdx) + absi(cdy) == 1
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "from_cell": TYPE_VECTOR2I, "to_cell": TYPE_VECTOR2I, "movement_kind": TYPE_STRING_NAME, "move_cost": TYPE_FLOAT, "move_before": TYPE_FLOAT, "move_after": TYPE_FLOAT}):
		if draft["movement_kind"] == &"push":
			var pdx: int = int(draft["to_cell"].x) - int(draft["from_cell"].x); var pdy: int = int(draft["to_cell"].y) - int(draft["from_cell"].y)
			return draft["kind"] == &"moved" and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["actor_unit_id"] != draft["target_unit_id"] and absi(pdx) + absi(pdy) == 1 and draft["move_cost"] == 0.0 and draft["move_before"] == draft["move_after"] and is_finite(draft["move_before"]) and draft["move_before"] >= 0.0
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "attack_definition_id": TYPE_STRING_NAME, "actor_cell": TYPE_VECTOR2I, "target_cell": TYPE_VECTOR2I, "main_cost": TYPE_INT, "main_before": TYPE_INT, "main_after": TYPE_INT}):
		if draft["kind"] != &"attacked" or draft["actor_unit_id"] <= 0 or draft["actor_unit_id"] >= MAX_ID or draft["target_unit_id"] <= 0 or draft["target_unit_id"] >= MAX_ID or draft["target_unit_id"] == draft["actor_unit_id"]: return false
		if draft["attack_definition_id"] == &"" or String(draft["attack_definition_id"]).to_utf8_buffer().size() > AttackRules.MAX_DEFINITION_ID_BYTES: return false
		var attack_dx: int = int(draft["target_cell"].x) - int(draft["actor_cell"].x)
		var attack_dy: int = int(draft["target_cell"].y) - int(draft["actor_cell"].y)
		if context == null or context.get_attack_rules() == null: return false
		var definition := context.get_attack_rules().get_definition(draft["attack_definition_id"])
		if definition == null: return false
		var spatial := definition.profile in [AttackRules.SPATIAL_PROFILE, AttackRules.ARMOR_PROFILE]
		var geometry := (attack_dx == 0 or attack_dy == 0) and absi(attack_dx) + absi(attack_dy) >= 1 if spatial else absi(attack_dx) + absi(attack_dy) == 1
		return geometry and draft["main_cost"] == 1 and draft["main_before"] >= 1 and draft["main_before"] <= 4096 and draft["main_after"] == draft["main_before"] - 1
	if typeof(draft.get("movement_kind")) == TYPE_STRING_NAME and draft.get("movement_kind") == &"safe_retreat":
		return _valid_safe_retreat_draft(draft, context)
	if ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "from_cell": TYPE_VECTOR2I, "to_cell": TYPE_VECTOR2I, "movement_kind": TYPE_STRING_NAME, "move_cost": TYPE_FLOAT, "move_before": TYPE_FLOAT, "move_after": TYPE_FLOAT}):
		if draft["kind"] != &"moved" or draft["movement_kind"] != &"voluntary": return false
		if draft["actor_unit_id"] <= 0 or draft["actor_unit_id"] >= MAX_ID or draft["target_unit_id"] != draft["actor_unit_id"]: return false
		var dx: int = int(draft["to_cell"].x) - int(draft["from_cell"].x)
		var dy: int = int(draft["to_cell"].y) - int(draft["from_cell"].y)
		if absi(dx) + absi(dy) != 1: return false
		var cost: float = draft["move_cost"]
		var before: float = draft["move_before"]
		var after: float = draft["move_after"]
		return is_finite(cost) and cost >= 1.0 and is_finite(before) and before >= cost and is_finite(after) and after >= 0.0 and after < before and after == before - cost and before - after == cost
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "source": TYPE_DICTIONARY, "hp_before": TYPE_FLOAT, "hp_after": TYPE_FLOAT, "amount": TYPE_FLOAT, "alive_before": TYPE_BOOL, "alive_after": TYPE_BOOL}): return false
	if draft["kind"] not in [&"damaged", &"healed", &"died"]: return false
	for key: String in ["hp_before", "hp_after", "amount"]:
		if not is_finite(draft[key]) or draft[key] < 0.0: return false
	if draft["kind"] == &"died" and draft["amount"] != 0.0: return false
	var source: Dictionary = draft["source"]
	if source.get("kind") == &"mage" and not DamageSource.valid_mage(source): return false
	if not ItemSimulationSnapshot._shape(source, {"kind": TYPE_STRING_NAME, "source_instance_id": TYPE_INT, "origin_cell": TYPE_VECTOR2I, "instigator_unit_id": TYPE_INT, "credit_unit_id": TYPE_INT}): return false
	if source["kind"] not in DamageSource.KINDS or source["instigator_unit_id"] != draft["actor_unit_id"]: return false
	for key: String in ["source_instance_id", "instigator_unit_id", "credit_unit_id"]:
		if source[key] < 0 or source[key] >= MAX_ID: return false
	return draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID

static func _valid_transit_draft(draft: Dictionary, context: ActionContext) -> bool:
	if context == null or context.get_move_rules() == null or context.get_move_rules().get_profile() != &"spatial_move_v1": return false
	if draft.get("kind") != &"moved" or draft.get("movement_kind") not in [&"voluntary", &"safe_retreat"]: return false
	var path_value: Variant = draft["transit_path"]
	if not path_value is Array or path_value.size() < 3 or path_value.size() > MoveCommand.MAX_PATH_CELLS: return false
	for index in range(path_value.size()):
		if typeof(path_value[index]) != TYPE_VECTOR2I: return false
		if index > 0:
			var dx: int = int(path_value[index].x) - int(path_value[index - 1].x)
			var dy: int = int(path_value[index].y) - int(path_value[index - 1].y)
			if absi(dx) + absi(dy) != 1: return false
	if path_value[0] != draft.get("from_cell") or path_value[-1] != draft.get("to_cell") or path_value[0] == path_value[-1]: return false
	# Старый строгий формат и арифметику сохраняем; только новый сегмент несёт весь путь.
	var adjacent := draft.duplicate(true)
	adjacent.erase("transit_path")
	adjacent["from_cell"] = path_value[-2]
	if draft["movement_kind"] == &"safe_retreat": return _valid_safe_retreat_draft(adjacent, context) and float(draft["move_cost"]) >= float(path_value.size() - 1)
	# Каждое ребро стоит хотя бы 1. Геометрию заново не читаем: callback мог
	# изменить её, а fault обязан сохранить событие уже оплаченного сегмента.
	return valid_draft(adjacent, context) and float(draft["move_cost"]) >= float(path_value.size() - 1)

static func _valid_safe_retreat_draft(draft: Dictionary, context: ActionContext) -> bool:
	var fields := {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "from_cell": TYPE_VECTOR2I, "to_cell": TYPE_VECTOR2I, "movement_kind": TYPE_STRING_NAME, "move_cost": TYPE_FLOAT, "move_before": TYPE_FLOAT, "move_after": TYPE_FLOAT, "main_cost": TYPE_INT, "main_before": TYPE_INT, "main_after": TYPE_INT}
	if not ItemSimulationSnapshot._shape(draft, fields): return false
	if context == null or context.get_move_rules() == null or context.get_move_rules().get_profile() != &"spatial_move_v1": return false
	if draft["kind"] != &"moved" or draft["movement_kind"] != &"safe_retreat" or draft["actor_unit_id"] <= 0 or draft["actor_unit_id"] >= MAX_ID or draft["target_unit_id"] != draft["actor_unit_id"]: return false
	var dx: int = int(draft["to_cell"].x) - int(draft["from_cell"].x)
	var dy: int = int(draft["to_cell"].y) - int(draft["from_cell"].y)
	var cost: float = draft["move_cost"]
	var before: float = draft["move_before"]
	var after: float = draft["move_after"]
	var main_cost: int = draft["main_cost"]
	var main_before: int = draft["main_before"]
	return absi(dx) + absi(dy) == 1 and is_finite(cost) and cost >= 1.0 and is_finite(before) and before >= cost and is_finite(after) and after >= 0.0 and after < before and after == before - cost and before - after == cost and main_cost in [0, 1] and main_before >= main_cost and main_before <= 4096 and draft["main_after"] == main_before - main_cost

static func _valid_bleeding_draft(draft: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "reason": TYPE_STRING_NAME, "before": TYPE_DICTIONARY, "after": TYPE_DICTIONARY}): return false
	if draft["actor_unit_id"] < 0 or draft["actor_unit_id"] >= MAX_ID or draft["target_unit_id"] < 1 or draft["target_unit_id"] >= MAX_ID: return false
	var before: Dictionary = draft["before"]; var after: Dictionary = draft["after"]
	if not BleedingState.valid(before) or not BleedingState.valid(after) or before["immune"] != after["immune"]: return false
	if before["stacked"] or after["stacked"]:
		return _valid_stacked_bleeding(draft)
	if draft["actor_unit_id"] == 0: return false
	if draft["reason"] == &"tick":
		if before["ticks_left"] < 1 or after["ticks_left"] != before["ticks_left"] - 1 or before["source"]["instigator_unit_id"] != draft["actor_unit_id"]: return false
		return after["ticks_left"] == 0 or (after["source"] == before["source"] and after["hit_id"] == before["hit_id"])
	if before["ticks_left"] > BleedingState.MAX_TICKS - BleedingState.DURATION: return false
	return not after["immune"] and after["ticks_left"] == before["ticks_left"] + BleedingState.DURATION and after["source"]["instigator_unit_id"] == draft["actor_unit_id"] and ((draft["reason"] == &"applied" and before["ticks_left"] == 0) or (draft["reason"] == &"refreshed" and before["ticks_left"] > 0))

static func _valid_control_draft(draft: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "target_unit_id": TYPE_INT, "before": TYPE_DICTIONARY, "after": TYPE_DICTIONARY, "reason": TYPE_STRING_NAME}): return false
	if draft["target_unit_id"] <= 0 or draft["target_unit_id"] >= MAX_ID or not ControlState.valid(draft["before"]) or not ControlState.valid(draft["after"]): return false
	var before: Dictionary = draft["before"]
	var after: Dictionary = draft["after"]
	if draft["reason"] == &"push": return before["entangled_turns"] == 1 and after["entangled_turns"] == 0 and before["stunned_turns"] == after["stunned_turns"]
	if draft["reason"] == &"turn_end": return before != after and after["stunned_turns"] == 0 and after["entangled_turns"] == 0
	if draft["reason"] in [&"entangled", &"refreshed"]:
		return after["entangled_turns"] == 1 and before["stunned_turns"] == after["stunned_turns"] and ((draft["reason"] == &"entangled" and before["entangled_turns"] == 0) or (draft["reason"] == &"refreshed" and before["entangled_turns"] == 1))
	if draft["reason"] in [&"stunned", &"stun_refreshed"]:
		return after["stunned_turns"] == 1 and before["entangled_turns"] == after["entangled_turns"] and ((draft["reason"] == &"stunned" and before["stunned_turns"] == 0) or (draft["reason"] == &"stun_refreshed" and before["stunned_turns"] == 1))
	return false

static func _valid_stacked_bleeding(draft: Dictionary) -> bool:
	var before: Dictionary = draft["before"]
	var after: Dictionary = draft["after"]
	if not before["stacked"] or not after["stacked"]: return false
	if draft["reason"] == &"burned":
		return before["ticks_left"] > 0 and after["ticks_left"] == 0
	if draft["reason"] == &"tick":
		if before["ticks_left"] < 1 or after["ticks_left"] != before["ticks_left"] - 1 or before["source"]["instigator_unit_id"] != draft["actor_unit_id"]: return false
		return after["ticks_left"] == 0 or (after["stacks"] == before["stacks"] and after["source"] == before["source"] and after["hit_id"] == before["hit_id"])
	if before["stacks"] == BleedingState.MAX_STACKS or after["immune"]: return false
	return after["ticks_left"] == 3 and after["stacks"] == before["stacks"] + 1 and after["source"]["instigator_unit_id"] == draft["actor_unit_id"] and ((draft["reason"] == &"applied" and before["ticks_left"] == 0) or (draft["reason"] == &"refreshed" and before["ticks_left"] > 0))

static func _valid_elemental_draft(draft: Dictionary) -> bool:
	if draft["kind"] == &"elemental_cast":
		if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "effect": TYPE_STRING_NAME, "main_before": TYPE_INT, "main_after": TYPE_INT}): return false
		return draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["effect"] in [&"burning", &"wet", &"freeze"] and draft["main_before"] > 0 and draft["main_before"] <= 4096 and draft["main_after"] == draft["main_before"] - 1
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "reason": TYPE_STRING_NAME, "before": TYPE_DICTIONARY, "after": TYPE_DICTIONARY}): return false
	if draft["actor_unit_id"] < 0 or draft["actor_unit_id"] >= MAX_ID or draft["target_unit_id"] < 1 or draft["target_unit_id"] >= MAX_ID: return false
	var before: Dictionary = draft["before"]
	var after: Dictionary = draft["after"]
	if not ElementalState.valid(before) or not ElementalState.valid(after) or before == after or before["freeze_immune"] != after["freeze_immune"]: return false
	var ticks := 1
	if draft["reason"] == &"burning" and after["burning_ticks"] > before["burning_ticks"]: ticks = after["burning_ticks"] - before["burning_ticks"]
	if draft["reason"] == &"freeze" and after["frozen_turns"] > before["frozen_turns"]: ticks = after["frozen_turns"] - before["frozen_turns"]
	# Источник нужен лишь для ветки действительного горения; отмена его не хранит.
	var source: Dictionary = after["burning_source"] if after["burning_stacks"] > 0 else DamageSource.new(&"cell", 1, Vector2i.ZERO).to_dict()
	var expected := ElementalRules.transition(before, draft["reason"], ticks, source, true)
	return expected.get("reason", &"") == &"" and expected.get("after") == after

static func _valid_armor_draft(draft: Dictionary) -> bool:
	var fields := {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "source": TYPE_DICTIONARY}
	if draft.get("kind") == &"armor_changed": fields.merge({"grants": TYPE_ARRAY, "items": TYPE_ARRAY})
	else: fields.merge({"hit_id": TYPE_STRING, "hit": TYPE_DICTIONARY})
	if not ItemSimulationSnapshot._shape(draft, fields) or draft["target_unit_id"] < 1 or draft["target_unit_id"] >= MAX_ID: return false
	var source: Dictionary = draft["source"]
	if source.get("kind") == &"mage" and not DamageSource.valid_mage(source): return false
	if not ItemSimulationSnapshot._shape(source, {"kind": TYPE_STRING_NAME, "source_instance_id": TYPE_INT, "origin_cell": TYPE_VECTOR2I, "instigator_unit_id": TYPE_INT, "credit_unit_id": TYPE_INT}) or source["kind"] not in DamageSource.KINDS or source["instigator_unit_id"] != draft["actor_unit_id"]: return false
	for key: String in ["source_instance_id", "instigator_unit_id", "credit_unit_id"]:
		if source[key] < 0 or source[key] >= MAX_ID: return false
	if draft["kind"] == &"armor_changed":
		if draft["grants"].is_empty() and draft["items"].is_empty(): return false
		for changes: Array in [draft["grants"], draft["items"]]:
			for delta: Variant in changes:
				if not ItemSimulationSnapshot._shape(delta, {"id": TYPE_INT, "before": TYPE_INT, "after": TYPE_INT}) or delta["id"] < 1 or delta["before"] < 0 or delta["after"] < 0 or delta["before"] == delta["after"]: return false
		return true
	var hit: Dictionary = draft["hit"]
	return not draft["hit_id"].is_empty() and typeof(hit.get("rows")) == TYPE_ARRAY and typeof(hit.get("hp_before")) == TYPE_INT and typeof(hit.get("hp_after")) == TYPE_INT and typeof(hit.get("total_damage")) == TYPE_INT and typeof(hit.get("total_healing")) == TYPE_INT
