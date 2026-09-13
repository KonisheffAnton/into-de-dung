extends RefCounted
class_name ActionQueue

const MAX_ID: int = 9223372036854775807
var _max_commands: int
var _max_events: int
var _max_depth: int
var _busy := false
var _faulted := false
var _pending: Array[Dictionary] = []
var _processed_event_seq: Dictionary = {}
var _reaction_keys: Dictionary = {}
var _dispatch_reason: StringName = &""

func _init(max_commands: int = 256, max_events: int = 512, max_depth: int = 32) -> void:
	_max_commands = max_commands
	_max_events = max_events
	_max_depth = max_depth

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
			else: reason = accepted.validate(context)
	if reason == &"" and (context._next_root_id < 1 or context._next_root_id >= MAX_ID or not _can_step(context)):
		reason = &"sequence_exhausted"
	if reason != &"":
		_release(context)
		return _reject(receipt, reason)
	receipt.status = &"APPLIED"
	receipt.root_id = context._take_root_id()
	_pending.append({"command": accepted, "parent_event_seq": 0, "depth": 0})
	while not _pending.is_empty() and receipt.status != &"FAULTED":
		var entry: Dictionary = _pending.pop_back()
		if receipt._steps.size() >= _max_commands:
			_fault(receipt, context, &"command_limit")
			break
		if entry["depth"] > _max_depth:
			_fault(receipt, context, &"depth_limit")
			break
		if not _can_step(context):
			_fault(receipt, context, &"sequence_exhausted")
			break
		_execute_entry(entry, receipt, context)
	receipt.revision_after = context.get_revision()
	_pending.clear()
	# Публикация только завершённого prefix; sink не участвует в вычислении реакций.
	for event in receipt._events: context.get_sink().publish(event.duplicate(true))
	_processed_event_seq.clear()
	_reaction_keys.clear()
	_dispatch_reason = &""
	_release(context)
	return receipt

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
	if result.status not in [&"APPLIED", &"SKIPPED", &"FAULTED"] or result.events.size() > 2 or (result.status == &"SKIPPED" and (result.state_changed or not result.events.is_empty())):
		_fault(receipt, context, &"malformed_step")
		return
	step["status"] = result.status
	step["reason"] = result.reason
	var events: Array[Dictionary] = []
	for draft in result.events:
		if not _valid_draft(draft):
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
	children.append_array(item_reactions)
	for child in result.reactions: children.append({"command": child, "parent_event_seq": 0, "depth": int(entry["depth"]) + 1})
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

static func _valid_draft(draft: Dictionary) -> bool:
	if not ItemSimulationSnapshot._shape(draft, {"kind": TYPE_STRING_NAME, "actor_unit_id": TYPE_INT, "target_unit_id": TYPE_INT, "source": TYPE_DICTIONARY, "hp_before": TYPE_FLOAT, "hp_after": TYPE_FLOAT, "amount": TYPE_FLOAT, "alive_before": TYPE_BOOL, "alive_after": TYPE_BOOL}): return false
	if draft["kind"] not in [&"damaged", &"healed", &"died"]: return false
	for key: String in ["hp_before", "hp_after", "amount"]:
		if not is_finite(draft[key]) or draft[key] < 0.0: return false
	if draft["kind"] == &"died" and draft["amount"] != 0.0: return false
	var source: Dictionary = draft["source"]
	if not ItemSimulationSnapshot._shape(source, {"kind": TYPE_STRING_NAME, "source_instance_id": TYPE_INT, "origin_cell": TYPE_VECTOR2I, "instigator_unit_id": TYPE_INT, "credit_unit_id": TYPE_INT}): return false
	if source["kind"] not in DamageSource.KINDS or source["instigator_unit_id"] != draft["actor_unit_id"]: return false
	for key: String in ["source_instance_id", "instigator_unit_id", "credit_unit_id"]:
		if source[key] < 0 or source[key] >= MAX_ID: return false
	return draft["target_unit_id"] > 0 and draft["target_unit_id"] < MAX_ID

static func _can_step(context: ActionContext) -> bool:
	return context._next_command_seq >= 1 and context._next_command_seq < MAX_ID and context._next_event_seq >= 1 and context._next_event_seq <= MAX_ID - 2 and context._revision >= 0 and context._revision < MAX_ID - 1

func _fault(receipt: ActionReceipt, context: ActionContext, reason: StringName) -> void:
	receipt.status = &"FAULTED"
	receipt.reason = reason
	_faulted = true
	context._faulted = true
	_pending.clear()

func _release(context: ActionContext) -> void:
	_busy = false
	context._busy = false

static func _reject(receipt: ActionReceipt, reason: StringName) -> ActionReceipt:
	receipt.reason = reason
	return receipt
