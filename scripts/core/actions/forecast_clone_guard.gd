extends RefCounted
class_name ForecastCloneGuard

static func is_safe(roots: Array, board: BattleBoard = null) -> bool:
	var allowed_scripts: Array[Script] = [
		ForecastSimulation.Prepared, ItemSimulationSnapshot, ActionContext, ActionQueue,
		ActionRngPort, CombatRng, ActionEventSink, MoveRules, AttackRules, AttackDefinition,
		ItemSimulationState, BattleBoard, UnitState, StatsBag, Stat, StatModifier, Vitals,
		ActionResources, ArmorState, BleedingState, ControlState, CombatPerksState,
		CombatPerksDefinition, ElementalState, ItemOwnerState, InventoryState, EquipmentState,
		ItemInstance, ItemDef, SummonDefinition, HealOnDamageEffect, HealOnDamageEffectRuntime,
		StatModifierEffect, StatModifierEffectRuntime, BattleAbilityState, AbilityDefinition,
		BattleArtifactState, BattleDeckState, BattleCardEffectState, CombatEnvironmentState,
		DamageSource, AttackCommand, UseHealingItemCommand, UseSummoningItemCommand, MoveCommand,
		RaiseCorpseCommand, GuardCommand, RaiseShieldsCommand, RestoreArmorCommand,
		CollapsePhaseCommand, ElementalCastCommand, MageCastCommand, PlayMageCardCommand,
		MageDeckChangeCommand, ConfirmMageMulliganCommand
	]
	var pending: Array = roots.duplicate()
	var metadata: Array = []
	var visited_objects: Dictionary = {}
	var visited_containers: Array = []
	var script_fields: Dictionary = {}
	var budget: int = 50000
	while not pending.is_empty():
		budget -= 1
		if budget < 0: return false
		var value: Variant = pending.pop_back()
		if value is Callable or value is Signal: return false
		if value is Array or value is Dictionary:
			var seen_container: bool = false
			for previous: Variant in visited_containers:
				if is_same(previous, value):
					seen_container = true
					break
			if seen_container: continue
			visited_containers.append(value)
			if value is Array:
				pending.append_array(value)
			else:
				pending.append_array(value.keys())
				pending.append_array(value.values())
		elif value is Object:
			var object := value as Object
			if object == null: return false
			if object is Script: return false
			var object_id: int = object.get_instance_id()
			if visited_objects.has(object_id): continue
			visited_objects[object_id] = true
			var script := object.get_script() as Script
			if not (object is RandomNumberGenerator and script == null) and script not in allowed_scripts:
				return false
			if object == board and not _owned_callback_registry(board): return false
			for signal_info: Dictionary in object.get_signal_list():
				for connection: Dictionary in object.get_signal_connection_list(signal_info.name):
					if not _owned_death_callback(board, object, signal_info.name, connection): return false
			for key: StringName in object.get_meta_list():
				metadata.append(object.get_meta(key))
			if script == null: continue
			var dynamic_fields: bool = object.has_method(&"_get_property_list")
			if dynamic_fields or not script_fields.has(script):
				var fields: Array[StringName] = []
				for property: Dictionary in object.get_property_list():
					if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
						fields.append(StringName(property.name))
				script_fields[script] = fields
			for field: StringName in script_fields[script]:
				# После проверки всех сигналов этот реестр допустим только у указанной доски.
				if object == board and field == &"_death_callbacks": continue
				pending.append(object.get(field))
	return _metadata_values_only(metadata, budget)

static func _metadata_values_only(pending: Array, budget: int) -> bool:
	# Resource.duplicate(true) сохраняет RefCounted в metadata по ссылке.
	# Известный script не доказывает владение: здесь допустимы только значения.
	var visited: Array = []
	while not pending.is_empty():
		budget -= 1
		if budget < 0: return false
		var value: Variant = pending.pop_back()
		if value is Object or value is Callable or value is Signal or value is RID: return false
		if value is Array or value is Dictionary:
			var seen := false
			for previous: Variant in visited:
				if is_same(previous, value):
					seen = true
					break
			if seen: continue
			visited.append(value)
			if value is Array:
				pending.append_array(value)
			else:
				pending.append_array(value.keys())
				pending.append_array(value.values())
	return true

static func _owned_callback_registry(board: BattleBoard) -> bool:
	# Проверки самих сигналов недостаточно: лишняя запись реестра тоже может
	# удерживать чужой объект, хотя ни один Vitals на неё не подписан.
	if board._death_callbacks.size() != board._units.size(): return false
	for key: Variant in board._death_callbacks:
		if not key is int or not board._death_callbacks[key] is Callable: return false
		var unit := board.get_unit_by_id(key)
		if unit == null or unit.vitals == null: return false
		var found := false
		for connection: Dictionary in unit.vitals.get_signal_connection_list(&"died"):
			if connection.callable == board._death_callbacks[key]:
				found = _owned_death_callback(board, unit.vitals, &"died", connection)
		if not found: return false
	return true

static func _owned_death_callback(board: BattleBoard, object: Object, signal_name: StringName, connection: Dictionary) -> bool:
	if board == null or not object is Vitals or signal_name != &"died" or int(connection.flags) != 0: return false
	var callback: Callable = connection.callable
	if callback.get_object() != board or callback.get_method() != &"_on_registered_unit_died": return false
	var args := callback.get_bound_arguments()
	if args.size() != 3 or not args[0] is int or not args[1] is WeakRef or not args[2] is WeakRef: return false
	var unit := board.get_unit_by_id(args[0])
	return unit != null and unit.vitals == object and args[1].get_ref() == unit and args[2].get_ref() == object and board._death_callbacks.get(unit.id) == callback
