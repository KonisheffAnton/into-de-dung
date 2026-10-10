extends SceneTree

var passed: int = 0
var failed: int = 0
var mutate_ability: BattleAbilityState

class TraceQueue extends ActionQueue:
	var trace: Array[Dictionary] = []
	func submit(command: Command, context: ActionContext) -> ActionReceipt:
		var receipt := super.submit(command, context)
		trace.append_array(receipt.get_steps())
		return receipt

func _initialize() -> void: call_deferred("_run")

func check(condition: bool, label: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		printerr("FAIL MAGE COOLDOWNS: " + label)

func _run() -> void:
	_test_codec_and_clocks()
	_test_cooldown_lengths()
	_test_catalog_references()
	await _test_real_session_preview_live_worker()
	_test_heal_and_admission()
	_test_fault_prefix()
	_test_terminal_preview_parity()
	print("MAGE COOLDOWNS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _test_catalog_references() -> void:
	var session := _player_session()
	if session == null: return
	var original := _snapshot(session)
	var item_use := ""
	var item_effect := ""
	var attack := ""
	for descriptor: Dictionary in original.abilities.catalog:
		var id: String = descriptor.ability_id
		if id.begins_with("item_use:"): item_use = id
		if id.begins_with("item_effect:"): item_effect = id
		if id.begins_with("attack:"): attack = id
	check(not item_use.is_empty() and not item_effect.is_empty() and not attack.is_empty(), "catalog reference fixture populated")
	for id: String in ["guard:default", item_use, item_effect]:
		var bad := original.duplicate(true)
		for index: int in range(bad.abilities.catalog.size() - 1, -1, -1):
			if bad.abilities.catalog[index].ability_id == id: bad.abilities.catalog.remove_at(index)
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "snapshot rejects missing " + id)
		var direct := ItemSimulationSnapshot.new(); direct._data = bad
		check(direct.instantiate({}).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "restore independently rejects missing " + id)
	for id: String in ["alien", "item_use:alien:heal_self", "item_effect:alien:0"]:
		var bad := original.duplicate(true)
		var descriptor := AbilityDefinition.new(); descriptor.ability_id = StringName(id)
		bad.abilities.catalog.append(descriptor.to_dict())
		bad.abilities.catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ability_id < b.ability_id)
		check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "snapshot rejects extra " + id)
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	var before := session.context.simulation_counters()
	for index: int in range(session.state.abilities.catalog.size() - 1, -1, -1):
		if String(session.state.abilities.catalog[index].ability_id) == attack: session.state.abilities.catalog.remove_at(index)
	check(session.prepare_mage_forecast(&"mage.fire", target.id).reason == &"ability/attack_catalog", "preview checks all external attack references")
	check(TurnForecast.prepare(session).reason == &"ability/attack_catalog", "turn preview checks external attack references")
	check(session.cast_mage_spell(&"mage.fire", target.id).reason == &"ability/attack_catalog" and session.context.simulation_counters() == before, "mage root rejects missing unrelated attack without allocation")
	session.state.abilities = BattleAbilityState.from_dict(original.abilities)
	var extra := AbilityDefinition.new(); extra.ability_id = &"attack:alien"
	session.state.abilities.catalog.append(extra)
	session.state.abilities.catalog.sort_custom(func(a: AbilityDefinition, b: AbilityDefinition) -> bool: return String(a.ability_id) < String(b.ability_id))
	check(session.cast_mage_spell(&"mage.fire", target.id).reason == &"ability/attack_catalog" and session.context.simulation_counters() == before, "root rejects unknown external attack without allocation")
	session.close()

func _test_codec_and_clocks() -> void:
	var state := _ability_state(2)
	check(BattleAbilityState.valid(state.to_dict()), "setup state validates")
	var restored := BattleAbilityState.from_dict(state.to_dict())
	check(restored != null and restored.to_dict() == state.to_dict() and restored.catalog[0] != state.catalog[0], "codec roundtrip owns descriptor copies")
	var bad := state.to_dict(); bad.mana = true
	check(not BattleAbilityState.valid(bad), "reject boolean mana")
	bad = state.to_dict(); bad.catalog[0].erase("cooldown_turns")
	check(not BattleAbilityState.valid(bad), "reject missing descriptor scalar")
	bad = state.to_dict(); bad.catalog[0]["unknown"] = 1
	check(not BattleAbilityState.valid(bad), "reject unknown descriptor scalar")
	bad = state.to_dict(); bad.catalog[0]["amount"] = 1.0
	check(not BattleAbilityState.valid(bad), "reject floating descriptor scalar")
	var current := _to_player_turn(state)
	check(current != null and current.mage_allowed, "clock opens player mage window")
	var wrong := current.boundary(&"close", Faction.Type.ENEMY, current.serials[0])
	check(wrong.is_empty(), "reject wrong-team boundary")
	var close := current.boundary(&"close", Faction.Type.PLAYER, current.serials[0])
	current.apply_values(close)
	var ended := current.boundary(&"end", Faction.Type.PLAYER, current.serials[0])
	check(not ended.is_empty(), "first end boundary accepted")
	current.apply_values(ended)
	var before := current.to_dict()
	check(current.boundary(&"end", Faction.Type.PLAYER, current.serials[0]).is_empty() and current.to_dict() == before, "duplicate end rejected without mutation")
	var ledger_state := _to_player_turn(_ability_state(2))
	ledger_state.apply_values(ledger_state.paid(&"mage.fire"))
	var malformed := ledger_state.to_dict(); malformed.ledger[0].remaining = 0
	check(not BattleAbilityState.valid(malformed), "reject zero remaining with skip flag")
	malformed = ledger_state.to_dict(); malformed.ledger[0].source_instance_id = 2
	check(not BattleAbilityState.valid(malformed), "reject wrong stable source instance")
	malformed = ledger_state.to_dict(); malformed.ledger[0].remaining = 3
	check(not BattleAbilityState.valid(malformed), "reject remaining beyond definition")
	var overflow := _ability_state(2)
	overflow = _to_player_turn(overflow)
	var player_close := overflow.boundary(&"close", Faction.Type.PLAYER, overflow.serials[0]); overflow.apply_values(player_close)
	var player_end := overflow.boundary(&"end", Faction.Type.PLAYER, overflow.serials[0]); overflow.apply_values(player_end)
	overflow.serials[1] = BattleAbilityState.MAX
	overflow.ended[1] = BattleAbilityState.MAX
	overflow.serials[0] = BattleAbilityState.MAX
	overflow.ended[0] = BattleAbilityState.MAX
	var overflow_dict := overflow.to_dict()
	var before_overflow := overflow.to_dict()
	check(overflow.boundary(&"begin", Faction.Type.PLAYER, overflow.serials[0]).is_empty() and overflow.to_dict() == before_overflow, "reject serial overflow before mutation")
	check(BattleAbilityState.valid(overflow_dict), "overflow fixture starts valid")

func _test_cooldown_lengths() -> void:
	for cooldown: int in [0, 1, 2]:
		var state := _to_player_turn(_ability_state(cooldown))
		var paid := state.paid(&"mage.fire")
		check(not paid.is_empty() and paid.mana == 4, "cooldown %d pays spell once" % cooldown)
		state.apply_values(paid)
		check(state.remaining(&"mage.fire") == cooldown, "cooldown %d recorded" % cooldown)
		check(state.ledger.is_empty() if cooldown == 0 else state.ledger[0].skip_current_end, "cooldown %d ledger canonical" % cooldown)
		if cooldown == 0: continue
		_advance_player_turn(state)
		check(state.remaining(&"mage.fire") == cooldown and not state.ledger[0].skip_current_end, "cooldown %d skips casting turn end" % cooldown)
		for next_turn: int in cooldown:
			_advance_player_turn(state)
			check(state.remaining(&"mage.fire") == cooldown - next_turn - 1, "cooldown %d advances next own turn %d" % [cooldown, next_turn + 1])
		check(state.remaining(&"mage.fire") == 0 and state.paid(&"mage.fire").size() > 0, "cooldown %d ready at correct later player turn" % cooldown)

func _test_real_session_preview_live_worker() -> void:
	var first_unit_id := UnitId.get_counter()
	var session := _player_session()
	if session == null: return
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	var actor := session.selected_unit()
	var main_before := actor.action_resources.get_main_left()
	var ability_before := session.state.abilities.to_dict()
	var counters_before := session.context.simulation_counters()
	var rng_before := session.context.get_rng().to_dict()
	var live_before := _snapshot(session)
	check(live_before.get("schema_version") == ItemSimulationSnapshot.SCHEMA_VERSION and live_before.get("scope") == ItemSimulationSnapshot.SCOPE, "battle snapshot uses current schema eleven")
	var captured := ItemSimulationSnapshot.from_dict(live_before)
	var definitions := _definition_catalog(session)
	var roundtrip := captured.snapshot.instantiate(definitions)
	check(roundtrip.code == ItemSnapshotResult.Code.OK and roundtrip.state.abilities.to_dict() == ability_before, "schema 7 retains complete ability state")
	var first := ForecastSimulation.run_prepared(session.prepare_mage_forecast(&"mage.fire", target.id))
	var second := ForecastSimulation.run_prepared(session.prepare_mage_forecast(&"mage.fire", target.id))
	check(first.status == ActionReceipt.APPLIED and second.status == first.status, "repeated mage preview executes")
	check(first.events == second.events and first.steps == second.steps and first.snapshot_after == second.snapshot_after and first.rng_after == second.rng_after and first.counters_after == second.counters_after and first.admission_after == second.admission_after, "repeated previews deterministic")
	check(_snapshot(session) == live_before and session.state.abilities.to_dict() == ability_before and session.context.simulation_counters() == counters_before and session.context.get_rng().to_dict() == rng_before, "preview leaves live state untouched")
	var preview_snapshot := ItemSimulationSnapshot.from_dict(first.snapshot_after)
	check(preview_snapshot.code == ItemSnapshotResult.Code.OK and preview_snapshot.snapshot.instantiate(definitions).state.abilities.remaining(&"mage.fire") == 2, "preview output carries mage cooldown")
	var worker := ActionForecastWorker.new()
	worker.start(session.prepare_mage_forecast(&"mage.fire", target.id))
	var worker_result: ForecastSimulation = await _take_forecast(worker)
	check(worker_result != null and worker_result.status == first.status and worker_result.reason == first.reason and worker_result.events == first.events and worker_result.steps == first.steps and worker_result.snapshot_before == first.snapshot_before and worker_result.snapshot_after == first.snapshot_after and worker_result.rng_after == first.rng_after and worker_result.counters_after == first.counters_after and worker_result.admission_after == first.admission_after, "forecast worker matches synchronous mage preview")
	worker.close()
	var receipt := session.cast_mage_spell(&"mage.fire", target.id)
	check(receipt.status == ActionReceipt.APPLIED and receipt.get_events() == first.events and receipt.get_steps() == first.steps and _snapshot(session) == first.snapshot_after and session.context.get_rng().to_dict() == first.rng_after and session.context.simulation_counters() == first.counters_after and SummonAdmission.values(session.context) == first.admission_after, "live mage cast matches forecast state/events/steps/RNG/counters/admission")
	check(actor.action_resources.get_main_left() == main_before and session.state.abilities.mana == 4 and session.state.abilities.remaining(&"mage.fire") == 2, "fire pays mana and cooldown without hero main")
	var sync_events := receipt.get_events()
	var sync_steps := receipt.get_steps()
	var sync_snapshot := _snapshot(session)
	var sync_rng := session.context.get_rng().to_dict()
	var sync_counters := session.context.simulation_counters()
	var sync_admission := SummonAdmission.values(session.context)
	var sync_phase := session.phase
	UnitId.set_counter(first_unit_id)
	var worker_session := _player_session()
	if worker_session != null:
		var worker_target := worker_session.board.get_unit_by_id(worker_session.living_ids(Faction.Type.ENEMY)[0])
		var live_worker := BattleExecutionWorker.new()
		check(live_worker.start(worker_session, &"cast_mage_spell", [&"mage.fire", worker_target.id]), "battle execution worker accepts mage command")
		var completed: Dictionary = live_worker.take_finished(true)
		var worker_receipt: ActionReceipt = completed.get("result")
		check(worker_receipt != null and worker_receipt.status == ActionReceipt.APPLIED and worker_session.state.abilities.remaining(&"mage.fire") == 2 and worker_session.state.abilities.mana == 4, "battle execution worker applies same spell price/cooldown")
		if worker_receipt != null and not worker_receipt.get_events().is_empty(): check(worker_receipt.get_events()[0].spell_id == &"mage.fire", "battle execution worker publishes mage event")
		if worker_receipt != null:
			check(worker_receipt.get_events() == sync_events, "battle execution worker matches sync events")
			check(worker_receipt.get_steps() == sync_steps, "battle execution worker matches sync steps")
			check(_snapshot(worker_session) == sync_snapshot, "battle execution worker matches sync snapshot")
			check(worker_session.context.get_rng().to_dict() == sync_rng and worker_session.context.simulation_counters() == sync_counters and SummonAdmission.values(worker_session.context) == sync_admission and worker_session.phase == sync_phase, "battle execution worker matches sync RNG/counters/admission/phase")
		worker_session.close()
	session.close()
	UnitId.set_counter(first_unit_id)
	var turn_session := _player_session()
	if turn_session == null: return
	var turn_target := turn_session.board.get_unit_by_id(turn_session.living_ids(Faction.Type.ENEMY)[0])
	var turn_cast := turn_session.cast_mage_spell(&"mage.fire", turn_target.id)
	check(turn_cast.status == ActionReceipt.APPLIED, "turn forecast fixture mage cast applied")
	var before_turn := _snapshot(turn_session)
	var before_turn_rng := turn_session.context.get_rng().to_dict()
	var before_turn_counters := turn_session.context.simulation_counters()
	var before_turn_allocator := UnitId.get_counter()
	var forecast_turn := TurnForecast.build(turn_session)
	check(forecast_turn.status == ActionReceipt.APPLIED and forecast_turn.transitioned and forecast_turn.phase_after == BattleTacticalSession.Phase.ENEMY_TURN, "TurnForecast predicts enemy start with K18 state")
	check(_snapshot(turn_session) == before_turn and turn_session.context.get_rng().to_dict() == before_turn_rng and turn_session.context.simulation_counters() == before_turn_counters and UnitId.get_counter() == before_turn_allocator, "TurnForecast preserves live mage state/RNG/counters/allocator")
	var trace_queue := TraceQueue.new()
	trace_queue._max_commands = turn_session._queue._max_commands
	trace_queue._max_events = turn_session._queue._max_events
	trace_queue._max_depth = turn_session._queue._max_depth
	turn_session._queue = trace_queue
	var previous_turn_event_count: int = turn_session.turn_events.size()
	check(turn_session.end_player_turn(), "live player end starts enemy turn after mage cast")
	check(turn_session.phase == forecast_turn.phase_after, "TurnForecast/live phase matches")
	check(_snapshot(turn_session) == forecast_turn.snapshot_after, "TurnForecast/live snapshot matches")
	check(forecast_turn.events == turn_session.turn_events.slice(previous_turn_event_count), "TurnForecast/live events match")
	check(trace_queue.trace == forecast_turn.steps, "TurnForecast/live complete steps match")
	check(turn_session.context.get_rng().to_dict() == forecast_turn.rng_after, "TurnForecast/live RNG matches")
	check(turn_session.context.simulation_counters() == forecast_turn.counters_after, "TurnForecast/live counters match")
	check(SummonAdmission.values(turn_session.context) == forecast_turn.admission_after, "TurnForecast/live admission matches")
	turn_session.close()

func _test_heal_and_admission() -> void:
	var session := _player_session()
	if session == null: return
	var ally: UnitState = session.units[0]
	ally.vitals.apply_damage(10.0)
	var main_before := session.selected_unit().action_resources.get_main_left()
	var hp_before := ally.vitals.get_hp()
	var mana_before := session.state.abilities.mana
	var receipt := session.cast_mage_spell(&"mage.heal", ally.id)
	check(receipt.status == ActionReceipt.APPLIED and ally.vitals.get_hp() == minf(ally.get_stat(StatTypes.StatType.HP_MAX), hp_before + 4.0), "mage heal restores four HP")
	check(session.selected_unit().action_resources.get_main_left() == main_before and session.state.abilities.mana == mana_before - 3 and session.state.abilities.remaining(&"mage.heal") == 2, "heal uses mage resources only")
	var enemy := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	var before_invalid := _snapshot(session)
	var rejected := session.cast_mage_spell(&"mage.heal", enemy.id)
	check(rejected.status != ActionReceipt.APPLIED and _snapshot(session) == before_invalid, "wrong-faction target rejected without mutation")
	session.close()
	var full := _player_session()
	if full == null: return
	var full_ally: UnitState = full.units[0]
	var full_before := _snapshot(full)
	var full_receipt := full.cast_mage_spell(&"mage.heal", full_ally.id)
	check(full_receipt.status != ActionReceipt.APPLIED and _snapshot(full) == full_before, "full HP rejected without price or cooldown")
	full.close()

func _test_fault_prefix() -> void:
	var session := _player_session()
	if session == null: return
	var target := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
	mutate_ability = session.state.abilities
	target.vitals.hp_changed.connect(_mutate_mana)
	var receipt := session.cast_mage_spell(&"mage.fire", target.id)
	check(receipt.status == ActionReceipt.FAULTED and session.phase == BattleTacticalSession.Phase.FAULTED, "mana mutation callback faults cast")
	check(session.state.abilities.remaining(&"mage.fire") == 2 and session.state.abilities.mana == 3 and target.vitals.get_hp() < target.get_stat(StatTypes.StatType.HP_MAX), "fault preserves paid prefix and callback mutation")
	target.vitals.hp_changed.disconnect(_mutate_mana)
	mutate_ability = null
	session.close()

func _test_terminal_preview_parity() -> void:
	var session := _player_session()
	if session == null: return
	var enemies := session.living_ids(Faction.Type.ENEMY)
	var target := session.board.get_unit_by_id(enemies.back())
	for enemy_id: int in enemies:
		if enemy_id == target.id: continue
		var enemy := session.board.get_unit_by_id(enemy_id)
		var death := session._queue.submit(DeathCommand.new(enemy_id, DamageSource.new(&"test", 0, enemy.cell)), session.context)
		check(death.status == ActionReceipt.APPLIED, "remove other enemy for terminal parity setup")
	var owner := session.state.get_owner(target.id)
	for item: ItemInstance in owner._items.values(): item.armor_remaining = 0
	target.vitals.set_hp(1.0)
	target.elemental.frozen_turns = 2
	var preview := ForecastSimulation.run_prepared(session.prepare_mage_forecast(&"mage.fire", target.id))
	check(preview.status == ActionReceipt.APPLIED and preview.snapshot_after.get("abilities", {}).get("stage") == "terminal", "forecast drains terminal battle capability: %s stage=%s hp=%s" % [String(preview.reason), str(preview.snapshot_after.get("abilities", {}).get("stage", "missing")), str(preview.units_after.get(target.id, {}).get("hp", -1.0))])
	var receipt := session.cast_mage_spell(&"mage.fire", target.id)
	check(receipt.status == preview.status and receipt.get_events() == preview.events and _snapshot(session) == preview.snapshot_after, "session victory agrees with terminal preview snapshot")
	check(session.phase == BattleTacticalSession.Phase.VICTORY and session.state.abilities.stage == "terminal" and not session.state.abilities.mage_allowed, "live terminal closes mage window: phase=%d stage=%s hp=%.1f living=%s" % [session.phase, session.state.abilities.stage, target.vitals.get_hp(), str(session.living_ids(Faction.Type.ENEMY))])
	session.close()

func _mutate_mana(_old_hp: float, _new_hp: float) -> void:
	if mutate_ability != null: mutate_ability.mana -= 1

func _player_session() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	check(session.phase == BattleTacticalSession.Phase.ENEMY_TURN and session.state.abilities != null, "real K18 session starts enemy with capability")
	if session.phase != BattleTacticalSession.Phase.ENEMY_TURN or session.state.abilities == null:
		session.close(); return null
	session._enemy_index = session._enemy_ids.size()
	session.step_enemy()
	check(session.phase == BattleTacticalSession.Phase.PLAYER_TURN and session.state.abilities.mage_allowed, "real enemy-to-player transition opens capability")
	if session.phase != BattleTacticalSession.Phase.PLAYER_TURN:
		session.close(); return null
	return session

func _snapshot(session: BattleCoreReactionsSession) -> Dictionary:
	var result := ItemSimulationSnapshot.capture(session.state, [])
	check(result.code == ItemSnapshotResult.Code.OK, "snapshot capture: " + result.reason)
	return result.snapshot.to_dict() if result.snapshot != null else {}

func _definition_catalog(session: BattleCoreReactionsSession) -> Dictionary:
	var result: Dictionary = {}
	for owner: ItemOwnerState in session.state.get_owners():
		for id: StringName in owner._definitions: result[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return result

func _ability_state(fire_cooldown: int) -> BattleAbilityState:
	var definitions := AbilityCatalog.defaults()
	for index: int in definitions.size():
		if definitions[index].ability_id == &"mage.fire":
			definitions[index] = definitions[index].copy()
			definitions[index].cooldown_turns = fire_cooldown
	return BattleAbilityState.create(definitions)

func _to_player_turn(state: BattleAbilityState) -> BattleAbilityState:
	var values := state.boundary(&"start", Faction.Type.ENEMY, 0)
	if values.is_empty(): return null
	state.apply_values(values)
	values = state.boundary(&"close", Faction.Type.ENEMY, state.serials[1]); state.apply_values(values)
	values = state.boundary(&"end", Faction.Type.ENEMY, state.serials[1]); state.apply_values(values)
	values = state.boundary(&"begin", Faction.Type.ENEMY, state.serials[1]); state.apply_values(values)
	values = state.boundary(&"open", Faction.Type.PLAYER, state.serials[0]); state.apply_values(values)
	return state if state.mage_allowed else null

func _advance_player_turn(state: BattleAbilityState) -> void:
	var values := state.boundary(&"close", Faction.Type.PLAYER, state.serials[0]); state.apply_values(values)
	values = state.boundary(&"end", Faction.Type.PLAYER, state.serials[0]); state.apply_values(values)
	values = state.boundary(&"begin", Faction.Type.PLAYER, state.serials[0]); state.apply_values(values)
	values = state.boundary(&"open", Faction.Type.ENEMY, state.serials[1]); state.apply_values(values)
	values = state.boundary(&"close", Faction.Type.ENEMY, state.serials[1]); state.apply_values(values)
	values = state.boundary(&"end", Faction.Type.ENEMY, state.serials[1]); state.apply_values(values)
	values = state.boundary(&"begin", Faction.Type.ENEMY, state.serials[1]); state.apply_values(values)
	values = state.boundary(&"open", Faction.Type.PLAYER, state.serials[0]); state.apply_values(values)

func _take_forecast(worker: ActionForecastWorker) -> ForecastSimulation:
	var result: ForecastSimulation = null
	for _i: int in 1000:
		result = worker.take_finished()
		if result != null: return result
		await process_frame
	return null
