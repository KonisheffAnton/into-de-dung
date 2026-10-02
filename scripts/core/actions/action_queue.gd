extends RefCounted
class_name ActionQueue

const PresentationState = preload("res://scripts/core/actions/action_presentation_state.gd")

const MAX_ID: int = 9223372036854775807
var _max_commands: int
var _max_events: int
var _max_depth: int
var capture_presentation: bool = false
var _busy := false
var _faulted := false
var _pending: Array[Dictionary] = []
var _processed_event_seq: Dictionary = {}
var _reaction_keys: Dictionary = {}
var _dispatch_reason: StringName = &""
var _attack_stances: Array[Dictionary] = []
var _defer_item_reactions: bool = false
var _deferred_item_reactions: Array[Dictionary] = []
var _perk_guard: CombatPerkGuard

func _init(max_commands: int = 256, max_events: int = 512, max_depth: int = 32) -> void:
	_max_commands = max_commands
	_max_events = max_events
	_max_depth = max_depth

func copy_for_simulation() -> ActionQueue:
	if _busy or _faulted or get_script() != ActionQueue: return null
	# Только завершённая очередь: pending/reaction keys живут внутри одного submit.
	return ActionQueue.new(_max_commands, _max_events, _max_depth)

func submit(command: Command, context: ActionContext) -> ActionReceipt:
	var receipt := ActionReceipt.new()
	if context != null:
		receipt.revision_before = context.get_revision()
		receipt.revision_after = context.get_revision()
	if _busy or (context != null and context.is_busy()): return _reject(receipt, &"BUSY")
	if _faulted or (context != null and context.is_faulted()): return _reject(receipt, &"CONTEXT_FAULTED")
	if context == null: return _reject(receipt, &"invalid_context")
	# Оба guards предшествуют пользовательским copy/validate, включая другой экземпляр очереди.
	_busy = true
	context._busy = true
	var reason: StringName = &""
	var accepted: Command = null
	if _max_commands < 1 or _max_commands > 4096 or _max_events < 1 or _max_events > 8192 or _max_depth < 1 or _max_depth > 64:
		reason = &"invalid_limits"
	elif context.get_state() == null or context.get_rng() == null or context.get_sink() == null:
		reason = &"invalid_context"
	elif command == null:
		reason = &"unknown_command"
	else:
		accepted = command.copy_for_queue()
		if accepted == null:
			reason = &"unknown_command"
		else:
			var capture := ItemSimulationSnapshot.capture(context.get_state(), context.get_unsupported_runtime_ids())
			if capture.code != ItemSnapshotResult.Code.OK:
				reason = &"BUSY" if capture.code == ItemSnapshotResult.Code.SNAPSHOT_BUSY else StringName(capture.reason)
			elif accepted is AttackCommand and (accepted as AttackCommand).is_reaction():
				reason = &"reaction/internal_attack"
			elif accepted is ReactionStopCommand:
				reason = &"reaction/internal_stop"
			elif accepted is AttackHitCommand:
				reason = &"attack/internal_hit"
			elif accepted is ArtifactHitEffectCommand or accepted is ArtifactFormationCommand or accepted is ArtifactRepairCommand:
				reason = &"artifact/internal_command"
			elif accepted is MoveFallCommand:
				reason = &"move/internal_fall"
			elif accepted is ArmorEndBattleCommand:
				reason = &"armor/internal_expiry"
			elif accepted is BleedingApplyCommand or accepted is BleedingTickCommand or accepted is BleedingMovementCommand or accepted is ElementalTickCommand or accepted is StatusTurnUnitCommand:
				reason = &"bleeding/internal_command"
			elif accepted is ControlExpireCommand or accepted is ControlApplyCommand:
				reason = &"control/internal_command"
			elif accepted is EnvironmentCommand:
				reason = &"environment/internal_command"
			elif accepted is CollapseCellCommand:
				reason = &"collapse/internal_command"
			elif accepted is DeathCommand and ((accepted as DeathCommand)._has_spatial_binding or (accepted as DeathCommand)._spatial_binding != null):
				reason = &"move/internal_death"
			elif accepted is MoveCommand and (accepted as MoveCommand)._is_continuation():
				reason = &"move/internal_continuation"
			elif accepted is BalanceCommand:
				reason = &"balance/internal_command"
			elif accepted is PushChainCommand:
				reason = &"chain/internal_command"
			elif accepted is PushCommand:
				reason = &"push/internal_command"
			elif accepted is PushDamageCommand:
				reason = &"push/internal_damage"
			elif accepted is CollisionDamageCommand:
				reason = &"push/internal_collision"
			else: reason = accepted.validate(context)
	if reason == &"" and not AbilityCatalog.attack_references_valid(context): reason = &"ability/attack_catalog"
	if reason == &"" and context.get_state().artifacts != null and not BattleArtifactRules.references_valid(context): reason = &"artifact/attack_catalog"
	if reason == &"" and context.get_state().abilities != null and accepted.get_script() in [AttackCommand, MoveCommand, GuardCommand, RestoreArmorCommand, RaiseCorpseCommand, ElementalCastCommand, UseHealingItemCommand, UseSummoningItemCommand, MageCastCommand]:
		var descriptor := accepted.get_ability_definition(context)
		var registered := context.get_state().abilities.definition(descriptor.ability_id) if descriptor != null else null
		if descriptor == null or registered == null or descriptor.to_dict() != registered.to_dict(): reason = &"ability/unregistered_action"
	if reason == &"" and (context._next_root_id < 1 or context._next_root_id >= MAX_ID or not _can_step(context)):
		reason = &"sequence_exhausted"
	if reason != &"":
		_release(context)
		return _reject(receipt, reason)
	receipt.status = &"APPLIED"
	receipt.root_id = context._take_root_id()
	_perk_guard = CombatPerkGuard.capture(context.get_state().get_board())
	if accepted is AttackCommand:
		var attacker := (accepted as AttackCommand).get_actor_unit_id()
		var definition := context.get_attack_rules().get_definition((accepted as AttackCommand).get_attack_definition_id())
		_defer_item_reactions = definition != null and (definition.bleeding_policy != &"" or definition.entangle_on_physical_hp or definition.stun_on_physical_hp or definition.chain_push)
		if context.get_state().artifacts != null and context.get_state().artifacts.ordinary(attacker,(accepted as AttackCommand).get_attack_definition_id()): _defer_item_reactions = true
		# Срок отмены — весь каскад атаки, включая legacy balance/push и item-heal.
		for unit in context.get_state().get_board().get_all_units():
			_attack_stances.append({"unit": unit, "expected": false if unit.id == attacker else unit.guard_stance})
	_pending.append({"command": accepted, "parent_event_seq": 0, "depth": 0})
	var ability_ref := context.get_state().abilities
	var ability_definitions: Array = ability_ref.catalog.duplicate() if ability_ref != null else []
	var ability_expected: Dictionary = ability_ref.to_dict() if ability_ref != null else {}
	if accepted is MageCastCommand: ability_expected = (accepted as MageCastCommand).projected_after(context)
	if accepted is AbilityBoundaryCommand: ability_expected = (accepted as AbilityBoundaryCommand).projected_after(context)
	var ability_check := func() -> bool:
		return context.get_state().abilities == ability_ref and (ability_ref == null or (ability_ref.catalog == ability_definitions and ability_ref.to_dict() == ability_expected))
	var artifact_ref := context.get_state().artifacts
	var artifact_expected: Dictionary = artifact_ref.to_dict() if artifact_ref != null else {}
	var artifact_check := func() -> bool:
		return context.get_state().artifacts == artifact_ref and (artifact_ref == null or artifact_ref.to_dict() == artifact_expected)
	var armor_finish_scheduled := false
	# Единственный ответ принадлежит корневой добровольной атаке, не её событиям.
	var counter_considered := false
	while not _pending.is_empty() and receipt.status != &"FAULTED":
		var entry: Dictionary = _pending.pop_back()
		if receipt._steps.size() >= _max_commands:
			_fault(receipt, context, &"command_limit")
			break
		if entry["depth"] > _max_depth:
			_fault(receipt, context, &"depth_limit")
			break
		if not _can_step(context, _event_capacity(entry["command"] as Command)):
			_fault(receipt, context, &"sequence_exhausted")
			break
		if entry.command is ArtifactFormationCommand:
			var projected := (entry.command as ArtifactFormationCommand).projected_after(context)
			if not projected.is_empty(): artifact_expected.merge(projected,true)
		var step_count_before := receipt._steps.size()
		var event_count_before := receipt._events.size()
		_execute_entry(entry, receipt, context)
		if receipt.status != &"FAULTED" and not ability_check.call(): _fault(receipt, context, &"ability/checkpoint")
		if receipt.status != &"FAULTED" and not artifact_check.call(): _fault(receipt, context, &"artifact/checkpoint")
		if capture_presentation and receipt._steps.size() > step_count_before:
			var new_events: Array[Dictionary] = []
			for event_index: int in range(event_count_before, receipt._events.size()):
				new_events.append(receipt._events[event_index].duplicate(true))
			receipt._presentation_frames.append({
				"step": receipt._steps[-1].duplicate(true),
				"events": new_events,
				"after": PresentationState.capture(context.get_state()),
			})
		if _pending.is_empty() and receipt.status == &"APPLIED" and _defer_item_reactions:
			# Сначала spatial и состояния исходного hit, затем optional реакции предметов.
			_defer_item_reactions = false
			for i in range(_deferred_item_reactions.size() - 1, -1, -1): _pending.append(_deferred_item_reactions[i])
			_deferred_item_reactions.clear()
		if _pending.is_empty() and receipt.status == &"APPLIED" and not counter_considered:
			counter_considered = true
			var counter := _counterattack_after(accepted, context)
			if counter != null:
				var response := context.get_attack_rules().get_definition(counter.get_attack_definition_id())
				_defer_item_reactions = response.bleeding_policy != &""
				_pending.append({"command": counter, "parent_event_seq": int(receipt._events[0]["event_seq"]), "depth": 1})
		# Смерть на клетке прерывает продолжение пути, но уже завершает бой;
		# временная броня должна истечь и у такого корректного prefix.
		if _pending.is_empty() and receipt.status in [&"APPLIED", &"INTERRUPTED"] and not armor_finish_scheduled and ArmorEndBattleCommand.battle_over(context):
			armor_finish_scheduled = true
			var units := context.get_state().get_board().get_all_units()
			units.sort_custom(func(a: UnitState, b: UnitState) -> bool: return a.id < b.id)
			units.reverse()
			for unit: UnitState in units:
				if unit.armor != null and unit.armor.in_battle:
					_pending.append({"command": ArmorEndBattleCommand.new(unit.id), "parent_event_seq": 0, "depth": 0})
	if receipt.status in [&"APPLIED", &"INTERRUPTED"] and ability_ref != null and BattleAbilityState.battle_over(context.get_state()):
		if not ability_check.call(): _fault(receipt, context, &"ability/checkpoint")
		else:
			ability_expected["stage"] = "terminal"; ability_expected["mage_allowed"] = false
			ability_ref.apply_values(ability_expected)
			context._bump_revision()
	receipt.revision_after = context.get_revision()
	_pending.clear()
	# Публикация только завершённого prefix; sink не участвует в вычислении реакций.
	for event in receipt._events:
		context.get_sink().publish(event.duplicate(true))
		if receipt.status != &"FAULTED" and not ability_check.call():
			_fault(receipt, context, &"ability/checkpoint")
			break
		if receipt.status != &"FAULTED" and not artifact_check.call():
			_fault(receipt, context, &"artifact/checkpoint")
			break
	_processed_event_seq.clear()
	_reaction_keys.clear()
	_dispatch_reason = &""
	_release(context)
	return receipt

static func _counterattack_after(root: Command, context: ActionContext) -> AttackCommand:
	if root.get_script() != AttackCommand or (root as AttackCommand).is_reaction(): return null
	var attack := root as AttackCommand
	var rules := context.get_attack_rules()
	var definition := rules.get_definition(attack.get_attack_definition_id())
	var response := rules.get_definition(&"counter_strike")
	# Только прямой weapon pipeline с явно заданным обычным ответом.
	if definition == null or definition.profile != AttackRules.ARMOR_PROFILE or response == null or not response.reaction_strike: return null
	var board := context.get_state().get_board()
	var defender := board.get_unit_by_id(attack.get_target_unit_id())
	var attacker := board.get_unit_by_id(attack.get_actor_unit_id())
	if not MeleeThreat.reaction_ready(context, defender, CombatPerksState.Mode.COUNTERATTACK) or not MeleeThreat.threatens(context, defender, attacker): return null
	return AttackCommand.counterattack(defender, attacker, context.get_revision())

func _execute_entry(entry: Dictionary, receipt: ActionReceipt, context: ActionContext) -> void:
	var command: Command = entry["command"]
	var seq := context._take_command_seq()
	var result: CommandStepResult
	# HP-команды сами различают исчезнувшую цель и неверный payload. Остальные
	# доверенные реализации также обязаны подтвердить дочерний payload до execute.
	if not receipt._steps.is_empty() and not (command is DamageCommand or command is HealCommand or command is DeathCommand):
		var reason := command.validate(context)
		result = command.execute(context) if reason == &"" else CommandStepResult.faulted(reason)
	else:
		result = command.execute(context)
	var step := {"command_seq": seq, "parent_event_seq": int(entry["parent_event_seq"]), "kind": command.get_kind(), "status": &"FAULTED", "reason": &"malformed_step"}
	receipt._steps.append(step)
	if result == null:
		_fault(receipt, context, &"malformed_step")
		return
	if result.state_changed: context._bump_revision()
	if result.status not in [&"APPLIED", &"SKIPPED", &"FAULTED", &"INTERRUPTED"] or result.events.size() > _event_capacity(command) or (result.status == &"SKIPPED" and (result.state_changed or not result.events.is_empty())) or (result.status == &"INTERRUPTED" and (result.state_changed or not result.events.is_empty() or not result.mandatory.is_empty() or not result.reactions.is_empty() or result.continuation != null)):
		_fault(receipt, context, &"malformed_step")
		return
	step["status"] = result.status
	step["reason"] = result.reason
	if result.status == &"INTERRUPTED":
		if receipt.status == &"APPLIED":
			receipt.status = &"INTERRUPTED"
			if receipt.reason == &"": receipt.reason = result.reason
		return
	var events: Array[Dictionary] = []
	for draft in result.events:
		if not _valid_draft(draft, context):
			step["status"] = &"FAULTED"
			step["reason"] = &"malformed_event"
			_fault(receipt, context, &"malformed_event")
			return
		var event := draft.duplicate(true)
		event["event_seq"] = context._take_event_seq()
		event["root_id"] = receipt.root_id
		event["command_seq"] = seq
		event["parent_event_seq"] = int(entry["parent_event_seq"])
		events.append(event)
		receipt._events.append(event)
	if result.status == &"FAULTED":
		_fault(receipt, context, result.reason)
		return
	if not result.combat_perk_changes.is_empty():
		if command.get_script() not in [AttackCommand, GuardCommand, BattleTurnRefill]:
			_fault(receipt, context, &"perks/invalid_delta")
			return
		if _perk_guard == null:
			_fault(receipt, context, &"perks/invalid_delta")
			return
		_perk_guard.accept(result.combat_perk_changes)
	if _perk_guard != null and not _perk_guard.check(context.get_state().get_board()):
		if not result.state_changed: context._bump_revision()
		_fault(receipt, context, &"perks/invalid_runtime")
		return
	for stance in _attack_stances:
		var unit: UnitState = stance["unit"]
		if unit.guard_stance != stance["expected"]:
			# Шаг и его события уже записаны; непроверенный хвост больше не исполняется.
			if not result.state_changed: context._bump_revision()
			step["status"] = &"FAULTED"
			step["reason"] = &"attack/invalid_stance"
			_fault(receipt, context, &"attack/invalid_stance")
			return
	# Атомарный шаг целиком остаётся в prefix, даже когда он пересёк event limit.
	if receipt._events.size() > _max_events:
		_fault(receipt, context, &"event_limit")
		return
	var children: Array[Dictionary] = []
	var item_reactions: Array[Dictionary] = []
	for event in events:
		for reaction in _dispatch_event(event, context):
			item_reactions.append({"command": reaction, "parent_event_seq": int(event["event_seq"]), "depth": int(entry["depth"]) + 1})
		if _dispatch_reason != &"":
			_fault(receipt, context, _dispatch_reason)
			return
	for child in result.mandatory: children.append({"command": child, "parent_event_seq": 0, "depth": int(entry["depth"]) + 1})
	# Среда следует после обязательного падения/столкновения, до реакций предметов
	# и до следующего сегмента добровольного пути. Preview использует тот же путь.
	for event in events:
		for child in EnvironmentRules.consequences(event, context):
			children.append({"command": child, "parent_event_seq": int(event["event_seq"]), "depth": int(entry["depth"]) + 1})
	for child in result.reactions: item_reactions.append({"command": child, "parent_event_seq": 0, "depth": int(entry["depth"]) + 1})
	if _defer_item_reactions:
		for child: Dictionary in item_reactions:
			var original: Command = child["command"]
			var copy: Command = original.copy_for_queue() if original != null else null
			if copy == null:
				_fault(receipt, context, &"invalid_child")
				return
			_deferred_item_reactions.append({"command": copy, "parent_event_seq": child["parent_event_seq"], "depth": child["depth"]})
	else: children.append_array(item_reactions)
	if result.continuation != null: children.append({"command": result.continuation, "parent_event_seq": 0, "depth": int(entry["depth"]) + 1})
	var copies: Array[Dictionary] = []
	for child in children:
		var original: Command = child["command"]
		var copy: Command = original.copy_for_queue() if original != null else null
		if copy == null:
			_fault(receipt, context, &"invalid_child")
			return
		copies.append({"command": copy, "parent_event_seq": child["parent_event_seq"], "depth": child["depth"]})
	# LIFO обращает только список siblings, каждое поддерево завершается до следующего.
	for i in range(copies.size() - 1, -1, -1): _pending.append(copies[i])

func _dispatch_event(event: Dictionary, context: ActionContext) -> Array[Command]:
	var seq: int = event["event_seq"]
	if _processed_event_seq.has(seq): return []
	_processed_event_seq[seq] = true
	if event["kind"] != &"damaged": return []
	var collected := ItemReactionCollector.collect_damage(context.get_state(), {"event_seq": seq, "target_unit_id": int(event["target_unit_id"]), "dealt": float(event["amount"])})
	if collected.code != ItemReactionResult.Code.OK:
		_dispatch_reason = StringName("collector/" + collected.reason)
		return []
	return _bind_batch(collected.descriptions, seq, context)

func _bind_batch(descriptions: Array[Dictionary], event_seq: int, context: ActionContext) -> Array[Command]:
	var result: Array[Command] = []
	var batch: Dictionary = {}
	var ordered: Array[Dictionary] = []
	for description in descriptions:
		var bound := ItemReactionAdapter.bind(description, context)
		if bound == null or description["event_seq"] != event_seq:
			_dispatch_reason = &"invalid_reaction"
			return []
		var key: Array = [event_seq, description["priority"], description["owner_unit_id"], description["effect_instance_id"], description["local_index"]]
		if batch.has(key):
			_dispatch_reason = &"duplicate_reaction_key"
			return []
		batch[key] = true
		ordered.append({"key": key, "command": bound})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		for i in 5:
			if a["key"][i] != b["key"][i]: return a["key"][i] < b["key"][i]
		return false)
	for record in ordered:
		if _reaction_keys.has(record["key"]): continue
		_reaction_keys[record["key"]] = true
		result.append(record["command"] as Command)
	return result

static func _valid_draft(draft: Dictionary, context: ActionContext = null) -> bool:
	if draft.get("kind") == &"mage_cast": return MageCastCommand.valid_draft(draft)
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
		return _valid_draft(guarded, context)
	if draft.get("kind") in [&"opportunity_attacked", &"counterattacked"] and not draft.has("modifiers"):
		if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "attack_definition_id": TYPE_STRING_NAME, "actor_cell": TYPE_VECTOR2I, "target_cell": TYPE_VECTOR2I, "main_cost": TYPE_INT, "main_before": TYPE_INT, "main_after": TYPE_INT}): return false
		if context == null: return false
		var reaction_def := context.get_attack_rules().get_definition(draft["attack_definition_id"])
		return reaction_def != null and reaction_def.reaction_strike and draft["actor_unit_id"] > 0 and draft["actor_unit_id"] < MAX_ID and draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID and draft["actor_unit_id"] != draft["target_unit_id"] and draft["main_cost"] == 0 and draft["main_before"] >= 0 and draft["main_before"] <= 4096 and draft["main_after"] == draft["main_before"]
	if draft.get("kind") == &"corpse_created": return EnvironmentRules.valid_draft(draft)
	if draft.get("kind") == &"corpse_raised": return RaiseCorpseCommand.valid_draft(draft)
	if draft.get("kind") == &"bleeding_changed": return _valid_bleeding_draft(draft)
	if draft.get("kind") == &"control_changed": return _valid_control_draft(draft)
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
			return _valid_draft(reduced, context)
		if not ItemSimulationSnapshot._shape(draft["modifiers"], {"backstab_percent": TYPE_INT, "critical": TYPE_BOOL}): return false
		var clean := draft.duplicate(true)
		clean.erase("modifiers")
		if not _valid_draft(clean, context): return false
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
	return _valid_draft(adjacent, context) and float(draft["move_cost"]) >= float(path_value.size() - 1)

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

static func _event_capacity(command: Command) -> int:
	if command is PushChainCommand: return 9
	if command is AttackCommand and (command as AttackCommand).is_reaction(): return 3
	if command is PushCommand and (command as PushCommand)._binding != null and (command as PushCommand)._binding.target != null and (command as PushCommand)._binding.target.control != null: return 4
	if command is ElementalCastCommand or command is MageCastCommand: return 7
	if command is ElementalTickCommand: return 5
	if command is BleedingMovementCommand: return 4
	if command is EnvironmentCommand: return 4
	if command is BleedingTickCommand: return 5
	if command is CollisionDamageCommand and (command as CollisionDamageCommand)._binding != null and (command as CollisionDamageCommand)._binding.values.get("armor", false): return 8
	if command is DamageCommand and (command as DamageCommand).request != null and (command as DamageCommand).request.armor_mode == &"armor": return 4
	if command is MoveFallCommand and (command as MoveFallCommand)._binding != null and (command as MoveFallCommand)._binding.request != null and (command as MoveFallCommand)._binding.request.armor_mode == &"armor": return 4
	return 4 if command != null and command.get_script() == CollisionDamageCommand else 2

static func _valid_bleeding_draft(draft: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "reason": TYPE_STRING_NAME, "before": TYPE_DICTIONARY, "after": TYPE_DICTIONARY}): return false
	if draft["actor_unit_id"] < 0 or draft["actor_unit_id"] >= MAX_ID or draft["target_unit_id"] < 1 or draft["target_unit_id"] >= MAX_ID: return false
	var before: Dictionary = draft["before"]; var after: Dictionary = draft["after"]
	if not BleedingState.valid(before) or not BleedingState.valid(after) or before["immune"] != after["immune"]: return false
	if before["schema_version"] == 3 or after["schema_version"] == 3:
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
	if before["schema_version"] != 3 or after["schema_version"] != 3: return false
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

static func _can_step(context: ActionContext, event_capacity: int = 2) -> bool:
	return context._next_command_seq >= 1 and context._next_command_seq < MAX_ID and context._next_event_seq >= 1 and context._next_event_seq <= MAX_ID - event_capacity and context._revision >= 0 and context._revision < MAX_ID - 1

func _fault(receipt: ActionReceipt, context: ActionContext, reason: StringName) -> void:
	receipt.status = &"FAULTED"
	receipt.reason = reason
	_faulted = true
	context._faulted = true
	_pending.clear()

func _release(context: ActionContext) -> void:
	_perk_guard = null
	_attack_stances.clear()
	_deferred_item_reactions.clear()
	_defer_item_reactions = false
	_busy = false
	context._busy = false

static func _reject(receipt: ActionReceipt, reason: StringName) -> ActionReceipt:
	receipt.reason = reason
	return receipt
