extends "res://tools/demo/profile_item_graph_clone.gd"

const ResultProbe = preload("res://tests/fixtures/forecast_result_probe.gd")

func record_parity(label: String, data: Dictionary) -> void:
	if OS.get_cmdline_user_args().has("--emit-parity"):
		print("FORECAST_CLONE_PARITY " + JSON.stringify({"label": label, "digest": ResultProbe.digest(data)}))

## Используем те же fixture-команды, но штатные prepare/run/worker и их cleanup.
class PublicationSink extends ActionEventSink:
	var context_ref: WeakRef
	var fault: bool = false
	var publications: Array[Dictionary] = []
	func publish(event: Dictionary) -> void:
		publications.append(event.duplicate(true))
		if fault:
			var context := context_ref.get_ref() as ActionContext
			context.get_state().deck.replaced_serial += 1

class ObservedWorker extends ActionForecastWorker:
	var fault: bool = false
	func _start_thread(prepared: ForecastSimulation.Prepared) -> Error:
		return _thread.start(_observed.bind(prepared, fault))
	static func _observed(prepared: ForecastSimulation.Prepared, inject_fault: bool) -> ForecastSimulation:
		# Только измерительный runner: подписчик создаётся внутри владеющего потока
		# после штатного gate, не передаёт callbacks или ссылки на live.
		var sink := PublicationSink.new()
		sink.context_ref = weakref(prepared.context)
		sink.fault = inject_fault
		prepared.context._sink = sink
		var result := ForecastSimulation.run_prepared(prepared)
		result.set_meta(&"publications", sink.publications)
		return result

class FailedWorker extends ActionForecastWorker:
	func _start_thread(_prepared: ForecastSimulation.Prepared) -> Error: return ERR_CANT_CREATE

class GatedWorker extends ActionForecastWorker:
	var gate := Semaphore.new()
	func _start_thread(prepared: ForecastSimulation.Prepared) -> Error:
		return _thread.start(_gated.bind(prepared, gate))
	static func _gated(prepared: ForecastSimulation.Prepared, semaphore: Semaphore) -> ForecastSimulation:
		semaphore.wait()
		return ForecastSimulation.run_prepared(prepared)

func collect(worker: ActionForecastWorker) -> ForecastSimulation:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var result := worker.take_finished()
		if result != null: return result
		OS.delay_usec(50)
	worker.close()
	check(false, "forecast worker deadline")
	return ForecastSimulation.rejected(&"timeout")

func result_values(result: ForecastSimulation) -> Dictionary:
	var data := ResultProbe.values(result)
	data["publications"] = result.get_meta(&"publications", [])
	return data

func prepare(session: BattleDemoSession, command: Command, clone: bool) -> ForecastSimulation.Prepared:
	session.forecast_clone_enabled = clone
	return session.prepare_action_forecast(command)

func ownership(source: Array, prepared: ForecastSimulation.Prepared) -> void:
	var original := Transfer.graph(source, null, false)
	var detached := Transfer.graph([prepared], null, false)
	check(original.error.is_empty() and detached.error.is_empty(), "identity walks complete")
	for id: int in detached.objects: check(not original.objects.has(id), "no live object in Prepared")
	for container: Variant in detached.containers:
		var shared := false
		for previous: Variant in original.containers:
			if is_same(container, previous): shared = true; break
		check(not shared, "no live container in Prepared")

func command_case(session: BattleCoreReactionsSession, command: Command, label: String, fault: bool = false, expected_status: StringName = ActionReceipt.APPLIED) -> void:
	if command is AttackCommand or command is MoveCommand:
		session.close()
		return
	var before := values(session.state)
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var counters_before := session.context.simulation_counters()
	var allocator := UnitId.get_counter()
	var outputs: Array[Dictionary] = []
	for use_clone: bool in [false, true]:
		var prepared := prepare(session, command, use_clone)
		check(prepared.reason == &"" and (prepared.cloned_state != null) == use_clone, label + " strategy prepared")
		ownership([session.context, session._queue, command], prepared)
		var copy := prepared.cloned_state
		var worker := ObservedWorker.new()
		worker.fault = fault
		worker.start(prepared)
		check(prepared.consumed and prepared.context == null and prepared.cloned_state == null, label + " synchronous ownership transfer")
		check(worker.last_preparation == (&"clone" if use_clone else &"snapshot"), label + " admitted requested strategy")
		var result := collect(worker)
		check(result.status == expected_status, label + " status: " + String(result.reason))
		outputs.append(result_values(result))
		if copy != null: check(copy.get_board().get_all_units().is_empty() and copy.get_owners()[0].is_closed(), label + " joined clone cleanup")
		worker.start(prepared)
		check(collect(worker).reason == &"preview/request_consumed", label + " second start refused")
		worker.close()
	check(outputs[0] == outputs[1], label + " complete forecast/publication parity")
	record_parity("forecast/" + label, outputs[0])
	check(values(session.state) == before and session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before and UnitId.get_counter() == allocator, label + " live purity")
	var sink := RecordingSink.new()
	if fault: sink.mutate_deck = session.state.deck
	session.context._sink = sink
	var receipt := session._queue.submit(command, session.context)
	var result: Dictionary = outputs[1]
	check(result.status == receipt.status and result.reason == receipt.reason and result.events == receipt.get_events() and result.steps == receipt.get_steps() and result.snapshot_after == values(session.state) and result.rng_after == session.context.get_rng().to_dict() and result.counters_after == session.context.simulation_counters() and result.admission_after == SummonAdmission.values(session.context) and result.publications == sink.publications, label + " live parity including publications")
	session.close()

func lifecycle_cases() -> void:
	var session := PlayerFixture.create()
	var command := GuardCommand.new(session.selected_id, session.context.get_revision())
	var before := values(session.state)
	var expected := ForecastSimulation.run(session.context, session._queue, command)
	var prepared := prepare(session, command, true)
	var copy := prepared.cloned_state
	var worker := GatedWorker.new()
	worker.start(prepared)
	session.selected_unit().vitals.set_hp(2.0)
	worker.gate.post()
	check(result_values(collect(worker)) == result_values(expected), "live mutation after start cannot alter captured result")
	check(copy.get_board().get_all_units().is_empty(), "gated result closes graph")
	var fresh := prepare(session, command, true)
	check(fresh.snapshot.to_dict() != before and fresh.snapshot.to_dict() == values(session.state), "fresh prepare without revision change")
	copy = fresh.cloned_state
	ForecastSimulation.discard_prepared(fresh)
	ForecastSimulation.discard_prepared(fresh)
	check(copy.get_board().get_all_units().is_empty() and fresh.consumed, "unstarted explicit discard idempotent")
	var failing := FailedWorker.new()
	prepared = prepare(session, command, true)
	copy = prepared.cloned_state
	failing.start(prepared)
	check(failing.take_finished().reason == &"preview/worker_unavailable" and copy.get_board().get_all_units().is_empty(), "OS refusal closes clone without execution")
	prepared = prepare(session, command, true)
	copy = prepared.cloned_state
	var joined := ActionForecastWorker.new()
	joined.start(prepared)
	joined.close()
	check(not joined.is_started() and copy.get_board().get_all_units().is_empty(), "discard result joins and closes clone")
	for kind: String in ["metadata", "signal", "node", "script", "registry", "known_stat", "nested_stat"]:
		prepared = prepare(session, command, true)
		copy = prepared.cloned_state
		var node := Node.new()
		if kind == "metadata": copy.set_meta(&"unsafe", func() -> void: pass)
		if kind == "signal": copy.get_board().get_all_units()[0].vitals.died.connect(func(_reason: Variant = null) -> void: pass)
		if kind == "node": copy.set_meta(&"unsafe", node)
		if kind == "script": copy.set_meta(&"unsafe", load("res://scripts/demo/battle_demo.gd"))
		if kind == "registry": copy.get_board()._death_callbacks[999999] = Callable(session, &"close")
		if kind == "known_stat": copy.set_meta(&"unsafe", session.selected_unit().stats._stats.values()[0])
		if kind == "nested_stat": copy.set_meta(&"unsafe", {"nested": [{session.selected_unit().stats._stats.values()[0]: 1}]})
		joined.start(prepared)
		check(joined.last_preparation == &"snapshot_fallback", kind + " clone transfer falls back")
		check(collect(joined).snapshot_after == ForecastSimulation.run(session.context, session._queue, command).snapshot_after, kind + " fallback preserves result")
		check(copy.get_board().get_all_units().is_empty(), kind + " fallback cleans graph")
		if copy.has_meta(&"unsafe"): copy.remove_meta(&"unsafe")
		node.free()
	prepared = prepare(session, command, true)
	copy = prepared.cloned_state
	copy.set_meta(&"values", {"nested": [1, "label", Vector2i(2, 3), {"alive": true}]})
	joined.start(prepared)
	check(joined.last_preparation == &"clone" and collect(joined).reason == &"", "value-only metadata admits clone")
	copy.remove_meta(&"values")
	# Один id может встречаться у нескольких владельцев: помечаем все определения,
	# чтобы последний элемент каталога не затёр metadata до проверки переноса.
	var definition: ItemDef = session.state.get_owners()[0]._definitions.values()[0]
	var live_stat: Stat = session.selected_unit().stats._stats.values()[0]
	var source_before := values(session.state)
	for owner: ItemOwnerState in session.state.get_owners():
		if owner._definitions.has(definition.id): owner._definitions[definition.id].set_meta(&"live_stat", live_stat)
	for clone: bool in [false, true]:
		prepared = prepare(session, command, clone)
		check(prepared.reason == &"preview/unsupported_definition_metadata" and prepared.definitions.is_empty() and prepared.cloned_state == null, "live definition metadata refused before copying")
		joined.start(prepared)
		check(joined._thread == null and collect(joined).reason == &"preview/unsupported_definition_metadata", "live definition metadata never starts Thread")
	check(values(session.state) == source_before, "metadata refusal preserves source")
	for owner: ItemOwnerState in session.state.get_owners():
		if owner._definitions.has(definition.id): owner._definitions[definition.id].remove_meta(&"live_stat")
	prepared = prepare(session, command, true)
	copy = prepared.cloned_state
	prepared.context.set_meta(&"unsafe", func() -> void: pass)
	joined.start(prepared)
	check(joined._thread == null and collect(joined).reason == &"preview/unsupported_worker_graph" and copy.get_board().get_all_units().is_empty(), "unsafe fallback packet never starts")
	for kind: String in ["unsupported", "busy", "invalid"]:
		if kind == "unsupported": session.context._unsupported_runtime_ids.append(&"test_unknown")
		if kind == "busy": session.state.get_owners()[0]._guard = true
		if kind == "invalid": session.state.get_owners()[0]._next_item_id = 0
		var control := prepare(session, command, false)
		var clone := prepare(session, command, true)
		check(control.reason != &"" and control.reason == clone.reason and clone.cloned_state == null, kind + " same fresh admission reason")
		ForecastSimulation.discard_prepared(control)
		ForecastSimulation.discard_prepared(clone)
		session.context._unsupported_runtime_ids.clear()
		session.state.get_owners()[0]._guard = false
	session.close()

func remaining_commands() -> void:
	var collapse := PlayerFixture.create()
	collapse.state.environment.collapse = {"turn": 0, "marked": []}
	command_case(collapse, CollapsePhaseCommand.new(collapse.context.get_revision()), "collapse")
	var elemental := PlayerFixture.create()
	command_case(elemental, ElementalCastCommand.new(elemental.selected_id, elemental.selected_id, &"wet", elemental.context.get_revision()), "elemental")
	var mage := BattleCoreReactionsSession.new()
	mage._enemy_index = mage._enemy_ids.size()
	mage.step_enemy()
	command_case(mage, MageCastCommand.new(&"mage.fire", mage.living_ids(Faction.Type.ENEMY)[0], mage.context.get_revision()), "mage fire")
	var shield := BattleCoreReactionsSession.new()
	shield._enemy_index = shield._enemy_ids.size()
	shield.step_enemy()
	shield.selected_id = shield.living_ids(Faction.Type.PLAYER)[0]
	shield.selected_unit().armor.raised_shield = RaisedShield.make()
	shield.state.abilities.catalog.append(RaiseShieldsCommand.definition())
	shield.state.abilities.catalog.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool: return String(a.ability_id) < String(b.ability_id))
	command_case(shield, RaiseShieldsCommand.new(shield.selected_id, shield.context.get_revision()), "raise shields")
	var replace := deck_fixture()
	command_case(replace, MageDeckChangeCommand.new(&"replace", [replace.state.deck.hand_ids[0]], replace.context.get_revision()), "replace card")
	var mulligan := deck_fixture()
	mulligan.state.deck = BattleDeckState.create(mulligan.state.deck.cards, 88)
	mulligan.state.abilities = BattleAbilityState.create_deck(mulligan.state.abilities.catalog, Faction.Type.ENEMY)
	command_case(mulligan, ConfirmMageMulliganCommand.new([], mulligan.context.get_revision()), "confirm mulligan")

func external_resource_case() -> void:
	var session := PlayerFixture.create()
	var serial := 0
	var effects := 0
	var summons := 0
	for owner: ItemOwnerState in session.state.get_owners():
		for definition: ItemDef in owner._definitions.values():
			for index: int in definition.effects.size():
				var path := "user://forecast_external_%d.tres" % serial
				serial += 1
				check(ResourceSaver.save(definition.effects[index], path) == OK, "save external effect fixture")
				definition.effects[index] = load(path) as ItemEffect
				check((definition.duplicate(true) as ItemDef).effects[index] == definition.effects[index], "default Resource copy shares external effect")
				effects += 1
			if definition.use_summon:
				var path := "user://forecast_external_%d.tres" % serial
				serial += 1
				check(ResourceSaver.save(definition.get_summon_definition(), path) == OK, "save external summon fixture")
				definition.summon_definition = load(path) as SummonDefinition
				check((definition.duplicate(true) as ItemDef).summon_definition == definition.summon_definition, "default Resource copy shares external summon")
				summons += 1
	check(effects > 0 and summons > 0, "external nested Resource fixture populated")
	var before := values(session.state)
	var command := GuardCommand.new(session.selected_id, session.context.get_revision())
	var expected := result_values(ForecastSimulation.run(session.context, session._queue, command))
	for fallback: bool in [false, true]:
		var prepared := prepare(session, command, true)
		ownership([session.context, session._queue, command], prepared)
		var copy := prepared.cloned_state
		if fallback: copy.set_meta(&"unsafe", Callable(session, &"close"))
		var worker := ActionForecastWorker.new()
		worker.start(prepared)
		check(worker.last_preparation == (&"snapshot_fallback" if fallback else &"clone"), "external Resource strategy")
		check(result_values(collect(worker)) == expected and values(session.state) == before, "external Resource result parity/source purity")
		check(copy.get_board().get_all_units().is_empty(), "external Resource graph cleanup")
		if fallback: copy.remove_meta(&"unsafe")
		worker.close()
	session.close()

func benchmark_forecast(session: BattleDemoSession, label: String) -> void:
	var command := GuardCommand.new(session.selected_id, session.context.get_revision())
	var before := values(session.state)
	var expected := result_values(ForecastSimulation.run(session.context, session._queue, command))
	var reverse := OS.get_cmdline_user_args().has("--reverse")
	for index: int in range(-3, 21):
		var order: Array = [false, true] if (index % 2 == 0) != reverse else [true, false]
		for clone: bool in order:
			var started := Time.get_ticks_usec()
			var prepared := prepare(session, command, clone)
			var prepared_at := Time.get_ticks_usec()
			var worker := ActionForecastWorker.new()
			worker.start(prepared)
			var launched_at := Time.get_ticks_usec()
			var result := collect(worker)
			worker.close()
			var finished_at := Time.get_ticks_usec()
			check(worker.last_preparation == (&"clone" if clone else &"snapshot") and result_values(result) == expected, label + " timed path and parity")
			if index >= 0:
				print("FORECAST_CLONE_SAMPLE " + JSON.stringify({"fixture": label, "clone": clone, "index": index, "prepare": prepared_at-started, "admission_launch": launched_at-prepared_at, "execute_join_cleanup": finished_at-launched_at, "total": finished_at-started}))
	check(values(session.state) == before, label + " benchmark source pure")
	session.close()

func _run() -> void:
	command_cases()
	remaining_commands()
	lifecycle_cases()
	external_resource_case()
	if failed == 0 and not OS.get_cmdline_user_args().has("--verify-only"):
		benchmark_forecast(PlayerFixture.create(), "tactical")
		benchmark_forecast(artifact_fixture(), "artifacts")
		benchmark_forecast(deck_fixture(), "deck")
	print("FORECAST CLONE RESULTS: %d passed, %d failed" % [passed, failed])
	print("FORECAST CLONE DONE")
	quit(0 if failed == 0 else 1)
