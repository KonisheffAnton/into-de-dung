extends SceneTree

const FRESHNESS = preload("res://scripts/demo/battle_forecast_freshness.gd")

var passed: int = 0
var failed: int = 0

class UnsupportedNode extends RefCounted:
	var value: int = 1

class DynamicPropertyNode extends RefCounted:
	var value: int = 1
	func _get_property_list() -> Array[Dictionary]:
		return [{"name": "value", "type": TYPE_INT, "usage": PROPERTY_USAGE_SCRIPT_VARIABLE}]

class DerivedBattleSession extends BattleCoreReactionsSession:
	pass

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if condition: passed += 1
	else:
		failed += 1
		printerr("FAIL BATTLE FORECAST FRESHNESS: " + label)

func run() -> void:
	var session := _make_production_session()
	check(session != null, "production expedition fixture includes deck, abilities, owners and combat RNG")
	if session == null:
		_finish(); return
	var witness := FRESHNESS.capture(session)
	check(witness != null, "capture accepts the exact supported production session graph")
	if witness == null:
		session.close(); _finish(); return
	_test_unchanged_purity(session, witness)
	_test_live_inputs(session, witness)
	_test_metadata_and_connections(session)
	_test_unsupported_graphs(session)
	session.close()
	_finish()

func _make_production_session() -> BattleCoreReactionsSession:
	var hub := HeroHubState.create(9404)
	hub.enable_mage_deck()
	var started := ExpeditionTransitions.apply(hub, "start", {})
	if not started.is_ok(): return null
	var bundle := HeroHubBattleFactory.create(started.profile)
	if bundle.is_empty(): return null
	var session: BattleCoreReactionsSession = bundle.session
	if session.state.deck == null or session.state.abilities == null or session.state.get_owners().is_empty():
		session.close(); return null
	return session

func _test_unchanged_purity(session: BattleCoreReactionsSession, witness: BattleForecastFreshness) -> void:
	var captured := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	var before := captured.snapshot.to_dict() if captured.snapshot != null else {}
	var rng_before := session.context.get_rng().to_dict().duplicate(true)
	var counters_before := session.context.simulation_counters().duplicate(true)
	var receipt_id := session.last_receipt.get_instance_id() if session.last_receipt != null else 0
	var revision := session.context.get_revision()
	for _attempt: int in 3: check(witness.matches(session), "exact unchanged live graph matches repeatedly")
	var after := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	check(after.snapshot != null and after.snapshot.to_dict() == before
		and session.context.get_rng().to_dict() == rng_before and session.context.simulation_counters() == counters_before
		and session.context.get_revision() == revision
		and (session.last_receipt.get_instance_id() if session.last_receipt != null else 0) == receipt_id,
		"matching reads do not change snapshot, combat RNG, counters, revision or receipt")

func _test_live_inputs(session: BattleCoreReactionsSession, witness: BattleForecastFreshness) -> void:
	var actor := session.units[0]
	var old_mana: int = session.state.abilities.mana
	session.state.abilities.mana = old_mana + 1
	check(not witness.matches(session), "direct same-revision mana change invalidates the witness")
	session.state.abilities.mana = old_mana
	check(witness.matches(session), "restored mana returns to exact captured values")

	var old_burning: int = actor.elemental.burning_ticks
	actor.elemental.burning_ticks = old_burning + 1
	check(not witness.matches(session), "nested status field mutation invalidates the witness")
	actor.elemental.burning_ticks = old_burning
	check(witness.matches(session), "restored nested status matches again")

	var original_elemental := actor.elemental
	actor.elemental = ElementalState.from_dict(original_elemental.to_dict())
	check(not witness.matches(session), "same-value runtime object replacement invalidates identity witness")
	actor.elemental = original_elemental
	check(witness.matches(session), "restoring original object identity restores witness match")

	var old_base := actor.stats.get_base_value(StatTypes.StatType.STRENGTH)
	actor.stats.set_base_value(StatTypes.StatType.STRENGTH, old_base + 0.25)
	check(not witness.matches(session), "same-revision stat base change invalidates witness")
	actor.stats.set_base_value(StatTypes.StatType.STRENGTH, old_base)
	check(witness.matches(session), "restored stat base matches witness")

	var modifier := StatModifier.new(&"freshness_probe", StatModifier.Operation.ADD_FLAT, 0.25)
	actor.stats.add_modifier(StatTypes.StatType.STRENGTH, modifier)
	var modifier_witness := FRESHNESS.capture(session)
	check(modifier_witness != null, "fixture graph with a stat modifier remains supported")
	var old_modifier_value := modifier.value
	modifier.value = old_modifier_value + 0.5
	check(not modifier_witness.matches(session), "nested stat modifier value invalidates witness")
	modifier.value = old_modifier_value
	check(modifier_witness.matches(session), "restored modifier value matches captured graph")

	_test_items(session)
	_test_deck_and_rng(session)
	_test_board_and_queue(session, witness)

func _test_items(session: BattleCoreReactionsSession) -> void:
	var owner_with_item: ItemOwnerState
	var item: ItemInstance
	for owner: ItemOwnerState in session.state.get_owners():
		if owner._items.is_empty(): continue
		owner_with_item = owner
		item = owner._items.values()[0] as ItemInstance
		break
	check(item != null, "production expedition has a live owned item")
	if item == null: return
	var charges_before: int = item._charges_left
	var witness := FRESHNESS.capture(session)
	item._charges_left = charges_before + 1
	check(not witness.matches(session), "direct owner item charge change invalidates witness")
	item._charges_left = charges_before
	check(witness.matches(session), "restored owner item charge matches witness")
	var original_definition: ItemDef = owner_with_item._definitions[item.get_definition_id()]
	var isolated_definition := original_definition.duplicate(true) as ItemDef
	item._definition = isolated_definition
	owner_with_item._definitions[item.get_definition_id()] = isolated_definition
	var definition_witness := FRESHNESS.capture(session)
	check(definition_witness != null, "runtime item definition graph remains supported")
	var original_name := isolated_definition.display_name
	isolated_definition.display_name = original_name + " probe"
	check(not definition_witness.matches(session), "nested item-definition display mutation invalidates witness")
	isolated_definition.display_name = original_name
	check(definition_witness.matches(session), "restored nested item-definition graph matches")

func _test_deck_and_rng(session: BattleCoreReactionsSession) -> void:
	var deck := session.state.deck
	check(deck != null and not deck.cards.is_empty() and not deck.hand_ids.is_empty(), "deck fixture has cards and hand")
	if deck == null or deck.cards.is_empty() or deck.hand_ids.is_empty(): return
	var witness := FRESHNESS.capture(session)
	var old_type: String = deck.cards[0].type_id
	var changed_type: String = "card.heal" if old_type == "card.fire" else "card.fire"
	deck.cards[0].type_id = changed_type
	check(not witness.matches(session), "nested card definition change invalidates witness")
	deck.cards[0].type_id = old_type
	check(witness.matches(session), "restored card definition matches witness")
	var hand_count := deck.hand_ids.size()
	deck.hand_ids.append(deck.hand_ids[0])
	check(not witness.matches(session), "deck hand membership/order mutation invalidates witness")
	deck.hand_ids.resize(hand_count)
	check(witness.matches(session), "restored deck hand matches witness")
	var generator: RandomNumberGenerator = deck.draw_rng._generator
	var old_rng_state: int = generator.state
	var old_rng_seed: int = generator.seed
	generator.seed = old_rng_seed + 1
	check(not witness.matches(session), "native deck draw RNG seed mutation invalidates witness")
	generator.seed = old_rng_seed
	generator.state = old_rng_state
	check(witness.matches(session), "restored native deck RNG seed and state match witness")
	generator.randi()
	check(not witness.matches(session), "native deck draw RNG state mutation invalidates witness")
	generator.state = old_rng_state
	check(witness.matches(session), "restored native deck RNG state matches witness")
	var combat_rng: CombatRng = session.context.get_rng() as CombatRng
	var old_combat_state: int = combat_rng._generator.state
	var old_combat_seed: int = combat_rng._generator.seed
	combat_rng._generator.seed = old_combat_seed + 1
	check(not witness.matches(session), "CombatRng native generator seed mutation invalidates witness")
	combat_rng._generator.seed = old_combat_seed
	combat_rng._generator.state = old_combat_state
	check(witness.matches(session), "restored CombatRng native generator seed and state match witness")
	combat_rng._generator.randi()
	check(not witness.matches(session), "CombatRng native generator draw invalidates witness")
	combat_rng._generator.state = old_combat_state
	check(witness.matches(session), "restored CombatRng native generator state matches witness")

func _test_board_and_queue(session: BattleCoreReactionsSession, _witness: BattleForecastFreshness) -> void:
	var witness := FRESHNESS.capture(session)
	var old_limit: int = session._queue._max_events
	session._queue._max_events = old_limit + 1
	check(not witness.matches(session), "queue limits are part of the forecast witness")
	session._queue._max_events = old_limit
	check(witness.matches(session), "restored queue limits match witness")
	var old_counter: int = session.context._next_event_seq
	session.context._next_event_seq = old_counter + 1
	check(not witness.matches(session), "context simulation counters invalidate witness without revision change")
	session.context._next_event_seq = old_counter
	check(witness.matches(session), "restored context counters match witness")
	var free_cell := _find_free_floor(session.board)
	check(free_cell.x >= 0, "fixture has a free floor cell for board height probe")
	if free_cell.x < 0: return
	var board_version: int = session.board.board_version
	var old_height: int = session.board.get_height_steps(free_cell)
	session.board.set_height_steps(free_cell, old_height + 1)
	check(not witness.matches(session), "board terrain height change invalidates witness")
	session.board.set_height_steps(free_cell, old_height)
	session.board.board_version = board_version
	check(witness.matches(session), "restored terrain height matches witness")
	var moving := session.units[0]
	var old_cell := moving.cell
	board_version = session.board.board_version
	var destination := _find_free_floor(session.board)
	if destination == old_cell: destination = _find_free_floor(session.board, old_cell)
	check(destination.x >= 0 and session.board.move_unit(moving, destination), "board occupancy mutation uses BattleBoard move API")
	check(not witness.matches(session), "board occupancy and unit position mutation invalidates witness")
	check(session.board.move_unit(moving, old_cell), "board occupancy restoration uses BattleBoard move API")
	session.board.board_version = board_version
	var restored_board_witness := FRESHNESS.capture(session)
	check(restored_board_witness != null and restored_board_witness.matches(session),
		"restored board occupancy remains a supported exact graph after conservative dictionary-order invalidation")

func _find_free_floor(board: BattleBoard, excluded: Vector2i = Vector2i(-1, -1)) -> Vector2i:
	for y: int in board.height:
		for x: int in board.width:
			var cell := Vector2i(x, y)
			if cell == excluded or board.is_occupied(cell) or board.get_terrain(cell) != TerrainType.Type.FLOOR or board.is_lethal(cell): continue
			return cell
	return Vector2i(-1, -1)

func _test_metadata_and_connections(session: BattleCoreReactionsSession) -> void:
	session.set_meta(&"freshness_number", 17)
	var witness := FRESHNESS.capture(session)
	session.set_meta(&"freshness_number", 17.0)
	check(not witness.matches(session), "metadata int-to-float change invalidates typed witness despite numeric equality")
	session.set_meta(&"freshness_number", StringName("17"))
	check(not witness.matches(session), "metadata String-to-StringName change invalidates typed witness")
	session.set_meta(&"freshness_number", 17)
	check(witness.matches(session), "restored metadata scalar type and value matches")
	var addition_witness := FRESHNESS.capture(session)
	session.set_meta(&"freshness_added", 9)
	check(not addition_witness.matches(session), "new scalar metadata field invalidates witness")
	session.remove_meta(&"freshness_added")
	check(addition_witness.matches(session), "removing added metadata restores witness match")
	session.set_meta(&"freshness_text", "same")
	var string_witness := FRESHNESS.capture(session)
	session.set_meta(&"freshness_text", StringName("same"))
	check(not string_witness.matches(session), "String-to-StringName equality still invalidates typed witness")
	session.set_meta(&"freshness_text", "same")
	check(string_witness.matches(session), "restored String metadata matches")
	session.remove_meta(&"freshness_text")
	var baseline_connections := FRESHNESS.capture(session)
	session.board.board_changed.connect(_signal_probe)
	check(not baseline_connections.matches(session), "new signal connection invalidates witness")
	session.board.board_changed.disconnect(_signal_probe)
	check(baseline_connections.matches(session), "restored signal connections match witness")
	var callback_witness := FRESHNESS.capture(session)
	var callback_unit_id: int = session.units[0].id
	var callback: Callable = session.board._death_callbacks.get(callback_unit_id, Callable())
	check(callback.is_valid(), "production board registers a death callback for each live unit")
	if callback.is_valid():
		session.board._death_callbacks.erase(callback_unit_id)
		check(not callback_witness.matches(session), "death callback registry removal invalidates witness even while signal stays connected")
		session.board._death_callbacks[callback_unit_id] = callback
		check(callback_witness.matches(session), "restoring the exact death callback registry entry restores witness")
	var board := session.board
	session.board = null
	check(FRESHNESS.capture(session) == null, "null board is rejected before freshness graph traversal")
	session.board = board
	session.remove_meta(&"freshness_number")
	var rid_witness := FRESHNESS.capture(session)
	session.set_meta(&"freshness_rid", RID())
	session.set_meta(&"freshness_number", 17)
	check(not rid_witness.matches(session), "adding RID metadata invalidates an existing supported witness")
	check(FRESHNESS.capture(session) == null, "RID plus integer metadata is rejected instead of collapsing into an empty byte encoding")
	session.remove_meta(&"freshness_rid")
	session.remove_meta(&"freshness_number")

	var list: Array = [1, 2]
	session.set_meta(&"freshness_cycle_probe", list)
	var finite := FRESHNESS.capture(session)
	list.append(list)
	check(not finite.matches(session), "new cycle differs from finite witness without recursive error")
	list.pop_back()
	check(finite.matches(session), "finite restored metadata again matches")
	session.remove_meta(&"freshness_cycle_probe")

func _test_unsupported_graphs(session: BattleCoreReactionsSession) -> void:
	var derived := DerivedBattleSession.new()
	check(FRESHNESS.capture(derived) == null, "unsupported BattleCoreReactionsSession subclass falls back")
	derived.close()
	session.set_meta(&"unsupported_node", UnsupportedNode.new())
	check(FRESHNESS.capture(session) == null, "unknown runtime object in metadata falls back")
	session.remove_meta(&"unsupported_node")
	session.set_meta(&"dynamic_property_node", DynamicPropertyNode.new())
	check(FRESHNESS.capture(session) == null, "dynamic-property runtime object in metadata falls back")
	session.remove_meta(&"dynamic_property_node")
	session.set_meta(&"callable_value", Callable(self, "_signal_probe"))
	check(FRESHNESS.capture(session) == null, "callable metadata falls back")
	session.remove_meta(&"callable_value")
	var cycle: Array = []
	cycle.append(cycle)
	session.set_meta(&"cyclic_value", cycle)
	check(FRESHNESS.capture(session) == null, "cycle in the initial graph falls back")
	session.remove_meta(&"cyclic_value")

func _signal_probe() -> void:
	pass

func _finish() -> void:
	print("BATTLE FORECAST FRESHNESS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
