extends "res://tools/demo/profile_forecast_clone.gd"

## Проверяем реальный default prepare, прямой restore и потребителей пакета.
func externalize(session: BattleCoreReactionsSession) -> void:
	var serial := 0
	var effect_count := 0
	var summon_count := 0
	for owner: ItemOwnerState in session.state.get_owners():
		for definition: ItemDef in owner._definitions.values():
			definition.set_meta(&"values", {"nested": [1, {"text": "source"}]})
			for index: int in definition.effects.size():
				var path := "user://restore_effect_%d.tres" % serial
				serial += 1
				check(ResourceSaver.save(definition.effects[index], path) == OK, "external effect saved")
				definition.effects[index] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ItemEffect
				definition.effects[index].set_meta(&"values", {"nested": [2, 3]})
				effect_count += 1
			if definition.use_summon:
				var path := "user://restore_summon_%d.tres" % serial
				serial += 1
				check(ResourceSaver.save(definition.get_summon_definition(), path) == OK, "external summon saved")
				definition.summon_definition = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SummonDefinition
				definition.summon_definition.set_meta(&"values", {"nested": [4, 5]})
				summon_count += 1
	check(effect_count > 0 and summon_count > 0, "external fixture covers effects and summons")

func mutate_source(session: BattleCoreReactionsSession) -> void:
	for owner: ItemOwnerState in session.state.get_owners():
		for definition: ItemDef in owner._definitions.values():
			definition.display_name += " changed"
			definition.get_meta(&"values")["nested"][1]["text"] = "changed"
			for effect: ItemEffect in definition.effects:
				effect.get_meta(&"values")["nested"][0] = 999
				if effect is StatModifierEffect: effect.value += 1.0
				if effect is HealOnDamageEffect: effect.heal_amount += 1.0
			if definition.summon_definition != null:
				definition.summon_definition.hp_max += 1.0
				definition.summon_definition.get_meta(&"values")["nested"][0] = 999

func output_values(output: Object) -> Dictionary:
	var data: Dictionary = {}
	for property: Dictionary in output.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			data[property.name] = output.get(property.name)
	return data

func take_worker(worker: Object) -> Object:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var result: Object = worker.take_finished()
		if result != null:
			worker.close()
			return result
		OS.delay_usec(50)
	worker.close()
	check(false, "restore worker deadline")
	return null

func external_consumer(kind: String) -> void:
	var session := PlayerFixture.create()
	externalize(session)
	for y: int in session.board.height:
		for x: int in session.board.width:
			session.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			session.board.set_height_steps(Vector2i(x, y), 0)
	for index: int in session.units.size():
		if session.units[index].is_alive(): session.board.move_unit(session.units[index], Vector2i(index, 7))
	session.select_unit(session.units[2].id)
	session.board.move_unit(session.selected_unit(), Vector2i(3, 3))
	session.board.move_unit(session.units[5], Vector2i(4, 3))
	session.state.environment.fires.clear()
	var actor := session.selected_unit()
	var command: Command = GuardCommand.new(actor.id, session.context.get_revision())
	if kind == "attack":
		command = session._command_for(session.units[5].id)
	if kind == "move":
		command = MoveCommand.new(actor.id, [actor.cell, actor.cell + Vector2i(0, 1)], session.context.get_revision())
	var before := values(session.state)
	var counters := session.context.simulation_counters()
	var rng_before := session.context.get_rng().to_dict()
	var allocator := UnitId.get_counter()
	var expected: Object
	var package: Object
	var worker: Object
	if kind == "turn":
		expected = TurnForecast.build(session)
		package = TurnForecast.prepare(session)
		worker = TurnForecastWorker.new()
	else:
		package = ForecastSimulation.prepare(session.context, session._queue, command)
		if kind == "attack":
			expected = AttackForecast.build(session.context, session._queue, command)
			worker = AttackForecastWorker.new()
		elif kind == "move":
			expected = MoveForecast.build(session.context, session._queue, command)
			worker = MoveForecastWorker.new()
		else:
			expected = ForecastSimulation.run(session.context, session._queue, command)
			worker = ActionForecastWorker.new()
	check(package.reason == &"", kind + " default package accepted")
	check(expected.status == ActionReceipt.APPLIED, kind + " fixture executes an applied forecast: " + String(expected.reason))
	if package.reason != &"":
		session.close()
		return
	check(values(session.state) == before, kind + " prepare preserves source")
	# Этот путь использует и battle_click_attack: вызывающий восстанавливает Prepared сам.
	var direct := package.snapshot.instantiate(package.definitions) as ItemSnapshotResult
	check(direct.code == ItemSnapshotResult.Code.OK and values(direct.state) == before, kind + " direct instantiate complete parity")
	if direct.state != null: ForecastSimulation.close(direct.state)
	if package is ForecastSimulation.Prepared: ownership([session.context, session._queue, command], package)
	else:
		var source := Transfer.graph([session.context, session._queue, session.actor_loadouts], null, false)
		var copy := Transfer.graph([package.definitions, package.context, package.queue, package.actor_loadouts], null, false)
		check(source.error.is_empty() and copy.error.is_empty(), "turn ownership walks complete")
		for id: int in copy.objects: check(not source.objects.has(id), "turn no live object in copied roots")
	mutate_source(session)
	# Содержимое live уже другое, но пакет обязан исполнить старый захваченный граф.
	worker.start(package)
	var result := take_worker(worker)
	check(result != null and output_values(result) == output_values(expected), kind + " external live mutation cannot change captured result")
	check(session.context.simulation_counters() == counters and session.context.get_rng().to_dict() == rng_before and UnitId.get_counter() == allocator, kind + " live RNG counters allocator pure")
	session.close()

func metadata_refusal(kind: String) -> void:
	var session := PlayerFixture.create()
	var definition: ItemDef = session.state.get_owners()[0]._definitions.values()[0]
	var original_hp := session.selected_unit().vitals.get_hp()
	for owner: ItemOwnerState in session.state.get_owners():
		if owner._definitions.has(definition.id):
			owner._definitions[definition.id].set_meta(&"live", {"nested": [session.selected_unit().vitals]})
	var command: Command = GuardCommand.new(session.selected_id, session.context.get_revision())
	var prepared: Object
	var worker: Object
	if kind == "turn":
		prepared = TurnForecast.prepare(session)
		worker = TurnForecastWorker.new()
	else:
		if kind == "attack":
			var target: UnitState = session.units.back()
			command = AttackCommand.new(session.selected_id, target.id, session.selected_unit().cell, target.cell, &"basic", session.context.get_revision())
		if kind == "move": command = MoveCommand.new(session.selected_id, [session.selected_unit().cell], session.context.get_revision())
		prepared = ForecastSimulation.prepare(session.context, session._queue, command)
		if kind == "attack": worker = AttackForecastWorker.new()
		elif kind == "move": worker = MoveForecastWorker.new()
		else: worker = ActionForecastWorker.new()
	check(prepared.reason in [&"preview/unsupported_definition_metadata", &"turn/unsupported_runtime"] and prepared.definitions.is_empty(), kind + " unsafe metadata rejected without catalogue")
	worker.start(prepared)
	check(worker._thread == null, kind + " rejected package starts no thread")
	var result := take_worker(worker)
	check(result != null and result.status == ActionReceipt.REJECTED and result.reason == prepared.reason, kind + " worker preserves refusal")
	check(session.selected_unit().vitals.get_hp() == original_hp, kind + " refusal leaves HP unchanged")
	for owner: ItemOwnerState in session.state.get_owners():
		if owner._definitions.has(definition.id): owner._definitions[definition.id].remove_meta(&"live")
	session.close()

func _run() -> void:
	for kind: String in ["action", "attack", "move", "turn"]:
		external_consumer(kind)
		metadata_refusal(kind)
	capture_before_metadata_gate()
	print("FORECAST RESTORE ISOLATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func capture_before_metadata_gate() -> void:
	var session := PlayerFixture.create()
	var cycle: Array = []
	cycle.append(cycle)
	var roots: Array[Resource] = []
	for owner: ItemOwnerState in session.state.get_owners():
		for definition: ItemDef in owner._definitions.values():
			if definition.summon_definition != null: roots.append(definition.summon_definition)
	check(not roots.is_empty(), "capture regression has explicit summon definitions")
	var before := values(session.state)
	var deep: Variant = 0
	for _index: int in range(34): deep = [deep]
	for metadata: Variant in [cycle, deep, {"object": session.selected_unit().vitals}]:
		for root: Resource in roots: root.set_meta(&"unsupported", metadata)
		check(values(session.state) == before, "capture reads summon values without duplicating metadata")
		for clone: bool in [false, true]:
			var prepared := ForecastSimulation.prepare(session.context, session._queue, GuardCommand.new(session.selected_id, session.context.get_revision()), clone)
			check(prepared.reason == &"preview/unsupported_definition_metadata" and prepared.definitions.is_empty(), "source summon metadata refused safely after capture")
			ForecastSimulation.discard_prepared(prepared)
		var turn := TurnForecast.prepare(session)
		check(turn.reason in [&"preview/unsupported_definition_metadata", &"turn/unsupported_runtime"] and turn.definitions.is_empty(), "turn source summon metadata refused safely")
		for root: Resource in roots: root.remove_meta(&"unsupported")
	cycle.clear()
	session.close()
