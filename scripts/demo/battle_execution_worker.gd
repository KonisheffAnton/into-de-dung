extends RefCounted
class_name BattleExecutionWorker

## Session передаётся целиком одному исполнителю; UI возвращает её только после join.
const METHODS: Array[StringName] = [&"move_to", &"retreat_to", &"attack_unit", &"cast_unit", &"cast_mage_spell", &"cast_mage_cell", &"guard_selected", &"use_healing_item", &"use_summoning_item", &"raise_corpse", &"restore_selected_armor", &"set_reaction_guard", &"end_player_turn", &"step_enemy"]

var _thread: Thread
var _session: BattleCoreReactionsSession
var method: StringName
var target_attempt: bool = false

static func can_transfer(session: BattleDemoSession) -> bool:
	var runtime_scripts: Array[Script] = [BattleAbilityState, AbilityDefinition, BattleCoreReactionsSession, BattleBoard, ItemSimulationState, ActionQueue, ActionContext, ActionRngPort, CombatRng, ActionEventSink, MoveRules, AttackRules, AttackDefinition, UnitState, StatsBag, Stat, StatModifier, Vitals, ActionResources, ArmorState, BleedingState, ElementalState, ControlState, CombatPerksState, CombatPerksDefinition, CombatEnvironmentState, ItemOwnerState, InventoryState, EquipmentState, ItemInstance, ItemDef, SummonDefinition, HealOnDamageEffect, HealOnDamageEffectRuntime, StatModifierEffect, StatModifierEffectRuntime]
	runtime_scripts.append(BattleArtifactState)
	if session == null or session.get_script() != BattleCoreReactionsSession: return false
	if session.context == null or session._queue == null or session._queue.get_script() != ActionQueue: return false
	if session.context.is_busy() or session._queue._busy: return false
	if session.state.artifacts != null and not BattleArtifactRules.references_valid(session.context): return false
	# Это проверка владения, не замена capture/admission внутри реального submit.
	# Старый receipt не исполняется повторно; очередь тоже входит в аудит графа.
	var pending: Array = [session]
	var seen: Dictionary = {}
	var budget: int = 50000
	while not pending.is_empty():
		budget -= 1
		if budget < 0: return false
		var value: Variant = pending.pop_back()
		if value is Callable or value is Signal: return false
		if value is Array:
			pending.append_array(value)
		elif value is Dictionary:
			pending.append_array(value.keys())
			pending.append_array(value.values())
		elif value is Object:
			var object := value as Object
			if object == null: continue
			if seen.has(object.get_instance_id()): continue
			seen[object.get_instance_id()] = true
			if not (object is RandomNumberGenerator and object.get_script() == null) and object.get_script() not in runtime_scripts:
				return false
			for signal_info: Dictionary in object.get_signal_list():
				for connection: Dictionary in object.get_signal_connection_list(signal_info.name):
					if not _owned_death_callback(session, object, signal_info.name, connection):
						return false
			for property: Dictionary in object.get_property_list():
				if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
				var key: StringName = property.name
				if object == session and key == &"last_receipt": continue
				if object == session.board and key == &"_death_callbacks": continue
				pending.append(object.get(key))
	return true

static func _owned_death_callback(session: BattleDemoSession, object: Object, signal_name: StringName, connection: Dictionary) -> bool:
	if not object is Vitals or signal_name != &"died" or int(connection.flags) != 0: return false
	var callback: Callable = connection.callable
	if callback.get_object() != session.board or callback.get_method() != &"_on_registered_unit_died": return false
	var args := callback.get_bound_arguments()
	if args.size() != 3 or not args[0] is int or not args[1] is WeakRef or not args[2] is WeakRef: return false
	var unit := session.board.get_unit_by_id(args[0])
	return unit != null and unit.vitals == object and args[1].get_ref() == unit and args[2].get_ref() == object and session.board._death_callbacks.get(unit.id) == callback

func is_started() -> bool:
	return _thread != null

func start(session: BattleCoreReactionsSession, action: StringName, args: Array, attempt: bool = false) -> bool:
	assert(not is_started())
	if not _valid_request(action, args) or not can_transfer(session): return false
	_session = session
	method = action
	target_attempt = attempt
	_thread = Thread.new()
	if _thread.start(_run.bind(args.duplicate())) == OK: return true
	_thread = null
	_session = null
	return false

static func _valid_request(action: StringName, args: Array) -> bool:
	if action not in METHODS: return false
	if action in [&"move_to", &"retreat_to", &"use_summoning_item", &"raise_corpse"]:
		return args.size() == 1 and args[0] is Vector2i
	if action in [&"attack_unit", &"cast_unit"]: return args.size() == 1 and args[0] is int
	if action == &"cast_mage_spell": return args.size() == 2 and typeof(args[0]) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(args[1]) == TYPE_INT
	if action == &"cast_mage_cell": return args.size() == 2 and typeof(args[0]) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(args[1]) == TYPE_VECTOR2I
	if action == &"set_reaction_guard":
		return args.size() in [1, 2] and args[0] is int and (args.size() == 1 or args[1] is int)
	return args.is_empty()

func _run(args: Array) -> Variant:
	return _session.callv(method, args)

func take_finished(wait: bool = false) -> Dictionary:
	if _thread == null or (not wait and _thread.is_alive()): return {}
	var result: Variant = _thread.wait_to_finish()
	_thread = null
	var completed := {"session": _session, "method": method, "result": result, "target_attempt": target_attempt}
	_session = null
	return completed
