extends RefCounted

## Только opt-in проверка переноса уже отделённого графа, не production worker API.
class RecordingSink extends ActionEventSink:
	var publications: Array[Dictionary] = []
	var mutate_deck: BattleDeckState
	func publish(event: Dictionary) -> void:
		publications.append(event.duplicate(true))
		if mutate_deck != null: mutate_deck.replaced_serial += 1

class Packet extends RefCounted:
	var context: ActionContext
	var queue: ActionQueue
	var command: Command
	var consumed: bool = false

	func run() -> Dictionary:
		if consumed: return {"error": "consumed"}
		consumed = true
		var state := context.get_state()
		var before := ItemSimulationSnapshot.capture(state, [])
		var admission_before := SummonAdmission.values(context)
		var receipt := queue.submit(command, context)
		var after := ItemSimulationSnapshot.capture(state, [])
		var sink := context.get_sink() as RecordingSink
		var result := {"before": before.snapshot.to_dict() if before.snapshot != null else {},
			"status": receipt.status, "reason": receipt.reason, "events": receipt.get_events(),
			"steps": receipt.get_steps(), "after": after.snapshot.to_dict() if after.snapshot != null else {},
			"rng": context.get_rng().to_dict(), "counters": context.simulation_counters(),
			"admission_before": admission_before, "admission": SummonAdmission.values(context),
			"publications": sink.publications.duplicate(true)}
		return result

static func prepare(context: ActionContext, queue: ActionQueue, command: Command, state: ItemSimulationState, fault: bool) -> Packet:
	var packet := Packet.new()
	packet.context = context.copy_for_simulation(state, context.get_rng().clone())
	packet.queue = queue.copy_for_simulation()
	packet.command = command.copy_for_queue()
	var sink := RecordingSink.new()
	if fault: sink.mutate_deck = state.deck
	packet.context._sink = sink
	return packet

## Закрытый набор fixture-типов: native/неизвестные объекты нельзя признать
## безопасными одним обходом script-полей. Это диагностический gate harness.
static func graph(roots: Array, board: BattleBoard, strict: bool) -> Dictionary:
	var scripts: Array[Script] = [Packet, RecordingSink, ActionContext, ActionQueue,
		ActionRngPort, CombatRng, ActionEventSink, MoveRules, AttackRules, AttackDefinition,
		ItemSimulationState, BattleBoard, UnitState, StatsBag, Stat, StatModifier, Vitals,
		ActionResources, ArmorState, BleedingState, ControlState, CombatPerksState, CombatPerksDefinition, ElementalState,
		ItemOwnerState, InventoryState, EquipmentState, ItemInstance, ItemDef, SummonDefinition,
		HealOnDamageEffect, HealOnDamageEffectRuntime, StatModifierEffect, StatModifierEffectRuntime,
		BattleAbilityState, AbilityDefinition, BattleArtifactState, BattleDeckState,
		BattleCardEffectState, CombatEnvironmentState, DamageSource,
		AttackCommand, UseHealingItemCommand, UseSummoningItemCommand, MoveCommand,
		RaiseCorpseCommand, GuardCommand, RaiseShieldsCommand, RestoreArmorCommand,
		CollapsePhaseCommand, ElementalCastCommand, MageCastCommand, PlayMageCardCommand,
		MageDeckChangeCommand, ConfirmMageMulliganCommand]
	var objects: Dictionary = {}
	var containers: Array = []
	var pending := roots.duplicate()
	var budget := 50000
	while not pending.is_empty():
		budget -= 1
		if budget < 0: return {"error": "budget"}
		var value: Variant = pending.pop_back()
		if value is Callable or value is Signal:
			if strict: return {"error": "callback"}
		elif value is Array or value is Dictionary:
			var seen := false
			for previous: Variant in containers:
				if is_same(previous, value):
					seen = true
					break
			if seen: continue
			containers.append(value)
			if value is Array: pending.append_array(value)
			else:
				pending.append_array(value.keys())
				pending.append_array(value.values())
		elif value is Object:
			var object := value as Object
			if object == null or object is Script: continue
			var id := object.get_instance_id()
			if objects.has(id): continue
			objects[id] = true
			if strict:
				if not (object is RandomNumberGenerator and object.get_script() == null) and object.get_script() not in scripts:
					return {"error": "unknown object: " + (object.get_script().resource_path if object.get_script() != null else object.get_class())}
				for signal_info: Dictionary in object.get_signal_list():
					for connection: Dictionary in object.get_signal_connection_list(signal_info.name):
						if not owned_death_callback(board, object, signal_info.name, connection): return {"error": "signal"}
			for key: StringName in object.get_meta_list(): pending.append(object.get_meta(key))
			for property: Dictionary in object.get_property_list():
				if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
				# Реестр содержит те же callbacks, уже проверенные по сигналам и bound args.
				if object is BattleBoard and property.name == &"_death_callbacks": continue
				pending.append(object.get(property.name))
	return {"error": "", "objects": objects, "containers": containers}

static func owned_death_callback(board: BattleBoard, object: Object, signal_name: StringName, connection: Dictionary) -> bool:
	if not object is Vitals or signal_name != &"died" or int(connection.flags) != 0: return false
	var callback: Callable = connection.callable
	if callback.get_object() != board or callback.get_method() != &"_on_registered_unit_died": return false
	var args := callback.get_bound_arguments()
	if args.size() != 3 or not args[0] is int or not args[1] is WeakRef or not args[2] is WeakRef: return false
	var unit := board.get_unit_by_id(args[0])
	return unit != null and unit.vitals == object and args[1].get_ref() == unit and args[2].get_ref() == object and board._death_callbacks.get(unit.id) == callback

static func isolation_error(source: Array, packet: Packet) -> String:
	var original := graph(source, null, false)
	if not original.error.is_empty(): return original.error
	var detached := graph([packet], packet.context.get_state().get_board(), true)
	if not detached.error.is_empty(): return detached.error
	for id: int in detached.objects:
		if original.objects.has(id): return "shared object"
	for container: Variant in detached.containers:
		for previous: Variant in original.containers:
			if is_same(container, previous): return "shared container"
	return ""

class Worker extends RefCounted:
	var _thread: Thread
	var _used: bool = false

	func start(packet: Packet, gate: Semaphore = null, fail_launch: bool = false) -> bool:
		if _used: return false
		_used = true
		_thread = Thread.new()
		# Отказ ОС моделируется до передачи; пакет остаётся у вызывающего.
		if fail_launch or _thread.start(_run.bind(packet, gate)) != OK:
			_thread = null
			return false
		return true

	static func _run(packet: Packet, gate: Semaphore) -> Dictionary:
		if gate != null: gate.wait()
		return packet.run()

	func take() -> Dictionary:
		if _thread == null: return {}
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		return result

	func close() -> void:
		# Отбрасывание результата всё равно возвращает владение только после join.
		take()
