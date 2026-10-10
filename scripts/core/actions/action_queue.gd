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
var _attack_policy: ActionAttackPolicy
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
	var admission := ActionAdmission.check(command, context, _max_commands, _max_events, _max_depth)
	var reason := admission.reason
	var accepted := admission.accepted
	if reason == &"" and (context._next_root_id < 1 or context._next_root_id >= MAX_ID or not _can_step(context)):
		reason = &"sequence_exhausted"
	if reason != &"":
		_release(context)
		return _reject(receipt, reason)
	receipt.status = &"APPLIED"
	receipt.root_id = context._take_root_id()
	context._current_root_id = receipt.root_id
	_perk_guard = CombatPerkGuard.capture(context.get_state().get_board())
	_attack_policy = ActionAttackPolicy.new(accepted, context)
	_pending.append({"command": accepted, "parent_event_seq": 0, "depth": 0})
	var ability_ref := context.get_state().abilities
	var ability_definitions: Array = ability_ref.catalog.duplicate() if ability_ref != null else []
	var ability_expected: Dictionary = ability_ref.to_dict() if ability_ref != null else {}
	if accepted is MageCastCommand: ability_expected = (accepted as MageCastCommand).projected_after(context)
	if accepted is PlayMageCardCommand: ability_expected = (accepted as PlayMageCardCommand).projected_after(context)
	if accepted is AbilityBoundaryCommand: ability_expected = (accepted as AbilityBoundaryCommand).projected_after(context)
	var ability_check := func() -> bool:
		return context.get_state().abilities == ability_ref and (ability_ref == null or (ability_ref.catalog == ability_definitions and ability_ref.to_dict() == ability_expected))
	var artifact_ref := context.get_state().artifacts
	var artifact_expected: Dictionary = artifact_ref.to_dict() if artifact_ref != null else {}
	var artifact_check := func() -> bool:
		return context.get_state().artifacts == artifact_ref and (artifact_ref == null or artifact_ref.to_dict() == artifact_expected)
	var armor_finish_scheduled := false
	var deck_ref := context.get_state().deck
	var effects_ref := context.get_state().card_effects
	var deck_rng: CombatRng = deck_ref.draw_rng if deck_ref != null else null
	var deck_expected: Dictionary = deck_ref.to_dict() if deck_ref != null else {}
	var effects_expected: Dictionary = effects_ref.to_dict() if effects_ref != null else {}
	if deck_ref != null:
		if accepted is PlayMageCardCommand:
			deck_expected = (accepted as PlayMageCardCommand).projected_deck(context)
			effects_expected = (accepted as PlayMageCardCommand).projected_effects(context)
		elif accepted is MageDeckChangeCommand: deck_expected = (accepted as MageDeckChangeCommand).projected_deck(context)
		elif accepted is AbilityBoundaryCommand:
			deck_expected = (accepted as AbilityBoundaryCommand).projected_deck(context)
			effects_expected = (accepted as AbilityBoundaryCommand).projected_effects(context)
	var deck_check := func() -> bool:
		return context.get_state().deck == deck_ref and context.get_state().card_effects == effects_ref and (deck_ref == null or (deck_ref.draw_rng == deck_rng and deck_ref.to_dict() == deck_expected and effects_ref.to_dict() == effects_expected))
	while not _pending.is_empty() and receipt.status != &"FAULTED":
		var entry: Dictionary = _pending.pop_back()
		if receipt._steps.size() >= _max_commands:
			_fault(receipt, context, &"command_limit")
			break
		if entry["depth"] > _max_depth:
			_fault(receipt, context, &"depth_limit")
			break
		var event_capacity := _reserved_event_capacity(entry["command"] as Command, context)
		if not _can_step(context, event_capacity):
			_fault(receipt, context, &"sequence_exhausted")
			break
		if entry.command is ArtifactFormationCommand:
			var projected := (entry.command as ArtifactFormationCommand).projected_after(context)
			if not projected.is_empty(): artifact_expected.merge(projected,true)
		var step_count_before := receipt._steps.size()
		var event_count_before := receipt._events.size()
		_execute_entry(entry, receipt, context, event_capacity, effects_ref, effects_expected)
		if receipt.status != &"FAULTED" and context._current_root_id != receipt.root_id: _fault(receipt, context, &"raise_shields/root_checkpoint")
		if deck_ref != null:
			# Новое admission принадлежит исполненному шагу, включая FAULTED prefix.
			if entry.command is UseSummoningItemCommand or entry.command is RaiseCorpseCommand:
				for binding: Dictionary in effects_ref.ordinary_attacks:
					if context.get_state().is_summon(binding.unit_id) and binding.attack_id == "demo_strike" and not effects_expected.ordinary_attacks.any(func(value: Dictionary) -> bool: return value.unit_id == binding.unit_id):
						effects_expected.ordinary_attacks.append(binding.duplicate(true))
		if receipt.status != &"FAULTED" and not deck_check.call(): _fault(receipt,context,&"deck/checkpoint")
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
		if _pending.is_empty() and receipt.status == &"APPLIED" and _attack_policy.finish_deferred_phase():
			# Сначала spatial и состояния исходного hit, затем optional реакции предметов.
			for i in range(_deferred_item_reactions.size() - 1, -1, -1): _pending.append(_deferred_item_reactions[i])
			_deferred_item_reactions.clear()
		if _pending.is_empty() and receipt.status == &"APPLIED":
			var counter := _attack_policy.take_counterattack(context)
			if counter != null:
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
			if effects_ref != null:
				effects_ref.fire_imbues.clear(); effects_expected.fire_imbues.clear()
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
		if receipt.status != &"FAULTED" and not deck_check.call():
			_fault(receipt, context, &"deck/checkpoint")
			break
	_processed_event_seq.clear()
	_reaction_keys.clear()
	_dispatch_reason = &""
	_release(context)
	return receipt

func _execute_entry(entry: Dictionary, receipt: ActionReceipt, context: ActionContext, event_capacity: int, effects_ref: BattleCardEffectState, effects_expected: Dictionary) -> void:
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
	if result.status not in [&"APPLIED", &"SKIPPED", &"FAULTED", &"INTERRUPTED"] or result.events.size() > event_capacity or (result.status == &"SKIPPED" and (result.state_changed or not result.events.is_empty())) or (result.status == &"INTERRUPTED" and (result.state_changed or not result.events.is_empty() or not result.mandatory.is_empty() or not result.reactions.is_empty() or result.continuation != null)):
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
		if not ActionEventValidator.valid_draft(draft, context):
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
		if effects_ref != null and event.kind == &"died":
			# Очистка входит в подтверждённый prefix смерти до snapshot коллектора
			# реакций; внешние callbacks шага уже прошли свои фазовые guards.
			var id: int = event.target_unit_id
			effects_ref.fire_imbues = effects_ref.fire_imbues.filter(func(value: Dictionary) -> bool: return value.unit_id != id)
			effects_expected.fire_imbues = effects_expected.fire_imbues.filter(func(value: Dictionary) -> bool: return value.unit_id != id)
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
	if not _attack_policy.stances_valid():
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
	if _attack_policy.defer_item_reactions:
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

static func _reserved_event_capacity(command: Command, context: ActionContext) -> int:
	# Резерв фиксируется до execute: исчезнувший щит всё равно оставляет событие.
	# Без щита сохраняется прежняя граница sequence_exhausted.
	var ids: Array[int] = []
	if command is PushChainCommand:
		var chain := command as PushChainCommand
		if chain._stage == &"pair": ids.assign(chain._pair_target_ids())
	elif command is CollisionDamageCommand:
		var collision := command as CollisionDamageCommand
		if collision._binding != null and collision._binding.values.get("armor", false):
			for request: DamageRequest in [collision._first, collision._second]:
				if request != null: ids.append(request.target_unit_id)
	elif command is DamageCommand:
		var request := (command as DamageCommand).request
		if request != null and request.armor_mode == &"armor": ids.append(request.target_unit_id)
	elif command is MoveFallCommand:
		var binding := (command as MoveFallCommand)._binding
		if binding != null and binding.request != null and binding.request.armor_mode == &"armor": ids.append(binding.request.target_unit_id)
	elif command is ElementalTickCommand:
		var tick := command as ElementalTickCommand
		if tick._unit != null and not tick._expire: ids.append(tick._unit.id)
	elif command is EnvironmentCommand:
		var environment := command as EnvironmentCommand
		if environment._target != null and not environment._death: ids.append(environment._target.id)
	var capacity := _event_capacity(command)
	for id: int in ids:
		var unit := context.get_state().get_board().get_unit_by_id(id)
		if unit != null and unit.armor != null and not unit.armor.shield.is_empty(): capacity += 1
		if unit != null and unit.armor != null and not unit.armor.raised_shield.is_empty(): capacity += 1
	# Корневые заклинания исполняют прямой hit внутри собственного шага.
	if command is ElementalCastCommand or command is MageCastCommand or command is PlayMageCardCommand:
		for unit: UnitState in context.get_state().get_board().get_all_units():
			if unit.armor != null and not unit.armor.raised_shield.is_empty(): capacity += 1
	return capacity

static func _event_capacity(command: Command) -> int:
	if command is HazardCommand: return 3
	if command is AcidCommand: return 2
	if command is PlayMageCardCommand: return 9
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
	_attack_policy = null
	_deferred_item_reactions.clear()
	_busy = false
	context._busy = false
	context._current_root_id = 0

static func _reject(receipt: ActionReceipt, reason: StringName) -> ActionReceipt:
	receipt.reason = reason
	return receipt
