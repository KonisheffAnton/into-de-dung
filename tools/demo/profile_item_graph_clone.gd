extends SceneTree

const Probe = preload("res://tools/demo/item_graph_clone_probe.gd")
const Transfer = preload("res://tools/demo/item_clone_transfer_probe.gd")
const PlayerFixture = preload("res://tests/fixtures/player_turn_fixture.gd")
var passed: int = 0
var failed: int = 0

class RecordingSink extends ActionEventSink:
	var publications: Array[Dictionary] = []
	var mutate_deck: BattleDeckState
	func publish(event: Dictionary) -> void:
		publications.append(event.duplicate(true))
		if mutate_deck != null: mutate_deck.replaced_serial += 1

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL ITEM GRAPH CLONE: " + label)

func values(state: ItemSimulationState) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "capture values: " + captured.reason)
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func record_parity(label: String, data: Dictionary) -> void:
	if OS.get_cmdline_user_args().has("--emit-parity"):
		var digest := var_to_bytes(SimulationSnapshot._canonical(data)).hex_encode().sha256_text()
		print("ITEM_GRAPH_PARITY " + JSON.stringify({"label": label, "digest": digest}))

func catalogue(state: ItemSimulationState) -> Dictionary:
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in state.get_owners():
		for id: StringName in owner._definitions:
			definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	return definitions

func restore(state: ItemSimulationState) -> ItemSimulationState:
	var captured := ItemSimulationSnapshot.capture(state, [])
	check(captured.snapshot != null, "control capture")
	if captured.snapshot == null: return null
	var restored := captured.snapshot.instantiate(catalogue(state))
	check(restored.state != null, "control restore: " + restored.reason)
	return restored.state

func caches(state: ItemSimulationState) -> Array:
	var result: Array = []
	for unit: UnitState in state.get_board().get_all_units():
		for stat: Stat in unit.stats._stats.values():
			result.append([stat.get_instance_id(), stat._cache_dirty, stat._cached_value])
		result.append(unit.vitals.died.get_connections())
	return result

func close_checked(state: ItemSimulationState, label: String) -> void:
	if state == null: return
	var board := state.get_board()
	var units := board.get_all_units()
	ForecastSimulation.close(state)
	check(board._death_callbacks.is_empty(), label + " callback registry cleanup")
	for unit: UnitState in units:
		check(unit.vitals.died.get_connections().is_empty(), label + " death subscriptions cleanup")
	for owner: ItemOwnerState in state.get_owners():
		check(owner.is_closed(), label + " owner closed")

func identities(source: ItemSimulationState, clone: ItemSimulationState, label: String) -> void:
	check(source != clone and source.get_board() != clone.get_board(), label + " state/board detached")
	for original: UnitState in source.get_board().get_all_units():
		var unit := clone.get_board().get_unit_by_id(original.id)
		check(unit != original and unit.stats != original.stats and unit.vitals != original.vitals, label + " unit/stats/vitals detached")
		for key: int in original.stats._stats:
			var a: Stat = original.stats._stats[key]
			var b: Stat = unit.stats._stats[key]
			check(a != b and a._modifiers.size() == b._modifiers.size(), label + " stat detached")
			for i: int in a._modifiers.size(): check(a._modifiers[i] != b._modifiers[i], label + " modifier detached")
		for key: String in ["action_resources", "armor", "bleeding", "control", "combat_perks", "elemental"]:
			check((original.get(key) == null and unit.get(key) == null) or original.get(key) != unit.get(key), label + " component " + key)
	for original: ItemOwnerState in source.get_owners():
		var owner := clone.get_owner(original._owner.id)
		check(owner != original and owner._owner == clone.get_board().get_unit_by_id(original._owner.id), label + " owner binds cloned unit")
		for id: StringName in original._definitions:
			var a: ItemDef = original._definitions[id]
			var b: ItemDef = owner._definitions[id]
			check(a != b, label + " definition detached")
			if a.use_summon: check(a.summon_definition != b.summon_definition, label + " summon definition detached")
			for i: int in a.effects.size(): check(a.effects[i] != b.effects[i], label + " definition effect detached")
		for id: int in original._items:
			var a: ItemInstance = original._items[id]
			var b: ItemInstance = owner._items[id]
			check(a != b and b._definition == owner._definitions[b._definition_id], label + " item definition binding")
			for i: int in a._effects.size(): check(a._effects[i] != b._effects[i], label + " effect runtime detached")
	for facade: InventoryState in clone.get_inventories():
		check(facade._state == clone.get_owner(facade._state._owner.id) and facade != source.get_inventory(facade._state._owner.id), label + " inventory binding")
	for facade: EquipmentState in clone.get_equipment_facades():
		check(facade._state == clone.get_owner(facade._state._owner.id) and facade != source.get_equipment(facade._state._owner.id), label + " equipment binding")
	for key: String in ["environment", "abilities", "artifacts", "deck", "card_effects"]:
		check((source.get(key) == null and clone.get(key) == null) or source.get(key) != clone.get(key), label + " optional " + key)

func graph_case(session: BattleDemoSession, label: String) -> void:
	var before := values(session.state)
	record_parity("graph/" + label, before)
	var cache_before := caches(session.state)
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var counters_before := session.context.simulation_counters()
	var allocator := UnitId.get_counter()
	var first := Probe.clone_state(session.state)
	var second := Probe.clone_state(session.state)
	var control := restore(session.state)
	check(first.admission.code == ItemSnapshotResult.Code.OK and first.state != null and first.admission.snapshot == null, label + " clone admitted without published DTO")
	if first.state != null and second.state != null and control != null:
		check(values(first.state) == before and values(first.state) == values(control), label + " complete DTO equality")
		check(ItemSimulationSnapshot.capture(first.state, []).snapshot.canonical_bytes() == ItemSimulationSnapshot.capture(control, []).snapshot.canonical_bytes(), label + " canonical bytes equality")
		identities(session.state, first.state, label)
		identities(first.state, second.state, label + " siblings")
		check(caches(session.state) == cache_before, label + " source caches/signals unchanged")
		# Изменяем вложенные ветви копии; затем проверяем исходник и вторую копию целиком.
		var unit := first.state.get_board().get_all_units()[0]
		unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 123.0)
		unit.vitals.set_hp(1.0)
		for owner: ItemOwnerState in first.state.get_owners():
			owner._next_item_id += 1
			for definition: ItemDef in owner._definitions.values():
				definition.use_heal_amount += 1.0
				if definition.use_summon: definition.summon_definition.hp_max += 1.0
		for key: String in ["environment", "abilities", "artifacts", "deck", "card_effects"]:
			var branch: RefCounted = first.state.get(key)
			if branch == null: continue
			# Содержательные мутации коллекций ловят shallow-copy внутри codec.
			match key:
				"environment": first.state.environment.corpses.clear()
				"abilities": first.state.abilities.catalog[0].mana_cost += 1
				"artifacts": first.state.artifacts.formation_serials[0] += 1
				"deck": first.state.deck.cards[0]["origin"] = "probe"
				"card_effects": first.state.card_effects.ordinary_attacks[0]["attack_id"] = "probe"
		if not first.state._summons.is_empty(): first.state._summons[0]["pending"] = not first.state._summons[0]["pending"]
		check(values(session.state) == before and values(second.state) == before, label + " nested isolation")
		check(session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before and UnitId.get_counter() == allocator, label + " source RNG/counters/UnitId pure")
	close_checked(first.state, label)
	close_checked(second.state, label)
	close_checked(control, label)
	check(values(session.state) == before, label + " clone cleanup leaves source intact")
	session.close()

func deck_fixture() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	var cards: Array = []
	for card: MageCardDefinition in MageCardCatalog.all(): cards.append({"id": cards.size() + 1, "type_id": card.id, "origin": "base" if cards.size() < 10 else "found"})
	session.state.deck = BattleDeckState.create(cards, 88)
	session.state.card_effects = BattleCardEffectState.new()
	for unit: UnitState in session.units:
		session.state.card_effects.ordinary_attacks.append({"unit_id": unit.id, "attack_id": "demo_strike"})
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
		unit.vitals.set_hp(80.0)
		unit.control.stunned_turns = 0
		unit.control.entangled_turns = 0
		unit.elemental.frozen_turns = 0
	session.state.abilities = BattleAbilityState.create_deck(session.state.abilities.catalog, Faction.Type.ENEMY)
	check(session._queue.submit(ConfirmMageMulliganCommand.new([], session.context.get_revision()), session.context).status == ActionReceipt.APPLIED, "deck mulligan")
	check(session._queue.submit(AbilityBoundaryCommand.new(&"start", 1, 0, session.context.get_revision()), session.context).status == ActionReceipt.APPLIED, "deck start")
	session._enemy_index = session._enemy_ids.size()
	session.step_enemy()
	session.selected_id = session.living_ids(Faction.Type.PLAYER)[0]
	return session

func card_in_hand(session: BattleCoreReactionsSession, type_id: String) -> int:
	for card: Dictionary in session.state.deck.cards:
		if card.type_id != type_id: continue
		if not session.state.deck.hand_ids.has(card.id):
			var index := session.state.deck.draw_ids.find(card.id)
			var old: int = session.state.deck.hand_ids[0]
			session.state.deck.hand_ids[0] = card.id
			session.state.deck.draw_ids[index] = old
		return card.id
	return 0

func artifact_fixture() -> BattleCoreReactionsSession:
	var session := PlayerFixture.create()
	var heroes := session.living_ids(Faction.Type.PLAYER)
	heroes.sort()
	var data := {"schema": 1, "heroes": heroes, "mages": [heroes[2]], "attacks": [], "equipped": [{"id": 41, "unit_id": heroes[2], "slot": 1, "definition": "spark", "version": 1, "stacks": 2}], "formation_serials": [0, 0]}
	for id: int in heroes: data.attacks.append({"unit_id": id, "attack_id": "demo_strike"})
	session.state.artifacts = BattleArtifactState.from_dict(data)
	return session

func admission_case(source: ItemSimulationState, label: String, ids: Array[StringName] = []) -> void:
	var expected := ItemSimulationSnapshot.capture(source, ids)
	var actual := Probe.clone_state(source, ids)
	check(expected.code != ItemSnapshotResult.Code.OK, label + " rejection fixture")
	check(actual.admission.code == expected.code and actual.admission.reason == expected.reason and actual.admission.unsupported_ids == expected.unsupported_ids, label + " exact admission/reason/IDs")
	check(actual.state == null and actual.admission.snapshot == null, label + " no state/DTO on refusal")

func admission_cases() -> void:
	admission_case(null, "null")
	admission_case(null, "external IDs first", [&"z", &"a", &"z"])
	for kind: String in ["guard", "item", "owner", "modifier", "summon", "deck", "card_effects", "definition", "facade"]:
		var session := deck_fixture() if kind in ["deck", "card_effects"] else PlayerFixture.create()
		var owner := session.state.get_owners()[0]
		match kind:
			"guard": owner._guard = true; session.board.width = -1
			"item": (owner._items.values()[0] as ItemInstance)._charges_left = -99
			"owner": owner._next_item_id = 0
			"modifier": (owner._owner.stats._stats.values()[0] as Stat)._next_modifier_slot = -1
			"summon": session.state._summons.append({"unit_id": 999999, "owner_unit_id": owner._owner.id, "pending": false})
			"deck": session.state.deck.hand_ids.append(999999)
			"card_effects": session.state.card_effects.ordinary_attacks[0]["unit_id"] = 999999
			"definition": (owner._definitions.values()[0] as ItemDef).use_heal_amount = -1.0
			"facade": session.state._inventories.append(session.state._inventories[0])
		admission_case(session.state, kind)
		owner._guard = false
		if kind == "guard": session.board.width = 6
		if kind == "facade": session.state._inventories.pop_back()
		session.close()

func outcome(session: BattleCoreReactionsSession, state: ItemSimulationState, command: Command, fault: bool) -> Dictionary:
	var context := session.context.copy_for_simulation(state, session.context.get_rng().clone())
	var queue := session._queue.copy_for_simulation()
	var sink := RecordingSink.new()
	if fault: sink.mutate_deck = state.deck
	context._sink = sink
	var before := values(state)
	var admission_before := SummonAdmission.values(context)
	var receipt := queue.submit(command.copy_for_queue(), context)
	return {"before": before, "status": receipt.status, "reason": receipt.reason, "events": receipt.get_events(), "steps": receipt.get_steps(), "after": values(state), "rng": context.get_rng().to_dict(), "counters": context.simulation_counters(), "admission_before": admission_before, "admission": SummonAdmission.values(context), "publications": sink.publications}

func worker_outcome(session: BattleCoreReactionsSession, command: Command, fault: bool, use_clone: bool, expected: Dictionary, label: String) -> void:
	var state := Probe.clone_state(session.state).state if use_clone else restore(session.state)
	check(state != null, label + " worker graph admitted")
	if state == null: return
	var packet := Transfer.prepare(session.context, session._queue, command, state, fault)
	var error := Transfer.isolation_error([session.context, session._queue, command], packet)
	check(error.is_empty(), label + " whole packet ownership: " + error)
	if error.is_empty():
		var worker := Transfer.Worker.new()
		var started := worker.start(packet)
		check(started, label + " real thread started")
		if started:
			var result := worker.take()
			check(result == expected, label + " threaded before/after/receipt/publications/RNG/counters/admission")
			check(worker.take().is_empty() and not worker.start(packet) and packet.run() == {"error": "consumed"}, label + " one shot")
		worker.close()
	close_checked(state, label + " worker joined cleanup")

func command_case(session: BattleCoreReactionsSession, command: Command, label: String, fault: bool = false, expected_status: StringName = ActionReceipt.APPLIED) -> void:
	var before := values(session.state)
	var original_rng := session.context.get_rng().to_dict().duplicate(true)
	var original_counters := session.context.simulation_counters()
	var original_admission := SummonAdmission.values(session.context)
	var allocator := UnitId.get_counter()
	var control := restore(session.state)
	var clone := Probe.clone_state(session.state)
	check(control != null and clone.state != null, label + " both strategies admitted")
	if control != null and clone.state != null:
		var expected := outcome(session, control, command, fault)
		record_parity("command/" + label, expected)
		var actual := outcome(session, clone.state, command, fault)
		check(expected.status == expected_status, label + " expected status: " + String(expected.reason))
		check(actual == expected, label + " full command/publication/RNG/counters/admission parity")
		worker_outcome(session, command, fault, false, expected, label + " restore")
		worker_outcome(session, command, fault, true, expected, label + " clone")
		check(values(session.state) == before and session.context.get_rng().to_dict() == original_rng and session.context.simulation_counters() == original_counters and SummonAdmission.values(session.context) == original_admission and UnitId.get_counter() == allocator, label + " isolated execution")
		if not fault:
			var preview := ForecastSimulation.run(session.context, session._queue, command)
			check(preview.status == actual.status and preview.reason == actual.reason and preview.events == actual.events and preview.steps == actual.steps and preview.snapshot_after == actual.after and preview.rng_after == actual.rng and preview.counters_after == actual.counters and preview.admission_after == actual.admission, label + " production preview parity")
		var sink := RecordingSink.new()
		if fault: sink.mutate_deck = session.state.deck
		session.context._sink = sink
		var live := session._queue.submit(command.copy_for_queue(), session.context)
		check(live.status == actual.status and live.reason == actual.reason and live.get_events() == actual.events and live.get_steps() == actual.steps and values(session.state) == actual.after and session.context.get_rng().to_dict() == actual.rng and session.context.simulation_counters() == actual.counters and SummonAdmission.values(session.context) == actual.admission and sink.publications == actual.publications, label + " live parity")
		if live.status == ActionReceipt.APPLIED:
			var post := Probe.clone_state(session.state)
			check(post.state != null and values(post.state) == actual.after, label + " clone populated result graph")
			if post.state != null: identities(session.state, post.state, label + " populated result")
			close_checked(post.state, label + " populated result")
	close_checked(control, label)
	close_checked(clone.state, label)
	session.close()

func command_cases() -> void:
	for kind: String in ["guard", "heal", "summon", "raise", "armor", "attack", "move", "reject"]:
		var session := PlayerFixture.create()
		var actor := session.selected_unit()
		var command: Command
		match kind:
			"guard", "reject": command = GuardCommand.new(actor.id, session.context.get_revision() + (1 if kind == "reject" else 0))
			"heal":
				actor.vitals.set_hp(10.0)
				command = session.item_command(actor.id, session.healing_item().get_item_instance_id())
			"summon": command = session.item_command(actor.id, session.summoning_item().get_item_instance_id(), Vector2i(0, 1))
			"raise": command = session._raise_command(Vector2i(0, 3))
			"armor":
				for item: ItemInstance in session.state.get_owner(actor.id)._items.values():
					if item.get_definition().armor_max > 0: item.armor_remaining = 0
				command = RestoreArmorCommand.new(actor.id, 20, session.context.get_revision())
			"attack":
				session.select_unit(session.units[2].id)
				command = session._command_for(session.units[3].id)
			"move": command = MoveCommand.new(actor.id, session.path_to(Vector2i(1, 2)), session.context.get_revision())
		command_case(session, command, kind, false, ActionReceipt.REJECTED if kind == "reject" else ActionReceipt.APPLIED)
	for card: MageCardDefinition in MageCardCatalog.all():
		var session := deck_fixture()
		var id := card_in_hand(session, card.id)
		var target_id: int = session.living_ids(Faction.Type.ENEMY)[0] if card.target_policy in ["enemy_unit", "living_unit"] else session.selected_id
		var cell := Vector2i(-1, -1)
		if card.target_policy in ["valid_cell", "corpse_cell"]:
			for delta: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
				var candidate := session.selected_unit().cell + delta
				if UseSummoningItemCommand.valid_cell(session.board, session.selected_unit().cell, candidate) and session.state.environment.fire_at(candidate).is_empty():
					cell = candidate
					break
			check(cell != Vector2i(-1, -1), "cell card fixture")
			if card.id == "card.raise":
				var fallen := session.board.get_unit_by_id(session.living_ids(Faction.Type.ENEMY)[0])
				check(session.board.move_unit(fallen, cell), "raise corpse placement")
				check(session._queue.submit(DeathCommand.new(fallen.id, DamageSource.new(&"test", 0, cell)), session.context).status == ActionReceipt.APPLIED, "raise corpse creation")
			target_id = 0
		command_case(session, PlayMageCardCommand.new(id, target_id, cell, session.context.get_revision()), card.id)
	var faulted := deck_fixture()
	var fault_id := card_in_hand(faulted, "card.fire_imbue")
	command_case(faulted, PlayMageCardCommand.new(fault_id, faulted.selected_id, Vector2i(-1, -1), faulted.context.get_revision()), "card publication fault", true, ActionReceipt.FAULTED)
	var artifacts := artifact_fixture()
	artifacts.select_unit(artifacts.units[2].id)
	command_case(artifacts, artifacts._command_for(artifacts.units[3].id), "artifact attack")

func freshness_and_lifecycle() -> void:
	var session := PlayerFixture.create()
	var before := Probe.clone_state(session.state)
	var version := session.board.board_version
	var revision := session.context.get_revision()
	session.state.get_owners()[0]._next_item_id += 1
	session.units[0].vitals.set_hp(2.0)
	var after := Probe.clone_state(session.state)
	check(after.state != null and values(after.state) == values(session.state) and values(before.state) != values(after.state), "fresh clone sees mutation")
	check(session.board.board_version == version and session.context.get_revision() == revision, "freshness without version/revision")
	session.state.get_owners()[0]._guard = true
	admission_case(session.state, "fresh busy after success")
	session.state.get_owners()[0]._guard = false
	close_checked(before.state, "fresh before"); close_checked(after.state, "fresh after")
	session.close()
	for kind: String in ["retired", "closed", "irregular", "summoned"]:
		var item_session := PlayerFixture.create()
		var owner := item_session.state.get_owners()[0]
		if kind in ["retired", "closed"]:
			var inventory := item_session.state.get_inventory(owner._owner.id)
			inventory.close(); item_session.state._inventories.erase(inventory)
			var equipment := item_session.state.get_equipment(owner._owner.id)
			equipment.close(); item_session.state._equipment.erase(equipment)
			if kind == "closed": owner.close()
		elif kind == "irregular":
			item_session.board._occupancy.erase(item_session.units[0].cell)
			item_session.units[0].height += 3
		elif kind == "summoned":
			check(item_session.use_summoning_item(Vector2i(0, 1)).status == ActionReceipt.APPLIED, "active summon fixture")
		graph_case(item_session, kind)

func transfer_lifecycle() -> void:
	var session := PlayerFixture.create()
	var command := GuardCommand.new(session.selected_id, session.context.get_revision())
	var state := Probe.clone_state(session.state).state
	var packet := Transfer.prepare(session.context, session._queue, command, state, false)
	var roots: Array = [session.context, session._queue, command]
	check(Transfer.isolation_error(roots, packet).is_empty(), "transfer baseline ownership")
	var own_rng := packet.context._rng
	packet.context._rng = session.context._rng
	check(Transfer.isolation_error(roots, packet) == "shared object", "ownership rejects RNG alias")
	packet.context._rng = own_rng
	var definition: ItemDef = state.get_owners()[0]._definitions.values()[0]
	definition.set_meta(&"probe", session.context)
	check(not Transfer.isolation_error(roots, packet).is_empty(), "ownership follows metadata alias")
	definition.remove_meta(&"probe")
	var nested: Dictionary = {"values": [1, 2]}
	session.context.set_meta(&"probe", nested)
	definition.set_meta(&"probe", nested)
	check(Transfer.isolation_error(roots, packet) == "shared container", "ownership rejects nested container alias")
	session.context.remove_meta(&"probe")
	definition.remove_meta(&"probe")
	definition.set_meta(&"probe", Callable(session, "close"))
	check(Transfer.isolation_error(roots, packet) == "callback", "ownership rejects callback")
	definition.remove_meta(&"probe")
	var foreign := RefCounted.new()
	definition.set_meta(&"probe", foreign)
	check(Transfer.isolation_error(roots, packet).begins_with("unknown object:"), "ownership rejects unknown native object")
	definition.remove_meta(&"probe")
	var callback := func() -> void: pass
	state.get_board().get_all_units()[0].vitals.died.connect(callback)
	check(Transfer.isolation_error(roots, packet) == "signal", "ownership rejects external signal")
	state.get_board().get_all_units()[0].vitals.died.disconnect(callback)
	check(Transfer.isolation_error(roots, packet).is_empty(), "ownership fresh after negative cases")
	var failed_worker := Transfer.Worker.new()
	check(not failed_worker.start(packet, null, true) and not packet.consumed and failed_worker.take().is_empty(), "launch refusal retains packet")
	failed_worker.close()
	close_checked(state, "launch refusal")
	# Поток ждёт gate; main меняет только исходник и не читает переданный пакет.
	state = Probe.clone_state(session.state).state
	packet = Transfer.prepare(session.context, session._queue, command, state, false)
	var expected_state := restore(session.state)
	var expected := outcome(session, expected_state, command, false)
	close_checked(expected_state, "transfer expected")
	check(Transfer.isolation_error(roots, packet).is_empty(), "delayed transfer ownership")
	var gate := Semaphore.new()
	var worker := Transfer.Worker.new()
	var started := worker.start(packet, gate)
	check(started, "delayed real thread started")
	if started:
		session.units[0].vitals.set_hp(3.0)
		for owner: ItemOwnerState in session.state.get_owners():
			for item_definition: ItemDef in owner._definitions.values():
				if item_definition.use_heal_amount > 0.0: item_definition.use_heal_amount += 1.0
		var changed := values(session.state)
		gate.post()
		check(worker.take() == expected, "worker independent of source mutation after transfer")
		check(values(session.state) == changed, "worker leaves mutated source untouched")
	worker.close()
	close_checked(state, "delayed transfer")
	state = Probe.clone_state(session.state).state
	packet = Transfer.prepare(session.context, session._queue, command, state, false)
	check(Transfer.isolation_error(roots, packet).is_empty(), "discard ownership")
	worker = Transfer.Worker.new()
	started = worker.start(packet)
	check(started, "discard real thread started")
	worker.close()
	check((not started or packet.consumed) and worker.take().is_empty(), "discard joins before returning ownership")
	close_checked(state, "discard joined cleanup")
	session.close()

func benchmark(session: BattleDemoSession, label: String) -> void:
	var before := values(session.state)
	var raw: Array[Dictionary] = []
	var reverse := OS.get_cmdline_user_args().has("--reverse")
	for iteration: int in range(-3, 21):
		for slot: int in 2:
			var strategy := (slot + iteration + 4 + int(reverse)) % 2
			var start := Time.get_ticks_usec()
			var state: ItemSimulationState
			var phases: Dictionary
			if strategy == 0:
				var capture := ItemSimulationSnapshot.capture(session.state, [])
				var captured_at := Time.get_ticks_usec()
				var definitions := catalogue(session.state)
				var catalogued_at := Time.get_ticks_usec()
				state = capture.snapshot.instantiate(definitions).state
				phases = {"capture": captured_at - start, "catalogue": catalogued_at - captured_at, "build": Time.get_ticks_usec() - catalogued_at}
			else:
				var result := Probe.clone_state(session.state)
				state = result.state
				phases = result.phases_usec.duplicate()
			var built_at := Time.get_ticks_usec()
			ForecastSimulation.close(state)
			phases["cleanup"] = Time.get_ticks_usec() - built_at
			phases["total"] = Time.get_ticks_usec() - start
			if iteration >= 0: raw.append({"fixture": label, "iteration": iteration, "strategy": "capture_restore" if strategy == 0 else "capture_checked_clone", "usec": phases})
	check(values(session.state) == before, label + " benchmark source pure")
	for row: Dictionary in raw: print("ITEM_GRAPH_SAMPLE " + JSON.stringify(row))
	session.close()

func _run() -> void:
	graph_case(BattleTacticalSession.new(), "tactical")
	graph_case(BattleEnvironmentSession.new(), "environment")
	graph_case(BattleCoreReactionsSession.new(), "core")
	graph_case(artifact_fixture(), "artifacts")
	graph_case(deck_fixture(), "deck")
	var profile := HeroHubState.create(997)
	profile.enable_mage_deck()
	profile = ExpeditionTransitions.apply(profile, "start").profile
	var bundle := HeroHubBattleFactory.create(profile)
	check(not bundle.is_empty(), "production fixture")
	if not bundle.is_empty(): graph_case(bundle.session, "production")
	admission_cases()
	freshness_and_lifecycle()
	command_cases()
	transfer_lifecycle()
	if failed == 0 and not OS.get_cmdline_user_args().has("--verify-only"):
		benchmark(BattleTacticalSession.new(), "tactical")
		benchmark(artifact_fixture(), "artifacts")
		benchmark(deck_fixture(), "deck")
	print("ITEM GRAPH CLONE RESULTS: %d passed, %d failed" % [passed, failed])
	print("ITEM GRAPH CLONE DONE")
	quit(0 if failed == 0 else 1)
