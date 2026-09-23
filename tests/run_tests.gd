extends SceneTree

## Минимальный headless-раннер регрессионных тестов (первый шаг к G-5).
##
## ЗАЧЕМ ЭТО ЕСТЬ. Дефекты C-2 (порча HP через base_value) и C-3 (состояние
## владельца в разделяемом Resource) уехали в статус "Done" именно потому, что
## единственной проверкой был headless-прогон "нет ошибок компиляции". Он
## по своей природе не может отличить "HP уменьшилось на 3" от "HP выросло на 2".
##
## Тесты покрывают ТОЛЬКО чистую детерминированную логику — там, где
## визуальная проверка бессильна (округления, edge-case высот, порядок
## очереди, конвейер модификаторов). UI и флоу проверяются глазами.
##
## Запуск:
##   & $env:GODOT_BIN --path . --headless --script tests/run_tests.gd
##
## ПРИМЕЧАНИЕ: это временный самодельный раннер, а не полноценный фреймворк.
## Полноценный gdUnit4 будет подключён после работающего вертикального
## среза (R-7) — сейчас важнее, чтобы регрессии ловились вообще хоть чем-то,
## чем чтобы это было красиво.

var _passed: int = 0
var _failed: int = 0
var _current_suite: String = ""


func _initialize() -> void:
	print("=== Running regression tests ===\n")

	_suite("Stat pipeline (D-4.1)")
	_test_stat_flat_and_percent_order_independence()
	_test_stat_multiply_applies_to_total()
	_test_remove_modifiers_by_source()

	_suite("Vitals / C-2 regression")
	_test_damage_does_not_corrupt_base_value()
	_test_heal_clamped_by_max()
	_test_death_fires_once()
	_test_balance_break_resets()

	_suite("DamageCalculator (C-2, S-4)")
	_test_damage_calculator_is_pure()
	_test_damage_calculator_reports_events()
	_test_would_kill_prediction()
	_test_nested_damage_death_belongs_to_inner_apply()
	_test_death_apply_is_idempotent_for_domain_events()

	_suite("PushResolver (D-6.1)")
	_test_push_direction_axis_only()
	_test_push_blocked_by_wall_and_height()

	_suite("BattleBoard (C-4)")
	_test_board_occupancy_single_source_of_truth()
	_test_board_move_keeps_occupancy_in_sync()
	_test_board_version_increments()
	_test_pathfinding_respects_occupancy()
	_test_dead_unit_does_not_block()
	_test_death_clears_before_sink_and_preserves_corpse()
	_test_loaded_death_and_dead_add_do_not_occupy()
	_test_board_removes_death_subscriptions()

	_suite("Push outcomes (D-6.2 / C-4)")
	_test_push_collision_with_unit()
	_test_push_into_hazard_is_lethal()
	_test_push_off_board_is_lethal()
	_test_push_down_ledge_records_fall_height()
	_test_damage_info_exposes_collision_victim()

	_suite("InitiativeTimeline (D-4.6, D-4.7)")
	_test_death_does_not_restart_round()
	_test_round_boundary_signals()

	_suite("Grid math (D-1.x)")
	_test_grid_screen_roundtrip()

	_suite("Pathfinder consistency (module 3 invariant)")
	_test_path_and_reachable_agree_on_height_rule()

	_suite("AI scoring (S-3)")
	_test_abstain_excluded_from_average()
	_test_veto_zeroes_candidate()
	_test_ai_decision_is_deterministic()
	_test_ai_never_targets_occupied_cell()

	_suite("Serialization (R-4, G-2)")
	_test_board_roundtrip_serialization()

	_suite("P02 Board Snapshot")
	_test_p02_a01_roundtrip()
	_test_p02_a02_modifiers()
	_test_p02_a03_canonical_order()
	_test_p02_a04_isolation()
	_test_p02_a05_vitals_owner()
	_test_p02_a06_unit_id()
	_test_p02_a07_subscriptions()
	_test_p02_a08_value_ownership()
	_test_p02_a09_codec()
	_test_p02_a10_rejections()
	_test_p02_a11_board_edges()
	_test_p02_a12_old_save_unchanged()

	_suite("P03a Item ownership")
	_test_p03a_item_ownership()
	_test_p03a_acceptance()

	_suite("P03b Item snapshot and reactions")
	_test_p03b_b01_roundtrip()
	_test_p03b_b02_isolation()
	_test_p03b_b03_ids_and_placements()
	_test_p03b_b04_lifecycle()
	_test_p03b_b05_modifier_links()
	_test_p03b_b06_invalid_inputs()
	_test_p03b_b07_exact_types()
	_test_p03b_b08_catalogue()
	_test_p03b_b09_reactions()
	_test_p03b_b10_dto_ownership()
	_test_p03b_extended()
	_test_p03b_b11_codec()
	_test_p03b_b12_ownership_limits()
	_test_p03b_b13_purity()
	_test_p03b_review_boundaries()

	_suite("P04 action queue HP / RNG")
	_test_p04_c01_damage_sources_and_armor()
	_test_p04_c02_death_and_alive_at_zero()
	_test_p04_c03_heal_boundaries_and_rejections()
	_test_p04_c04_item_reactions()
	_test_p04_c05_bindings()
	_test_p04_c06_scheduler()
	_test_p04_c07_reentrancy()
	_test_p04_c08_dispatch_and_values()
	_test_p04_c09_limits()
	_test_p04_c10_faults_and_counters()
	_test_p04_c11_rng_port_isolation()

	_suite("P05 Move")
	_test_p05_m01_contracts()
	_test_p05_m02_geometry_and_budget()
	_test_p05_m03_root_rejections()
	_test_p05_m04_arithmetic()
	_test_p05_m05_hazard_death()
	_test_p05_m06_continuation_guards()
	_test_p05_m07_hazard_boundaries()
	_test_p05_m08_no_moved_reactions()
	_test_p05_m09_moved_schema()
	_test_p05_m10_interrupted_receipt()
	_test_p05_m11_depth_and_limits()
	_test_p05_m12_isolation()

	_suite("P06 resources and snapshots")
	_test_p06_a06_refill()
	_test_p06_a09_snapshot_versions()
	_test_p06_a10_rejections()

	_suite("P06 Attack")
	_test_p06_attack_happy_path()
	_test_p06_attack_rules_and_reach()
	_test_p06_attack_admission()
	_test_p06_attack_formula_and_items()
	_test_p06_attack_hit_seal()
	_test_p06_attack_move_and_limits()
	_test_p06_attack_event_schema()
	_test_p06_attack_rejection_matrix()
	_test_p06_attack_binding_matrix()
	_test_p06_attack_queue_guards()
	_test_p06_attack_reentrancy()
	_test_p06_attack_restored_isolation()

	_suite("P07 Balance / Push")
	_test_p07_a01_profiles()
	_test_p07_a02_balance()
	_test_p07_a03_lethal_hit()
	_test_p07_a04_directions()
	_test_p07_a05_blocked()
	_test_p07_a06_collision()
	_test_p07_a07_healing()
	_test_p07_a08_arithmetic()
	_test_p07_a09_drop()
	_test_p07_a10_lethal_push()
	_test_p07_a11_admission()
	_test_p07_a12_bindings()
	_test_p07_a13_limits()
	_test_p07_a14_events_busy()
	_test_p07_a15_snapshots()
	_test_p07_a16_entry()
	_test_p07_a17_prefix()
	_test_p07_extended_boundaries()
	_test_p07_collateral_guards()
	_test_p07_version_preflight()
	_test_p07_api_preflight()
	_test_p08_numbers()
	_test_p08_reactions_limits()
	_test_p08_lifecycle_callbacks_and_items()

	_suite("P08 spatial geometry")
	_test_p08_spatial_geometry()
	_test_p08_commands()
	_test_p08_refs()
	_test_p08_lifecycle_replay()
	_test_p08_receipts_and_seals()
	_test_p08_terminal_matrix()
	_test_p08_boundaries()
	_test_p08_move_binding_limits()
	_test_p08_command_reserves()
	_test_p08_lifecycle_mutations()
	_test_p08_paths()
	_test_p08_final_closure()
	_test_p08_unknown_malformed_priority()

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

func _p08rl_fixture(blocker_hp: float = -1.0) -> Dictionary:
	var fixture := _p07_fixture(blocker_hp)
	fixture.definition.profile = AttackRules.SPATIAL_PROFILE
	fixture.rules = AttackRules.new([fixture.actor.id], [{"actor_unit_id": fixture.actor.id, "target_unit_id": fixture.target.id}], [fixture.definition])
	fixture.context = ActionContext.new(fixture.state, P04TestRng.new(), ActionEventSink.new(), [], null, fixture.rules)
	return fixture

func _test_p08_reactions_limits() -> void:
	var move := _p05_fixture()
	var move_unit: UnitState = move["unit"]
	move_unit.action_resources = ActionResources.new(move_unit.id,1,1)
	var move_board: BattleBoard = move["board"]
	move_unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
	move_unit.stats.set_base_value(StatTypes.StatType.ARMOR, 3.0)
	move_unit.vitals.set_hp(100.0)
	move_board.set_height_steps(Vector2i(1, 1), -3)
	move_board.set_height_steps(Vector2i(2, 1), -3)
	move["context"] = ActionContext.new(move["state"], P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([201], 1, &"spatial_move_v1"))
	var heal_def := ItemDef.new(); heal_def.id = &"p08_move_heal"
	var heal_effect := HealOnDamageEffect.new(); heal_effect.heal_amount = 5.0; heal_def.effects = [heal_effect]
	var heal_item := (move["state"] as ItemSimulationState).get_owner(201).create_item(heal_def)
	(move["state"] as ItemSimulationState).get_inventory(201).add_item(heal_item)
	var move_receipt := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(3), 0), move["context"])
	_check(move_receipt.status == &"APPLIED" and move_unit.cell == Vector2i(2, 1) and move_unit.vitals.get_hp() == 83.0 and _p07_kinds(move_receipt).slice(0, 3) == [&"moved", &"damaged", &"healed"], "P08 spatial move fall and item reaction", move_receipt.reason)
	var lethal_move := _p05_fixture()
	var lethal_unit: UnitState = lethal_move["unit"]
	lethal_unit.action_resources = ActionResources.new(lethal_unit.id,1,1)
	lethal_unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 10.0)
	lethal_unit.stats.set_base_value(StatTypes.StatType.ARMOR, 3.0)
	lethal_unit.vitals.set_hp(10.0)
	(lethal_move["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.HAZARD)
	lethal_move["context"] = ActionContext.new(lethal_move["state"], P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([201], 1, &"spatial_move_v1"))
	var lethal_receipt := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(3), 0), lethal_move["context"])
	_check(lethal_receipt.status == &"INTERRUPTED" and lethal_receipt.reason == &"move/actor_dead" and _p07_kinds(lethal_receipt) == [&"moved",&"died"] and lethal_unit.move_points_left == 97.0, "P08 lethal move interrupts continuation without second debit", lethal_receipt.reason)
	var collision := _p08rl_fixture(8.0)
	collision.board.set_height_steps(collision.destination, -3)
	_p07_heal(collision, collision.target)
	_p07_heal(collision, collision.blocker)
	var collision_receipt := _p07_submit(collision)
	var collision_kinds := _p07_kinds(collision_receipt)
	_check(collision_receipt.status == &"APPLIED" and collision_kinds.slice(0, 9) == [&"attacked", &"damaged", &"balance_broken", &"collision", &"damaged", &"damaged", &"died", &"moved", &"damaged"], "P08 spatial collision mandatory prefix", collision_receipt.reason)
	_check(collision_kinds.has(&"moved") and collision_kinds.has(&"died") and _p07_events(collision_receipt, &"damaged").size() >= 4, "P08 spatial collision entry and fall events", collision_receipt.reason)
	var hazard := _p08rl_fixture()
	hazard.board.set_terrain(hazard.destination, TerrainType.Type.HAZARD)
	var hazard_receipt := _p07_submit(hazard)
	_check(hazard_receipt.status == &"APPLIED" and _p07_kinds(hazard_receipt) == [&"attacked", &"damaged", &"balance_broken", &"moved", &"died"], "P08 hazard has moved/death without numeric fall", hazard_receipt.reason)
	var limits := _p08rl_fixture(8.0)
	limits.target.vitals.set_hp(9.0)
	limits.board.set_height_steps(limits.destination, -3)
	limits.context._next_event_seq = ActionContext.MAX_ID - 4
	var limited := _p07_submit(limits)
	_check(limited.status == &"FAULTED" and limited.reason == &"sequence_exhausted" and limits.actor.action_resources.get_main_left() == 3 and _p07_kinds(limited) == [&"attacked",&"damaged",&"balance_broken"], "P08 spatial event boundary preserves prefix", limited.reason)
	move = {}; lethal_move = {}; collision = {}; hazard = {}; limits = {}

func _test_p08_lifecycle_callbacks_and_items() -> void:
	var source := _p08rl_fixture()
	var heal_definition := _p07_heal(source, source.target)
	var captured := ItemSimulationSnapshot.capture(source.state, [])
	_check(captured.code == ItemSnapshotResult.Code.OK, "P08 closure capture with influencing heal item")
	if captured.code != ItemSnapshotResult.Code.OK or captured.snapshot == null:
		source = {}
		return
	var catalogue: Dictionary = {heal_definition.id: heal_definition}
	var first := captured.snapshot.instantiate(catalogue)
	var second := captured.snapshot.instantiate(catalogue)
	_check(first.code == ItemSnapshotResult.Code.OK and second.code == ItemSnapshotResult.Code.OK, "P08 closure restores two item states")
	if first.state != null and second.state != null:
		var first_bytes := ItemSimulationSnapshot.capture(first.state, []).snapshot.canonical_bytes()
		var second_bytes := ItemSimulationSnapshot.capture(second.state, []).snapshot.canonical_bytes()
		_check(first_bytes == second_bytes and first_bytes == captured.snapshot.canonical_bytes(), "P08 restored item snapshots are canonical and independent")
		var first_unit := first.state.get_board().get_unit_by_id(source.target.id)
		var second_unit := second.state.get_board().get_unit_by_id(source.target.id)
		first_unit.vitals.set_hp(77.0)
		_check(second_unit.vitals.get_hp() != 77.0 and source.target.vitals.get_hp() == 100.0, "P08 restored item state does not mutate source")
	# Lifecycle 0/2 with a null facade is valid; invalid registration flags reject capture.
	source.board.remove_unit(source.target)
	var retired_owner := ItemOwnerState.new(source.actor)
	retired_owner._inventory_retired = true
	var retired_state := ItemSimulationState.new(source.board, [retired_owner], [], [])
	var retired_capture := ItemSimulationSnapshot.capture(retired_state, [])
	_check(retired_capture.code == ItemSnapshotResult.Code.OK, "P08 retired lifecycle without facade is valid")
	retired_owner._inventory_registered = true
	var invalid_capture := ItemSimulationSnapshot.capture(retired_state, [])
	_check(invalid_capture.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "P08 registered and retired lifecycle rejects")
	source = {}
	retired_state = null
	retired_owner = null

func _test_p08_numbers() -> void:
	var expected: Dictionary = {1: [8.0, 11.0], 2: [9.0, 12.0], -2: [5.0, 8.0], -4: [3.0, 6.0], -10: [1.0, 1.0]}
	for signed_steps: int in expected:
		var fixture := _p07_fixture()
		fixture.definition.profile = AttackRules.SPATIAL_PROFILE
		fixture.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 10.0)
		fixture.target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0)
		fixture.board.set_height_steps(fixture.actor.cell, signed_steps)
		fixture.rules = AttackRules.new([fixture.actor.id], [{"actor_unit_id": fixture.actor.id, "target_unit_id": fixture.target.id}], [fixture.definition])
		fixture.context = ActionContext.new(fixture.state, P04TestRng.new(), ActionEventSink.new(), [], null, fixture.rules)
		var range: int = 1 + floori(float(absi(signed_steps)) / 2.0)
		fixture.actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, float(range))
		var command := AttackCommand.new(fixture.actor.id, fixture.target.id, fixture.actor.cell, fixture.target.cell, fixture.definition.id, fixture.context.get_revision())
		var receipt := ActionQueue.new().submit(command, fixture.context)
		var pair: Array = expected[signed_steps]
		_check(receipt.status == &"APPLIED" and is_equal_approx(fixture.target.vitals.get_hp(), 100.0 - pair[0]) and is_equal_approx(fixture.target.vitals.get_balance(), pair[1]), "P08 spatial hit/impact signed %d" % signed_steps, receipt.reason)
	# I=0 remains zero, while a positive sub-unit impact receives spatial minimum one.
	var zero := _p07_fixture(); zero.definition.profile = AttackRules.SPATIAL_PROFILE; zero.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0); zero.target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0); zero.rules = AttackRules.new([zero.actor.id], [{"actor_unit_id": zero.actor.id, "target_unit_id": zero.target.id}], [zero.definition]); zero.context = ActionContext.new(zero.state, P04TestRng.new(), ActionEventSink.new(), [], null, zero.rules)
	var zero_receipt := _p07_submit(zero)
	_check(zero_receipt.status == &"APPLIED" and zero.target.vitals.get_balance() == 0.0, "P08 spatial impact zero remains zero")
	var fractional := _p07_fixture(); fractional.definition.profile = AttackRules.SPATIAL_PROFILE; fractional.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.5); fractional.target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 100.0); fractional.rules = AttackRules.new([fractional.actor.id], [{"actor_unit_id": fractional.actor.id, "target_unit_id": fractional.target.id}], [fractional.definition]); fractional.context = ActionContext.new(fractional.state, P04TestRng.new(), ActionEventSink.new(), [], null, fractional.rules)
	_check(_p07_submit(fractional).status == &"APPLIED" and fractional.target.vitals.get_balance() == 1.0, "P08 spatial positive impact minimum one")
	var fractional_board := _p07_fixture(); fractional_board.definition.profile = AttackRules.SPATIAL_PROFILE; fractional_board.board.set_height_steps(fractional_board.actor.cell, 1); fractional_board.rules = AttackRules.new([fractional_board.actor.id], [{"actor_unit_id": fractional_board.actor.id, "target_unit_id": fractional_board.target.id}], [fractional_board.definition]); fractional_board.context = ActionContext.new(fractional_board.state, P04TestRng.new(), ActionEventSink.new(), [], null, fractional_board.rules)
	_check(_p07_submit(fractional_board).status == &"APPLIED", "P08 spatial flat/half profile executes")
	var legacy := _p07_fixture(); legacy.board.set_height_steps(legacy.actor.cell, 1); legacy.definition.profile = AttackRules.PROFILE; legacy.rules = AttackRules.new([legacy.actor.id], [{"actor_unit_id": legacy.actor.id, "target_unit_id": legacy.target.id}], [legacy.definition]); legacy.context = ActionContext.new(legacy.state, P04TestRng.new(), ActionEventSink.new(), [], null, legacy.rules)
	var legacy_receipt := _p07_submit(legacy)
	_check(legacy_receipt.status == &"REJECTED" and legacy.actor.action_resources.get_main_left() == 4, "P08 legacy attack rejects fractional board before payment")

func _test_p08_spatial_geometry() -> void:
	var board := BattleBoard.new(5, 1)
	_check(board.set_height_steps(Vector2i(1, 0), 1) and board.get_height_steps(Vector2i(1, 0)) == 1, "P08 half setter stores positive half")
	_check(board.set_height_steps(Vector2i(2, 0), -1) and board.get_height_steps(Vector2i(2, 0)) == -1 and board.get_height(Vector2i(2, 0)) == -1, "P08 negative half uses mathematical floor")
	_check(board.set_height_steps(Vector2i(3, 0), -4294967296) and board.get_height_steps(Vector2i(3, 0)) == -4294967296, "P08 minimum steps")
	_check(board.set_height_steps(Vector2i(4, 0), 4294967295) and board.get_height_steps(Vector2i(4, 0)) == 4294967295, "P08 maximum steps")
	var board_v2 := board.to_snapshot_dict()
	_check(board_v2.get("schema_version") == 2 and board_v2.get("height_half_steps").size() == 5, "P08 schema2 canonical half array")
	var restored := BattleBoard.from_snapshot_dict(board_v2)
	_check(restored != null and restored.get_height_steps(Vector2i(2, 0)) == -1 and restored.get_height_steps(Vector2i(4, 0)) == 4294967295, "P08 schema2 independent restore")
	var all_zero: Dictionary = board_v2.duplicate(true)
	all_zero["height_half_steps"] = [0, 0, 0, 0, 0]
	_check(not BattleBoard.validate_snapshot_dict(all_zero), "P08 schema2 all zero is noncanonical")
	var missing_bits: Dictionary = board_v2.duplicate(true)
	missing_bits.erase("height_half_steps")
	_check(not BattleBoard.validate_snapshot_dict(missing_bits), "P08 schema2 missing bits is invalid")
	var unknown_shape: Dictionary = board_v2.duplicate(true)
	unknown_shape["schema_version"] = 3
	_check(not BattleBoard.validate_snapshot_dict(unknown_shape), "P08 unknown board schema rejected")
	for malformed_bit: Variant in [true, 0.5, -1, 2]:
		var malformed: Dictionary = board_v2.duplicate(true)
		malformed["height_half_steps"] = [malformed_bit, 0, 0, 0, 1]
		_check(not BattleBoard.validate_snapshot_dict(malformed), "P08 malformed half type/value rejected " + str(malformed_bit))
	var wrong_length: Dictionary = board_v2.duplicate(true)
	wrong_length["height_half_steps"] = [1]
	_check(not BattleBoard.validate_snapshot_dict(wrong_length), "P08 half array length rejected")
	_check(board.to_dict().is_empty(), "P08 legacy DTO gate on fractional board")
	_check(not board.set_height_steps(Vector2i(-1, 0), 0) and not board.set_height_steps(Vector2i(0, 0), 4294967296), "P08 setter rejects bounds and range")
	var spatial := board.make_spatial_data_provider()
	_check(spatial.has_spatial_heights() and spatial.cell_height_steps(Vector2i(1, 0)) == 1, "P08 spatial provider capability")
	_check(not board.make_data_provider().cell_is_walkable(Vector2i(0, 0)) and not board.make_terrain_only_provider().cell_is_walkable(Vector2i(0, 0)), "P08 legacy providers fail closed on halves")
	var flat := BattleBoard.new(3, 1)
	var provider := flat.make_spatial_data_provider()
	var edge := SpatialRules.inspect_edge(provider, Vector2i(0, 0), Vector2i(1, 0))
	_check(edge.reason == &"" and edge.cost == 1.0 and edge.drop_steps == 0, "P08 flat edge cost")
	flat.set_height_steps(Vector2i(1, 0), 1)
	edge = SpatialRules.inspect_edge(flat.make_spatial_data_provider(), Vector2i(0, 0), Vector2i(1, 0))
	_check(edge.reason == &"" and edge.cost == 1.0, "P08 half rise costs one")
	flat.set_height_steps(Vector2i(1, 0), 2)
	edge = SpatialRules.inspect_edge(flat.make_spatial_data_provider(), Vector2i(0, 0), Vector2i(1, 0))
	_check(edge.reason == &"" and edge.cost == 2.0, "P08 full rise costs two")
	var path := MovePathCheck.inspect(flat, null, [Vector2i(0, 0), Vector2i(1, 0)], 1, 3.0, &"spatial_move_v1")
	_check(path.get_reason() == &"move/invalid_runtime", "P08 path rejects missing actor")
	_check(is_equal_approx(SpatialRules.height_multiplier(0), 1.0) and is_equal_approx(SpatialRules.height_multiplier(1), 1.1) and is_equal_approx(SpatialRules.height_multiplier(-10), 0.0), "P08 linear height multiplier")
	_check(SpatialRules.fall_amount(100.0, 0.0, 2, false) == 25.0 and SpatialRules.fall_amount(100.0, 0.0, 2, true) == 0.0, "P08 fall threshold and amount")
	var actor_stats := StatsBag.new()
	var target_stats := StatsBag.new()
	var actor := UnitState.create(Faction.Type.PLAYER, Vector2i(0, 0), actor_stats, "p08_actor")
	var target := UnitState.create(Faction.Type.ENEMY, Vector2i(2, 0), target_stats, "p08_target")
	flat.set_height_steps(Vector2i(2, 0), 2)
	var reach := AttackReachCheck.inspect_spatial(flat, actor, target, 2.0)
	_check(reach == &"attack/out_of_reach", "P08 spatial reach includes full-level distance")
	_check(PushResolver.compute_push_direction(Vector2i(0, 0), Vector2i(4, 2)) == Vector2i(1, 0), "P08 push direction remains deterministic axis")
	flat.set_height_steps(Vector2i(1, 0), 1)
	var push := PushResolver.resolve_push_steps(flat, null, Vector2i(0, 0), Vector2i(1, 0), 1)
	_check(push.outcome == PushResult.Outcome.MOVED and push.fall_steps == 0, "P08 spatial push result")
	var move_board := BattleBoard.new(3, 2)
	var mover := UnitState.create(Faction.Type.PLAYER, Vector2i(0, 0), StatsBag.new(), "p08_mover")
	_check(move_board.add_unit(mover), "P08 path fixture placement")
	move_board.set_height_steps(Vector2i(1, 0), 1)
	move_board.set_height_steps(Vector2i(1, 1), 1)
	var finder := GridPathfinder.new()
	finder.configure(move_board.get_bounds(), move_board.make_spatial_data_provider(mover), 1, &"spatial_move_v1")
	var found_path := finder.find_path(Vector2i(0, 0), Vector2i(2, 0))
	var reachable := finder.get_reachable_cells(Vector2i(0, 0), 3.0)
	_check(found_path == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)] and reachable.has(Vector2i(2, 0)), "P08 spatial path and reachable share edge costs")
	var attack_board := BattleBoard.new(5, 1)
	var attack_stats := StatsBag.new()
	var enemy_stats := StatsBag.new()
	var attack_actor := UnitState.create(Faction.Type.PLAYER, Vector2i(0, 0), attack_stats, "p08_attack_actor")
	var friendly := UnitState.create(Faction.Type.PLAYER, Vector2i(1, 0), StatsBag.new(), "p08_friendly")
	var attack_target := UnitState.create(Faction.Type.ENEMY, Vector2i(3, 0), enemy_stats, "p08_attack_target")
	attack_board.add_unit(attack_actor); attack_board.add_unit(friendly); attack_board.add_unit(attack_target)
	_check(AttackReachCheck.inspect_spatial(attack_board, attack_actor, attack_target, 3.0) == &"", "P08 friendly occupant does not block line")
	attack_board.clear_occupancy(friendly)
	_check(AttackReachCheck.inspect_spatial(attack_board, attack_actor, attack_target, 3.0) == &"", "P08 clear line reaches target")
	var enemy_blocker := UnitState.create(Faction.Type.ENEMY, Vector2i(1, 0), StatsBag.new(), "p08_enemy_blocker")
	attack_board.add_unit(enemy_blocker)
	_check(AttackReachCheck.inspect_spatial(attack_board, attack_actor, attack_target, 3.0) == &"attack/line_blocked", "P08 enemy occupant blocks line")
	attack_board.remove_unit(enemy_blocker)
	var neutral := UnitState.create(Faction.Type.NEUTRAL, Vector2i(1, 0), StatsBag.new(), "p08_neutral")
	attack_board.add_unit(neutral)
	_check(AttackReachCheck.inspect_spatial(attack_board, attack_actor, attack_target, 3.0) == &"attack/line_blocked", "P08 player and neutral are not friendly")
	neutral.vitals._is_alive = false
	attack_board.clear_occupancy(neutral)
	_check(AttackReachCheck.inspect_spatial(attack_board, attack_actor, attack_target, 3.0) == &"", "P08 corpse does not block line")
	attack_board.set_terrain(Vector2i(2, 0), TerrainType.Type.WALL)
	_check(AttackReachCheck.inspect_spatial(attack_board, attack_actor, attack_target, 3.0) == &"attack/line_blocked", "P08 wall precedes terrain unsupported")
	attack_board.set_terrain(Vector2i(2, 0), TerrainType.Type.VOID)
	_check(AttackReachCheck.inspect_spatial(attack_board, attack_actor, attack_target, 3.0) == &"attack/terrain_shape_unsupported", "P08 void line is unsupported")
	var item_fixture := _p07_fixture()
	item_fixture.board.set_height_steps(Vector2i.ZERO, 1)
	var item_capture := ItemSimulationSnapshot.capture(item_fixture.state, [])
	_check(item_capture.code == ItemSnapshotResult.Code.OK, "P08 item snapshot v2 capture")
	if item_capture.snapshot != null:
		var item_dto := item_capture.snapshot.to_dict()
		var item_result := ItemSimulationSnapshot.from_dict(item_dto)
		_check(item_result.code == ItemSnapshotResult.Code.OK and item_result.snapshot.canonical_bytes() == item_capture.snapshot.canonical_bytes(), "P08 item snapshot canonical roundtrip")
	# Освобождаем локальные Callable/board graph до ObjectDB leak check раннера.
	provider = null
	spatial = null
	finder = null
	move_board = null
	attack_board = null
	flat = null
	board = null
	item_fixture = {}
	actor = null
	target = null
	attack_actor = null
	attack_target = null
	friendly = null
	neutral = null
	enemy_blocker = null


# --- Инфраструктура --------------------------------------------------------

func _suite(name: String) -> void:
	_current_suite = name
	print("[%s]" % name)

func _test_p03a_item_ownership() -> void:
	var stats:=StatsBag.new(); stats.set_base_value(StatTypes.StatType.STRENGTH,3.0)
	var unit:=UnitState.create(Faction.Type.PLAYER,Vector2i.ZERO,stats,"P03a")
	var state:=ItemOwnerState.new(unit); var inventory:=InventoryState.new(state)
	var definition:=ItemDef.new(); definition.id=&"p03a_test"
	var effect:=StatModifierEffect.new(); effect.stat_type=StatTypes.StatType.STRENGTH; effect.value=2.0; definition.effects=[effect]
	var a:=state.create_item(definition); var b:=state.create_item(definition)
	_check(a!=null and b!=null,"instances created")
	_check(inventory.add_item(a) and inventory.add_item(b),"copies activate independently")
	_check_eq(unit.get_stat(StatTypes.StatType.STRENGTH),7.0,"two copies stack")
	_check(inventory.remove_item(a),"remove one copy")
	_check_eq(unit.get_stat(StatTypes.StatType.STRENGTH),5.0,"one source remains")
	_check(a.get_item_instance_id()!=b.get_item_instance_id(),"identity ids differ")
	state.close(); _check(not b.is_active(),"close deactivates runtime")


func _check(condition: bool, label: String, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s %s" % [label, detail])


func _check_eq(actual: float, expected: float, label: String) -> void:
	_check(
		is_equal_approx(actual, expected),
		label,
		"(expected %.4f, got %.4f)" % [expected, actual]
	)

func _p06_unit() -> UnitState:
	var bag := StatsBag.new()
	bag.set_base_value(StatTypes.StatType.HP_MAX, 10.0)
	bag.set_base_value(StatTypes.StatType.MOVE_RANGE, 3.0)
	bag.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 2.0)
	bag.set_base_value(StatTypes.StatType.BONUS_ACTIONS_MAX, 1.0)
	bag.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 1.0)
	bag.set_base_value(StatTypes.StatType.ATTACK_RANGE, 1.0)
	return UnitState.create(Faction.Type.PLAYER, Vector2i.ZERO, bag, "P06")

func _p06_attack_fixture(main_max: float = 2.0) -> Dictionary:
	var board := BattleBoard.new(3, 1)
	var actor := _p06_unit()
	actor.stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, main_max)
	actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 2.0)
	var target := _p06_unit()
	target.cell = Vector2i(1, 0)
	target.stats.set_base_value(StatTypes.StatType.ARMOR, 1.0)
	board.add_unit(actor)
	board.add_unit(target)
	var actor_owner := ItemOwnerState.new(actor)
	var target_owner := ItemOwnerState.new(target)
	var actor_inventory := InventoryState.new(actor_owner)
	var target_inventory := InventoryState.new(target_owner)
	var actor_equipment := EquipmentState.new(actor_owner)
	var target_equipment := EquipmentState.new(target_owner)
	var state := ItemSimulationState.new(board, [actor_owner, target_owner], [actor_inventory, target_inventory], [actor_equipment, target_equipment])
	actor.enable_action_resources()
	actor.try_refill_turn_resources()
	var definition := AttackDefinition.new()
	definition.id = &"p06_flat"
	definition.profile = &"flat_melee_v1"
	var rules := AttackRules.new([actor.id], [{"actor_unit_id": actor.id, "target_unit_id": target.id}], [definition])
	var context := ActionContext.new(state, P04TestRng.new(), ActionEventSink.new(), [], null, rules)
	return {"board": board, "actor": actor, "target": target, "state": state, "actor_owner": actor_owner, "actor_inventory": actor_inventory, "actor_equipment": actor_equipment, "owner": target_owner, "inventory": target_inventory, "target_equipment": target_equipment, "definition": definition, "rules": rules, "context": context}

func _p06_attack(fixture: Dictionary) -> AttackCommand:
	var actor: UnitState = fixture["actor"]
	var target: UnitState = fixture["target"]
	return AttackCommand.new(actor.id, target.id, actor.cell, target.cell, fixture["definition"].id, fixture["context"].get_revision())

func _test_p06_attack_happy_path() -> void:
	var fixture := _p06_attack_fixture()
	var actor: UnitState = fixture["actor"]
	var target: UnitState = fixture["target"]
	var board_version_before: int = (fixture["board"] as BattleBoard).board_version
	var receipt: ActionReceipt = ActionQueue.new().submit(_p06_attack(fixture), fixture["context"] as ActionContext)
	var events: Array[Dictionary] = receipt.get_events()
	_check(receipt.status == &"APPLIED" and events.size() == 2 and events[0]["kind"] == &"attacked" and events[1]["kind"] == &"damaged" and target.vitals.get_hp() == 6.0, "P06 A04/A07 attack applies STR + weapon - armor once")
	_check(actor.action_resources.get_main_left() == 1 and actor.has_attacked and actor.move_points_left == 3.0 and actor.action_resources.get_bonus_left() == 1 and fixture["board"].board_version == board_version_before, "P06 A05 root spends exactly one main only")
	_check(events[0].keys().size() == 13 and events[0]["main_before"] == 2 and events[0]["main_after"] == 1 and events[1]["source"]["kind"] == &"attack" and events[1]["source"]["instigator_unit_id"] == actor.id, "P06 A09 attacked schema and attack source")
	var second: ActionReceipt = ActionQueue.new().submit(_p06_attack(fixture), fixture["context"] as ActionContext)
	_check(second.status == &"APPLIED" and actor.action_resources.get_main_left() == 0 and target.vitals.get_hp() == 2.0, "P06 A05 second main ignores legacy has_attacked")
	var replacement_context: ActionContext = ActionContext.new(fixture["state"] as ItemSimulationState, P04TestRng.new(), ActionEventSink.new(), [], null, fixture["rules"] as AttackRules)
	_check(actor.action_resources.get_main_left() == 0 and not actor.can_attack() and replacement_context.get_attack_rules().allows(actor.id, target.id), "P06 A05 new context never refills an existing ledger")
	var legacy := _p06_unit()
	legacy.has_attacked = true
	_check(legacy.action_resources == null and not legacy.can_attack(), "P06 A05 null ledger keeps legacy has_attacked behavior")

func _test_p06_attack_rules_and_reach() -> void:
	var fixture := _p06_attack_fixture()
	var context: ActionContext = fixture["context"]
	var copied: AttackRules = context.get_attack_rules()
	fixture["rules"]._actors.clear()
	_check(copied != null and copied.allows(fixture["actor"].id, fixture["target"].id) and context.get_attack_rules().allows(fixture["actor"].id, fixture["target"].id), "P06 A01 context owns independent copied attack rules")
	var exposed: AttackDefinition = copied.get_definition((fixture["definition"] as AttackDefinition).id)
	exposed.id = &"caller_mutation"
	_check(copied.get_definition(fixture["definition"].id) != null and context.get_attack_rules().get_definition(fixture["definition"].id) != null, "P06 A01 definition getters return independent Resource copies")
	var duplicate_pair: AttackRules = AttackRules.new([(fixture["actor"] as UnitState).id], [{"actor_unit_id": (fixture["actor"] as UnitState).id, "target_unit_id": (fixture["target"] as UnitState).id}, {"actor_unit_id": (fixture["actor"] as UnitState).id, "target_unit_id": (fixture["target"] as UnitState).id}], [fixture["definition"] as AttackDefinition])
	var duplicate_actor: AttackRules = AttackRules.new([(fixture["actor"] as UnitState).id, (fixture["actor"] as UnitState).id], [], [fixture["definition"] as AttackDefinition])
	_check(duplicate_pair.validate() == &"attack/invalid_rules" and duplicate_actor.validate() == &"attack/invalid_rules" and AttackRules.new([], [], []).validate() == &"", "P06 A01 duplicate rules reject and empty rules remain valid")
	var board: BattleBoard = fixture["board"]
	var actor: UnitState = fixture["actor"]
	var target: UnitState = fixture["target"]
	var compass := BattleBoard.new(3, 3)
	var compass_actor := _p06_unit()
	compass_actor.cell = Vector2i(1, 1)
	compass_actor.height = 99
	var all_adjacent := true
	for cell: Vector2i in [Vector2i(1, 0), Vector2i(2, 1), Vector2i(1, 2), Vector2i(0, 1)]:
		var compass_target := _p06_unit()
		compass_target.cell = cell
		compass_target.height = -99
		all_adjacent = all_adjacent and AttackReachCheck.inspect(compass, compass_actor, compass_target, 1.0) == &""
	_check(all_adjacent, "P06 A03 all four orthogonal directions use board cells, not Unit height")
	for range_value: float in [0.0, NAN, INF, 1.5]:
		_check(AttackReachCheck.inspect(board, actor, target, range_value) == &"attack/invalid_range", "P06 A03 invalid range %s" % range_value)
	_check(AttackReachCheck.inspect(board, actor, target, 2.0) == &"attack/reach_unsupported", "P06 A03 range two unsupported")
	target.cell = Vector2i(2, 0)
	_check(AttackReachCheck.inspect(board, actor, target, 1.0) == &"attack/not_adjacent", "P06 A03 nonadjacent refused")
	target.cell = Vector2i(1, 0)
	board.set_height(target.cell, 1)
	_check(AttackReachCheck.inspect(board, actor, target, 1.0) == &"attack/height_unsupported", "P06 A03 board height, not Unit height")
	board.set_height(actor.cell, 2)
	_check(AttackReachCheck.inspect(board, actor, target, 1.0) == &"attack/height_unsupported", "P06 A03 height mismatch rejects in reverse direction")
	target.cell = Vector2i(1, 1)
	_check(AttackReachCheck.inspect(compass, actor, target, 1.0) == &"attack/not_adjacent", "P06 A03 diagonal rejects")
	actor.cell = Vector2i(-1, 0)
	_check(AttackReachCheck.inspect(board, actor, target, 1.0) == &"attack/out_of_bounds", "P06 A03 out-of-bounds is explicit reach reason")

func _test_p06_attack_admission() -> void:
	var fixture := _p06_attack_fixture(1.0)
	var command := _p06_attack(fixture)
	var actor: UnitState = fixture["actor"]
	var target: UnitState = fixture["target"]
	var before := [actor.action_resources.get_main_left(), target.vitals.get_hp(), fixture["context"].get_revision()]
	for mutation: String in ["self", "definition", "revision", "rules", "ledger", "range"]:
		var local := _p06_attack_fixture(1.0)
		var attack := _p06_attack(local)
		if mutation == "self": attack = AttackCommand.new(local["actor"].id, local["actor"].id, local["actor"].cell, local["actor"].cell, local["definition"].id, 0)
		elif mutation == "definition": attack = AttackCommand.new(local["actor"].id, local["target"].id, local["actor"].cell, local["target"].cell, &"missing", 0)
		elif mutation == "revision": attack = AttackCommand.new(local["actor"].id, local["target"].id, local["actor"].cell, local["target"].cell, local["definition"].id, 1)
		elif mutation == "rules": local["context"]._attack_rules = null
		elif mutation == "ledger": local["actor"].action_resources = null
		else: local["actor"].stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 2.0)
		var rejected := ActionQueue.new().submit(attack, local["context"])
		_check(rejected.status == &"REJECTED" and rejected.root_id == 0 and rejected.get_events().is_empty(), "P06 A02 admission refuses " + mutation)
	_check(ActionQueue.new().submit(AttackHitCommand.new(), fixture["context"]).reason == &"attack/internal_hit" and before == [actor.action_resources.get_main_left(), target.vitals.get_hp(), fixture["context"].get_revision()], "P06 A11 external Hit is rejected before mutation")

func _test_p06_attack_formula_and_items() -> void:
	for values: Array in [[3.0, 2.0, 99.0, 1.0], [-3.0, 0.0, 0.0, 1.0], [3.5, 2.0, 1.0, 4.5], [3.0, 2.0, -2.0, 7.0]]:
		var fixture := _p06_attack_fixture(1.0)
		fixture["actor"].stats.set_base_value(StatTypes.StatType.STRENGTH, values[0])
		fixture["actor"].stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, values[1])
		fixture["target"].stats.set_base_value(StatTypes.StatType.ARMOR, values[2])
		var receipt: ActionReceipt = ActionQueue.new().submit(_p06_attack(fixture), fixture["context"] as ActionContext)
		var events: Array[Dictionary] = receipt.get_events()
		_check(receipt.status == &"APPLIED" and events[1]["amount"] == values[3] and fixture["target"].vitals.get_balance() == 0.0, "P06 A04 exact signed formula %s" % str(values))
	var overflow := _p06_attack_fixture(1.0)
	overflow["actor"].stats.set_base_value(StatTypes.StatType.STRENGTH, 1e308)
	overflow["actor"].stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 1e308)
	_p06_assert_attack_rejected(overflow, _p06_attack(overflow), &"attack/nonfinite_damage", "finite sum overflow")
	var healing := _p06_attack_fixture(1.0)
	healing["target"].stats.set_base_value(StatTypes.StatType.ARMOR, 99.0)
	var heal_definition := ItemDef.new()
	heal_definition.id = &"p06_attack_heal"
	var heal_effect := HealOnDamageEffect.new()
	heal_effect.heal_amount = 1.0
	heal_definition.effects = [heal_effect]
	var heal_item: ItemInstance = healing["owner"].create_item(heal_definition)
	healing["inventory"].add_item(heal_item)
	var healed: ActionReceipt = ActionQueue.new().submit(_p06_attack(healing), healing["context"] as ActionContext)
	var kinds: Array[StringName] = []
	for event in healed.get_events(): kinds.append(event["kind"])
	_check(healed.status == &"APPLIED" and kinds == [&"attacked", &"damaged", &"healed"] and healing["target"].vitals.get_hp() == 10.0, "P06 A07 real HealOnDamage follows minimum hit")
	var lethal := _p06_attack_fixture(1.0)
	lethal["target"].vitals.set_hp(4.0)
	var lethal_item: ItemInstance = lethal["owner"].create_item(heal_definition)
	lethal["inventory"].add_item(lethal_item)
	var killed: ActionReceipt = ActionQueue.new().submit(_p06_attack(lethal), lethal["context"] as ActionContext)
	var lethal_kinds: Array[StringName] = []
	for event in killed.get_events(): lethal_kinds.append(event["kind"])
	_check(killed.status == &"APPLIED" and lethal_kinds == [&"attacked", &"damaged", &"died"] and not lethal["target"].is_alive() and lethal["board"].occupant_at(lethal["target"].cell) == null, "P06 A07 lethal attack does not heal and clears occupancy")
	var overkill := _p06_attack_fixture(1.0)
	overkill["target"].vitals.set_hp(2.0)
	var overkill_receipt: ActionReceipt = ActionQueue.new().submit(_p06_attack(overkill), overkill["context"] as ActionContext)
	_check(overkill_receipt.status == &"APPLIED" and overkill_receipt.get_events()[1]["amount"] == 2.0 and overkill_receipt.get_events()[1]["hp_before"] == 2.0, "P06 A07 damaged event reports actual HP loss, not requested overkill")

class P06AttackHitHook extends Command:
	var inner: AttackCommand
	var mutation: StringName
	func _init(value: AttackCommand, p_mutation: StringName = &"amount") -> void:
		inner = value
		mutation = p_mutation
	func get_kind() -> StringName: return &"attack"
	func copy_for_queue() -> Command: return P06AttackHitHook.new(inner.copy_for_queue() as AttackCommand, mutation)
	func validate(context: ActionContext) -> StringName: return inner.validate(context)
	func execute(context: ActionContext) -> CommandStepResult:
		var result: CommandStepResult = inner.execute(context)
		if result.status == &"APPLIED" and not result.mandatory.is_empty():
			var hit: AttackHitCommand = result.mandatory[0] as AttackHitCommand
			if mutation == &"amount": hit.request.amount += 1.0
			elif mutation == &"target": hit.request.target_unit_id = hit.request.source.instigator_unit_id
			elif mutation == &"damage_type": hit.request.damage_type = &"test"
			elif mutation == &"armor_mode": hit.request.armor_mode = &"flat"
			elif mutation == &"kind": hit.request.source.kind = &"test"
			elif mutation == &"source_id": hit.request.source.source_instance_id = 1
			elif mutation == &"origin": hit.request.source.origin_cell += Vector2i.RIGHT
			elif mutation == &"instigator": hit.request.source.instigator_unit_id = 0
			elif mutation == &"credit": hit.request.source.credit_unit_id = 0
			elif mutation == &"request_null": hit.request = null
			elif mutation == &"source_null": hit.request.source = null
		return result

func _test_p06_attack_hit_seal() -> void:
	for mutation: StringName in [&"amount", &"target", &"damage_type", &"armor_mode", &"kind", &"source_id", &"origin", &"instigator", &"credit", &"request_null", &"source_null"]:
		var fixture := _p06_attack_fixture(1.0)
		var before_hp: float = fixture["target"].vitals.get_hp()
		var result: ActionReceipt = ActionQueue.new().submit(P06AttackHitHook.new(_p06_attack(fixture), mutation), fixture["context"] as ActionContext)
		_check(result.status == &"FAULTED" and result.reason == &"attack/invalid_hit" and fixture["actor"].action_resources.get_main_left() == 0 and fixture["target"].vitals.get_hp() == before_hp and result.get_events().size() == 1 and result.get_events()[0]["kind"] == &"attacked", "P06 A11 seal survives copied Hit corruption " + mutation)

func _test_p06_attack_move_and_limits() -> void:
	var fixture := _p06_attack_fixture(1.0)
	var actor: UnitState = fixture["actor"]
	var target: UnitState = fixture["target"]
	fixture["board"].move_unit(target, Vector2i(2, 0))
	fixture["context"] = ActionContext.new(fixture["state"], P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([actor.id], 0), fixture["rules"])
	var move_one := MoveCommand.new(actor.id, [Vector2i.ZERO, Vector2i(1, 0)], fixture["context"].get_revision())
	var moved: ActionReceipt = ActionQueue.new().submit(move_one, fixture["context"] as ActionContext)
	var attacked: ActionReceipt = ActionQueue.new().submit(_p06_attack(fixture), fixture["context"] as ActionContext)
	var move_two := MoveCommand.new(actor.id, [Vector2i(1, 0), Vector2i.ZERO], fixture["context"].get_revision())
	var moved_back: ActionReceipt = ActionQueue.new().submit(move_two, fixture["context"] as ActionContext)
	_check(moved.status == &"APPLIED" and attacked.status == &"APPLIED" and moved_back.status == &"APPLIED" and actor.cell == Vector2i.ZERO and actor.move_points_left == 1.0 and target.vitals.get_hp() == 6.0, "P06 A08 Move-Attack-Move keeps independent move budget and rules")
	var command_limit := _p06_attack_fixture(1.0)
	var target_hp: float = command_limit["target"].vitals.get_hp()
	var limited: ActionReceipt = ActionQueue.new(1).submit(_p06_attack(command_limit), command_limit["context"] as ActionContext)
	_check(limited.status == &"FAULTED" and limited.reason == &"command_limit" and limited.get_events().size() == 1 and limited.get_events()[0]["kind"] == &"attacked" and command_limit["actor"].action_resources.get_main_left() == 0 and command_limit["target"].vitals.get_hp() == target_hp, "P06 A13 command limit preserves paid attacked prefix before Hit")
	var alive_zero := _p06_attack_fixture(1.0)
	alive_zero["target"].vitals.set_hp(0.0)
	var zero_receipt: ActionReceipt = ActionQueue.new().submit(_p06_attack(alive_zero), alive_zero["context"] as ActionContext)
	_check(zero_receipt.status == &"APPLIED" and not alive_zero["target"].is_alive() and zero_receipt.get_events().size() == 2 and zero_receipt.get_events()[1]["kind"] == &"died" and zero_receipt.get_events()[1]["amount"] == 0.0, "P06 A07 alive-at-zero attack emits only attacked and died")

func _test_p06_attack_event_schema() -> void:
	# Validator теперь получает definition context; прежние schema assertions остаются теми же.
	var schema_definition := AttackDefinition.new()
	schema_definition.id = &"flat"
	schema_definition.profile = AttackRules.PROFILE
	var schema_context := ActionContext.new(null, null, null, [], null, AttackRules.new([], [], [schema_definition]))
	var valid := {"kind": &"attacked", "actor_unit_id": 1, "target_unit_id": 2, "attack_definition_id": &"flat", "actor_cell": Vector2i.ZERO, "target_cell": Vector2i(1, 0), "main_cost": 1, "main_before": 1, "main_after": 0}
	_check(ActionQueue._valid_draft(valid, schema_context), "P06 A12 accepts exact attacked value schema")
	for key: String in valid.keys():
		var missing: Dictionary = valid.duplicate(true)
		missing.erase(key)
		var wrong_type: Dictionary = valid.duplicate(true)
		wrong_type[key] = "wrong"
		_check(not ActionQueue._valid_draft(missing, schema_context) and not ActionQueue._valid_draft(wrong_type, schema_context), "P06 A12 attacked key/type rejects " + key)
	for mutation: String in ["extra", "damage", "diagonal", "before", "type"]:
		var malformed := valid.duplicate(true)
		if mutation == "extra": malformed["hit"] = true
		elif mutation == "damage": malformed["main_cost"] = 2
		elif mutation == "diagonal": malformed["target_cell"] = Vector2i(1, 1)
		elif mutation == "before": malformed["main_before"] = 0
		else: malformed["attack_definition_id"] = "flat"
		_check(not ActionQueue._valid_draft(malformed, schema_context), "P06 A12 attacked schema rejects " + mutation)
	for range_case: Dictionary in [{"main_before": 4097, "main_after": 4096}, {"main_before": 1, "main_after": 1}, {"actor_unit_id": 0}, {"target_unit_id": 1}]:
		var malformed_range: Dictionary = valid.duplicate(true)
		for key: String in range_case: malformed_range[key] = range_case[key]
		_check(not ActionQueue._valid_draft(malformed_range, schema_context), "P06 A12 attacked arithmetic/range rejects")
	var fixture := _p06_attack_fixture(1.0)
	var sink := P04HookSink.new()
	fixture["context"] = ActionContext.new(fixture["state"] as ItemSimulationState, P04TestRng.new(), sink, [], null, fixture["rules"] as AttackRules)
	var stat_signals: Array[int] = [0]
	(fixture["actor"] as UnitState).stats.stat_changed.connect(func(_type: StatTypes.StatType, _before: float, _after: float) -> void: stat_signals[0] += 1)
	var receipt: ActionReceipt = ActionQueue.new().submit(_p06_attack(fixture), fixture["context"] as ActionContext)
	var receipt_copy: Array[Dictionary] = receipt.get_events()
	receipt_copy[0]["main_after"] = 99
	sink.events[0]["main_after"] = 98
	_check(receipt.get_events()[0]["main_after"] == 0 and stat_signals[0] == 0 and sink.events[0]["main_after"] == 98, "P06 A12 attacked receipt/sink DTO copies and no stat signal")

func _p06_assert_attack_rejected(fixture: Dictionary, command: AttackCommand, reason: StringName, label: String) -> void:
	var context: ActionContext = fixture["context"]
	var state: ItemSimulationState = fixture["state"]
	var actor: UnitState = fixture["actor"]
	var board: BattleBoard = fixture["board"]
	var snapshot: ItemSnapshotResult = ItemSimulationSnapshot.capture(state, [])
	var before_bytes: PackedByteArray = snapshot.snapshot.canonical_bytes() if snapshot.code == ItemSnapshotResult.Code.OK else PackedByteArray()
	var stat: Stat = actor.stats._stats[StatTypes.StatType.MAIN_ACTIONS_MAX]
	var cache_before: Array = [stat._cache_dirty, stat._cached_value, stat._next_modifier_slot, stat._modifier_slots.duplicate()]
	var rng_before: Dictionary = context.get_rng().to_dict()
	var counters: Array = [context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision(), board.board_version]
	var direct: StringName = command.validate(context)
	var receipt: ActionReceipt = ActionQueue.new().submit(command, context)
	var after: ItemSnapshotResult = ItemSimulationSnapshot.capture(state, [])
	_check(direct == reason and receipt.status == &"REJECTED" and receipt.reason == reason and receipt.root_id == 0 and receipt.get_steps().is_empty() and receipt.get_events().is_empty() and after.code == ItemSnapshotResult.Code.OK and after.snapshot.canonical_bytes() == before_bytes and [stat._cache_dirty, stat._cached_value, stat._next_modifier_slot, stat._modifier_slots] == cache_before and context.get_rng().to_dict() == rng_before and [context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision(), board.board_version] == counters, "P06 A02 rejection is pure " + label)

func _p06_assert_attack_validate_only(command: AttackCommand, context: ActionContext, reason: StringName, label: String) -> void:
	var before: Array = [context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision()]
	_check(command.validate(context) == reason and before == [context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision()], "P06 A02 direct malformed runtime stays pure " + label)

func _test_p06_attack_rejection_matrix() -> void:
	var bad_actor := _p06_attack_fixture()
	_p06_assert_attack_rejected(bad_actor, AttackCommand.new(0, bad_actor["target"].id, Vector2i.ZERO, bad_actor["target"].cell, bad_actor["definition"].id, 0), &"attack/invalid_actor_id", "actor id")
	var bad_target := _p06_attack_fixture()
	_p06_assert_attack_rejected(bad_target, AttackCommand.new(bad_target["actor"].id, 0, bad_target["actor"].cell, Vector2i.ZERO, bad_target["definition"].id, 0), &"attack/invalid_target_id", "target id")
	var self_target := _p06_attack_fixture()
	_p06_assert_attack_rejected(self_target, AttackCommand.new(self_target["actor"].id, self_target["actor"].id, self_target["actor"].cell, self_target["actor"].cell, self_target["definition"].id, 0), &"attack/self_target", "self target")
	var invalid_definition := _p06_attack_fixture()
	_p06_assert_attack_rejected(invalid_definition, AttackCommand.new(invalid_definition["actor"].id, invalid_definition["target"].id, invalid_definition["actor"].cell, invalid_definition["target"].cell, &"", 0), &"attack/invalid_definition_id", "definition id")
	var invalid_revision := _p06_attack_fixture()
	_p06_assert_attack_rejected(invalid_revision, AttackCommand.new(invalid_revision["actor"].id, invalid_revision["target"].id, invalid_revision["actor"].cell, invalid_revision["target"].cell, invalid_revision["definition"].id, -1), &"attack/invalid_revision", "revision payload")
	var stale_revision := _p06_attack_fixture()
	_p06_assert_attack_rejected(stale_revision, AttackCommand.new(stale_revision["actor"].id, stale_revision["target"].id, stale_revision["actor"].cell, stale_revision["target"].cell, stale_revision["definition"].id, 1), &"attack/stale_revision", "revision state")
	var no_rules := _p06_attack_fixture(); no_rules["context"]._attack_rules = null
	_p06_assert_attack_rejected(no_rules, _p06_attack(no_rules), &"attack/rules_missing", "rules missing")
	var unknown_definition := _p06_attack_fixture()
	_p06_assert_attack_rejected(unknown_definition, AttackCommand.new(unknown_definition["actor"].id, unknown_definition["target"].id, unknown_definition["actor"].cell, unknown_definition["target"].cell, &"unknown", 0), &"attack/unknown_definition", "definition registry")
	var missing := _p06_attack_fixture(); missing["board"].remove_unit(missing["actor"]); missing["state"] = ItemSimulationState.new(missing["board"], [missing["owner"]], [missing["inventory"]], [missing["target_equipment"]]); missing["context"] = ActionContext.new(missing["state"], P04TestRng.new(), ActionEventSink.new(), [], null, missing["rules"])
	_p06_assert_attack_rejected(missing, _p06_attack(missing), &"attack/missing_actor", "missing actor")
	var missing_target := _p06_attack_fixture(); missing_target["board"].remove_unit(missing_target["target"]); missing_target["state"] = ItemSimulationState.new(missing_target["board"], [missing_target["actor_owner"]], [missing_target["actor_inventory"]], [missing_target["actor_equipment"]]); missing_target["context"] = ActionContext.new(missing_target["state"], P04TestRng.new(), ActionEventSink.new(), [], null, missing_target["rules"])
	_p06_assert_attack_rejected(missing_target, _p06_attack(missing_target), &"attack/missing_target", "missing target")
	var dead_actor := _p06_attack_fixture(); dead_actor["actor"].vitals.apply_damage(99.0)
	_p06_assert_attack_rejected(dead_actor, _p06_attack(dead_actor), &"attack/dead_actor", "dead actor")
	var dead := _p06_attack_fixture(); dead["target"].vitals.apply_damage(99.0)
	_p06_assert_attack_rejected(dead, _p06_attack(dead), &"attack/dead_target", "dead target")
	var actor_cell := _p06_attack_fixture()
	_p06_assert_attack_rejected(actor_cell, AttackCommand.new(actor_cell["actor"].id, actor_cell["target"].id, Vector2i(2, 0), actor_cell["target"].cell, actor_cell["definition"].id, 0), &"attack/actor_cell_mismatch", "actor cell")
	var target_cell := _p06_attack_fixture()
	_p06_assert_attack_rejected(target_cell, AttackCommand.new(target_cell["actor"].id, target_cell["target"].id, target_cell["actor"].cell, Vector2i(2, 0), target_cell["definition"].id, 0), &"attack/target_cell_mismatch", "target cell")
	var unplaced := _p06_attack_fixture(); unplaced["board"].clear_occupancy(unplaced["target"])
	_p06_assert_attack_rejected(unplaced, _p06_attack(unplaced), &"attack/target_not_placed", "target occupancy")
	var actor_unplaced := _p06_attack_fixture(); actor_unplaced["board"].clear_occupancy(actor_unplaced["actor"])
	_p06_assert_attack_rejected(actor_unplaced, _p06_attack(actor_unplaced), &"attack/actor_not_placed", "actor occupancy")
	var denied := _p06_attack_fixture(); denied["context"]._attack_rules = AttackRules.new([], [], [denied["definition"]])
	_p06_assert_attack_rejected(denied, _p06_attack(denied), &"attack/not_admitted", "pair")
	var exhausted := _p06_attack_fixture(1.0); exhausted["actor"].action_resources.try_spend_main(1)
	_p06_assert_attack_rejected(exhausted, _p06_attack(exhausted), &"attack/insufficient_main", "main")
	var resources_missing := _p06_attack_fixture(); resources_missing["actor"].action_resources = null
	_p06_assert_attack_rejected(resources_missing, _p06_attack(resources_missing), &"attack/resources_missing", "ledger missing")
	var missing_stat := _p06_attack_fixture(); missing_stat["actor"].stats._stats.erase(StatTypes.StatType.ATTACK_RANGE)
	_p06_assert_attack_rejected(missing_stat, _p06_attack(missing_stat), &"attack/missing_stat", "attack range declaration")
	var invalid_stat := _p06_attack_fixture(); invalid_stat["actor"].stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 1.5)
	_p06_assert_attack_rejected(invalid_stat, _p06_attack(invalid_stat), &"attack/invalid_stat", "fractional maximum")
	for nonfinite: float in [NAN, INF]:
		var nonfinite_fixture := _p06_attack_fixture()
		var nonfinite_actor: UnitState = nonfinite_fixture["actor"]
		nonfinite_actor.stats.set_base_value(StatTypes.StatType.STRENGTH, nonfinite)
		var counters: Array = [(nonfinite_fixture["context"] as ActionContext)._next_root_id, (nonfinite_fixture["context"] as ActionContext)._next_command_seq, (nonfinite_fixture["context"] as ActionContext)._next_event_seq]
		var nonfinite_receipt: ActionReceipt = ActionQueue.new().submit(_p06_attack(nonfinite_fixture), nonfinite_fixture["context"] as ActionContext)
		_check(_p06_attack(nonfinite_fixture).validate(nonfinite_fixture["context"] as ActionContext) != &"" and nonfinite_receipt.status == &"REJECTED" and nonfinite_receipt.root_id == 0 and counters == [(nonfinite_fixture["context"] as ActionContext)._next_root_id, (nonfinite_fixture["context"] as ActionContext)._next_command_seq, (nonfinite_fixture["context"] as ActionContext)._next_event_seq] and nonfinite_actor.action_resources.get_main_left() == 2, "P06 A04 nonfinite preflight rejects without payment %s" % nonfinite)
	var invalid_rules := _p06_attack_fixture(); invalid_rules["context"]._attack_rules = AttackRules.new([invalid_rules["actor"].id, invalid_rules["actor"].id], [], [invalid_rules["definition"]])
	_p06_assert_attack_rejected(invalid_rules, _p06_attack(invalid_rules), &"attack/invalid_rules", "invalid rules")
	var corrupt_registry := _p06_attack_fixture()
	var registry_key: int = (corrupt_registry["actor"] as UnitState).id
	var target_id: int = (corrupt_registry["target"] as UnitState).id
	(corrupt_registry["board"] as BattleBoard)._units[registry_key].id = registry_key + 100
	var corrupt_command: AttackCommand = AttackCommand.new(registry_key, target_id, (corrupt_registry["actor"] as UnitState).cell, (corrupt_registry["target"] as UnitState).cell, (corrupt_registry["definition"] as AttackDefinition).id, 0)
	_p06_assert_attack_validate_only(corrupt_command, corrupt_registry["context"] as ActionContext, &"attack/invalid_runtime", "registry key and actor id")
	var foreign_resources := _p06_attack_fixture()
	foreign_resources["actor"].action_resources = ActionResources.new(foreign_resources["actor"].id + 1, 1, 0)
	_p06_assert_attack_validate_only(_p06_attack(foreign_resources), foreign_resources["context"] as ActionContext, &"attack/invalid_resources", "foreign ledger")
	var oversized: Array[int] = []
	for id in AttackRules.MAX_ACTORS + 1: oversized.append(id + 1)
	var malformed_pair := {"actor_unit_id": 1, "target_unit_id": 2, "nested": {"large": PackedByteArray([1, 2, 3])}}
	var bad_rules := AttackRules.new(oversized, [], [])
	var pair_rules := AttackRules.new([1], [malformed_pair], [])
	var invalid_definition_resource := AttackDefinition.new(); invalid_definition_resource.id = StringName("x".repeat(129)); invalid_definition_resource.profile = &"flat_melee_v1"
	var definition_rules := AttackRules.new([1], [], [invalid_definition_resource])
	var unicode_definition := AttackDefinition.new(); unicode_definition.id = StringName("я".repeat(65)); unicode_definition.profile = &"flat_melee_v1"
	var unicode_rules := AttackRules.new([1], [], [unicode_definition])
	var derived_definition := P06AttackDefinitionSubclass.new(); derived_definition.id = &"derived"; derived_definition.profile = &"flat_melee_v1"
	var derived_rules := AttackRules.new([1], [], [derived_definition])
	var too_many_pairs: Array[Dictionary] = []
	for pair_index in AttackRules.MAX_PAIRS + 1: too_many_pairs.append({"actor_unit_id": 1, "target_unit_id": pair_index + 2})
	var too_many_definitions: Array[AttackDefinition] = []
	for definition_index in AttackRules.MAX_DEFINITIONS + 1:
		var definition_value: AttackDefinition = AttackDefinition.new(); definition_value.id = StringName("p06_%d" % definition_index); definition_value.profile = &"flat_melee_v1"; too_many_definitions.append(definition_value)
	var pair_limit_rules: AttackRules = AttackRules.new([1], too_many_pairs, [])
	var definition_limit_rules: AttackRules = AttackRules.new([1], [], too_many_definitions)
	var mutable_pair := {"actor_unit_id": 1, "target_unit_id": 2}
	var copied_pair_rules: AttackRules = AttackRules.new([1], [mutable_pair], [])
	mutable_pair["target_unit_id"] = 3
	_check(bad_rules.validate() == &"attack/invalid_rules" and pair_rules.validate() == &"attack/invalid_rules" and definition_rules.validate() == &"attack/invalid_rules" and unicode_rules.validate() == &"attack/invalid_rules" and derived_rules.validate() == &"attack/invalid_rules" and pair_limit_rules.validate() == &"attack/invalid_rules" and definition_limit_rules.validate() == &"attack/invalid_rules" and copied_pair_rules.allows(1, 2) and not copied_pair_rules.allows(1, 3) and bad_rules._actors.is_empty() and pair_rules._pairs.is_empty() and definition_rules._definitions.is_empty(), "P06 A01 bounded invalid lists and caller pair copy")

class P06AttackDefinitionSubclass extends AttackDefinition:
	pass

class P06AttackBindingHook extends Command:
	var inner: AttackCommand
	var mode: StringName
	func _init(value: AttackCommand, p_mode: StringName) -> void:
		inner = value
		mode = p_mode
	func get_kind() -> StringName: return inner.get_kind()
	func copy_for_queue() -> Command: return P06AttackBindingHook.new(inner.copy_for_queue() as AttackCommand, mode)
	func validate(context: ActionContext) -> StringName: return inner.validate(context)
	func execute(context: ActionContext) -> CommandStepResult:
		var result: CommandStepResult = inner.execute(context)
		if result.status != &"APPLIED": return result
		var board: BattleBoard = context.get_state().get_board()
		var actor: UnitState = board.get_unit_by_id(inner.get_actor_unit_id())
		var target: UnitState = board.get_unit_by_id(inner.get_target_unit_id())
		if mode == &"target_dead": target.vitals.apply_damage(99.0)
		elif mode == &"actor_dead": actor.vitals.apply_damage(99.0)
		elif mode == &"target_displaced": board.move_unit(target, Vector2i(2, 0))
		elif mode == &"actor_displaced": board.move_unit(actor, Vector2i(2, 0))
		elif mode == &"target_removed": board.remove_unit(target)
		elif mode == &"actor_removed": board.remove_unit(actor)
		elif mode == &"target_replaced":
			var replacement_target := UnitState.from_snapshot_dict(target.to_snapshot_dict())
			board.remove_unit(target)
			board.add_unit(replacement_target)
		elif mode == &"actor_replaced":
			var replacement_actor := UnitState.from_snapshot_dict(actor.to_snapshot_dict())
			board.remove_unit(actor)
			board.add_unit(replacement_actor)
		elif mode == &"ledger_replaced": actor.action_resources = ActionResources.new(actor.id, 0, 0)
		elif mode == &"main_changed": actor.action_resources.try_spend_main(1)
		elif mode == &"sequence": context._next_command_seq = ActionContext.MAX_ID
		elif mode == &"event_sequence": context._next_event_seq = ActionContext.MAX_ID - 1
		elif mode == &"revision_sequence": context._revision = ActionContext.MAX_ID - 1
		return result

func _test_p06_attack_binding_matrix() -> void:
	for mode: StringName in [&"target_dead", &"actor_dead", &"target_displaced", &"actor_displaced", &"target_removed", &"actor_removed", &"target_replaced", &"actor_replaced", &"ledger_replaced"]:
		var fixture := _p06_attack_fixture(1.0)
		var before_hp: float = 0.0 if mode == &"target_dead" else fixture["target"].vitals.get_hp()
		var receipt: ActionReceipt = ActionQueue.new().submit(P06AttackBindingHook.new(_p06_attack(fixture), mode), fixture["context"] as ActionContext)
		_check(receipt.status == &"FAULTED" and receipt.reason == &"attack/invalid_hit" and fixture["target"].vitals.get_hp() == before_hp and fixture["actor"].action_resources.get_main_left() == 0 and receipt.get_events().size() == 1, "P06 A11 binding mutation faults before HP " + mode)
	var changed_main := _p06_attack_fixture(2.0)
	var main_receipt: ActionReceipt = ActionQueue.new().submit(P06AttackBindingHook.new(_p06_attack(changed_main), &"main_changed"), changed_main["context"] as ActionContext)
	_check(main_receipt.status == &"FAULTED" and main_receipt.reason == &"attack/invalid_hit" and changed_main["target"].vitals.get_hp() == 10.0, "P06 A11 changed ledger counter faults Hit")

func _test_p06_attack_queue_guards() -> void:
	var with_heal := _p06_attack_fixture(1.0)
	with_heal["target"].stats.set_base_value(StatTypes.StatType.ARMOR, 99.0)
	var definition := ItemDef.new(); definition.id = &"p06_guard_heal"; var effect := HealOnDamageEffect.new(); effect.heal_amount = 1.0; definition.effects = [effect]
	var heal_item: ItemInstance = with_heal["owner"].create_item(definition)
	with_heal["inventory"].add_item(heal_item)
	var command_two: ActionReceipt = ActionQueue.new(2).submit(_p06_attack(with_heal), with_heal["context"] as ActionContext)
	_check(command_two.status == &"FAULTED" and command_two.reason == &"command_limit" and command_two.get_events().size() == 2 and with_heal["target"].vitals.get_hp() == 9.0, "P06 A13 max_commands two faults before Heal")
	var depth := _p06_attack_fixture(1.0)
	depth["target"].stats.set_base_value(StatTypes.StatType.ARMOR, 99.0)
	var depth_item: ItemInstance = depth["owner"].create_item(definition); depth["inventory"].add_item(depth_item)
	var depth_receipt: ActionReceipt = ActionQueue.new(32, 512, 1).submit(_p06_attack(depth), depth["context"] as ActionContext)
	_check(depth_receipt.status == &"FAULTED" and depth_receipt.reason == &"depth_limit" and depth_receipt.get_events().size() == 2, "P06 A13 depth blocks item Heal after Hit")
	var event_limit := _p06_attack_fixture(1.0); event_limit["target"].vitals.set_hp(4.0)
	var event_receipt: ActionReceipt = ActionQueue.new(32, 2).submit(_p06_attack(event_limit), event_limit["context"] as ActionContext)
	_check(event_receipt.status == &"FAULTED" and event_receipt.reason == &"event_limit" and event_receipt.get_events().size() == 3 and not event_limit["target"].is_alive(), "P06 A13 lethal event limit keeps complete HP prefix")
	var root_sequence := _p06_attack_fixture(); root_sequence["context"]._next_root_id = ActionContext.MAX_ID
	_check(ActionQueue.new().submit(_p06_attack(root_sequence), root_sequence["context"]).reason == &"sequence_exhausted" and root_sequence["actor"].action_resources.get_main_left() == 2, "P06 A13 root sequence rejects before debit")
	for field: String in ["_next_command_seq", "_next_event_seq", "_revision"]:
		var exhausted_sequence := _p06_attack_fixture()
		exhausted_sequence["context"].set(field, ActionContext.MAX_ID if field != "_next_event_seq" else ActionContext.MAX_ID - 1)
		# Payload revision ограничен MAX-2 и проверяется раньше резервирования очереди.
		var expected_reason: StringName = &"attack/invalid_revision" if field == "_revision" else &"sequence_exhausted"
		_check(ActionQueue.new().submit(_p06_attack(exhausted_sequence), exhausted_sequence["context"]).reason == expected_reason and exhausted_sequence["actor"].action_resources.get_main_left() == 2, "P06 A13 root %s exhaustion before debit" % field)
	var child_sequence := _p06_attack_fixture(1.0)
	var child_receipt: ActionReceipt = ActionQueue.new().submit(P06AttackBindingHook.new(_p06_attack(child_sequence), &"sequence"), child_sequence["context"] as ActionContext)
	_check(child_receipt.status == &"FAULTED" and child_receipt.reason == &"sequence_exhausted" and child_receipt.get_events().size() == 1 and child_sequence["target"].vitals.get_hp() == 10.0, "P06 A13 sequence exhaustion after root keeps paid attack")
	for mode: StringName in [&"event_sequence", &"revision_sequence"]:
		var between := _p06_attack_fixture(1.0)
		var between_receipt: ActionReceipt = ActionQueue.new().submit(P06AttackBindingHook.new(_p06_attack(between), mode), between["context"] as ActionContext)
		_check(between_receipt.status == &"FAULTED" and between_receipt.reason == &"sequence_exhausted" and between_receipt.get_events().size() == 1 and between["target"].vitals.get_hp() == 10.0, "P06 A13 %s exhaustion between attack and Hit" % mode)
	var lethal_max := _p06_attack_fixture(1.0); lethal_max["target"].vitals.set_hp(4.0); lethal_max["board"].board_version = ActionContext.MAX_ID
	_check(ActionQueue.new().submit(_p06_attack(lethal_max), lethal_max["context"]).reason == &"attack/board_version_exhausted" and lethal_max["actor"].action_resources.get_main_left() == 1, "P06 A13 lethal MAX version rejects before debit")
	var lethal_edge := _p06_attack_fixture(1.0); lethal_edge["target"].vitals.set_hp(4.0); lethal_edge["board"].board_version = ActionContext.MAX_ID - 1
	var edge_receipt: ActionReceipt = ActionQueue.new().submit(_p06_attack(lethal_edge), lethal_edge["context"] as ActionContext)
	_check(edge_receipt.status == &"APPLIED" and lethal_edge["board"].board_version == ActionContext.MAX_ID, "P06 A13 lethal MAX-1 consumes one board version")
	var nonlethal_max := _p06_attack_fixture(1.0); nonlethal_max["board"].board_version = ActionContext.MAX_ID
	var nonlethal_receipt: ActionReceipt = ActionQueue.new().submit(_p06_attack(nonlethal_max), nonlethal_max["context"] as ActionContext)
	_check(nonlethal_receipt.status == &"APPLIED" and nonlethal_max["board"].board_version == ActionContext.MAX_ID and nonlethal_max["target"].vitals.get_hp() == 6.0, "P06 A13 nonlethal attack never reserves a board version")

func _test_p06_attack_reentrancy() -> void:
	var fixture := _p06_attack_fixture(1.0)
	fixture["target"].vitals.set_hp(4.0)
	var queue := ActionQueue.new()
	var other := ActionQueue.new()
	var nested: Array[ActionReceipt] = []
	var context: ActionContext = fixture["context"]
	var probe := func() -> void:
		nested.append(queue.submit(P04Work.new(&"p06_busy"), context))
		nested.append(other.submit(P04Work.new(&"p06_busy"), context))
	var hp_hook := func(_before: float, _after: float) -> void: probe.call()
	fixture["target"].vitals.hp_changed.connect(hp_hook)
	fixture["target"].vitals.died.connect(probe)
	fixture["board"].board_changed.connect(probe)
	var sink := P04HookSink.new()
	sink.hook = func(_event: Dictionary) -> void: probe.call()
	context._sink = sink
	var receipt: ActionReceipt = queue.submit(_p06_attack(fixture), context)
	# Callback держит context, поэтому тест снимает свои подписки и разрывает цикл владения.
	fixture["target"].vitals.hp_changed.disconnect(hp_hook)
	fixture["target"].vitals.died.disconnect(probe)
	fixture["board"].board_changed.disconnect(probe)
	sink.hook = Callable()
	var all_busy: bool = not nested.is_empty()
	for nested_receipt in nested: all_busy = all_busy and nested_receipt.reason == &"BUSY"
	_check(receipt.status == &"APPLIED" and nested.size() >= 8 and all_busy and fixture["actor"].action_resources.get_main_left() == 0, "P06 A12 HP, death, board and sink submissions are BUSY on both queues")

func _test_p06_attack_restored_isolation() -> void:
	var source := _p03b_fixture()
	var first_unit: UnitState = source.board.get_unit_by_id(101)
	first_unit.stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 1.0)
	first_unit.stats.set_base_value(StatTypes.StatType.BONUS_ACTIONS_MAX, 0.0)
	first_unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 2.0)
	first_unit.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 1.0)
	first_unit.stats.set_base_value(StatTypes.StatType.MOVE_RANGE, 3.0)
	first_unit.enable_action_resources(); first_unit.try_refill_turn_resources()
	var snapshot: ItemSnapshotResult = ItemSimulationSnapshot.capture(source.state, [])
	var first_result: ItemSnapshotResult = snapshot.snapshot.instantiate(_p03b_catalogue(source.definition))
	var second_result: ItemSnapshotResult = snapshot.snapshot.instantiate(_p03b_catalogue(source.definition))
	var states: Array[ItemSimulationState] = [first_result.state, second_result.state]
	var receipts: Array[ActionReceipt] = []
	var contexts: Array[ActionContext] = []
	var rngs: Array[P04TestRng] = []
	for state in states:
		var actor: UnitState = state.get_board().get_unit_by_id(101)
		var target: UnitState = state.get_board().get_unit_by_id(102)
		var attack_definition: AttackDefinition = AttackDefinition.new(); attack_definition.id = &"p06_restore"; attack_definition.profile = &"flat_melee_v1"
		var rules: AttackRules = AttackRules.new([actor.id], [{"actor_unit_id": actor.id, "target_unit_id": target.id}], [attack_definition])
		var rng: P04TestRng = P04TestRng.new()
		var context: ActionContext = ActionContext.new(state, rng, ActionEventSink.new(), [], null, rules)
		contexts.append(context)
		rngs.append(rng)
		receipts.append(ActionQueue.new().submit(AttackCommand.new(actor.id, target.id, actor.cell, target.cell, attack_definition.id, 0), context))
	var source_bytes: PackedByteArray = ItemSimulationSnapshot.capture(source.state, []).snapshot.canonical_bytes()
	_check(first_result.code == ItemSnapshotResult.Code.OK and second_result.code == ItemSnapshotResult.Code.OK and receipts.size() == 2 and receipts[0].status == &"APPLIED" and receipts[1].status == &"APPLIED" and not receipts[0].get_events().is_empty() and receipts[0].get_steps() == receipts[1].get_steps() and receipts[0].get_events() == receipts[1].get_events() and [contexts[0]._next_root_id, contexts[0]._next_command_seq, contexts[0]._next_event_seq, contexts[0].get_revision()] == [contexts[1]._next_root_id, contexts[1]._next_command_seq, contexts[1]._next_event_seq, contexts[1].get_revision()] and rngs[0].to_dict() == rngs[1].to_dict() and rngs[0].to_dict()["streams"][0]["cursor"] == 0 and ItemSimulationSnapshot.capture(states[0], []).snapshot.canonical_bytes() == ItemSimulationSnapshot.capture(states[1], []).snapshot.canonical_bytes() and source_bytes == snapshot.snapshot.canonical_bytes(), "P06 A14 two restored states attack identically without mutating source")

func _test_p06_a06_refill() -> void:
	var unit := _p06_unit()
	var main_stat: Stat = unit.stats._stats[StatTypes.StatType.MAIN_ACTIONS_MAX]
	main_stat.get_value()
	var cache_before := [main_stat._cache_dirty, main_stat._cached_value, main_stat._next_modifier_slot, main_stat._modifier_slots.duplicate()]
	_check(unit.enable_action_resources() == &"", "P06 A06 enable does not refill")
	_check(unit.action_resources.get_main_left() == 0 and unit.action_resources.get_bonus_left() == 0, "P06 A06 empty ledger after enable")
	_check(cache_before == [main_stat._cache_dirty, main_stat._cached_value, main_stat._next_modifier_slot, main_stat._modifier_slots], "P06 A06 enable reads copied stats")
	_check(unit.enable_action_resources() == &"resources/already_enabled", "P06 A06 repeat enable rejected")
	_check(unit.try_refill_turn_resources() == &"", "P06 A06 refill succeeds")
	_check(unit.action_resources.get_main_left() == 2 and unit.action_resources.get_bonus_left() == 1 and unit.move_points_left == 3.0, "P06 A06 refill replaces resources")
	unit.action_resources.try_spend_main(1)
	unit.stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 1.00000001)
	var before := unit.action_resources.to_snapshot_dict()
	var move_before := unit.move_points_left
	_check(unit.try_refill_turn_resources() == &"resources/invalid_maximum", "P06 A06 fractional maximum rejected")
	_check(unit.action_resources.to_snapshot_dict() == before and unit.move_points_left == move_before, "P06 A06 rejected refill is atomic")
	for maximum: float in [-1.0, 4097.0]:
		unit.stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, maximum)
		_check(unit.try_refill_turn_resources() == &"resources/invalid_maximum" and unit.action_resources.to_snapshot_dict() == before and unit.move_points_left == move_before, "P06 A06 maximum rejects atomically %s" % maximum)
	unit.stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 2.0)
	unit.stats.set_base_value(StatTypes.StatType.BONUS_ACTIONS_MAX, 1.5)
	_check(unit.try_refill_turn_resources() == &"resources/invalid_maximum" and unit.action_resources.to_snapshot_dict() == before and unit.move_points_left == move_before, "P06 A06 bonus maximum rejects atomically")
	unit.stats.set_base_value(StatTypes.StatType.BONUS_ACTIONS_MAX, 1.0)
	unit.vitals.apply_damage(999.0)
	_check(unit.try_refill_turn_resources() == &"resources/dead_unit" and unit.action_resources.to_snapshot_dict() == before and unit.move_points_left == move_before, "P06 A06 dead does not refill")
	var missing := _p06_unit()
	missing.stats._stats.erase(StatTypes.StatType.BONUS_ACTIONS_MAX)
	_check(missing.enable_action_resources() == &"resources/missing_stat" and missing.action_resources == null, "P06 A06 missing declaration rejects enable")
	var foreign := _p06_unit()
	_check(foreign.enable_action_resources() == &"" and foreign.try_refill_turn_resources() == &"", "P06 A06 foreign ledger fixture")
	foreign.action_resources = ActionResources.new(foreign.id + 1, 2, 1)
	var foreign_before := [foreign.move_points_left, foreign.has_attacked]
	_check(foreign.try_refill_turn_resources() == &"resources/owner_id" and not foreign.can_attack() and foreign_before == [foreign.move_points_left, foreign.has_attacked], "P06 A06 foreign ledger refuses atomically")
	foreign.action_resources = _P06ActionResources.new(foreign.id, 2, 1)
	_check(foreign.try_refill_turn_resources() == &"resources/invalid_runtime" and not foreign.can_attack() and foreign_before == [foreign.move_points_left, foreign.has_attacked], "P06 A06 ledger subclass is invalid runtime")
	var resources := ActionResources.new(1, 1, 0)
	_check(resources.try_spend_main(1) and not resources.try_spend_main(1) and not resources.try_spend_main(0) and resources.get_main_left() == 0, "P06 A06 ledger spends exactly once")

func _test_p06_a09_snapshot_versions() -> void:
	var legacy := _p06_unit()
	var v1 := legacy.to_snapshot_dict()
	_check(v1["schema_version"] == 1 and not v1.has("action_resources") and UnitState.validate_snapshot_dict(v1), "P06 A09 exact v1")
	var restored_v1 := UnitState.from_snapshot_dict(v1)
	_check(restored_v1 != null and restored_v1.action_resources == null, "P06 A09 v1 restores legacy")
	_check(legacy.enable_action_resources() == &"" and legacy.try_refill_turn_resources() == &"", "P06 A09 prepare v2")
	legacy.action_resources.try_spend_main(2)
	var v2 := legacy.to_snapshot_dict()
	var restored_v2 := UnitState.from_snapshot_dict(v2)
	_check(v2["schema_version"] == 2 and restored_v2 != null and restored_v2.action_resources.get_main_left() == 0, "P06 A09 v2 preserves ledger")
	v2["action_resources"]["bonus_left"] = 0
	_check(restored_v2.action_resources.get_bonus_left() == 1, "P06 A09 DTO is isolated")
	var board := BattleBoard.new(2, 1)
	var v1_unit := _p06_unit()
	var v2_unit := _p06_unit()
	v2_unit.cell = Vector2i(1, 0)
	_check(v2_unit.enable_action_resources() == &"" and v2_unit.try_refill_turn_resources() == &"", "P06 A09 mixed board fixture")
	board.add_unit(v1_unit)
	board.add_unit(v2_unit)
	var counter := UnitId.get_counter()
	var mixed := SimulationSnapshot.capture_board(board, [])
	var mixed_data := mixed.snapshot.to_dict() if mixed.snapshot != null else {}
	_check(mixed.code == BoardSnapshotResult.Code.OK and mixed_data["board"]["units"][0]["schema_version"] == 1 and mixed_data["board"]["units"][1]["schema_version"] == 2, "P06 A09 mixed v1/v2 P02 board")
	var first := mixed.snapshot.instantiate_board()
	var second := mixed.snapshot.instantiate_board()
	_check(UnitId.get_counter() == counter and first.get_unit_by_id(v2_unit.id).action_resources != second.get_unit_by_id(v2_unit.id).action_resources, "P06 A09 P02 import does not allocate and copies ledgers")
	var p03 := _p06_p03b_resources()
	var captured := ItemSimulationSnapshot.capture(p03.state, [])
	var fingerprint := captured.snapshot.fingerprint() if captured.snapshot != null else ""
	var catalogue := {p03.base_definition.id: p03.base_definition, p03.resource_definition.id: p03.resource_definition}
	var first_restore := captured.snapshot.instantiate(catalogue) if captured.snapshot != null else ItemSnapshotResult.new()
	var second_restore := captured.snapshot.instantiate(catalogue) if captured.snapshot != null else ItemSnapshotResult.new()
	var a := first_restore.state
	var b := second_restore.state
	var a_unit: UnitState = a.get_board().get_unit_by_id(101) if a != null else null
	var b_unit: UnitState = b.get_board().get_unit_by_id(101) if b != null else null
	_check(captured.code == ItemSnapshotResult.Code.OK and a_unit.action_resources != null and a_unit.get_stat(StatTypes.StatType.MAIN_ACTIONS_MAX) == 2.0 and a_unit.get_stat(StatTypes.StatType.ATTACK_RANGE) == 2.0, "P06 A09 item modifiers stat7..10 roundtrip")
	_check(a_unit != null and b_unit != null and a_unit.action_resources.try_spend_main(1) and ItemSimulationSnapshot.capture(a, []).snapshot.fingerprint() != fingerprint and ItemSimulationSnapshot.capture(b, []).snapshot.fingerprint() == fingerprint and b_unit.action_resources.get_main_left() == 2, "P06 A09 two independent P03b restores retain ledger")
	_check(legacy.to_dict().is_empty() and board.to_dict().is_empty(), "P06 A09 legacy exports refuse enabled resources")

func _test_p06_a10_rejections() -> void:
	var unit := _p06_unit()
	var v1 := unit.to_snapshot_dict()
	var extra := v1.duplicate(true)
	extra["extra"] = true
	_check(not UnitState.validate_snapshot_dict(extra), "P06 A10 extra unit key invalid")
	var v3 := v1.duplicate(true)
	v3["schema_version"] = 99
	_check(not UnitState.validate_snapshot_dict(v3), "P06 A10 unknown unit version rejected")
	_check(ActionResources.from_snapshot_dict({"schema_version": 2, "owner_unit_id": unit.id, "main_left": 0, "bonus_left": 0}, unit.id) == null, "P06 A10 unknown resource version rejected")
	_check(ActionResources.from_snapshot_dict({"schema_version": 1, "owner_unit_id": unit.id, "main_left": 4097, "bonus_left": 0}, unit.id) == null, "P06 A10 resource range rejected")
	_check(not StatsBag.validate_snapshot_dict({"schema_version": 1, "stats": [{"stat_type": 12, "stat": {}}]}), "P06 A10 unknown stat remains unsupported (M4 appends ID 11)")
	var board := BattleBoard.new(2, 1)
	var first := _p06_unit()
	var second := _p06_unit()
	second.cell = Vector2i(1, 0)
	_check(first.enable_action_resources() == &"" and first.try_refill_turn_resources() == &"" and second.enable_action_resources() == &"" and second.try_refill_turn_resources() == &"", "P06 A10 v2 rejection fixture")
	board.add_unit(first)
	board.add_unit(second)
	var snapshot := SimulationSnapshot.capture_board(board, []).snapshot
	for unit_key: String in ["schema_version", "id", "faction", "cell_x", "cell_y", "height", "debug_name", "ai_profile_path", "move_points_left", "has_attacked", "stats", "vitals", "action_resources"]:
		var missing_unit_key := snapshot.to_dict()
		missing_unit_key["board"]["units"][0].erase(unit_key)
		_check(SimulationSnapshot.from_dict(missing_unit_key).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 missing v2 Unit key " + unit_key)
		var wrong_unit_type := snapshot.to_dict()
		wrong_unit_type["board"]["units"][0][unit_key] = 1 if unit_key == "has_attacked" else true
		_check(SimulationSnapshot.from_dict(wrong_unit_type).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 wrong v2 Unit type " + unit_key)
	var extra_unit_key := snapshot.to_dict()
	extra_unit_key["board"]["units"][0]["extra"] = 1
	_check(SimulationSnapshot.from_dict(extra_unit_key).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 extra v2 Unit key invalid")
	for ledger_key: String in ["owner_unit_id", "main_left", "bonus_left"]:
		var malformed := snapshot.to_dict()
		malformed["board"]["units"][0]["action_resources"].erase(ledger_key)
		_check(SimulationSnapshot.from_dict(malformed).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 missing ledger " + ledger_key)
		malformed = snapshot.to_dict()
		malformed["board"]["units"][0]["action_resources"][ledger_key] = true
		_check(SimulationSnapshot.from_dict(malformed).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 ledger type " + ledger_key)
	var missing_resource_version := snapshot.to_dict()
	missing_resource_version["board"]["units"][0]["action_resources"].erase("schema_version")
	_check(SimulationSnapshot.from_dict(missing_resource_version).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 missing resource version invalid")
	var unknown_unit := snapshot.to_dict()
	unknown_unit["board"]["units"][0]["schema_version"] = 99
	_check(SimulationSnapshot.from_dict(unknown_unit).code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "P06 A10 Unit99 in v2 shape unsupported")
	var malformed_unknown_unit := snapshot.to_dict()
	malformed_unknown_unit["board"]["units"][0]["schema_version"] = 99
	malformed_unknown_unit["board"]["units"][0]["extra"] = 1
	_check(SimulationSnapshot.from_dict(malformed_unknown_unit).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 malformed Unit99 remains invalid")
	var malformed_unknown_unit_ledger := snapshot.to_dict()
	malformed_unknown_unit_ledger["board"]["units"][0]["schema_version"] = 99
	malformed_unknown_unit_ledger["board"]["units"][0]["action_resources"]["extra"] = 1
	_check(SimulationSnapshot.from_dict(malformed_unknown_unit_ledger).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 Unit99 malformed ledger remains invalid")
	var unknown_resource := snapshot.to_dict()
	unknown_resource["board"]["units"][0]["action_resources"]["schema_version"] = 2
	_check(SimulationSnapshot.from_dict(unknown_resource).code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "P06 A10 ActionResources2 unsupported")
	var malformed_unknown_resource := snapshot.to_dict()
	malformed_unknown_resource["board"]["units"][0]["action_resources"]["schema_version"] = 2
	malformed_unknown_resource["board"]["units"][0]["action_resources"]["extra"] = 1
	_check(SimulationSnapshot.from_dict(malformed_unknown_resource).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 malformed ActionResources2 remains invalid")
	var swapped := snapshot.to_dict()
	swapped["board"]["units"][0]["action_resources"] = swapped["board"]["units"][1]["action_resources"].duplicate(true)
	_check(SimulationSnapshot.from_dict(swapped).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 swapped ledger invalid")
	var extra_ledger := snapshot.to_dict()
	extra_ledger["board"]["units"][0]["action_resources"]["extra"] = 1
	_check(SimulationSnapshot.from_dict(extra_ledger).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 extra ledger key invalid")
	for invalid_counter: int in [-1, 4097]:
		var invalid_value := snapshot.to_dict()
		invalid_value["board"]["units"][0]["action_resources"]["main_left"] = invalid_counter
		_check(SimulationSnapshot.from_dict(invalid_value).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 ledger counter invalid %d" % invalid_counter)
	var counter := UnitId.get_counter()
	_check(UnitState.from_snapshot_dict(snapshot.to_dict()["board"]["units"][0]) != null and UnitId.get_counter() == counter, "P06 A10 Unit import leaves allocator untouched")
	var subclass_board := BattleBoard.new(1, 1)
	var subclass_unit := _p06_unit()
	_check(subclass_unit.enable_action_resources() == &"", "P06 A10 subclass ledger fixture")
	subclass_unit.action_resources = _P06ActionResources.new(subclass_unit.id)
	subclass_board.add_unit(subclass_unit)
	_check(SimulationSnapshot.capture_board(subclass_board, []).code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "P06 A10 P02 ledger subclass unsupported")
	var item_fixture := _p06_p03b_resources()
	var item_snapshot := ItemSimulationSnapshot.capture(item_fixture.state, []).snapshot
	var item_unknown := item_snapshot.to_dict()
	item_unknown["board_snapshot"]["board"]["units"][0]["schema_version"] = 99
	_check(ItemSimulationSnapshot.from_dict(item_unknown).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "P06 A10 P03b Unit99 unsupported")
	var item_malformed := item_snapshot.to_dict()
	item_malformed["board_snapshot"]["board"]["units"][0]["action_resources"].erase("main_left")
	_check(ItemSimulationSnapshot.from_dict(item_malformed).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "P06 A10 P03b malformed ledger invalid")

class _P06ActionResources extends ActionResources:
	pass

func _p06_p03b_resources() -> Dictionary:
	var fixture := _p03b_fixture()
	for owner: ItemOwnerState in fixture.owners:
		var unit := owner.get_owner()
		unit.stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.BONUS_ACTIONS_MAX, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		unit.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 1.0)
		unit.stats.set_base_value(StatTypes.StatType.MOVE_RANGE, 3.0)
		unit.enable_action_resources()
		unit.try_refill_turn_resources()
	var definition := ItemDef.new()
	definition.id = &"p06_all_resource_modifiers"
	for type: StatTypes.StatType in [StatTypes.StatType.MAIN_ACTIONS_MAX, StatTypes.StatType.BONUS_ACTIONS_MAX, StatTypes.StatType.WEAPON_DAMAGE, StatTypes.StatType.ATTACK_RANGE]:
		var effect := StatModifierEffect.new()
		effect.stat_type = type
		effect.operation = StatModifier.Operation.ADD_FLAT
		effect.value = 1.0
		definition.effects.append(effect)
	var item := fixture.owners[0].create_item(definition)
	fixture.inventories[0].add_item(item)
	fixture.owners[0].get_owner().try_refill_turn_resources()
	return {"state": fixture.state, "base_definition": fixture.definition, "resource_definition": definition}

func _p05_fixture() -> Dictionary:
	var board := BattleBoard.new(40, 3)
	var stats := _make_stats(10.0, 100.0)
	var unit := _p02_unit(201, Vector2i(0, 1), stats)
	unit.vitals.set_hp(10.0)
	unit.move_points_left = 100.0
	unit.has_attacked = true
	board.add_unit(unit)
	var owner := ItemOwnerState.new(unit)
	var inventory := InventoryState.new(owner)
	var equipment := EquipmentState.new(owner)
	var state := ItemSimulationState.new(board, [owner], [inventory], [equipment])
	var rules := MoveRules.new([201], 1)
	var context := ActionContext.new(state, P04TestRng.new(), ActionEventSink.new(), [], rules)
	return {"board": board, "unit": unit, "state": state, "owner": owner, "inventory": inventory, "equipment": equipment, "context": context, "rules": rules}

func _p05_path(length: int, y: int = 1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in length: result.append(Vector2i(x, y))
	return result

func _test_p05_m01_contracts() -> void:
	var f := _p05_fixture()
	var rules := f["rules"] as MoveRules
	var ids: Array[int] = [201]
	var copy := MoveRules.new(ids, 1)
	ids[0] = 202
	_check(copy.allows(201) and not copy.allows(202), "M01 rules copy isolates caller array")
	var context_rules := (f["context"] as ActionContext).get_move_rules()
	context_rules._admitted_unit_ids[0] = 202
	rules._admitted_unit_ids[0] = 203
	_check(context_rules != null and context_rules != rules and (f["context"] as ActionContext).get_move_rules().allows(201), "M01 context and getter rules isolate mutable arrays")
	for bad_ids in [[1, 1], [0], [-1], [MoveRules.MAX_ID]]:
		var typed_ids: Array[int] = Array(bad_ids, TYPE_INT, "", null)
		_check(MoveRules.new(typed_ids, 1).validate() == &"move/invalid_rules", "M01 invalid ids and duplicates reject %s" % str(bad_ids))
	for height: int in [-1, 2147483648]:
		_check(MoveRules.new([201], height).validate() == &"move/invalid_rules", "M01 invalid height %d" % height)
	_check(MoveRules.new([201], 0).validate() == &"" and MoveRules.new([201], 2147483647).validate() == &"", "M01 height boundaries accepted")
	_check(MoveRules.new([], 1).validate() == &"" and not MoveRules.new([], 1).allows(201) and MoveRules.new([999999], 1).allows(999999), "M01 empty and unknown allowlist semantics")
	var oversized: Array[int] = []
	for i in 65537: oversized.append(i + 1)
	_check(MoveRules.new(oversized, 1).validate() == &"move/invalid_rules", "M01 oversized rules retain invalid marker")
	var source: Array[Vector2i] = _p05_path(2)
	var command := MoveCommand.new(201, source, 0)
	source[1] = Vector2i(3, 1)
	var command_copy := command.copy_for_queue() as MoveCommand
	var returned := command.get_path()
	returned[0] = Vector2i(9, 1)
	_check(command_copy != null and command_copy.get_path() == [Vector2i(0, 1), Vector2i(1, 1)] and command.get_path()[0] == Vector2i(0, 1), "M01 move constructor copy getter and queued copy isolate path")
	for length: int in [0, 1, 34]:
		var invalid := MoveCommand.new(201, _p05_path(length), 0)
		_check(invalid.validate(f["context"]) == &"move/path_length" and (invalid.copy_for_queue() as MoveCommand).validate(f["context"]) == &"move/path_length", "M01 path length %d is retained across copy" % length)
	_check(MoveCommand.new(201, _p05_path(33), 0).validate(f["context"]) == &"", "M01 maximum 33-cell path accepted")
	for actor_id: int in [-1, 0, MoveCommand.MAX_ID]:
		_check(MoveCommand.new(actor_id, _p05_path(2), 0).validate(f["context"]) == &"move/invalid_actor_id", "M01 actor id boundary %d" % actor_id)
	for revision: int in [-1, MoveCommand.MAX_ID - 1, MoveCommand.MAX_ID]:
		_check(MoveCommand.new(201, _p05_path(2), revision).validate(f["context"]) == &"move/invalid_revision", "M01 revision boundary %d" % revision)
	var empty_admission := _p05_fixture()
	empty_admission["context"] = ActionContext.new(empty_admission["state"], P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([], 1))
	_check(MoveCommand.new(201, _p05_path(2), 0).validate(empty_admission["context"]) == &"move/not_admitted", "M01 empty admission rejects move")
	var unknown_admission := _p05_fixture()
	unknown_admission["context"] = ActionContext.new(unknown_admission["state"], P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([202], 1))
	_check(MoveCommand.new(202, _p05_path(2), 0).validate(unknown_admission["context"]) == &"move/missing_actor", "M01 unknown allowed id remains missing actor")
	var continuation := MoveCommand._make_continuation(command, 2, f["unit"] as UnitState)
	var before_counters := [(f["context"] as ActionContext)._next_root_id, (f["context"] as ActionContext)._next_command_seq, (f["context"] as ActionContext)._next_event_seq, (f["context"] as ActionContext).get_revision()]
	var rejected := ActionQueue.new().submit(continuation, f["context"])
	_check(rejected.status == &"REJECTED" and rejected.reason == &"move/internal_continuation" and rejected.root_id == 0 and rejected.get_steps().is_empty() and before_counters == [(f["context"] as ActionContext)._next_root_id, (f["context"] as ActionContext)._next_command_seq, (f["context"] as ActionContext)._next_event_seq, (f["context"] as ActionContext).get_revision()], "M01 external continuation rejected without counters")
	var preflight := _p05_fixture(); var preflight_continuation := MoveCommand._make_continuation(MoveCommand.new(201, _p05_path(2), 0), 2, preflight["unit"] as UnitState)
	(preflight["unit"] as UnitState).stats._stats[99] = RefCounted.new()
	var preflight_reject := ActionQueue.new().submit(preflight_continuation, preflight["context"])
	_check(preflight_reject.status == &"REJECTED" and preflight_reject.reason != &"move/internal_continuation" and preflight_reject.root_id == 0, "M01 invalid preflight wins over external continuation gate")
	var old := _test_p04_fixture()
	var old_move := MoveCommand.new(201, [Vector2i.ZERO, Vector2i(1, 0)], 0)
	var invalid_rules_context := ActionContext.new(old["state"], P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([0], 1))
	_check(old_move.validate(old["context"]) == &"move/rules_missing" and ActionQueue.new().submit(old_move, old["context"]).reason == &"move/rules_missing" and ActionQueue.new().submit(DamageCommand.new(DamageRequest.new(201, 1.0, &"physical", &"bypass", DamageSource.new(&"test"))), invalid_rules_context).status == &"APPLIED", "M01 old and invalid-rules contexts preserve HP compatibility")

func _test_p05_m02_geometry_and_budget() -> void:
	var f := _p05_fixture()
	var board := f["board"] as BattleBoard
	var unit := f["unit"] as UnitState
	var context := f["context"] as ActionContext
	var version := board.board_version
	unit.height = 999
	var board_changed: Array[Variant] = []
	var positions: Array[Array] = []
	board.board_changed.connect(func() -> void: board_changed.append(true))
	board.unit_position_changed.connect(func(moved: UnitState, from: Vector2i, to: Vector2i) -> void: positions.append([moved.id, from, to]))
	var receipt := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(3), 0), context)
	_check(receipt.status == &"APPLIED" and receipt.get_events().size() == 2 and receipt.get_steps().size() == 3, "M02 two edges include terminal step")
	_check(unit.cell == Vector2i(2, 1) and unit.height == board.get_height(unit.cell) and unit.move_points_left == 98.0 and unit.has_attacked and board.occupant_at(Vector2i(2, 1)) == unit and board.occupant_at(Vector2i(0, 1)) == null, "M02 board occupancy height and exact budget")
	_check(board.board_version == version + 2 and context.get_revision() == 2, "M02 board and context revisions increment per edge")
	_check(board_changed.size() == 2 and positions == [[201, Vector2i(0, 1), Vector2i(1, 1)], [201, Vector2i(1, 1), Vector2i(2, 1)]], "M02 board signals match both real edges")
	var loop := _p05_fixture()
	var loop_receipt := ActionQueue.new().submit(MoveCommand.new(201, [Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 1)], 0), loop["context"])
	_check(loop_receipt.status == &"APPLIED" and (loop["unit"] as UnitState).move_points_left == 98.0, "M02 return edge is charged again")
	var diagonal := _p05_fixture()
	var unattacked := _p05_fixture(); (unattacked["unit"] as UnitState).has_attacked = false
	_check(MoveCommand.new(201, [Vector2i(0, 1), Vector2i(1, 2)], 0).validate(diagonal["context"]) == &"move/not_adjacent" and MoveCommand.new(201, [Vector2i(0, 1), Vector2i(0, 1)], 0).validate(diagonal["context"]) == &"move/not_adjacent" and ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), unattacked["context"]).status == &"APPLIED" and not (unattacked["unit"] as UnitState).has_attacked, "M02 same and diagonal reject; attack flag is unrelated")

func _test_p05_m03_root_rejections() -> void:
	var cases: Array[Dictionary] = []
	var wall := _p05_fixture(); (wall["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.WALL); cases.append({"command": MoveCommand.new(201, _p05_path(2), 0), "fixture": wall, "reason": &"move/blocked"})
	var void_case := _p05_fixture(); (void_case["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.VOID); cases.append({"command": MoveCommand.new(201, _p05_path(2), 0), "fixture": void_case, "reason": &"move/blocked"})
	var bounds := _p05_fixture(); cases.append({"command": MoveCommand.new(201, [Vector2i(0, 1), Vector2i(2147483647, 1)], 0), "fixture": bounds, "reason": &"move/out_of_bounds"})
	var negative_bounds := _p05_fixture(); cases.append({"command": MoveCommand.new(201, [Vector2i(0, 1), Vector2i(-2147483648, 1)], 0), "fixture": negative_bounds, "reason": &"move/out_of_bounds"})
	var stale := _p05_fixture(); cases.append({"command": MoveCommand.new(201, _p05_path(2), 1), "fixture": stale, "reason": &"move/stale_revision"})
	var tail := _p05_fixture(); (tail["board"] as BattleBoard).set_terrain(Vector2i(2, 1), TerrainType.Type.WALL); cases.append({"command": MoveCommand.new(201, _p05_path(3), 0), "fixture": tail, "reason": &"move/blocked"})
	var occupied := _p05_fixture(); var other := _p02_unit(202, Vector2i(1, 1), _make_stats()); (occupied["board"] as BattleBoard).add_unit(other)
	var other_owner := ItemOwnerState.new(other); var other_inventory := InventoryState.new(other_owner); var other_equipment := EquipmentState.new(other_owner)
	occupied["state"] = ItemSimulationState.new(occupied["board"], [occupied["owner"], other_owner], [occupied["inventory"], other_inventory], [occupied["equipment"], other_equipment])
	occupied["context"] = ActionContext.new(occupied["state"], P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([201], 1))
	var occupied_before := (occupied["board"] as BattleBoard).to_snapshot_dict()
	var occupied_result := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), occupied["context"])
	_check(occupied_result.status == &"REJECTED" and occupied_result.reason == &"move/blocked" and occupied_result.get_steps().is_empty() and (occupied["board"] as BattleBoard).to_snapshot_dict() == occupied_before, "M03 occupied next cell rejects before mutation")
	var tall := _p05_fixture(); (tall["board"] as BattleBoard).set_height(Vector2i(1, 1), 2); cases.append({"command": MoveCommand.new(201, _p05_path(2), 0), "fixture": tall, "reason": &"move/height_step"})
	var downhill := _p05_fixture(); (downhill["board"] as BattleBoard).set_height(Vector2i(0, 1), 2); cases.append({"command": MoveCommand.new(201, _p05_path(2), 0), "fixture": downhill, "reason": &"move/height_step"})
	var start := _p05_fixture(); cases.append({"command": MoveCommand.new(201, [Vector2i(1, 1), Vector2i(2, 1)], 0), "fixture": start, "reason": &"move/start_mismatch"})
	for item in cases:
		var fixture: Dictionary = item["fixture"]
		_p05_assert_rejected(fixture, item["command"] as MoveCommand, item["reason"] as StringName, "M03 root rejection", bool(item.get("uncaptured", false)))
	var dead := _p05_fixture(); (dead["unit"] as UnitState).vitals.apply_damage(10.0); _p05_assert_rejected(dead, MoveCommand.new(201, _p05_path(2), 0), &"move/dead_actor", "M03 dead")
	var not_placed := _p05_fixture(); (not_placed["board"] as BattleBoard).clear_occupancy(not_placed["unit"]); _p05_assert_rejected(not_placed, MoveCommand.new(201, _p05_path(2), 0), &"move/actor_not_placed", "M03 unplaced")
	for budget: float in [0.0, 0.5]:
		var low := _p05_fixture(); (low["unit"] as UnitState).move_points_left = budget; _p05_assert_rejected(low, MoveCommand.new(201, _p05_path(2), 0), &"move/insufficient_move", "M03 budget %.1f" % budget)
	var missing := _p05_fixture(); _p05_assert_rejected(missing, MoveCommand.new(999, _p05_path(2), 0), &"move/missing_actor", "M03 missing actor")
	var nonfinite := _p05_fixture(); var nonfinite_context := nonfinite["context"] as ActionContext; var nonfinite_unit := nonfinite["unit"] as UnitState; nonfinite_unit.move_points_left = NAN
	var nonfinite_counters := [nonfinite_context._next_root_id, nonfinite_context._next_command_seq, nonfinite_context._next_event_seq, nonfinite_context.get_revision()]
	var nonfinite_result := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), nonfinite_context)
	_check(nonfinite_result.status == &"REJECTED" and is_nan(nonfinite_unit.move_points_left) and nonfinite_counters == [nonfinite_context._next_root_id, nonfinite_context._next_command_seq, nonfinite_context._next_event_seq, nonfinite_context.get_revision()], "M03 nonfinite live budget is rejected by preflight without repair")

func _test_p05_m04_arithmetic() -> void:
	for cost: float in [-1.0, 0.0, 0.5, NAN, INF, -INF]:
		_check(MovePathCheck._check_costs([cost], 10.0)["reason"] == &"move/invalid_cost", "M04 invalid cost %s" % str(cost))
	for budget: float in [-1.0, NAN, INF, -INF]:
		_check(MovePathCheck._check_costs([1.0], budget)["reason"] == &"move/invalid_budget", "M04 invalid budget %s" % str(budget))
	var valid := MovePathCheck._check_costs([1.0, 3.0, 1.0], 5.0)
	_check(valid["reason"] == &"" and valid["total"] == 5.0, "M04 exact FLOOR HAZARD FLOOR arithmetic")
	_check(MovePathCheck._check_costs([1e308, 1e308], 1.7e308)["reason"] == &"move/cost_overflow", "M04 positive cost overflow rejects")
	_check(MovePathCheck._check_costs([1e16, 1.0], 1e16)["reason"] == &"move/insufficient_move", "M04 sequential residual catches rounded sum")
	_check(MovePathCheck._check_costs([1.0], 1e20)["reason"] == &"move/unrepresentable_debit", "M04 unrepresentable debit rejects")
	var f := _p05_fixture(); (f["unit"] as UnitState).move_points_left = 1e20
	_p05_assert_rejected(f, MoveCommand.new(201, _p05_path(2), 0), &"move/unrepresentable_debit", "M04 board rejects free ULP step")
	var inspection := MovePathCheck.inspect(f["board"], f["unit"], _p05_path(2), 1, 100.0)
	var costs := inspection.get_costs(); costs[0] = 99.0
	_check(inspection.get_reason() == &"" and inspection.get_costs()[0] == 1.0, "M04 inspected costs are copied")
	_check(MovePathCheck.inspect(null, f["unit"], _p05_path(2), 1, 1.0).get_reason() == &"move/invalid_runtime" and MovePathCheck.inspect(f["board"], null, _p05_path(2), 1, 1.0).get_reason() == &"move/invalid_runtime" and MovePathCheck.inspect(f["board"], f["unit"], _p05_path(2), -1, 1.0).get_reason() == &"move/invalid_rules", "M04 inspect runtime and height guards")

func _p05_assert_rejected(fixture: Dictionary, command: MoveCommand, reason: StringName, label: String, use_board_snapshot: bool = false) -> void:
	var old_context := fixture["context"] as ActionContext
	var board := fixture["board"] as BattleBoard
	var state := fixture["state"] as ItemSimulationState
	var rng := old_context.get_rng()
	var sink := P04HookSink.new()
	var context := ActionContext.new(state, rng, sink, [], old_context.get_move_rules())
	fixture["context"] = context
	var capture := ItemSimulationSnapshot.capture(state, [])
	var canonical := capture.snapshot.canonical_bytes() if capture.code == ItemSnapshotResult.Code.OK else PackedByteArray()
	var board_snapshot := board.to_snapshot_dict()
	var raw_stats := (fixture["unit"] as UnitState).stats.to_snapshot_dict()
	var raw_stat: Stat = (fixture["unit"] as UnitState).stats._stats[StatTypes.StatType.HP_MAX]
	raw_stat.base_value = raw_stat.base_value
	var cache_before := [raw_stat._cache_dirty, raw_stat._cached_value, raw_stat._modifier_slots.duplicate(), raw_stat._next_modifier_slot]
	var rng_before := rng.to_dict()
	var counters := [context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision(), board.board_version]
	var signal_count: Array[int] = [0]
	var position_count: Array[int] = [0]
	board.board_changed.connect(func() -> void: signal_count[0] += 1)
	board.unit_position_changed.connect(func(_unit: UnitState, _from: Vector2i, _to: Vector2i) -> void: position_count[0] += 1)
	var direct := command.validate(context)
	var receipt := ActionQueue.new().submit(command, context)
	var after := ItemSimulationSnapshot.capture(state, [])
	var stable := board.to_snapshot_dict() == board_snapshot if use_board_snapshot else after.code == ItemSnapshotResult.Code.OK and after.snapshot.canonical_bytes() == canonical
	_check(direct == reason and receipt.status == &"REJECTED" and receipt.reason == reason and receipt.root_id == 0 and receipt.get_steps().is_empty() and receipt.get_events().is_empty() and stable and (fixture["unit"] as UnitState).stats.to_snapshot_dict() == raw_stats and [raw_stat._cache_dirty, raw_stat._cached_value, raw_stat._modifier_slots, raw_stat._next_modifier_slot] == cache_before and rng.to_dict() == rng_before and counters == [context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision(), board.board_version] and signal_count[0] == 0 and position_count[0] == 0 and sink.events.is_empty(), "%s %s preserves canonical/raw/counters" % [label, reason])

func _test_p05_m05_hazard_death() -> void:
	for edge: int in [1, 3]:
		var f := _p05_fixture()
		var path: Array[Vector2i] = _p05_path(4)
		var board := f["board"] as BattleBoard
		var before_version := board.board_version
		var hook := P05MoveHook.new(MoveCommand.new(201, path, 0), edge, [DamageCommand.new(DamageRequest.new(201, 99.0, &"physical", &"bypass", DamageSource.new(&"test")))])
		var receipt := ActionQueue.new().submit(hook, f["context"])
		var events := receipt.get_events()
		var unit := f["unit"] as UnitState
		_check(receipt.status == &"INTERRUPTED" and receipt.reason == &"move/actor_dead" and events.size() == edge + 2 and events[edge - 1]["kind"] == &"moved" and events[edge]["kind"] == &"damaged" and events[edge + 1]["kind"] == &"died", "M05 lethal child interrupts at edge%d" % edge)
		_check(unit.move_points_left == 100.0 - float(edge) and unit.cell == Vector2i(edge, 1) and board.board_version == before_version + edge + 1 and (f["context"] as ActionContext).get_revision() == edge + 1 and not unit.is_alive() and board.occupant_at(unit.cell) == null and board.get_unit_by_id(201) == unit, "M05 paid prefix, one death cleanup and corpse edge%d" % edge)

func _test_p05_m06_continuation_guards() -> void:
	var modes: Array[String] = ["displaced", "removed", "replaced", "wall", "height", "budget", "distant", "unrelated"]
	var last_fixture: Dictionary = {}
	for mode in modes:
		var f := _p05_fixture(); var board := f["board"] as BattleBoard; var unit := f["unit"] as UnitState
		var replacement: UnitState = null
		last_fixture = f
		var mutation := P04Work.new(&"m06_" + mode, func(_context: ActionContext) -> CommandStepResult:
			match mode:
				"displaced": board.move_unit(unit, Vector2i(5, 1))
				"removed":
					(f["inventory"] as InventoryState).close(); (f["equipment"] as EquipmentState).close(); (f["owner"] as ItemOwnerState).close()
					(f["state"] as ItemSimulationState)._owners.clear(); (f["state"] as ItemSimulationState)._inventories.clear(); (f["state"] as ItemSimulationState)._equipment.clear(); board.remove_unit(unit)
				"replaced":
					(f["inventory"] as InventoryState).close(); (f["equipment"] as EquipmentState).close(); (f["owner"] as ItemOwnerState).close(); board.remove_unit(unit)
					replacement = _p02_unit(201, Vector2i(1, 1), _make_stats())
					board.add_unit(replacement)
					var new_owner := ItemOwnerState.new(replacement); var new_inventory := InventoryState.new(new_owner); var new_equipment := EquipmentState.new(new_owner)
					(f["state"] as ItemSimulationState)._owners = [new_owner]; (f["state"] as ItemSimulationState)._inventories = [new_inventory]; (f["state"] as ItemSimulationState)._equipment = [new_equipment]
				"wall": board.set_terrain(Vector2i(2, 1), TerrainType.Type.WALL)
				"height": board.set_height(Vector2i(2, 1), 3)
				"budget": unit.move_points_left = 1.0
				"distant": board.set_terrain(Vector2i(3, 1), TerrainType.Type.WALL)
				"unrelated": board.set_terrain(Vector2i(5, 1), TerrainType.Type.WALL)
			return CommandStepResult.applied([], [], [], null, true))
		var hook := P05MoveHook.new(MoveCommand.new(201, _p05_path(4), 0), 1, [mutation])
		var receipt := ActionQueue.new().submit(hook, f["context"])
		var expected: StringName = &"move/actor_displaced"
		if mode == "removed": expected = &"move/actor_missing"
		elif mode == "replaced": expected = &"move/actor_replaced"
		elif mode == "wall" or mode == "distant": expected = &"move/path_blocked"
		elif mode == "height": expected = &"move/path_height"
		elif mode == "budget": expected = &"move/budget_exhausted"
		elif mode == "unrelated": expected = &""
		var expected_cell := Vector2i(1, 1); var expected_budget := 99.0
		if mode == "displaced": expected_cell = Vector2i(5, 1)
		elif mode == "budget" or mode == "distant": expected_cell = Vector2i(2, 1); expected_budget = 0.0 if mode == "budget" else 98.0
		elif mode == "unrelated": expected_cell = Vector2i(3, 1); expected_budget = 97.0
		var moved := board.get_unit_by_id(201) if mode == "replaced" else unit
		var capture := ItemSimulationSnapshot.capture(f["state"] as ItemSimulationState, [])
		var composition_ok := capture.code == ItemSnapshotResult.Code.OK if mode in ["removed", "replaced"] else true
		_check(((receipt.status == &"APPLIED" and expected == &"") or (receipt.status == &"INTERRUPTED" and receipt.reason == expected)) and (mode == "removed" or (moved as UnitState).cell == expected_cell) and (mode == "replaced" or unit.move_points_left == expected_budget) and composition_ok, "M06 dynamic %s exact prefix and composition" % mode)
	var terminal := _p05_fixture()
	var terminal_board := terminal["board"] as BattleBoard
	var terminal_child := P04Work.new(&"m06_terminal", func(_context: ActionContext) -> CommandStepResult:
		(terminal["unit"] as UnitState).move_points_left = 0.0
		terminal_board.set_terrain(Vector2i(1, 1), TerrainType.Type.WALL)
		return CommandStepResult.applied([], [], [], null, true))
	var terminal_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, _p05_path(2), 0), 1, [terminal_child]), terminal["context"])
	_check(terminal_result.status == &"APPLIED" and terminal_result.get_steps().size() == 3, "M06 terminal ignores depleted budget and changed old terrain")
	_check((last_fixture["context"] as ActionContext).get_revision() >= 1, "M06 paid prefix survives dynamic interruption")

func _test_p05_m07_hazard_boundaries() -> void:
	for hazard_index: int in [1, 2, 3]:
		var f := _p05_fixture(); var board := f["board"] as BattleBoard
		board.set_terrain(Vector2i(hazard_index, 1), TerrainType.Type.HAZARD)
		var version_before := board.board_version
		var receipt := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(4), 0), f["context"])
		var unit := f["unit"] as UnitState
		var events := receipt.get_events()
		var died_source: Dictionary = events[hazard_index]["source"]
		_check(receipt.status == &"INTERRUPTED" and receipt.reason == &"move/actor_dead" and not unit.is_alive() and unit.cell == Vector2i(hazard_index, 1) and unit.move_points_left == 100.0 - float(hazard_index + 2) and events.size() == hazard_index + 1 and receipt.get_steps().size() == hazard_index + 2 and (f["context"] as ActionContext).get_revision() == hazard_index + 1 and board.board_version == version_before + hazard_index + 1 and events[hazard_index - 1]["kind"] == &"moved" and events[hazard_index - 1]["move_cost"] == 3.0 and events[hazard_index]["kind"] == &"died" and died_source["kind"] == &"cell" and died_source["origin_cell"] == Vector2i(hazard_index, 1) and died_source["source_instance_id"] == 0 and died_source["instigator_unit_id"] == 0 and died_source["credit_unit_id"] == 0 and events[hazard_index]["actor_unit_id"] == 0 and events[hazard_index]["target_unit_id"] == 201, "M07 hazard index %d charges source and counters" % hazard_index)
	var zero := _p05_fixture(); (zero["unit"] as UnitState).vitals.set_hp(0.0); (zero["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.HAZARD)
	var zero_result := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), zero["context"])
	_check(zero_result.status == &"INTERRUPTED" and not (zero["unit"] as UnitState).is_alive() and zero_result.get_events().size() == 2 and zero_result.get_events()[1]["kind"] == &"died", "M07 alive-at-zero enters hazard and dies")
	var escape := _p05_fixture(); var escape_board := escape["board"] as BattleBoard; escape_board.set_terrain(Vector2i(0, 1), TerrainType.Type.HAZARD); escape_board.board_version = ActionContext.MAX_ID - 1
	var boundary := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), escape["context"])
	_check(boundary.status == &"APPLIED" and escape_board.board_version == ActionContext.MAX_ID, "M07 start hazard escape boundary")
	var invalid_tail := _p05_fixture(); (invalid_tail["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.HAZARD); (invalid_tail["board"] as BattleBoard).set_terrain(Vector2i(2, 1), TerrainType.Type.WALL)
	_check(ActionQueue.new().submit(MoveCommand.new(201, _p05_path(3), 0), invalid_tail["context"]).status == &"REJECTED", "M07 invalid tail rejects whole root")
	var expensive_tail := _p05_fixture(); (expensive_tail["unit"] as UnitState).move_points_left = 3.0; (expensive_tail["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.HAZARD)
	var void_tail := _p05_fixture(); (void_tail["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.VOID)
	_check(ActionQueue.new().submit(MoveCommand.new(201, _p05_path(3), 0), expensive_tail["context"]).reason == &"move/insufficient_move" and ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), void_tail["context"]).reason == &"move/blocked", "M07 expensive hazard and VOID tails reject root")
	var dynamic := _p05_fixture(); var dynamic_board := dynamic["board"] as BattleBoard
	var make_hazard := P04Work.new(&"hazard", func(_c: ActionContext) -> CommandStepResult:
		dynamic_board.set_terrain(Vector2i(2, 1), TerrainType.Type.HAZARD)
		return CommandStepResult.applied([], [], [], null, true))
	var dynamic_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, _p05_path(3), 0), 1, [make_hazard]), dynamic["context"])
	_check(dynamic_result.status == &"INTERRUPTED" and dynamic_result.get_events().size() == 3 and (dynamic["unit"] as UnitState).move_points_left == 96.0, "M07 dynamic floor to hazard uses current price and death")
	var poor := _p05_fixture(); (poor["unit"] as UnitState).move_points_left = 2.0; var poor_board := poor["board"] as BattleBoard
	var poor_hazard := P04Work.new(&"poor_hazard", func(_c: ActionContext) -> CommandStepResult:
		poor_board.set_terrain(Vector2i(2, 1), TerrainType.Type.HAZARD)
		return CommandStepResult.applied([], [], [], null, true))
	var poor_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, _p05_path(3), 0), 1, [poor_hazard]), poor["context"])
	_check(poor_result.status == &"INTERRUPTED" and poor_result.reason == &"move/budget_exhausted" and (poor["unit"] as UnitState).is_alive() and (poor["unit"] as UnitState).cell == Vector2i(1, 1) and (poor["unit"] as UnitState).move_points_left == 1.0 and poor_result.get_events().size() == 1, "M07 dynamic hazard insufficient budget avoids death")

func _test_p05_m08_no_moved_reactions() -> void:
	var f := _p05_reaction_fixture(1.5)
	var context := f["context"] as ActionContext
	var marker: Array[StringName] = []
	var explicit := P04Work.new(&"m08_explicit", func(_context: ActionContext) -> CommandStepResult:
		marker.append(&"explicit")
		return CommandStepResult.applied())
	var hook := P05MoveHook.new(MoveCommand.new(201, [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0)], 0), 1, [explicit], [DamageCommand.new(DamageRequest.new(201, 3.0, &"physical", &"bypass", DamageSource.new(&"test")))])
	var receipt := ActionQueue.new().submit(hook, context)
	var kinds: Array[String] = []
	for event in receipt.get_events(): kinds.append(String(event["kind"]))
	var step_kinds: Array[StringName] = []
	for step in receipt.get_steps(): step_kinds.append(step["kind"])
	_check(receipt.status == &"APPLIED" and kinds == ["moved", "damaged", "healed", "moved"] and marker == [&"explicit"] and step_kinds == [&"move", &"damage", &"heal", &"m08_explicit", &"move", &"move"], "M08 mandatory damage, item heal, explicit sibling, continuation drain", "%s %s" % [receipt.status, kinds])
	var plain := _p05_reaction_fixture(1.5); var plain_result := ActionQueue.new().submit(MoveCommand.new(201, [Vector2i.ZERO, Vector2i(1, 0)], 0), plain["context"])
	_check(plain_result.get_events().size() == 1 and plain_result.get_events()[0]["kind"] == &"moved", "M08 moved alone does not trigger heal item")

func _p05_reaction_fixture(heal_amount: float) -> Dictionary:
	var board := BattleBoard.new(3, 1)
	var unit := _p02_unit(201, Vector2i.ZERO, _make_stats())
	unit.vitals.set_hp(10.0)
	unit.move_points_left = 100.0
	board.add_unit(unit)
	var owner := ItemOwnerState.new(unit)
	var inventory := InventoryState.new(owner)
	var equipment := EquipmentState.new(owner)
	var definition := ItemDef.new()
	definition.id = &"p05_heal_on_damage"
	var heal := HealOnDamageEffect.new()
	heal.trigger_event = TriggeredEffect.TriggerEvent.UNIT_DAMAGED
	heal.heal_amount = heal_amount
	definition.effects = [heal]
	var item := owner.create_item(definition)
	_check(item != null and inventory.add_item(item), "M08 fixture activates real HealOnDamage item")
	var state := ItemSimulationState.new(board, [owner], [inventory], [equipment])
	return {"state": state, "board": board, "unit": unit, "definition": definition, "context": ActionContext.new(state, P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([201], 1))}

func _test_p05_m09_moved_schema() -> void:
	var f := _p05_fixture(); var sink := P04HookSink.new(); f["context"] = ActionContext.new(f["state"], P04TestRng.new(), sink, [], MoveRules.new([201], 1)); var receipt := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(3), 0), f["context"]); var event := receipt.get_events()[0]
	_check(event.keys().size() == 13 and event["kind"] == &"moved" and event["target_unit_id"] == 201 and event["parent_event_seq"] == 0, "M09 moved schema and parent sequence")
	var raw_event := event.duplicate(true)
	for metadata: String in ["event_seq", "root_id", "command_seq", "parent_event_seq"]: raw_event.erase(metadata)
	_check(ActionQueue._valid_draft(raw_event), "M09 moved draft validates")
	var malformed := event.duplicate(true); malformed["move_before"] = 1.0; malformed["move_cost"] = 1.0; malformed["move_after"] = 1e-20
	for metadata: String in ["event_seq", "root_id", "command_seq", "parent_event_seq"]: malformed.erase(metadata)
	_check(not ActionQueue._valid_draft(malformed), "M09 asymmetric arithmetic is rejected")
	for mutation in [{"move_cost": 0.0}, {"move_cost": NAN}, {"move_cost": 1}, {"move_before": NAN}, {"move_after": -1.0}, {"target_unit_id": 0}, {"target_unit_id": 202}, {"movement_kind": &"forced"}, {"to_cell": Vector2i(1, 2)}, {"to_cell": Vector2i(2147483647, 1)}, {"source": DamageSource.new(&"test")}, {"callback": Callable()}, {"extra": true}]:
		var bad := raw_event.duplicate(true)
		for key in mutation.keys(): bad[key] = mutation[key]
		_check(not ActionQueue._valid_draft(bad), "M09 malformed moved field %s rejects" % str(mutation.keys()))
	var missing := raw_event.duplicate(true); missing.erase("move_cost")
	var string_name_key := raw_event.duplicate(true); string_name_key.erase("move_cost"); string_name_key[&"move_cost"] = 1.0
	_check(not ActionQueue._valid_draft(missing) and not ActionQueue._valid_draft(string_name_key), "M09 missing and StringName draft keys reject")
	var copied := receipt.get_events(); copied[0]["move_cost"] = 99.0; var copied_steps := receipt.get_steps(); copied_steps[0]["kind"] = &"bad"; sink.events[0]["move_cost"] = 88.0
	_check(receipt.get_events()[0]["move_cost"] == 1.0 and receipt.get_steps()[0]["kind"] == &"move" and sink.events[0]["move_cost"] == 88.0 and receipt.get_events()[0]["event_seq"] == 1 and receipt.get_events()[1]["event_seq"] == 2 and receipt.get_steps()[2]["command_seq"] == 3, "M09 receipt steps and sink copies plus exact child sequences")
	var fault_fixture := _p05_fixture()
	var queue_bad_draft := raw_event.duplicate(true)
	queue_bad_draft["move_after"] = 1e-20
	var malformed_root := P04Work.new(&"m09_bad_event", func(_context: ActionContext) -> CommandStepResult:
		return CommandStepResult.applied([queue_bad_draft]))
	var malformed_result := ActionQueue.new().submit(malformed_root, fault_fixture["context"])
	_check(malformed_result.status == &"FAULTED" and malformed_result.reason == &"malformed_event" and ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), fault_fixture["context"]).reason == &"CONTEXT_FAULTED", "M09 malformed event faults queue and context latch")

func _test_p05_m10_interrupted_receipt() -> void:
	var f := _p05_fixture(); (f["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.HAZARD); var receipt := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), f["context"])
	_check(receipt.status == &"INTERRUPTED" and receipt.reason == &"move/actor_dead", "M10 first interruption reason preserved")
	_check(CommandStepResult.interrupted(&"x").continuation == null and not CommandStepResult.interrupted(&"x").state_changed, "M10 interrupted result has no children or state change")
	var reentrant := _p05_fixture()
	var queue := ActionQueue.new()
	var second_queue := ActionQueue.new()
	var copies: Array[int] = [0]
	var probe := P04Work.new(&"m10_probe")
	probe.copying = func() -> void: copies[0] += 1
	var nested: Array[ActionReceipt] = []
	var board := reentrant["board"] as BattleBoard
	board.board_changed.connect(func() -> void: nested.append(queue.submit(probe, reentrant["context"])))
	board.unit_position_changed.connect(func(_u: UnitState, _from: Vector2i, _to: Vector2i) -> void: nested.append(second_queue.submit(probe, reentrant["context"])))
	var hook_sink := P04HookSink.new()
	hook_sink.hook = func(_event: Dictionary) -> void: nested.append(queue.submit(probe, reentrant["context"]))
	reentrant["context"] = ActionContext.new(reentrant["state"], P04TestRng.new(), hook_sink, [], MoveRules.new([201], 1))
	var reentrant_result := queue.submit(MoveCommand.new(201, _p05_path(2), 0), reentrant["context"])
	var all_busy := true
	for nested_receipt in nested: all_busy = all_busy and (nested_receipt as ActionReceipt).reason == &"BUSY"
	_check(reentrant_result.status == &"APPLIED" and nested.size() == 3 and all_busy and copies[0] == 0 and (reentrant["context"] as ActionContext).get_rng().to_dict()["streams"][0]["cursor"] == 0, "M10 board signals and final sink reject same/different queue before copy/validate/RNG")
	var resume := _p05_fixture(); var resume_board := resume["board"] as BattleBoard; var resume_unit := resume["unit"] as UnitState
	var displacement := P04Work.new(&"m10_displace", func(_context: ActionContext) -> CommandStepResult:
		resume_board.move_unit(resume_unit, Vector2i(4, 1)); return CommandStepResult.applied([], [], [], null, true))
	var interrupted := queue.submit(P05MoveHook.new(MoveCommand.new(201, _p05_path(3), 0), 1, [displacement]), resume["context"])
	var resumed := queue.submit(MoveCommand.new(201, [Vector2i(4, 1), Vector2i(5, 1)], (resume["context"] as ActionContext).get_revision()), resume["context"])
	_check(interrupted.status == &"INTERRUPTED" and interrupted.reason == &"move/actor_displaced" and resumed.status == &"APPLIED", "M10 fresh root runs after ordinary interruption")
	var siblings := _p05_fixture(); var markers: Array[StringName] = []
	var first := P04Work.new(&"m10_first", func(_context: ActionContext) -> CommandStepResult: return CommandStepResult.interrupted(&"first"))
	var marker := P04Work.new(&"m10_marker", func(_context: ActionContext) -> CommandStepResult: markers.append(&"ran"); return CommandStepResult.applied())
	var second := P04Work.new(&"m10_second", func(_context: ActionContext) -> CommandStepResult: return CommandStepResult.interrupted(&"second"))
	var later_fault := P04Work.new(&"m10_fault", func(_context: ActionContext) -> CommandStepResult: return CommandStepResult.faulted(&"later"))
	var interrupt_only := P04Work.new(&"m10_interrupt_only", func(_context: ActionContext) -> CommandStepResult: return CommandStepResult.applied([], [], [first, marker, second]))
	var interrupt_only_result := ActionQueue.new().submit(interrupt_only, siblings["context"])
	_check(interrupt_only_result.status == &"INTERRUPTED" and interrupt_only_result.reason == &"first" and markers == [&"ran"], "M10 siblings preserve first interruption reason without fault")
	markers.clear()
	var siblings_root := P04Work.new(&"m10_root", func(_context: ActionContext) -> CommandStepResult: return CommandStepResult.applied([], [], [first, marker, second, later_fault]))
	var sibling_result := ActionQueue.new().submit(siblings_root, siblings["context"])
	_check(sibling_result.status == &"FAULTED" and sibling_result.reason == &"later" and markers == [&"ran"], "M10 siblings drain after interruption and later fault wins")
	var corrupted := _p05_fixture()
	var corrupt_result := ActionQueue.new().submit(P05CorruptContinuationHook.new(MoveCommand.new(201, _p05_path(3), 0)), corrupted["context"])
	_check(corrupt_result.status == &"FAULTED" and corrupt_result.reason == &"move/invalid_runtime" and (corrupted["unit"] as UnitState).cell == Vector2i(1, 1) and corrupt_result.get_events().size() == 1, "M10 captured corrupt continuation faults runtime after paid prefix")
	var terminal_displaced := _p05_fixture(); var terminal_board := terminal_displaced["board"] as BattleBoard; var terminal_unit := terminal_displaced["unit"] as UnitState
	var terminal_shift := P04Work.new(&"m10_terminal_shift", func(_context: ActionContext) -> CommandStepResult: terminal_board.move_unit(terminal_unit, Vector2i(4, 1)); return CommandStepResult.applied([], [], [], null, true))
	var terminal_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, _p05_path(3), 0), 2, [terminal_shift]), terminal_displaced["context"])
	var impossible := _p05_fixture(); var impossible_board := impossible["board"] as BattleBoard; var impossible_unit := impossible["unit"] as UnitState
	var clear := P04Work.new(&"m10_clear", func(_context: ActionContext) -> CommandStepResult: impossible_board.clear_occupancy(impossible_unit); return CommandStepResult.applied([], [], [], null, true))
	var impossible_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, _p05_path(3), 0), 1, [clear]), impossible["context"])
	_check(terminal_result.status == &"INTERRUPTED" and terminal_result.reason == &"move/actor_displaced" and impossible_result.status == &"FAULTED" and impossible_result.reason == &"move/invalid_runtime", "M10 terminal displacement interrupts and impossible occupancy faults")
	for malformed_kind: String in ["changed", "event", "mandatory", "reaction", "continuation"]:
		var malformed_fixture := _p05_fixture()
		var malformed_step := P04Work.new(&"m10_bad_" + malformed_kind, func(_context: ActionContext) -> CommandStepResult:
			var result := CommandStepResult.interrupted(&"bad")
			if malformed_kind == "changed": result.state_changed = true
			elif malformed_kind == "event": result.events.append({})
			elif malformed_kind == "mandatory": result.mandatory.append(P04Work.new())
			elif malformed_kind == "reaction": result.reactions.append(P04Work.new())
			else: result.continuation = P04Work.new()
			return result)
		var malformed_receipt := ActionQueue.new().submit(malformed_step, malformed_fixture["context"])
		_check(malformed_receipt.status == &"FAULTED" and malformed_receipt.reason == &"malformed_step", "M10 malformed interruption %s faults" % malformed_kind)

func _test_p05_m11_depth_and_limits() -> void:
	var f := _p05_fixture(); var full := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(33), 0), f["context"]); _check(full.status == &"APPLIED" and full.get_events().size() == 32 and full.get_steps().size() == 33, "M11 32 edges plus terminal fit default depth")
	var too_long := _p05_fixture(); var rejected := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(34), 0), too_long["context"]); _check(rejected.status == &"REJECTED" and rejected.reason == &"move/path_length", "M11 33 edges rejected by payload cap")
	var limited := _p05_fixture(); var limited_queue := ActionQueue.new(1, 512, 32); var fault := limited_queue.submit(MoveCommand.new(201, _p05_path(3), 0), limited["context"]); _check(fault.status == &"FAULTED" and fault.reason == &"command_limit" and (limited["unit"] as UnitState).cell == Vector2i(1, 1), "M11 command limit retains paid prefix")
	_check(ActionQueue.new().submit(MoveCommand.new(201, [Vector2i(1, 1), Vector2i(2, 1)], (limited["context"] as ActionContext).get_revision()), limited["context"]).reason == &"CONTEXT_FAULTED", "M11 command limit latches context")
	var fresh_after_fault := _p05_fixture()
	_check(limited_queue.submit(MoveCommand.new(201, _p05_path(2), 0), fresh_after_fault["context"]).reason == &"CONTEXT_FAULTED", "M11 faulted queue blocks a fresh context")
	var event_limited := _p05_fixture(); var event_fault := ActionQueue.new(32, 1, 32).submit(MoveCommand.new(201, _p05_path(3), 0), event_limited["context"])
	_check(event_fault.status == &"FAULTED" and event_fault.reason == &"event_limit" and (event_limited["unit"] as UnitState).cell == Vector2i(2, 1) and (event_limited["unit"] as UnitState).move_points_left == 98.0 and event_fault.get_events().size() == 2, "M11 event limit retains complete second edge prefix")
	var depth_limited := _p05_fixture(); var depth_fault := ActionQueue.new(32, 512, 1).submit(MoveCommand.new(201, _p05_path(3), 0), depth_limited["context"])
	_check(depth_fault.status == &"FAULTED" and depth_fault.reason == &"depth_limit" and (depth_limited["unit"] as UnitState).cell == Vector2i(2, 1), "M11 depth limit faults before terminal continuation")
	for command_limit: int in [1, 2]:
		var hazard := _p05_fixture(); (hazard["board"] as BattleBoard).set_terrain(Vector2i(1, 1), TerrainType.Type.HAZARD)
		var hazard_fault := ActionQueue.new(command_limit, 512, 32).submit(MoveCommand.new(201, _p05_path(2), 0), hazard["context"])
		var hazard_unit := hazard["unit"] as UnitState
		_check(hazard_fault.status == &"FAULTED" and hazard_fault.reason == &"command_limit" and hazard_unit.move_points_left == 97.0 and ((command_limit == 1 and hazard_unit.is_alive() and hazard_fault.get_events().size() == 1) or (command_limit == 2 and not hazard_unit.is_alive() and hazard_fault.get_events().size() == 2)), "M11 hazard command limit %d preserves correct mandatory prefix" % command_limit)
	for counter_name: String in ["_next_root_id", "_next_command_seq", "_next_event_seq"]:
		var exhausted := _p05_fixture()
		(exhausted["context"] as ActionContext).set(counter_name, ActionContext.MAX_ID if counter_name != "_next_event_seq" else ActionContext.MAX_ID - 1)
		var sequence_reject := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), exhausted["context"])
		_check(sequence_reject.status == &"REJECTED" and sequence_reject.reason == &"sequence_exhausted" and sequence_reject.get_events().is_empty(), "M11 root %s exhaustion rejects before mutation" % counter_name)
	var board_exhausted := _p05_fixture(); (board_exhausted["board"] as BattleBoard).board_version = ActionContext.MAX_ID
	_check(ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), board_exhausted["context"]).reason == &"move/board_version_exhausted", "M11 board version exhaustion rejects root")
	var post_start := _p05_fixture(); var post_context := post_start["context"] as ActionContext
	post_context._next_command_seq = ActionContext.MAX_ID - 1; post_context._next_event_seq = ActionContext.MAX_ID - 2; post_context._revision = ActionContext.MAX_ID - 2
	var post_result := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), ActionContext.MAX_ID - 2), post_context)
	_check(post_result.status == &"FAULTED" and post_result.reason == &"sequence_exhausted" and (post_start["unit"] as UnitState).cell == Vector2i(1, 1) and (post_start["unit"] as UnitState).move_points_left == 99.0 and post_result.get_events().size() == 1, "M11 post-start sequence exhaustion retains first moved prefix")
	for initial_version: int in [ActionContext.MAX_ID - 2, ActionContext.MAX_ID - 1]:
		var hazard_boundary := _p05_fixture(); var hazard_board := hazard_boundary["board"] as BattleBoard; hazard_board.set_terrain(Vector2i(1, 1), TerrainType.Type.HAZARD); hazard_board.board_version = initial_version
		var hazard_boundary_result := ActionQueue.new().submit(MoveCommand.new(201, _p05_path(2), 0), hazard_boundary["context"])
		_check((initial_version == ActionContext.MAX_ID - 2 and hazard_boundary_result.status == &"INTERRUPTED" and not (hazard_boundary["unit"] as UnitState).is_alive() and hazard_board.board_version == ActionContext.MAX_ID) or (initial_version == ActionContext.MAX_ID - 1 and hazard_boundary_result.reason == &"move/board_version_exhausted"), "M11 hazard board boundary %d" % initial_version)
	var consumed := _p05_fixture(); var consumed_board := consumed["board"] as BattleBoard; consumed_board.board_version = ActionContext.MAX_ID - 2
	var consume_version := P04Work.new(&"m11_consume", func(_context: ActionContext) -> CommandStepResult: consumed_board.set_height(Vector2i(5, 1), 1); return CommandStepResult.applied([], [], [], null, true))
	var consumed_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, _p05_path(3), 0), 1, [consume_version]), consumed["context"])
	_check(consumed_result.status == &"FAULTED" and consumed_result.reason == &"move/board_version_exhausted" and (consumed["unit"] as UnitState).cell == Vector2i(1, 1), "M11 child board mutation exhausts next edge capacity")
	var dynamic_capacity := _p05_fixture(); var dynamic_board := dynamic_capacity["board"] as BattleBoard; dynamic_board.board_version = ActionContext.MAX_ID - 3
	var make_hazard := P04Work.new(&"m11_hazard", func(_context: ActionContext) -> CommandStepResult: dynamic_board.set_terrain(Vector2i(2, 1), TerrainType.Type.HAZARD); return CommandStepResult.applied([], [], [], null, true))
	var dynamic_capacity_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, _p05_path(3), 0), 1, [make_hazard]), dynamic_capacity["context"])
	_check(dynamic_capacity_result.status == &"FAULTED" and dynamic_capacity_result.reason == &"move/board_version_exhausted" and (dynamic_capacity["unit"] as UnitState).cell == Vector2i(1, 1), "M11 dynamic hazard requires two remaining board versions")

func _test_p05_m12_isolation() -> void:
	var source := _p05_reaction_fixture(1.5)
	var captured := ItemSimulationSnapshot.capture(source["state"], []); var live_bytes := captured.snapshot.canonical_bytes(); var catalogue: Dictionary = {((source["definition"] as ItemDef).id): source["definition"]}; var first_state := captured.snapshot.instantiate(catalogue).state; var second_state := captured.snapshot.instantiate(catalogue).state
	var first := {"state": first_state, "board": first_state.get_board()}; var second := {"state": second_state, "board": second_state.get_board()}
	var first_rng := P04TestRng.new(); first_rng.cursors[&"combat"] = 1
	var second_rng := P04TestRng.new(); second_rng.cursors[&"combat"] = 1
	var second_rng_before := second_rng.to_dict()
	var first_context := ActionContext.new(first_state, first_rng, ActionEventSink.new(), [], MoveRules.new([201], 1)); var second_context := ActionContext.new(second_state, second_rng, ActionEventSink.new(), [], MoveRules.new([201], 1))
	var first_before := (first["board"] as BattleBoard).to_snapshot_dict(); var second_before := (second["board"] as BattleBoard).to_snapshot_dict()
	var first_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, [Vector2i.ZERO, Vector2i(1, 0)], 0), 1, [P04RandomDamageCommand.new(201)]), first_context)
	_check((first["board"] as BattleBoard).to_snapshot_dict() != first_before and (second["board"] as BattleBoard).to_snapshot_dict() == second_before and ItemSimulationSnapshot.capture(second_state, []).snapshot.canonical_bytes() == live_bytes and second_rng.to_dict() == second_rng_before and ItemSimulationSnapshot.capture(source.state, []).snapshot.canonical_bytes() == live_bytes, "M12 live and second clone isolated after first")
	var second_result := ActionQueue.new().submit(P05MoveHook.new(MoveCommand.new(201, [Vector2i.ZERO, Vector2i(1, 0)], 0), 1, [P04RandomDamageCommand.new(201)]), second_context)
	var kinds: Array[StringName] = []
	for event in first_result.get_events(): kinds.append(event["kind"])
	_check(first_result.status == &"APPLIED" and second_result.status == &"APPLIED" and kinds.has(&"moved") and kinds.has(&"damaged") and kinds.has(&"healed") and first_result.get_events() == second_result.get_events() and first_result.get_steps() == second_result.get_steps() and ItemSimulationSnapshot.capture(first_state, []).snapshot.canonical_bytes() == ItemSimulationSnapshot.capture(second_state, []).snapshot.canonical_bytes() and [first_context._next_root_id, first_context._next_command_seq, first_context._next_event_seq, first_context.get_revision()] == [second_context._next_root_id, second_context._next_command_seq, second_context._next_event_seq, second_context.get_revision()] and first_context.get_rng().to_dict() == second_context.get_rng().to_dict() and first_rng.cursors[&"combat"] == 2, "M12 canonical state receipts all counters and nonzero RNG match", "%s %s %s" % [kinds, first_result.status, first_result.get_steps()])


func _make_stats(hp_max: float = 10.0, balance_max: float = 100.0) -> StatsBag:
	var bag := StatsBag.new()
	bag.set_base_value(StatTypes.StatType.HP_MAX, hp_max)
	bag.set_base_value(StatTypes.StatType.BALANCE_MAX, balance_max)
	return bag


class _P03BFixture:
	var board: BattleBoard
	var state: ItemSimulationState
	var definition: ItemDef
	var owners: Array[ItemOwnerState] = []
	var inventories: Array[InventoryState] = []
	var equipment: Array[EquipmentState] = []


class _P03BItemDef extends ItemDef:
	pass


class _P03BHealRuntime extends HealOnDamageEffectRuntime:
	pass


class P04TestRng extends ActionRngPort:
	var cursors: Dictionary = {&"combat": 0, &"loot": 0}

	func next_int(stream: StringName, upper_exclusive: int) -> int:
		if stream not in [&"combat", &"loot"] or not cursors.has(stream) or upper_exclusive <= 0: return -1
		var cursor: int = cursors[stream]
		if cursor < 0 or cursor >= ActionContext.MAX_ID or cursor == ActionContext.MAX_ID - 1: return -1
		cursors[stream] = cursor + 1
		return cursor % upper_exclusive

	func clone() -> ActionRngPort:
		var result := P04TestRng.new()
		result.cursors = cursors.duplicate()
		return result

	func to_dict() -> Dictionary:
		return {"schema_version": 1, "streams": [{"name": "combat", "cursor": cursors[&"combat"]}, {"name": "loot", "cursor": cursors[&"loot"]}]}

	func from_dict(data: Dictionary) -> bool:
		if not ItemSimulationSnapshot._shape(data, {"schema_version": TYPE_INT, "streams": TYPE_ARRAY}) or data["schema_version"] != 1: return false
		var fresh: Dictionary = {}
		for row in data["streams"]:
			if not ItemSimulationSnapshot._shape(row, {"name": TYPE_STRING, "cursor": TYPE_INT}): return false
			var name := StringName(row["name"])
			var cursor: int = row["cursor"]
			if name not in [&"combat", &"loot"] or fresh.has(name) or cursor < 0 or cursor >= ActionContext.MAX_ID: return false
			fresh[name] = cursor
		if fresh.size() != 2: return false
		cursors = fresh
		return true


class P04RandomDamageCommand extends Command:
	var target_id: int
	func _init(p_target_id: int) -> void: target_id = p_target_id
	func get_kind() -> StringName: return &"p04_random_damage"
	func copy_for_queue() -> Command: return P04RandomDamageCommand.new(target_id)
	func validate(context: ActionContext) -> StringName:
		return &"" if context != null and context.get_rng() != null else &"rng"
	func execute(context: ActionContext) -> CommandStepResult:
		var draw := context.get_rng().next_int(&"combat", 3)
		if draw < 0: return CommandStepResult.faulted(&"rng")
		var source := DamageSource.new(&"test", 0, Vector2i.ZERO, 0, 0)
		var child := DamageCommand.new(DamageRequest.new(target_id, float(draw), &"physical", &"bypass", source))
		var result := CommandStepResult.applied([], [child], [], null, true)
		return result


class P05MoveHook extends Command:
	var inner: MoveCommand
	var inject_edge: int
	var injections: Array[Command] = []
	var mandatory_injections: Array[Command] = []
	var edge_number: int

	func _init(p_inner: MoveCommand, p_inject_edge: int = -1, p_injections: Array[Command] = [], p_mandatory_injections: Array[Command] = [], p_edge_number: int = 1) -> void:
		inner = p_inner
		inject_edge = p_inject_edge
		injections = p_injections.duplicate()
		mandatory_injections = p_mandatory_injections.duplicate()
		edge_number = p_edge_number

	func get_kind() -> StringName: return inner.get_kind()
	func copy_for_queue() -> Command:
		return P05MoveHook.new(inner.copy_for_queue() as MoveCommand, inject_edge, injections, mandatory_injections, edge_number)
	func validate(context: ActionContext) -> StringName: return inner.validate(context)
	func execute(context: ActionContext) -> CommandStepResult:
		var result := inner.execute(context)
		if result.status == &"APPLIED" and not result.events.is_empty() and result.events[0].get("kind", &"") == &"moved":
			if edge_number == inject_edge:
				for command in mandatory_injections: result.mandatory.append(command)
				for command in injections: result.reactions.append(command)
			if result.continuation != null and result.continuation is MoveCommand:
				result.continuation = P05MoveHook.new(result.continuation as MoveCommand, inject_edge, injections, mandatory_injections, edge_number + 1)
		return result


class P05CorruptContinuationHook extends Command:
	var inner: MoveCommand
	func _init(p_inner: MoveCommand) -> void: inner = p_inner
	func get_kind() -> StringName: return inner.get_kind()
	func copy_for_queue() -> Command: return P05CorruptContinuationHook.new(inner.copy_for_queue() as MoveCommand)
	func validate(context: ActionContext) -> StringName: return inner.validate(context)
	func execute(context: ActionContext) -> CommandStepResult:
		var result := inner.execute(context)
		if result.status == &"APPLIED" and result.continuation is MoveCommand:
			(result.continuation as MoveCommand)._actor_unit_id = 0
		return result


func _p03b_fixture() -> _P03BFixture:
	var fixture := _P03BFixture.new()
	fixture.board = BattleBoard.new(3, 1)
	var first_bag := _make_stats()
	var second_bag := _make_stats()
	first_bag.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	second_bag.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	var first := _p02_unit(101, Vector2i(0, 0), first_bag)
	var second := _p02_unit(102, Vector2i(1, 0), second_bag)
	fixture.board.add_unit(first)
	fixture.board.add_unit(second)
	fixture.definition = ItemDef.new()
	fixture.definition.id = &"p03b_shared"
	var stat := StatModifierEffect.new()
	stat.stat_type = StatTypes.StatType.STRENGTH
	stat.operation = StatModifier.Operation.ADD_FLAT
	stat.value = 2.0
	var heal := HealOnDamageEffect.new()
	heal.trigger_event = TriggeredEffect.TriggerEvent.UNIT_DAMAGED
	heal.heal_amount = 1.5
	# Повтор occurrence намеренный: snapshot обязан сохранить оба runtime id.
	fixture.definition.effects = [stat, heal, heal]
	var first_owner := ItemOwnerState.new(first)
	var second_owner := ItemOwnerState.new(second)
	var first_inventory := InventoryState.new(first_owner)
	var first_equipment := EquipmentState.new(first_owner)
	var second_inventory := InventoryState.new(second_owner)
	var second_equipment := EquipmentState.new(second_owner)
	var first_a := first_owner.create_item(fixture.definition)
	var first_b := first_owner.create_item(fixture.definition)
	var first_equipped := first_owner.create_item(fixture.definition)
	var second_equipped := second_owner.create_item(fixture.definition)
	_check(first_inventory.add_item(first_a) and first_inventory.add_item(first_b), "B fixture duplicate inventory items")
	_check(first_equipment.equip(EquipmentState.EquipSlot.ARMOR, first_equipped), "B fixture equipment placement")
	_check(second_equipment.equip(EquipmentState.EquipSlot.TRINKET, second_equipped), "B fixture second equipment placement")
	fixture.owners = [first_owner, second_owner]
	fixture.inventories = [first_inventory, second_inventory]
	fixture.equipment = [first_equipment, second_equipment]
	fixture.state = ItemSimulationState.new(fixture.board, fixture.owners, fixture.inventories, fixture.equipment)
	return fixture


func _p03b_capture(fixture: _P03BFixture) -> ItemSnapshotResult:
	return ItemSimulationSnapshot.capture(fixture.state, [])


func _p03b_catalogue(definition: ItemDef) -> Dictionary:
	return {definition.id: definition}


func _p03b_restore(fixture: _P03BFixture) -> ItemSimulationState:
	var captured := _p03b_capture(fixture)
	_check(captured.code == ItemSnapshotResult.Code.OK and captured.snapshot != null, "B snapshot capture")
	var restored := captured.snapshot.instantiate(_p03b_catalogue(fixture.definition))
	_check(restored.code == ItemSnapshotResult.Code.OK and restored.state != null, "B snapshot instantiate", restored.reason)
	return restored.state


func _test_p03b_b01_roundtrip() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	_check(result.code == ItemSnapshotResult.Code.OK, "B01 capture succeeds", result.reason)
	var restored_state := _p03b_restore(fixture)
	var restored_fixture := _P03BFixture.new()
	restored_fixture.state = restored_state
	var second := ItemSimulationSnapshot.capture(restored_state, [])
	_check(second.code == ItemSnapshotResult.Code.OK and second.snapshot.canonical_values() == result.snapshot.canonical_values(), "B01 canonical values roundtrip")
	_check(second.snapshot.canonical_bytes() == result.snapshot.canonical_bytes(), "B01 canonical bytes roundtrip")
	fixture.equipment[0].unequip(EquipmentState.EquipSlot.ARMOR)
	_check(fixture.owners[0].get_owner().get_stat(StatTypes.StatType.STRENGTH) == 7.0, "B01 STR 3+2+2")


func _test_p03b_b02_isolation() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	var a_result := result.snapshot.instantiate(_p03b_catalogue(fixture.definition))
	var b_result := result.snapshot.instantiate(_p03b_catalogue(fixture.definition))
	var a := a_result.state
	var b := b_result.state
	_check(a != b and a.get_board() != b.get_board(), "B02 states and boards are distinct")
	var a_owner := a.get_owner(101)
	var b_owner := b.get_owner(101)
	_check(a_owner != b_owner and a_owner._items[1] != b_owner._items[1], "B02 owner and item identities are distinct")
	var a_item := a.get_inventory(101).get_items()[0]
	_check(a.get_inventory(101).remove_item(a_item), "B02 mutate A")
	_check(b.get_inventory(101).size() == 2 and fixture.inventories[0].size() == 2, "B02 mutation does not leak")


func _test_p03b_b03_ids_and_placements() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	var data := result.snapshot.to_dict()
	var owners: Array = data["owners"]
	_check(owners[0]["inventory_order"].size() == 2, "B03 inventory order retained")
	var item_records: Array = owners[0]["items"]
	_check(item_records.size() == 3 and item_records[0]["item_instance_id"] < item_records[1]["item_instance_id"], "B03 detached and duplicate registry retained")
	_check(fixture.equipment[0].get_equipped(EquipmentState.EquipSlot.ARMOR) != null, "B03 equipment slot retained")


func _test_p03b_b04_lifecycle() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	var restored := result.snapshot.instantiate(_p03b_catalogue(fixture.definition)).state
	var inventory := restored.get_inventory(101)
	_check(inventory != null and not inventory.is_closed(), "B04 registered inventory restored open")
	inventory.close()
	_check(inventory.is_closed() and restored.get_owner(101)._inventory_retired, "B04 close retires inventory")
	_check(restored.get_equipment(101) != null and not restored.get_equipment(101).is_closed(), "B04 other facade remains open")


func _test_p03b_b05_modifier_links() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	var data := result.snapshot.to_dict()
	var owner_record: Dictionary = data["owners"][0]
	var runtime: Dictionary = owner_record["items"][0]["effects"][0]
	_check((runtime["modifier_link"] as Array).size() == 1, "B05 active modifier link captured")
	var bad := result.snapshot.to_dict()
	bad["owners"][0]["items"][0]["effects"][0]["modifier_link"][0]["stat_type"] = 0
	var rejected := ItemSimulationSnapshot.from_dict(bad)
	_check(rejected.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B05 wrong stat link rejected")


func _test_p03b_b06_invalid_inputs() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	var bad := result.snapshot.to_dict()
	bad["owners"][0]["owner_unit_id"] = 0
	var rejected := ItemSimulationSnapshot.from_dict(bad)
	_check(rejected.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID and rejected.snapshot == null, "B06 invalid owner rejected before restore")
	var live_bad := fixture.state.get_owners()
	live_bad.append(live_bad[0])
	var invalid_live := ItemSimulationState.new(fixture.board, live_bad, fixture.inventories, fixture.equipment)
	var live_result := ItemSimulationSnapshot.capture(invalid_live, [])
	_check(live_result.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B06 duplicate owner rejected")


func _test_p03b_b07_exact_types() -> void:
	var fixture := _p03b_fixture()
	var unsupported_def := _P03BItemDef.new()
	unsupported_def.id = &"p03b_subclass"
	var stat := StatModifierEffect.new()
	stat.value = 2.0
	unsupported_def.effects = [stat]
	var unit := _p02_unit(103, Vector2i(2, 0), _make_stats())
	var owner := ItemOwnerState.new(unit)
	var inventory := InventoryState.new(owner)
	var item := owner.create_item(unsupported_def)
	_check(item != null and inventory.add_item(item), "B07 subclass fixture created")
	var board := BattleBoard.new(3, 1)
	board.add_unit(unit)
	var state := ItemSimulationState.new(board, [owner], [inventory], [])
	var result := ItemSimulationSnapshot.capture(state, [])
	_check(result.code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "B07 unsupported exact definition rejected")


func _test_p03b_b08_catalogue() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	var missing := result.snapshot.instantiate({})
	_check(missing.code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED and missing.state == null, "B08 missing catalogue entry rejected")
	var changed := ItemDef.new()
	changed.id = fixture.definition.id
	var changed_stat := StatModifierEffect.new()
	changed_stat.value = 99.0
	changed.effects = [changed_stat]
	var conflict := result.snapshot.instantiate(_p03b_catalogue(changed))
	_check(conflict.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID or conflict.code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "B08 catalogue content conflict rejected")


func _test_p03b_b09_reactions() -> void:
	var fixture := _p03b_fixture()
	var before := fixture.state.get_owner(101)._next_effect_id
	var event := {"event_seq": 1, "target_unit_id": 101, "dealt": 1.0}
	var result := ItemReactionCollector.collect_damage(fixture.state, event)
	_check(result.code == ItemReactionResult.Code.OK and not result.descriptions.is_empty(), "B09 active heal descriptions collected")
	var descriptions := result.descriptions
	_check(descriptions[0]["target_unit_id"] == 101 and descriptions[0]["heal_amount"] == 1.5, "B09 description values")
	_check(fixture.state.get_owner(101)._next_effect_id == before and fixture.owners[0].get_owner().vitals.get_hp() == 17.0, "B09 collector has no runtime mutation")
	var zero := ItemReactionCollector.collect_damage(fixture.state, {"event_seq": 2, "target_unit_id": 101, "dealt": 0.0})
	_check(zero.code == ItemReactionResult.Code.OK and zero.descriptions.is_empty(), "B09 zero damage is empty")
	fixture.owners[0].get_owner().vitals.apply_damage(100.0)
	var dead := ItemReactionCollector.collect_damage(fixture.state, {"event_seq": 3, "target_unit_id": 101, "dealt": 1.0})
	_check(dead.code == ItemReactionResult.Code.OK and dead.descriptions.is_empty(), "B09 dead target is empty")


func _test_p03b_b10_dto_ownership() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	var dto := result.snapshot.to_dict()
	dto["owners"].clear()
	_check(result.snapshot.to_dict()["owners"].size() == 2, "B10 snapshot DTO is copied")
	var values := result.snapshot.canonical_values()
	values.clear()
	_check(not result.snapshot.canonical_values().is_empty(), "B10 canonical values are copied")
	var descriptions := ItemReactionCollector.collect_damage(fixture.state, {"event_seq": 4, "target_unit_id": 101, "dealt": 1.0}).descriptions
	if not descriptions.is_empty():
		descriptions[0]["heal_amount"] = 999.0
	var again := ItemReactionCollector.collect_damage(fixture.state, {"event_seq": 4, "target_unit_id": 101, "dealt": 1.0}).descriptions
	_check(again.is_empty() or again[0]["heal_amount"] == 1.5, "B10 reaction DTO is copied")


func _test_p03b_extended() -> void:
	_test_p03b_ext_b02_identity_and_mutation()
	_test_p03b_ext_b03_detached_and_counters()
	_test_p03b_ext_b04_facade_shape()
	_test_p03b_ext_b05_all_modifier_shapes()
	_test_p03b_ext_b06_raw_negative_matrix()
	_test_p03b_ext_b07_unsupported_and_busy()
	_test_p03b_ext_b08_catalogue_keys()
	_test_p03b_ext_b09_b10_reaction_matrix()
	_test_p03b_ext_b03_slots_and_restore_allocator()
	_test_p03b_ext_b04_lifecycle_matrix()
	_test_p03b_ext_b05_link_rejections()
	_test_p03b_ext_b06_graph_rejections()
	_test_p03b_ext_b07_capability_priority()
	_test_p03b_ext_b07_live_priority()
	_test_p03b_ext_b08_cross_owner_catalogue()


func _test_p03b_ext_b02_identity_and_mutation() -> void:
	var fixture := _p03b_fixture()
	var captured := _p03b_capture(fixture).snapshot
	var a := captured.instantiate(_p03b_catalogue(fixture.definition)).state
	var b := captured.instantiate(_p03b_catalogue(fixture.definition)).state
	var lu := fixture.board.get_unit_by_id(101)
	var au := a.get_board().get_unit_by_id(101)
	var bu := b.get_board().get_unit_by_id(101)
	_check(lu != au and lu != bu and au != bu and lu.stats != au.stats and au.stats != bu.stats, "B02 live/A/B unit and StatsBag identities")
	var ls: Stat = lu.stats._stats[StatTypes.StatType.STRENGTH]
	var ass: Stat = au.stats._stats[StatTypes.StatType.STRENGTH]
	var bss: Stat = bu.stats._stats[StatTypes.StatType.STRENGTH]
	_check(ls != ass and ass != bss and ls._modifiers[0] != ass._modifiers[0] and ass._modifiers[0] != bss._modifiers[0], "B02 Stat and modifier identities")
	_check(lu.vitals != au.vitals and au.vitals != bu.vitals and fixture.owners[0] != a.get_owner(101) and a.get_owner(101) != b.get_owner(101), "B02 Vitals and owner identities")
	var li := fixture.inventories[0].get_items()[0]
	var ai := a.get_inventory(101).get_items()[0]
	var bi := b.get_inventory(101).get_items()[0]
	_check(li != ai and ai != bi and li.get_effects()[0] != ai.get_effects()[0] and ai.get_effects()[0] != bi.get_effects()[0], "B02 item and runtime identities")
	_check(li.get_definition() == fixture.definition and ai.get_definition() == fixture.definition and bi.get_definition() == fixture.definition and a.get_board().make_data_provider() != b.get_board().make_data_provider(), "B01/B02 definitions shared while providers are isolated")
	_check(fixture.inventories[0] != a.get_inventory(101) and a.get_inventory(101) != b.get_inventory(101) and fixture.equipment[0] != a.get_equipment(101), "B02 facade identities")
	fixture.board.get_unit_by_id(101).vitals.apply_damage(1.0)
	_check(a.get_board().get_unit_by_id(101).is_alive() and b.get_board().get_unit_by_id(101).is_alive(), "B02 live death does not affect A/B")
	a.get_inventory(101).clear()
	b.get_equipment(101).clear()
	b.get_inventory(101).close()
	_check(fixture.inventories[0].size() == 2 and a.get_inventory(101).size() == 0 and b.get_equipment(101).get_occupied_slots().is_empty(), "B02 live/A/B mutations stay isolated")


func _test_p03b_ext_b03_detached_and_counters() -> void:
	var board := BattleBoard.new(3, 1)
	var unit := _p02_unit(301, Vector2i.ZERO, _make_stats())
	board.add_unit(unit)
	var owner := ItemOwnerState.new(unit)
	var inventory := InventoryState.new(owner)
	var equipment := EquipmentState.new(owner)
	var empty := ItemDef.new(); empty.id = &"p03b_empty"
	var first := owner.create_item(empty)
	var second := owner.create_item(empty)
	_check(first != null and second != null and inventory.add_item(second) and inventory.add_item(first), "B03 reverse inventory order fixture")
	_check(inventory.get_items()[0] == second and inventory.get_items()[1] == first, "B03 inventory_order [2,1]")
	var detached := owner.create_item(empty)
	_check(detached != null and not detached.is_active() and detached._get_placement() == 0, "B03 detached item retained")
	var state := ItemSimulationState.new(board, [owner], [inventory], [equipment])
	var result := ItemSimulationSnapshot.capture(state, [])
	_check(result.code == ItemSnapshotResult.Code.OK, "B03 detached snapshot")
	var data := result.snapshot.to_dict()
	_check(data["owners"][0]["items"].size() == 3 and data["owners"][0]["inventory_order"] == [2, 1], "B03 detached and semantic order encoded")
	var restored := result.snapshot.instantiate({empty.id: empty})
	_check(restored.code == ItemSnapshotResult.Code.OK and restored.state.get_inventory(301).get_items()[0].get_item_instance_id() == 2, "B03 detached restore preserves ids/order")


func _test_p03b_ext_b04_facade_shape() -> void:
	var fixture := _p03b_fixture()
	var result := _p03b_capture(fixture)
	var restored := result.snapshot.instantiate(_p03b_catalogue(fixture.definition)).state
	_check(restored.get_inventory(101) != null and restored.get_equipment(101) != null, "B04 registered facades restored once")
	var dup := ItemSimulationState.new(fixture.board, fixture.owners, [fixture.inventories[0], fixture.inventories[0], fixture.inventories[1]], fixture.equipment)
	_check(ItemSimulationSnapshot.capture(dup, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B04 duplicate facade rejected")
	var missing := ItemSimulationState.new(fixture.board, fixture.owners, [fixture.inventories[0]], fixture.equipment)
	_check(ItemSimulationSnapshot.capture(missing, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B04 missing facade rejected")
	var foreign_owner := ItemOwnerState.new(_p02_unit(999, Vector2i(2, 0), _make_stats()))
	var foreign := InventoryState.new(foreign_owner)
	var foreign_state := ItemSimulationState.new(fixture.board, fixture.owners, [foreign, fixture.inventories[1]], fixture.equipment)
	_check(ItemSimulationSnapshot.capture(foreign_state, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B04 foreign facade rejected")


func _test_p03b_ext_b05_all_modifier_shapes() -> void:
	var board := BattleBoard.new(1, 1)
	var unit := _p02_unit(401, Vector2i.ZERO, _make_stats())
	board.add_unit(unit)
	var owner := ItemOwnerState.new(unit)
	var inventory := InventoryState.new(owner)
	var definition := ItemDef.new(); definition.id = &"p03b_all_ops"
	var effects: Array[ItemEffect] = []
	for stat_type in 7:
		for operation in 3:
			var effect := StatModifierEffect.new()
			effect.stat_type = stat_type as StatTypes.StatType
			effect.operation = operation as StatModifier.Operation
			effect.value = 1.0
			effects.append(effect)
	definition.effects = effects
	var item := owner.create_item(definition)
	_check(item != null and inventory.add_item(item), "B05 seven stats and three operations activate")
	var state := ItemSimulationState.new(board, [owner], [inventory], [])
	var result := ItemSimulationSnapshot.capture(state, [])
	_check(result.code == ItemSnapshotResult.Code.OK and result.snapshot.to_dict()["owners"][0]["items"][0]["effects"].size() == 21, "B05 all modifier occurrences roundtrip")
	var bad := result.snapshot.to_dict()
	bad["owners"][0]["items"][0]["effects"][0]["modifier_link"].clear()
	_check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B05 missing link rejected")
	bad = result.snapshot.to_dict()
	bad["owners"][0]["items"][0]["effects"][0]["modifier_link"][0]["local_slot"] = -1
	_check(ItemSimulationSnapshot.from_dict(bad).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B05 invalid local slot rejected")


func _test_p03b_ext_b06_raw_negative_matrix() -> void:
	var fixture := _p03b_fixture()
	var snapshot := _p03b_capture(fixture).snapshot
	var cases: Array[Dictionary] = []
	var duplicate := snapshot.to_dict(); duplicate["owners"].append(duplicate["owners"][0]); cases.append(duplicate)
	var bad_type := snapshot.to_dict(); bad_type["schema_version"] = 1.0; cases.append(bad_type)
	var bad_counter := snapshot.to_dict(); bad_counter["owners"][0]["next_item_id"] = ItemOwnerState.MAX_ID + 1; cases.append(bad_counter)
	var bad_float := snapshot.to_dict(); bad_float["owners"][0]["items"][0]["effects"][0]["value"] = NAN; cases.append(bad_float)
	var rejected := 0
	for data in cases:
		if ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID: rejected += 1
	_check(rejected == cases.size(), "B06 duplicate/type/counter/nonfinite matrix rejected")
	var board_unit := _p02_unit(101, Vector2i(0, 0), _make_stats())
	var forged := _p02_unit(101, Vector2i(0, 0), _make_stats())
	var board := BattleBoard.new(3, 1); board.add_unit(board_unit)
	var forged_owner := ItemOwnerState.new(forged)
	var forged_inv := InventoryState.new(forged_owner)
	_check(ItemSimulationSnapshot.capture(ItemSimulationState.new(board, [forged_owner], [forged_inv], []), []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B06 forged same-id unit identity rejected")


func _test_p03b_ext_b07_unsupported_and_busy() -> void:
	var fixture := _p03b_fixture()
	var unsupported := _p03b_capture(fixture).snapshot.to_dict()
	unsupported["scope"] = "unknown"
	_check(ItemSimulationSnapshot.from_dict(unsupported).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "B07 unknown scope unsupported")
	var external := ItemSimulationSnapshot.capture(fixture.state, [&"z", &"a", &"a"])
	_check(external.code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED and external.unsupported_ids == [&"a", &"z"], "B07 external unsupported ids sorted unique")
	# Lambda захватывает скаляры по значению; mutable контейнер сохраняет результат callback.
	var busy_codes: Array[int] = [ItemSnapshotResult.Code.OK, ItemReactionResult.Code.OK]
	var callback := func(_item: ItemInstance) -> void:
		busy_codes[0] = ItemSimulationSnapshot.capture(fixture.state, []).code
		busy_codes[1] = ItemReactionCollector.collect_damage(fixture.state, {"event_seq": 30, "target_unit_id": 101, "dealt": 1.0}).code
	fixture.inventories[0].item_added.connect(callback)
	var item := fixture.owners[0].create_item(fixture.definition)
	fixture.inventories[0].add_item(item)
	fixture.inventories[0].item_added.disconnect(callback)
	_check(busy_codes[0] == ItemSnapshotResult.Code.SNAPSHOT_BUSY and busy_codes[1] == ItemReactionResult.Code.BUSY, "B07 capture and collect during item_added are busy")


func _test_p03b_ext_b08_catalogue_keys() -> void:
	var fixture := _p03b_fixture()
	var snapshot := _p03b_capture(fixture).snapshot
	var string_key := {String(fixture.definition.id): fixture.definition}
	var result := snapshot.instantiate(string_key)
	_check(result.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B08 String catalogue key rejected")
	var extra := _p03b_catalogue(fixture.definition)
	var unused := ItemDef.new(); unused.id = &"unused"
	extra[unused.id] = unused
	var with_extra := snapshot.instantiate(extra)
	_check(with_extra.code == ItemSnapshotResult.Code.OK, "B08 unused catalogue entry ignored")


func _test_p03b_ext_b09_b10_reaction_matrix() -> void:
	var fixture := _p03b_fixture()
	var event := {"event_seq": 22, "target_unit_id": 101, "dealt": 1.0}
	fixture.board.get_unit_by_id(101).vitals.set_hp(fixture.board.get_unit_by_id(101).vitals.get_hp_max())
	var before_hp := fixture.board.get_unit_by_id(101).vitals.get_hp()
	var before_counter := fixture.owners[0]._next_effect_id
	var result := ItemReactionCollector.collect_damage(fixture.state, event)
	var descriptions := result.descriptions
	_check(result.code == ItemReactionResult.Code.OK and descriptions.size() == 6, "B09 six target-owner repeated heal descriptions ordered")
	var ordered := true
	var seen: Dictionary = {}
	for i in descriptions.size():
		var current: Dictionary = descriptions[i]
		var key := "%d/%d/%d" % [current["owner_unit_id"], current["item_instance_id"], current["effect_instance_id"]]
		ordered = ordered and not seen.has(key)
		seen[key] = true
	_check(ordered and fixture.board.get_unit_by_id(101).vitals.get_hp() == before_hp and fixture.owners[0]._next_effect_id == before_counter, "B09 descriptions unique and collector pure")
	_check(not descriptions.is_empty(), "B09 full HP still yields deferred descriptions")
	var bad_target := ItemReactionCollector.collect_damage(fixture.state, {"event_seq": 23, "target_unit_id": 999, "dealt": 1.0})
	_check(bad_target.code == ItemReactionResult.Code.INVALID, "B09 unknown target rejected")
	var bad_event := ItemReactionCollector.collect_damage(fixture.state, {"event_seq": 0, "target_unit_id": 101, "dealt": 1.0})
	_check(bad_event.code == ItemReactionResult.Code.INVALID, "B09 bad event rejected")
	var removed := fixture.inventories[0].get_items()[0]
	_check(fixture.inventories[0].remove_item(removed), "B10 remove before recollect")
	var after_remove := ItemReactionCollector.collect_damage(fixture.state, event)
	_check(after_remove.descriptions.size() == 4, "B10 removed item reactions disappear")
	fixture.owners[0].close()
	_check(ItemReactionCollector.collect_damage(fixture.state, event).descriptions.is_empty(), "B10 closed owner reactions disappear")
	var board := BattleBoard.new(1, 1)
	var unit := _p02_unit(901, Vector2i.ZERO, _make_stats())
	board.add_unit(unit)
	var owner := ItemOwnerState.new(unit)
	var inventory := InventoryState.new(owner)
	var definition := ItemDef.new(); definition.id = &"p03b_zero_heal"
	var heal := HealOnDamageEffect.new(); heal.heal_amount = 0.0
	definition.effects = [heal]
	inventory.add_item(owner.create_item(definition))
	var zero_state := ItemSimulationState.new(board, [owner], [inventory], [])
	var zero_amount := ItemReactionCollector.collect_damage(zero_state, {"event_seq": 24, "target_unit_id": 901, "dealt": 1.0})
	_check(zero_amount.code == ItemReactionResult.Code.OK and zero_amount.descriptions.size() == 1 and zero_amount.descriptions[0]["heal_amount"] == 0.0, "B09 zero heal amount remains a deferred description")


func _test_p03b_ext_b03_slots_and_restore_allocator() -> void:
	var board := BattleBoard.new(1, 1)
	var unit := _p02_unit(302, Vector2i.ZERO, _make_stats())
	board.add_unit(unit)
	var owner := ItemOwnerState.new(unit)
	var equipment := EquipmentState.new(owner)
	var definition := ItemDef.new()
	definition.id = &"p03b_slots"
	var one := owner.create_item(definition)
	var two := owner.create_item(definition)
	var three := owner.create_item(definition)
	_check(equipment.equip(EquipmentState.EquipSlot.TRINKET, one) and equipment.equip(EquipmentState.EquipSlot.WEAPON, three) and equipment.equip(EquipmentState.EquipSlot.ARMOR, two), "B03 all slots accept order unlike item ids")
	var snapshot := ItemSimulationSnapshot.capture(ItemSimulationState.new(board, [owner], [], [equipment]), [])
	var records: Array = snapshot.snapshot.to_dict()["owners"][0]["items"]
	_check(records[0]["placement"] == 102 and records[1]["placement"] == 101 and records[2]["placement"] == 100, "B03 slot placements are bound to items, not creation order")
	var restored := snapshot.snapshot.instantiate({definition.id: definition}).state
	var original_next := owner.create_item(definition)
	var restored_next := restored.get_owner(302).create_item(definition)
	_check(original_next != null and restored_next != null and original_next.get_item_instance_id() == restored_next.get_item_instance_id() and original_next.get_effects().size() == restored_next.get_effects().size(), "B03 restore then create preserves allocators")
	var data := snapshot.snapshot.to_dict()
	data["owners"][0]["items"][0]["item_instance_id"] = ItemOwnerState.MAX_ID - 1
	data["owners"][0]["items"][0]["placement"] = 0
	data["owners"][0]["items"][0]["active"] = false
	data["owners"][0]["next_item_id"] = ItemOwnerState.MAX_ID
	data["owners"][0]["items"][1]["placement"] = 0
	data["owners"][0]["items"][1]["active"] = false
	data["owners"][0]["items"][2]["placement"] = 0
	data["owners"][0]["items"][2]["active"] = false
	data["owners"][0]["inventory_order"] = []
	var high := ItemSimulationSnapshot.from_dict(data)
	var high_state := high.snapshot.instantiate({definition.id: definition}).state if high.snapshot != null else null
	_check(high.code == ItemSnapshotResult.Code.OK and high_state != null and high_state.get_owner(302).create_item(definition) == null, "B03 MAX-1 item id and exhausted counter restore exactly")


func _test_p03b_ext_b04_lifecycle_matrix() -> void:
	for inventory_mode in [0, 1, 2]:
		for equipment_mode in [0, 1, 2]:
			var matrix_board := BattleBoard.new(1, 1)
			var matrix_unit := _p02_unit(410 + inventory_mode * 3 + equipment_mode, Vector2i.ZERO, _make_stats())
			matrix_board.add_unit(matrix_unit)
			var matrix_owner := ItemOwnerState.new(matrix_unit)
			var matrix_inventories: Array[InventoryState] = []
			var matrix_equipment: Array[EquipmentState] = []
			if inventory_mode == 1:
				matrix_inventories.append(InventoryState.new(matrix_owner))
			elif inventory_mode == 2:
				InventoryState.new(matrix_owner).close()
			if equipment_mode == 1:
				matrix_equipment.append(EquipmentState.new(matrix_owner))
			elif equipment_mode == 2:
				EquipmentState.new(matrix_owner).close()
			var matrix_snapshot := ItemSimulationSnapshot.capture(ItemSimulationState.new(matrix_board, [matrix_owner], matrix_inventories, matrix_equipment), [])
			var matrix_state := matrix_snapshot.snapshot.instantiate({}).state if matrix_snapshot.snapshot != null else null
			var matrix_id := matrix_unit.id
			var inventory_ok: bool = matrix_state != null and (matrix_state.get_inventory(matrix_id) != null) == (inventory_mode == 1)
			var equipment_ok: bool = matrix_state != null and (matrix_state.get_equipment(matrix_id) != null) == (equipment_mode == 1)
			if matrix_state != null and inventory_mode != 1:
				inventory_ok = inventory_ok and (not InventoryState.new(matrix_state.get_owner(matrix_id)).is_closed()) == (inventory_mode == 0)
			if matrix_state != null and equipment_mode != 1:
				equipment_ok = equipment_ok and (not EquipmentState.new(matrix_state.get_owner(matrix_id)).is_closed()) == (equipment_mode == 0)
			_check(matrix_snapshot.code == ItemSnapshotResult.Code.OK and inventory_ok and equipment_ok, "B04 lifecycle matrix inventory%d equipment%d" % [inventory_mode, equipment_mode])
	var board := BattleBoard.new(1, 1)
	var unit := _p02_unit(403, Vector2i.ZERO, _make_stats())
	board.add_unit(unit)
	var never := ItemOwnerState.new(unit)
	var never_state := ItemSimulationState.new(board, [never], [], [])
	var never_restored := ItemSimulationSnapshot.capture(never_state, []).snapshot.instantiate({}).state
	_check(never_restored.get_inventory(403) == null and never_restored.get_equipment(403) == null and not InventoryState.new(never_restored.get_owner(403)).is_closed(), "B04 never-created remains creatable without facade")
	var retired_board := BattleBoard.new(1, 1)
	var retired_unit := _p02_unit(404, Vector2i.ZERO, _make_stats())
	retired_board.add_unit(retired_unit)
	var retired_owner := ItemOwnerState.new(retired_unit)
	var retired_inventory := InventoryState.new(retired_owner)
	retired_inventory.close()
	var retired_state := ItemSimulationState.new(retired_board, [retired_owner], [], [])
	var retired_restored := ItemSimulationSnapshot.capture(retired_state, []).snapshot.instantiate({}).state
	_check(retired_restored.get_inventory(404) == null and InventoryState.new(retired_restored.get_owner(404)).is_closed(), "B04 retired inventory never reopens")
	var closed_board := BattleBoard.new(1, 1)
	var closed_unit := _p02_unit(405, Vector2i.ZERO, _make_stats())
	closed_board.add_unit(closed_unit)
	var closed_owner := ItemOwnerState.new(closed_unit)
	var closed_inventory := InventoryState.new(closed_owner)
	var closed_definition := ItemDef.new(); closed_definition.id = &"p03b_closed"
	var held := closed_owner.create_item(closed_definition)
	closed_inventory.add_item(held)
	closed_owner.close()
	var closed_state := ItemSimulationState.new(closed_board, [closed_owner], [], [])
	var closed_result := ItemSimulationSnapshot.capture(closed_state, [])
	var closed_restored := closed_result.snapshot.instantiate({closed_definition.id: closed_definition}).state if closed_result.snapshot != null else null
	_check(closed_result.code == ItemSnapshotResult.Code.OK and closed_restored != null and closed_restored.get_inventory(405) == null and closed_restored.get_equipment(405) == null and not held.is_active(), "B04 closed owner restores without retired facades")


func _test_p03b_ext_b05_link_rejections() -> void:
	var fixture := _p03b_fixture()
	var base := _p03b_capture(fixture).snapshot
	var mutations: Array[Dictionary] = []
	var duplicate := base.to_dict()
	duplicate["owners"][0]["items"][0]["effects"][0]["modifier_link"].append(duplicate["owners"][0]["items"][0]["effects"][0]["modifier_link"][0].duplicate())
	mutations.append(duplicate)
	var op := base.to_dict(); op["owners"][0]["items"][0]["effects"][0]["operation"] = StatModifier.Operation.MULTIPLY; mutations.append(op)
	var value := base.to_dict(); value["owners"][0]["items"][0]["effects"][0]["value"] = 91.0; mutations.append(value)
	var source := base.to_dict(); source["owners"][0]["items"][0]["effects"][0]["source_key"] = "p03a/o102/i1/e1"; mutations.append(source)
	var inactive := base.to_dict(); inactive["owners"][0]["items"][0]["effects"][0]["active"] = false; mutations.append(inactive)
	var rejected := 0
	for data in mutations:
		if ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID:
			rejected += 1
	_check(rejected == mutations.size(), "B05 duplicate/op/value/foreign-source/inactive links rejected")
	var orphan := base.to_dict()
	var stat_records: Array = orphan["board_snapshot"]["board"]["units"][0]["stats"]["stats"]
	for entry: Dictionary in stat_records:
		if entry["stat_type"] == StatTypes.StatType.STRENGTH:
			var modifier: Dictionary = entry["stat"]["modifiers"][0].duplicate(true)
			modifier["source_id"] = "p03a/o101/i999/e999"
			entry["stat"]["modifiers"].append(modifier)
	_check(ItemSimulationSnapshot.from_dict(orphan).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B05 orphan reserved source rejected")


func _test_p03b_ext_b06_graph_rejections() -> void:
	var snapshot := _p03b_capture(_p03b_fixture()).snapshot
	var cases: Array[Dictionary] = []
	var duplicate_item := snapshot.to_dict(); duplicate_item["owners"][0]["items"].append(duplicate_item["owners"][0]["items"][0].duplicate(true)); cases.append(duplicate_item)
	var duplicate_effect := snapshot.to_dict(); duplicate_effect["owners"][0]["items"][0]["effects"][1]["effect_instance_id"] = duplicate_effect["owners"][0]["items"][0]["effects"][0]["effect_instance_id"]; cases.append(duplicate_effect)
	var duplicate_index := snapshot.to_dict(); duplicate_index["owners"][0]["items"][0]["effects"][1]["effect_index"] = 0; cases.append(duplicate_index)
	var duplicate_order := snapshot.to_dict(); duplicate_order["owners"][0]["inventory_order"].append(duplicate_order["owners"][0]["inventory_order"][0]); cases.append(duplicate_order)
	var sentinel_item := snapshot.to_dict(); sentinel_item["owners"][0]["items"][0]["item_instance_id"] = ItemOwnerState.MAX_ID; cases.append(sentinel_item)
	var bad_placement := snapshot.to_dict(); bad_placement["owners"][0]["items"][0]["placement"] = 99; cases.append(bad_placement)
	var wrong_active := snapshot.to_dict(); wrong_active["owners"][0]["items"][0]["active"] = false; cases.append(wrong_active)
	var rejected := 0
	for data in cases:
		if ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID:
			rejected += 1
	_check(rejected == cases.size(), "B06 duplicate ids/indices/order, sentinel and placement matrix rejected")
	var fixture := _p03b_fixture()
	var missing := ItemSimulationState.new(fixture.board, [fixture.owners[0]], [fixture.inventories[0]], [fixture.equipment[0]])
	_check(ItemSimulationSnapshot.capture(missing, []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B06 missing owner for registered board unit rejected")
	var corpse_board := BattleBoard.new(1, 1)
	var corpse := _p02_unit(603, Vector2i.ZERO, _make_stats(), false)
	corpse_board.add_unit(corpse)
	_check(ItemSimulationSnapshot.capture(ItemSimulationState.new(corpse_board, [], [], []), []).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B06 missing owner for corpse rejected")


func _test_p03b_ext_b07_capability_priority() -> void:
	var snapshot := _p03b_capture(_p03b_fixture()).snapshot
	var unknown_kind := snapshot.to_dict(); unknown_kind["owners"][0]["definitions"][0]["effects"][0]["kind"] = "other"
	_check(ItemSimulationSnapshot.from_dict(unknown_kind).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "B07 unknown effect kind is unsupported")
	var unknown_trigger := snapshot.to_dict(); unknown_trigger["owners"][0]["definitions"][0]["effects"][1]["trigger_event"] = 7
	_check(ItemSimulationSnapshot.from_dict(unknown_trigger).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "B07 unknown trigger is unsupported")
	var malformed_unknown := snapshot.to_dict(); malformed_unknown["schema_version"] = 1.0; malformed_unknown["scope"] = "other"
	_check(ItemSimulationSnapshot.from_dict(malformed_unknown).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B07 raw shape precedes unsupported capability")
	var fixture := _p03b_fixture()
	var item := fixture.inventories[0].get_items()[0]
	var runtime := _P03BHealRuntime.new(101, item.get_item_instance_id(), 2, 1, 1.5, TriggeredEffect.TriggerEvent.UNIT_DAMAGED)
	runtime._active = true
	item._effects[1] = runtime
	_check(ItemSimulationSnapshot.capture(fixture.state, []).code == ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "B07 runtime subclass is unsupported")


func _test_p03b_ext_b07_live_priority() -> void:
	var board := BattleBoard.new(2, 1)
	var first_unit := _p02_unit(701, Vector2i(0, 0), _make_stats())
	var second_unit := _p02_unit(702, Vector2i(1, 0), _make_stats())
	board.add_unit(first_unit)
	board.add_unit(second_unit)
	var early_owner := ItemOwnerState.new(first_unit)
	var unsupported := _P03BItemDef.new(); unsupported.id = &"p03b_live_unsupported"
	unsupported.effects = [HealOnDamageEffect.new()]
	_check(early_owner.create_item(unsupported) != null, "B07 live priority unsupported fixture")
	var late_owner := ItemOwnerState.new(second_unit)
	var malformed := ItemDef.new(); malformed.id = &"p03b_live_nan"
	var malformed_stat := StatModifierEffect.new(); malformed_stat.value = NAN
	malformed.effects = [malformed_stat]
	# Повреждение registry позднего owner должно предшествовать раннему capability gap.
	late_owner._definitions[malformed.id] = malformed
	var result := ItemSimulationSnapshot.capture(ItemSimulationState.new(board, [early_owner, late_owner], [], []), [])
	_check(result.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B07 live invalid data precedes earlier unsupported capability")


func _test_p03b_ext_b08_cross_owner_catalogue() -> void:
	var fixture := _p03b_fixture()
	var data := _p03b_capture(fixture).snapshot.to_dict()
	data["owners"][1]["definitions"][0]["effects"][0]["value"] = 33.0
	_check(ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B08 same id descriptors across owners must agree")
	var snapshot := _p03b_capture(fixture).snapshot
	var renamed := ItemDef.new()
	renamed.id = &"other"
	renamed.effects = fixture.definition.effects
	_check(snapshot.instantiate({fixture.definition.id: renamed}).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B08 catalogue key and definition id must agree")
	var a := snapshot.instantiate(_p03b_catalogue(fixture.definition)).state
	var b := snapshot.instantiate(_p03b_catalogue(fixture.definition)).state
	var event := {"event_seq": 77, "target_unit_id": 101, "dealt": 1.0}
	_check(ItemReactionCollector.collect_damage(fixture.state, event).descriptions == ItemReactionCollector.collect_damage(a, event).descriptions and ItemReactionCollector.collect_damage(a, event).descriptions == ItemReactionCollector.collect_damage(b, event).descriptions, "B09/B10 live and restored descriptions match exactly")

# --- P02: независимые value-снимки, A01–A12 -------------------------------

func _p02_unit(id_value: int, cell_value: Vector2i, bag: StatsBag, alive: bool = true) -> UnitState:
	# Фикстура не вызывает create: проверка снимка не должна зависеть от allocator.
	var unit := UnitState.new()
	unit.id = id_value
	unit.cell = cell_value
	unit.faction = Faction.Type.PLAYER if alive else Faction.Type.ENEMY
	unit.stats = bag
	unit.vitals = Vitals.from_dict({"hp": 17.0 if alive else 0.0, "balance": 3.0, "is_alive": alive}, bag)
	unit.debug_name = "Юнит %d" % id_value
	unit.move_points_left = 2.5
	unit.has_attacked = true
	return unit


func _p02_board() -> BattleBoard:
	var board := BattleBoard.new(3, 2)
	var heights: Array[int] = [0, 1, -2, 3, 4, 5]
	var terrain: Array[int] = [0, 1, 2, 3, 0, 0]
	for i in 6:
		board.set_height(Vector2i(i % 3, i / 3), heights[i])
		board.set_terrain(Vector2i(i % 3, i / 3), terrain[i] as TerrainType.Type)
	var bag := StatsBag.new()
	var bases: Array[float] = [20.0, 0.0, 10.0, 10.0, 2.0, 5.0, 0.0]
	for i in bases.size():
		bag.set_base_value(i as StatTypes.StatType, bases[i])
	var shared := StatModifier.new(&"same", StatModifier.Operation.ADD_FLAT, 2.0)
	bag.add_modifier(StatTypes.StatType.STRENGTH, shared)
	bag.add_modifier(StatTypes.StatType.STRENGTH, shared)
	bag.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"removed", StatModifier.Operation.ADD_FLAT, 9.0))
	bag.remove_modifiers_by_source(&"removed")
	bag.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"", StatModifier.Operation.ADD_PERCENT, 0.5))
	bag.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"", StatModifier.Operation.MULTIPLY, 2.0))
	bag.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"Я", StatModifier.Operation.ADD_FLAT, 1.0))
	bag.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"А", StatModifier.Operation.ADD_FLAT, 3.0))
	var cleared: Stat = bag._stats[StatTypes.StatType.INITIATIVE]
	cleared.add_modifier(StatModifier.new(&"old", StatModifier.Operation.ADD_FLAT, 1.0))
	cleared.clear_modifiers()
	var corpse := _p02_unit(10, Vector2i.ZERO, StatsBag.new(), false)
	board.add_unit(corpse)
	board.add_unit(_p02_unit(2, Vector2i.ZERO, bag))
	board.add_unit(_p02_unit(20, Vector2i(1, 1), _make_stats()))
	board.set_height(Vector2i.ZERO, 7)
	board.board_version = 40
	return board


func _p02_capture(board: BattleBoard) -> SimulationSnapshot:
	var result := SimulationSnapshot.capture_board(board, [])
	_check(result.code == BoardSnapshotResult.Code.OK and result.snapshot != null, "P02 capture fixture", result.reason)
	return result.snapshot


func _p02_same(a: SimulationSnapshot, b: SimulationSnapshot, label: String) -> void:
	_check(a.to_dict() == b.to_dict(), label + " values")
	_check(a.canonical_values() == b.canonical_values(), label + " canonical values")
	_check(a.canonical_bytes() == b.canonical_bytes() and a.fingerprint() == b.fingerprint(), label + " bytes/hash")


func _p02_strength(data: Dictionary) -> Dictionary:
	return data["board"]["units"][0]["stats"]["stats"][3]["stat"]


func _p02_expect(data: Dictionary, code: BoardSnapshotResult.Code, label: String) -> void:
	var before := UnitId.get_counter()
	var result := SimulationSnapshot.from_dict(data)
	_check(result.code == code and result.snapshot == null and not result.reason.is_empty(), label, result.reason)
	_check(UnitId.get_counter() == before, label + " preserves UnitId")
	if code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED:
		_check(not result.unsupported_ids.is_empty(), label + " diagnostic ids")


func _p02_set(data: Dictionary, path: Array, value: Variant) -> void:
	var current: Variant = data
	for i in path.size() - 1:
		current = current[path[i]]
	current[path.back()] = value


func _p02_reverse_maps(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.reverse()
		for key in keys:
			result[key] = _p02_reverse_maps(value[key])
		return result
	if value is Array:
		var result: Array = []
		for child in value:
			result.append(_p02_reverse_maps(child))
		return result
	return value


func _test_p02_a01_roundtrip() -> void:
	var live := _p02_board()
	var snapshot := _p02_capture(live)
	var imported := SimulationSnapshot.from_dict(snapshot.to_dict())
	_check(imported.code == BoardSnapshotResult.Code.OK, "A01 envelope import")
	var a := imported.snapshot.instantiate_board()
	var b := imported.snapshot.instantiate_board()
	_p02_same(snapshot, _p02_capture(a), "A01 clone A roundtrip")
	_p02_same(snapshot, _p02_capture(b), "A01 clone B roundtrip")
	var u := a.get_unit_by_id(2)
	_check(a.width == 3 and a.height == 2 and a.board_version == 40, "A01 dimensions/version literals")
	_check(Array(a._heights) == [7, 1, -2, 3, 4, 5] and Array(a._terrain) == [0, 1, 2, 3, 0, 0], "A01 row-major heights and all terrain")
	_check(u.id == 2 and u.faction == Faction.Type.PLAYER and u.cell == Vector2i.ZERO and u.height == 0 and u.debug_name == "Юнит 2", "A01 unit fields literals")
	_check(u.vitals.get_hp() == 17.0 and u.vitals.get_balance() == 3.0 and u.move_points_left == 2.5 and u.has_attacked and u.is_alive(), "A01 resources preserved literally")
	_check(u.stats.get_declared_types().size() == 7 and u.stats.has_stat(StatTypes.StatType.ARMOR) and u.get_stat(StatTypes.StatType.ARMOR) == 0.0, "A01 all declared stats and declared zero")
	_check(not a.get_unit_by_id(10).stats.has_stat(StatTypes.StatType.ARMOR), "A01 absent stat differs from declared zero")
	_check(not a.get_unit_by_id(10).is_alive() and a.get_unit_by_id(10).cell == u.cell and a.occupant_at(u.cell) == u, "A01 corpse and living share cell")


func _test_p02_a02_modifiers() -> void:
	var live := _p02_board()
	var snapshot := _p02_capture(live)
	var data := _p02_strength(snapshot.to_dict())
	var clone := snapshot.instantiate_board()
	var stat: Stat = clone.get_unit_by_id(2).stats._stats[StatTypes.StatType.STRENGTH]
	_check(data["base_value"] == 10.0 and data["next_modifier_slot"] == 7 and data["modifiers"].size() == 6 and stat.get_value() == 54.0, "A02 base multiplicity slots and all operations")
	_check(stat._modifier_slots == [0, 1, 3, 4, 5, 6], "A02 deleted slot stays absent, evaluation order restored")
	_check(stat._modifiers[0] != stat._modifiers[1] and stat._modifiers[0].source_id == &"same" and stat._modifiers[1].source_id == &"same", "A02 repeated Resource restored per occurrence")
	_check(data["modifiers"][0]["source_id"] == "" and data["modifiers"][1]["source_id"] == "", "A02 duplicate empty sources retained")
	stat.add_modifier(StatModifier.new(&"next", StatModifier.Operation.ADD_FLAT, 1.0))
	_check(stat._modifier_slots.back() == 7 and stat._next_modifier_slot == 8, "A02 add continues saved local allocator")
	_check(stat.remove_modifiers_by_source(&"same") and stat._modifier_slots == [3, 4, 5, 6, 7] and stat.get_value() == 45.0, "A02 remove-by-source removes both occurrences")
	var cleared: Stat = clone.get_unit_by_id(2).stats._stats[StatTypes.StatType.INITIATIVE]
	_check(cleared.get_modifier_count() == 0 and cleared._next_modifier_slot == 1, "A02 empty cleared Stat retains counter")
	cleared.add_modifier(StatModifier.new(&"after-clear", StatModifier.Operation.ADD_FLAT, 2.0))
	_check(cleared._modifier_slots == [1], "A02 next add after restored clear")


func _test_p02_a03_canonical_order() -> void:
	var live := _p02_board()
	var stat: Stat = live.get_unit_by_id(2).stats._stats[StatTypes.StatType.STRENGTH]
	stat.clear_modifiers()
	stat.base_value = 0.0
	stat.add_modifier(StatModifier.new(&"z", StatModifier.Operation.ADD_FLAT, 1e16))
	stat.add_modifier(StatModifier.new(&"a", StatModifier.Operation.ADD_FLAT, -1e16))
	stat.add_modifier(StatModifier.new(&"m", StatModifier.Operation.ADD_FLAT, 1.0))
	_check(stat.get_value() == 1.0, "A03 live float order exact 1")
	var snapshot := _p02_capture(live)
	var data := snapshot.to_dict()
	_p02_strength(data)["modifiers"].reverse()
	var reordered := SimulationSnapshot.from_dict(data).snapshot
	_p02_same(snapshot, reordered, "A03 record permutation preserves state")
	_check(reordered.instantiate_board().get_unit_by_id(2).get_stat(StatTypes.StatType.STRENGTH) == 1.0, "A03 restore keeps arithmetic order")
	data = snapshot.to_dict()
	var records: Array = _p02_strength(data)["modifiers"]
	for i in records.size():
		records[i]["evaluation_order"] = i
	var changed := SimulationSnapshot.from_dict(data).snapshot
	_check(changed.instantiate_board().get_unit_by_id(2).get_stat(StatTypes.StatType.STRENGTH) == 0.0, "A03 evaluation permutation changes exact result")
	_check(changed.canonical_values() != snapshot.canonical_values() and changed.fingerprint() != snapshot.fingerprint(), "A03 evaluation order is semantic state")


func _p02_mutate(board: BattleBoard) -> void:
	var u := board.get_unit_by_id(2)
	var stat: Stat = u.stats._stats[StatTypes.StatType.STRENGTH]
	stat._modifiers[0].value += 5.0
	u.stats.set_base_value(StatTypes.StatType.STRENGTH, 30.0)
	u.stats.remove_modifiers_by_source(&"А")
	u.stats.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"new", StatModifier.Operation.MULTIPLY, 0.5))
	u.vitals.apply_damage(2.0)
	u.vitals.set_balance(9.0)
	u.move_points_left = 0.25
	u.has_attacked = false
	board.set_terrain(Vector2i(2, 1), TerrainType.Type.HAZARD)
	board.set_height(Vector2i(2, 1), 12)
	board.clear_occupancy(u)
	board.move_unit(u, Vector2i(2, 1))


func _test_p02_a04_isolation() -> void:
	var live := _p02_board()
	var snapshot := _p02_capture(live)
	var a := snapshot.instantiate_board()
	var b := snapshot.instantiate_board()
	var lu := live.get_unit_by_id(2)
	var au := a.get_unit_by_id(2)
	var bu := b.get_unit_by_id(2)
	_check(lu != au and lu != bu and au != bu and lu.stats != au.stats and lu.stats != bu.stats and au.stats != bu.stats and lu.vitals != au.vitals and au.vitals != bu.vitals, "A04 Unit Bag Vitals identities across all three")
	var ls: Stat = lu.stats._stats[StatTypes.StatType.STRENGTH]
	var sa: Stat = au.stats._stats[StatTypes.StatType.STRENGTH]
	var sb: Stat = bu.stats._stats[StatTypes.StatType.STRENGTH]
	_check(ls != sa and ls != sb and sa != sb, "A04 Stat identities across all three")
	for i in ls._modifiers.size():
		_check(ls._modifiers[i] != sa._modifiers[i] and ls._modifiers[i] != sb._modifiers[i] and sa._modifiers[i] != sb._modifiers[i], "A04 modifier occurrence %d independent" % i)
	_p02_mutate(live)
	_p02_same(snapshot, _p02_capture(a), "A04 live mutation leaves A")
	_p02_same(snapshot, _p02_capture(b), "A04 live mutation leaves B")
	var live_after := _p02_capture(live)
	_p02_mutate(a)
	_p02_same(live_after, _p02_capture(live), "A04 clone A mutation leaves live")
	_p02_same(snapshot, _p02_capture(b), "A04 clone A mutation leaves B and snapshot")
	_check(a.get_unit_by_id(2).cell == Vector2i(2, 1) and a.occupant_at(Vector2i(2, 1)) == au, "A04 clone mutation uses real board move")


func _test_p02_a05_vitals_owner() -> void:
	var live := _p02_board()
	var snapshot := _p02_capture(live)
	var a := snapshot.instantiate_board()
	var b := snapshot.instantiate_board()
	var au := a.get_unit_by_id(2)
	au.stats.set_base_value(StatTypes.StatType.HP_MAX, 30.0)
	au.vitals.heal(100.0)
	_check(au.vitals.get_hp() == 30.0 and au.vitals._stats == au.stats, "A05 heal uses A bag")
	_check(live.get_unit_by_id(2).vitals.get_hp() == 17.0 and b.get_unit_by_id(2).vitals.get_hp() == 17.0 and b.get_unit_by_id(2).vitals.get_hp_max() == 20.0, "A05 live and B vitals unchanged")
	var u := live.get_unit_by_id(2)
	u.stats.set_base_value(StatTypes.StatType.HP_MAX, 5.0)
	u.vitals.set_balance(500.0)
	var clone := _p02_capture(live).instantiate_board().get_unit_by_id(2)
	_check(clone.vitals.get_hp() == 17.0 and clone.vitals.get_hp_max() == 5.0 and clone.vitals.get_balance() == 500.0, "A05 over-max resources not clamped")
	u.vitals.set_hp(0.0)
	clone = _p02_capture(live).instantiate_board().get_unit_by_id(2)
	_check(clone.is_alive() and clone.vitals.get_hp() == 0.0, "A05 alive is independent of HP")


func _test_p02_a06_unit_id() -> void:
	var before := UnitId.get_counter()
	var board := BattleBoard.new(1, 1)
	board.add_unit(_p02_unit(before + 100000, Vector2i.ZERO, _make_stats()))
	for i in 3:
		var snap := _p02_capture(board)
		var imported := SimulationSnapshot.from_dict(snap.to_dict())
		_check(imported.snapshot.instantiate_board().get_all_units()[0].id == before + 100000, "A06 high id retained")
		var bad := snap.to_dict()
		bad["board"]["units"][0]["id"] = 0
		_p02_expect(bad, BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A06 invalid import")
	_check(UnitId.get_counter() == before, "A06 capture/import/instantiate never advance counter")
	_check(UnitId.next() == before and UnitId.get_counter() == before + 1, "A06 next explicit allocation advances exactly once")


func _test_p02_a07_subscriptions() -> void:
	var live := _p02_board()
	var counts: Dictionary = {"board": 0, "move": 0, "stat": 0, "hp": 0, "balance": 0, "died": 0}
	live.board_changed.connect(func() -> void: counts["board"] += 1)
	live.unit_position_changed.connect(func(_u: UnitState, _a: Vector2i, _b: Vector2i) -> void: counts["move"] += 1)
	var u := live.get_unit_by_id(2)
	u.stats.stat_changed.connect(func(_s: StatTypes.StatType, _a: float, _b: float) -> void: counts["stat"] += 1)
	u.vitals.hp_changed.connect(func(_a: float, _b: float) -> void: counts["hp"] += 1)
	u.vitals.balance_changed.connect(func(_a: float, _b: float) -> void: counts["balance"] += 1)
	u.vitals.died.connect(func() -> void: counts["died"] += 1)
	var snap := _p02_capture(live)
	var imported := SimulationSnapshot.from_dict(snap.to_dict()).snapshot
	var a := imported.instantiate_board()
	var b := imported.instantiate_board()
	var au := a.get_unit_by_id(2)
	_check(au.vitals.died.get_connections().size() == 1 and au.vitals.hp_changed.get_connections().is_empty() and au.stats.stat_changed.get_connections().is_empty(), "A07 only fresh board death listener restored")
	var provider := a.make_data_provider(a.get_unit_by_id(20))
	_check(not provider.cell_is_walkable(Vector2i.ZERO), "A07 clone provider sees occupied cell")
	au.vitals.apply_damage(100.0)
	_check(a.get_unit_by_id(2) == au and not a.is_occupied(Vector2i.ZERO) and a.board_version == 41, "A07 death clears once and keeps corpse")
	_check(provider.cell_is_walkable(Vector2i.ZERO) and a.move_unit(a.get_unit_by_id(20), Vector2i.ZERO), "A07 real move into clone death cell")
	a.set_height(Vector2i(2, 1), 99)
	_check(provider.cell_height(Vector2i(2, 1)) == 99 and live.get_height(Vector2i(2, 1)) == 5, "A07 provider binds clone board")
	_check(live.board_version == 40 and b.board_version == 40 and counts.values() == [0, 0, 0, 0, 0, 0], "A07 capture/load/death never emit live signals")
	var removed := a.get_unit_by_id(20)
	a.remove_unit(removed)
	var version := a.board_version
	removed.vitals.apply_damage(100.0)
	_check(a.board_version == version and removed.vitals.died.get_connections().is_empty(), "A07 remove disconnects own listener")
	var old := b.get_unit_by_id(20)
	b.resize(0, 0)
	version = b.board_version
	old.vitals.apply_damage(100.0)
	_check(b.board_version == version and old.vitals.died.get_connections().is_empty(), "A07 resize disconnects own listener")


func _test_p02_a08_value_ownership() -> void:
	var snap := _p02_capture(_p02_board())
	var input := snap.to_dict()
	var imported := SimulationSnapshot.from_dict(input).snapshot
	_p02_strength(input)["modifiers"][0]["value"] = 888.0
	input["board"]["occupancy"].clear()
	_p02_same(snap, imported, "A08 nested input ownership")
	var returned := imported.to_dict()
	_p02_strength(returned)["modifiers"].clear()
	returned["board"]["occupancy"][0]["x"] = 2
	var values := imported.canonical_values()
	values[0][1].clear()
	var bytes := imported.canonical_bytes()
	bytes[0] = 0
	_p02_same(snap, imported, "A08 every returned graph owned")
	var ids: Array[StringName] = [&"Я", &"a", &"Я", &"А"]
	var result := SimulationSnapshot.capture_board(_p02_board(), ids)
	ids.clear()
	_check(result.unsupported_ids == [&"a", &"А", &"Я"] and result.snapshot == null, "A08 runtime ids copied unique sorted")
	var returned_ids := result.unsupported_ids
	returned_ids.clear()
	_check(result.unsupported_ids == [&"a", &"А", &"Я"], "A08 returned unsupported ids cannot mutate result")


func _test_p02_a09_codec() -> void:
	var snap := _p02_capture(_p02_board())
	var data := snap.to_dict()
	for unit in data["board"]["units"]:
		for entry in unit["stats"]["stats"]:
			entry["stat"]["modifiers"].reverse()
		unit["stats"]["stats"].reverse()
	data["board"]["units"].reverse()
	data["board"]["occupancy"].reverse()
	data = _p02_reverse_maps(data)
	_p02_same(snap, SimulationSnapshot.from_dict(data).snapshot, "A09 all nonsemantic orders normalized")
	_check(snap.to_dict()["board"]["units"][0]["id"] == 2 and snap.to_dict()["board"]["units"][1]["id"] == 10, "A09 numeric unit id order 2 before 10")
	var mods: Array = _p02_strength(snap.to_dict())["modifiers"]
	_check(mods[4]["source_id"] == "А" and mods[5]["source_id"] == "Я", "A09 Cyrillic codepoint order")
	var stat := Stat.new()
	for i in 11:
		stat.add_modifier(StatModifier.new(&"same", StatModifier.Operation.ADD_FLAT, 1.0))
	_check(stat.to_snapshot_dict()["modifiers"][2]["local_slot"] == 2 and stat.to_snapshot_dict()["modifiers"][10]["local_slot"] == 10, "A09 numeric slot order 2 before 10")
	for field in ["hp", "modifier", "board_version"]:
		data = snap.to_dict()
		if field == "hp": data["board"]["units"][0]["vitals"]["hp"] += 1.0
		elif field == "modifier": _p02_strength(data)["modifiers"][0]["value"] += 0.1
		else: data["board"]["board_version"] += 1
		var changed := SimulationSnapshot.from_dict(data).snapshot
		_check(changed.canonical_values() != snap.canonical_values() and changed.canonical_bytes() != snap.canonical_bytes() and changed.fingerprint() != snap.fingerprint(), "A09 semantic mutation changes values/bytes/hash: " + field)
	var cases: Array = [
		[true, [1, 1]], [false, [1, 0]],
		[-2, [2, 254, 255, 255, 255, 255, 255, 255, 255]],
		[258, [2, 2, 1, 0, 0, 0, 0, 0, 0]],
		[1.0, [3, 0, 0, 0, 0, 0, 0, 240, 63]],
		[-0.0, [3, 0, 0, 0, 0, 0, 0, 0, 0]],
		["Я", [4, 2, 0, 0, 0, 0, 0, 0, 0, 208, 175]],
		[[], [5, 0, 0, 0, 0, 0, 0, 0, 0]],
	]
	for i in cases.size():
		var bytes := PackedByteArray()
		SimulationSnapshot._encode(cases[i][0], bytes)
		_check(bytes == PackedByteArray(cases[i][1]), "A09 literal codec leaf %d" % i)
	_check(snap.canonical_bytes().slice(0, 5) == PackedByteArray([80, 48, 50, 83, 1]), "A09 literal P02S prefix")
	var empty := SimulationSnapshot.capture_board(BattleBoard.new(), []).snapshot
	_check(empty.canonical_bytes().size() == 423 and empty.fingerprint() == "2131efbbb21524e70a9558c18f6010ac8c745d903ca6fd652a2bb44893dd7100", "A09 independent whole codec oracle")
	data = snap.to_dict()
	data["board"]["units"][0]["move_points_left"] = -0.0
	var negative := SimulationSnapshot.from_dict(data).snapshot
	data["board"]["units"][0]["move_points_left"] = 0.0
	_p02_same(negative, SimulationSnapshot.from_dict(data).snapshot, "A09 negative zero normalization")


func _test_p02_a10_rejections() -> void:
	var snap := _p02_capture(_p02_board())
	var bad_cases: Array = [
		[["schema_version"], "1"], [["scope"], 1], [["board", "schema_version"], true],
		[["board", "width"], 9223372036854775807], [["board", "height"], 9223372036854775807],
		[["board", "width"], 1025], [["board", "height"], -1], [["board", "board_version"], -1],
		[["board", "heights"], PackedInt32Array()], [["board", "terrain"], "bad"],
		[["board", "units"], {}], [["board", "occupancy"], null], [["board", "terrain"], [0]],
		[["board", "terrain", 0], 4], [["board", "heights", 0], 2147483648],
		[["board", "units", 0, "id"], 0], [["board", "units", 0, "faction"], 3],
		[["board", "units", 0, "cell_x"], 4294967296], [["board", "units", 0, "debug_name"], 1],
		[["board", "units", 0, "move_points_left"], 1], [["board", "units", 0, "has_attacked"], 1],
		[["board", "units", 0, "move_points_left"], -1.0], [["board", "units", 0, "vitals", "hp"], NAN],
		[["board", "units", 0, "vitals", "balance"], INF], [["board", "units", 0, "vitals", "is_alive"], 1],
		[["board", "units", 0, "stats"], null], [["board", "units", 0, "vitals"], {}],
		[["board", "units", 0, "stats", "stats"], {}], [["board", "units", 0, "stats", "stats", 0, "stat_type"], 12],
		[["board", "units", 0, "stats", "stats", 3, "stat", "base_value"], 1],
		[["board", "units", 0, "stats", "stats", 3, "stat", "base_value"], INF],
		[["board", "units", 0, "stats", "stats", 3, "stat", "modifiers"], {}],
		[["board", "units", 0, "stats", "stats", 3, "stat", "next_modifier_slot"], 6],
		[["board", "units", 0, "stats", "stats", 3, "stat", "modifiers", 0, "operation"], 3],
		[["board", "units", 0, "stats", "stats", 3, "stat", "modifiers", 0, "value"], NAN],
		[["board", "units", 0, "stats", "stats", 3, "stat", "modifiers", 0, "evaluation_order"], 90],
		[["board", "occupancy", 0, "unit_id"], 10], [["board", "occupancy", 0, "unit_id"], 999],
		[["board", "occupancy", 0, "x"], 1],
	]
	for i in bad_cases.size():
		var bad := snap.to_dict()
		_p02_set(bad, bad_cases[i][0], bad_cases[i][1])
		_p02_expect(bad, BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 invalid schema case %d" % i)
		_check(BattleBoard.from_snapshot_dict(bad["board"]) == null or bad_cases[i][0].size() == 1, "A10 low Board validates case %d" % i)
	for kind in ["unit", "stat", "slot", "order", "occupancy", "extra", "missing", "StringName"]:
		var bad := snap.to_dict()
		if kind == "unit": bad["board"]["units"].append(bad["board"]["units"][0].duplicate(true))
		elif kind == "stat": bad["board"]["units"][0]["stats"]["stats"].append(bad["board"]["units"][0]["stats"]["stats"][0].duplicate(true))
		elif kind == "slot": _p02_strength(bad)["modifiers"][0]["local_slot"] = _p02_strength(bad)["modifiers"][1]["local_slot"]
		elif kind == "order": _p02_strength(bad)["modifiers"][0]["evaluation_order"] = _p02_strength(bad)["modifiers"][1]["evaluation_order"]
		elif kind == "occupancy": bad["board"]["occupancy"].append(bad["board"]["occupancy"][0].duplicate(true))
		elif kind == "extra": _p02_strength(bad)["extra"] = 1
		elif kind == "missing": _p02_strength(bad).erase("base_value")
		else:
			var s := _p02_strength(bad)
			s.erase("base_value")
			s[&"base_value"] = 10.0
		_p02_expect(bad, BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 duplicate/key " + kind)
	var unsupported_cases: Array = [
		[["schema_version"], 2], [["scope"], "future"], [["board", "schema_version"], 3],
		[["board", "units", 0, "schema_version"], 99], [["board", "units", 0, "ai_profile_path"], "res://future.tres"],
		[["board", "units", 0, "stats", "schema_version"], 2],
		[["board", "units", 0, "stats", "stats", 3, "stat", "schema_version"], 2],
		[["board", "units", 0, "stats", "stats", 3, "stat", "modifiers", 0, "instance_id"], 1],
	]
	for i in unsupported_cases.size():
		var bad := snap.to_dict()
		_p02_set(bad, unsupported_cases[i][0], unsupported_cases[i][1])
		_p02_expect(bad, BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "A10 unsupported case %d" % i)
	var overflow := snap.to_dict()
	_p02_strength(overflow)["base_value"] = 1e308
	_p02_strength(overflow)["modifiers"][1]["value"] = 1e308
	_p02_expect(overflow, BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 finite fields computed overflow")
	var low_stat := Stat.new(1.0)
	low_stat.add_modifier(StatModifier.new(&"low", StatModifier.Operation.ADD_FLAT, 2.0))
	var malformed_stat := low_stat.to_snapshot_dict()
	malformed_stat["modifiers"][0]["operation"] = 99
	_check(Stat.from_snapshot_dict(malformed_stat) == null, "A10 low Stat rejects malformed modifier enum")
	var low_bag := StatsBag.new()
	low_bag.set_base_value(StatTypes.StatType.STRENGTH, 1.0)
	var malformed_bag := low_bag.to_snapshot_dict()
	malformed_bag["stats"][0]["stat_type"] = 99
	_check(StatsBag.from_snapshot_dict(malformed_bag) == null, "A10 low Bag rejects stat enum")
	# Меняем поля пустой доски напрямую: проверяем пределы snapshot без большой аллокации.
	for dimensions in [[1025, 0], [257, 256], [9223372036854775807, 0], [0, 9223372036854775807]]:
		var oversized := BattleBoard.new()
		oversized.width = dimensions[0]
		oversized.height = dimensions[1]
		_check(SimulationSnapshot.capture_board(oversized, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 capture rejects unallocated oversized %s" % str(dimensions))
	var live_overflow := _p02_board()
	var live_stat: Stat = live_overflow.get_unit_by_id(2).stats._stats[StatTypes.StatType.STRENGTH]
	live_stat.base_value = 1e308
	live_stat.add_modifier(StatModifier.new(&"overflow", StatModifier.Operation.ADD_FLAT, 1e308))
	_check(SimulationSnapshot.capture_board(live_overflow, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 capture rejects computed Stat overflow")
	for size in [Vector2i(257, 256), Vector2i(1024, 1024)]:
		var bad := snap.to_dict()
		bad["board"]["width"] = size.x
		bad["board"]["height"] = size.y
		_p02_expect(bad, BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 product exceeds MAX_CELLS")
	for size in [Vector2i(0, 0), Vector2i(1024, 0), Vector2i(0, 1024), Vector2i(256, 256)]:
		var edge := BattleBoard.new(size.x, size.y)
		var result := SimulationSnapshot.capture_board(edge, [])
		_check(result.code == BoardSnapshotResult.Code.OK and result.snapshot.instantiate_board().get_bounds() == edge.get_bounds(), "A10 valid boundary %s" % size)
	var live := _p02_board()
	var u := live.get_unit_by_id(2)
	var stats := u.stats
	u.stats = null
	_check(SimulationSnapshot.capture_board(live, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 missing live stats")
	u.stats = stats
	var vitals := u.vitals
	u.vitals = null
	_check(SimulationSnapshot.capture_board(live, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 missing live vitals")
	u.vitals = Vitals.new(StatsBag.new(), false)
	_check(SimulationSnapshot.capture_board(live, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 foreign Vitals bag")
	u.vitals = vitals
	u.ai_profile = AIBehaviorProfile.new()
	var unsupported := SimulationSnapshot.capture_board(live, [])
	_check(unsupported.code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED and unsupported.unsupported_ids.has(&"unit/2/ai_profile"), "A10 live profile diagnostic")
	u.ai_profile = null
	_check(SimulationSnapshot.capture_board(null, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A10 null board")
	live._units[99] = RefCounted.new()
	_check(SimulationSnapshot.capture_board(live, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID and live.to_snapshot_dict().is_empty(), "A10 foreign registry object safely rejected")
	live._units.erase(99)
	u.stats._stats[99] = RefCounted.new()
	_check(SimulationSnapshot.capture_board(live, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID and u.stats.to_snapshot_dict().is_empty(), "A10 foreign stat object safely rejected")
	u.stats._stats.erase(99)
	_test_p02_subtypes()
	_test_p02_cache()


func _test_p02_cache() -> void:
	var board := _p02_board()
	var unit := board.get_unit_by_id(2)
	var stat: Stat = unit.stats._stats[StatTypes.StatType.STRENGTH]
	var old := stat.get_value()
	var counts: Array[int] = [0]
	unit.stats.stat_changed.connect(func(_s: StatTypes.StatType, _a: float, _b: float) -> void: counts[0] += 1)
	board.board_changed.connect(func() -> void: counts[0] += 1)
	var counter := UnitId.get_counter()
	stat._modifiers[0].value = 100.0
	var result := SimulationSnapshot.capture_board(board, [])
	_check(result.code == BoardSnapshotResult.Code.SNAPSHOT_INVALID and result.snapshot == null and result.reason.contains("stat") and result.reason.contains("cache"), "A10 stale clean cache diagnostic path", result.reason)
	_check(stat._cached_value == old and not stat._cache_dirty and stat._modifiers[0].value == 100.0 and counts[0] == 0 and UnitId.get_counter() == counter, "A10 stale capture never repairs or emits")
	stat.base_value = 10.0
	stat._cached_value = NAN
	result = SimulationSnapshot.capture_board(board, [])
	_check(result.code == BoardSnapshotResult.Code.OK and stat._cache_dirty and is_nan(stat._cached_value), "A10 dirty cache ignored even if nonfinite")
	_check(result.snapshot.instantiate_board().get_unit_by_id(2).get_stat(StatTypes.StatType.STRENGTH) == 642.0, "A10 dirty clone calculates current finite modifiers")


func _test_p02_subtypes() -> void:
	var derived_board := _P02Board.new()
	_check(SimulationSnapshot.capture_board(derived_board, []).code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED and derived_board.to_snapshot_dict().is_empty(), "A10 Board subclass")
	for kind in ["unit", "bag", "vitals", "stat", "modifier"]:
		var board := _p02_board()
		var u := board.get_unit_by_id(2)
		if kind == "unit":
			var other := _P02Unit.new()
			other.id = 2
			other.stats = u.stats
			other.vitals = u.vitals
			board._units[2] = other
		elif kind == "bag": u.stats = _P02Bag.new()
		elif kind == "vitals": u.vitals = _P02Vitals.new(u.stats, false)
		elif kind == "stat": u.stats._stats[StatTypes.StatType.STRENGTH] = _P02Stat.new()
		else:
			var s: Stat = u.stats._stats[StatTypes.StatType.STRENGTH]
			s.add_modifier(_P02Modifier.new())
		var result := SimulationSnapshot.capture_board(board, [])
		_check(result.code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED and result.snapshot == null and String(result.unsupported_ids[0]).ends_with("/subclass"), "A10 subtype refused: " + kind)


func _test_p02_a11_board_edges() -> void:
	var board := _p02_board()
	var u := board.get_unit_by_id(2)
	board.clear_occupancy(u)
	var clone := _p02_capture(board).instantiate_board()
	_check(clone.get_unit_by_id(2).is_alive() and not clone.is_occupied(Vector2i.ZERO), "A11 living registry unit without occupancy retained")
	_check(clone.get_unit_by_id(2).height == 0 and clone.get_height(Vector2i.ZERO) == 7, "A11 unit height differs from tile")
	u.cell = Vector2i(3, 0)
	_check(SimulationSnapshot.capture_board(board, []).code == BoardSnapshotResult.Code.SNAPSHOT_INVALID, "A11 out-of-bounds unit explicitly refused")
	var low := _p02_unit(2, Vector2i.ZERO, _make_stats()).to_snapshot_dict()
	low["cell_x"] = 4294967296
	_check(UnitState.from_snapshot_dict(low) == null, "A11 low Unit import prevents Vector2i overflow")
	low = _p02_unit(2, Vector2i.ZERO, _make_stats()).to_snapshot_dict()
	low["height"] = 4294967296
	_check(UnitState.from_snapshot_dict(low).height == 4294967296, "A11 unit height remains int64 outside Vector2i")
	_check(Stat.from_snapshot_dict({}) == null and StatsBag.from_snapshot_dict({}) == null and UnitState.from_snapshot_dict({}) == null and BattleBoard.from_snapshot_dict({}) == null, "A11 low public APIs reject missing schema")


func _test_p02_a12_old_save_unchanged() -> void:
	var board := _p02_board()
	var bag := board.get_unit_by_id(2).stats
	var old := bag.to_dict()
	_check(old.keys() == ["bases"] and old["bases"]["3"] == 10.0, "A12 legacy bag saves only bases")
	_check(StatsBag.from_dict(old).get_value(StatTypes.StatType.STRENGTH) == 10.0, "A12 legacy bag load does not restore modifiers")
	var unit := board.get_unit_by_id(2)
	var old_unit := unit.to_dict()
	_check(not old_unit.has("schema_version") and old_unit["stats"] == old, "A12 legacy unit schema unchanged")
	var old_board := board.to_dict()
	_check(old_board.has("unit_id_counter") and not old_board.has("occupancy") and not old_board.has("board_version"), "A12 legacy board schema unchanged")
	var before := old_board.duplicate(true)
	_p02_capture(board).instantiate_board()
	_check(board.to_dict() == before, "A12 snapshot does not mutate legacy save state")


class _P02Board extends BattleBoard:
	pass

class _P02Unit extends UnitState:
	pass

class _P02Bag extends StatsBag:
	pass

class _P02Vitals extends Vitals:
	pass

class _P02Stat extends Stat:
	pass

class _P02Modifier extends StatModifier:
	pass
# --- Stat pipeline ---------------------------------------------------------

## Главное свойство фиксированного конвейера: результат НЕ зависит от порядка
## добавления модификаторов. Раньше он зависел от priority и порядка вставки,
## что ломало воспроизводимость после загрузки сейва (R-4).
func _test_stat_flat_and_percent_order_independence() -> void:
	var flat := StatModifier.new(&"a", StatModifier.Operation.ADD_FLAT, 5.0)
	var percent := StatModifier.new(&"b", StatModifier.Operation.ADD_PERCENT, 0.5)

	var stat_a := Stat.new(10.0)
	stat_a.add_modifier(flat)
	stat_a.add_modifier(percent)

	var stat_b := Stat.new(10.0)
	stat_b.add_modifier(percent)
	stat_b.add_modifier(flat)

	# (10 + 5) * (1 + 0.5) = 22.5
	_check_eq(stat_a.get_value(), 22.5, "flat+percent = (base+flat)*(1+percent)")
	_check_eq(stat_b.get_value(), stat_a.get_value(), "order independence")


func _test_stat_multiply_applies_to_total() -> void:
	var stat := Stat.new(10.0)
	stat.add_modifier(StatModifier.new(&"a", StatModifier.Operation.ADD_FLAT, 2.0))
	stat.add_modifier(StatModifier.new(&"b", StatModifier.Operation.MULTIPLY, 2.0))
	# (10 + 2) * 1.0 * 2.0 = 24
	_check_eq(stat.get_value(), 24.0, "multiply applies to accumulated total")


func _test_remove_modifiers_by_source() -> void:
	var bag := StatsBag.new()
	bag.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	bag.add_modifier(
		StatTypes.StatType.STRENGTH,
		StatModifier.new(&"item_x", StatModifier.Operation.ADD_FLAT, 2.0)
	)
	_check_eq(bag.get_value(StatTypes.StatType.STRENGTH), 5.0, "modifier applied")

	bag.remove_modifiers_by_source(&"item_x")
	_check_eq(bag.get_value(StatTypes.StatType.STRENGTH), 3.0, "modifier removed by source")


# --- Vitals: регрессия C-2 -------------------------------------------------

## ЭТО КЛЮЧЕВОЙ ТЕСТ АУДИТА. Воспроизводит ровно тот сценарий, который был
## сломан: HP_MAX база 10 + модификатор +5 от "амулета", затем урон 3.
## На старой модели HP становилось 17 (урон УВЕЛИЧИВАЛ здоровье), а снятие
## амулета оставляло +2 к базе навсегда.
func _test_damage_does_not_corrupt_base_value() -> void:
	var bag := _make_stats(10.0)
	bag.add_modifier(
		StatTypes.StatType.HP_MAX,
		StatModifier.new(&"amulet", StatModifier.Operation.ADD_FLAT, 5.0)
	)
	var vitals := Vitals.new(bag, true)

	_check_eq(vitals.get_hp_max(), 15.0, "HP_MAX = base 10 + amulet 5")
	_check_eq(vitals.get_hp(), 15.0, "starts at full HP")

	vitals.apply_damage(3.0)
	_check_eq(vitals.get_hp(), 12.0, "damage reduces HP (was 17.0 before fix)")
	_check_eq(vitals.get_hp_max(), 15.0, "HP_MAX unchanged by damage")
	_check_eq(bag.get_base_value(StatTypes.StatType.HP_MAX), 10.0, "base_value NOT corrupted")

	bag.remove_modifiers_by_source(&"amulet")
	_check_eq(bag.get_base_value(StatTypes.StatType.HP_MAX), 10.0, "base intact after unequip")
	_check_eq(vitals.get_hp_max(), 10.0, "HP_MAX back to base")


func _test_heal_clamped_by_max() -> void:
	var vitals := Vitals.new(_make_stats(10.0), true)
	vitals.apply_damage(4.0)
	var healed := vitals.heal(100.0)
	_check_eq(vitals.get_hp(), 10.0, "heal clamped by HP_MAX")
	_check_eq(healed, 4.0, "heal returns actual amount healed")
	_check_eq(vitals.heal(5.0), 0.0, "heal at full HP returns 0")


func _test_death_fires_once() -> void:
	var vitals := Vitals.new(_make_stats(10.0), true)
	var death_count := [0]
	vitals.died.connect(func() -> void: death_count[0] += 1)

	vitals.apply_damage(100.0)
	_check_eq(vitals.get_hp(), 0.0, "HP clamped at zero, not negative")
	_check(not vitals.is_alive(), "unit is dead")
	_check(death_count[0] == 1, "died fired once")

	# Добивание уже мёртвого не должно повторно триггерить эффекты смерти.
	vitals.apply_damage(50.0)
	_check(death_count[0] == 1, "died NOT fired again on overkill")


func _test_balance_break_resets() -> void:
	var vitals := Vitals.new(_make_stats(10.0, 100.0), true)

	_check(not vitals.would_break(40.0), "40 does not break 100")
	vitals.add_impact(40.0)
	vitals.add_impact(40.0)
	_check_eq(vitals.get_balance(), 80.0, "balance accumulates")
	_check(vitals.would_break(40.0), "preview predicts break at 120>=100")

	var broke := vitals.add_impact(40.0)
	_check(broke, "balance broke")
	_check_eq(vitals.get_balance(), 0.0, "balance resets to 0 after break")


# --- DamageCalculator ------------------------------------------------------

func _make_unit(faction: Faction.Type, cell: Vector2i, strength: float = 0.0) -> UnitState:
	var bag := _make_stats(20.0, 100.0)
	bag.set_base_value(StatTypes.StatType.STRENGTH, strength)
	bag.set_base_value(StatTypes.StatType.IMPACT_POWER, 40.0)
	bag.set_base_value(StatTypes.StatType.MOVE_RANGE, 4.0)
	return UnitState.create(faction, cell, bag, "TestUnit")


## calculate() обязан быть чистым: ИИ вызывает его десятки раз за ход для
## оценки кандидатов, и любая мутация исказила бы состояние боя.
func _test_damage_calculator_is_pure() -> void:
	var board := _make_board()
	var attacker := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0), 3.0)
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	board.add_unit(attacker)
	board.add_unit(target)

	var hp_before := target.vitals.get_hp()
	var balance_before := target.vitals.get_balance()

	for _i in 5:
		DamageCalculator.calculate(
			attacker, target, attacker.cell, target.cell, 1.0, 40.0, board, 1
		)

	_check_eq(target.vitals.get_hp(), hp_before, "calculate() does not change HP")
	_check_eq(target.vitals.get_balance(), balance_before, "calculate() does not change Balance")
	_check(board.occupant_at(Vector2i(1, 0)) == target, "calculate() does not move anyone")


func _test_damage_calculator_reports_events() -> void:
	var board := _make_board()
	var attacker := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0), 3.0)
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	board.add_unit(attacker)
	board.add_unit(target)
	var sink := RecordingEventSink.new()

	var info := DamageCalculator.calculate(
		attacker, target, attacker.cell, target.cell, 1.0, 40.0, board, 1
	)
	_check_eq(info.final_damage, 4.0, "damage = base 1 + STR 3")

	DamageCalculator.apply(info, sink)
	_check_eq(target.vitals.get_hp(), 16.0, "apply() subtracts 4 HP")
	_check(sink.has_event(&"unit_damaged"), "unit_damaged reported")
	_check(sink.has_event(&"unit_balance_changed"), "unit_balance_changed reported")
	_check(not sink.has_event(&"unit_died"), "no death at 16 HP")


func _test_would_kill_prediction() -> void:
	var board := _make_board()
	var attacker := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0), 3.0)
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	board.add_unit(attacker)
	board.add_unit(target)
	var sink := RecordingEventSink.new()

	target.vitals.set_hp(3.0)
	var info := DamageCalculator.calculate(
		attacker, target, attacker.cell, target.cell, 1.0, 0.0, board, 1
	)
	_check(info.would_kill, "would_kill predicted for 4 dmg vs 3 HP")

	DamageCalculator.apply(info, sink)
	_check(sink.has_event(&"unit_died"), "unit_died reported")
	_check(not target.is_alive(), "target is dead")


## Синхронная реакция на damaged может вложенно добить цель; внешний apply не
## должен повторно публиковать смерть, потому что переход произошёл внутри.
func _test_nested_damage_death_belongs_to_inner_apply() -> void:
	var board := _make_board()
	var attacker := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0))
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	board.add_unit(attacker)
	board.add_unit(target)
	var sink := _NestedDamageSink.new()
	sink.nested_info = DamageCalculator.calculate(
		attacker, target, attacker.cell, target.cell, 999.0, 0.0, board, 1
	)
	var outer_info := DamageCalculator.calculate(
		attacker, target, attacker.cell, target.cell, 1.0, 0.0, board, 1
	)
	DamageCalculator.apply(outer_info, sink)
	_check(sink.count_of(&"unit_damaged") == 2, "nested death reports damage for both applies")
	_check(sink.count_of(&"unit_died") == 1, "nested death publishes one unit_died")
	_check(not target.is_alive(), "nested damage kills target")


func _test_death_apply_is_idempotent_for_domain_events() -> void:
	var board := _make_board()
	var attacker := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0))
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	board.add_unit(attacker)
	board.add_unit(target)
	target.vitals.set_hp(1.0)
	var death_count: Array[int] = [0]
	target.vitals.died.connect(func() -> void: death_count[0] += 1)
	var sink := RecordingEventSink.new()
	var info := DamageCalculator.calculate(
		attacker, target, attacker.cell, target.cell, 1.0, 200.0, board, 1
	)
	DamageCalculator.apply(info, sink)
	DamageCalculator.apply(info, sink)
	_check(death_count[0] == 1, "two lethal applies emit one Vitals.died")
	_check(sink.count_of(&"unit_damaged") == 1, "two lethal applies report one damaged")
	_check(sink.count_of(&"unit_died") == 1, "two lethal applies report one unit_died")
	_check(sink.count_of(&"unit_balance_changed") == 0, "death has no balance change")
	_check(sink.count_of(&"unit_balance_broken") == 0, "death has no balance break")


func _test_death_clears_before_sink_and_preserves_corpse() -> void:
	var board := _make_board(3, 1)
	var attacker := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0))
	var corpse := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	var mover := _make_unit(Faction.Type.PLAYER, Vector2i(2, 0))
	board.add_unit(attacker)
	board.add_unit(corpse)
	board.add_unit(mover)
	var sink := _BoardDeathSink.new()
	sink.board = board
	sink.corpse = corpse
	sink.mover = mover
	var info := DamageCalculator.calculate(
		attacker, corpse, attacker.cell, corpse.cell, 999.0, 0.0, board, 1
	)
	DamageCalculator.apply(info, sink)
	_check(sink.saw_free_cell, "unit_died sees cell already free")
	_check(sink.moved_other, "other unit moves into freed cell during sink")
	_check(board.get_unit_by_id(corpse.id) == corpse, "corpse remains in registry")
	_check(board.occupant_at(corpse.cell) == mover, "new occupant is preserved")
	var version := board.board_version
	board.clear_occupancy(corpse)
	_check(board.board_version == version, "repeated corpse cleanup is idempotent")
	_check(board.occupant_at(corpse.cell) == mover, "repeated cleanup keeps new occupant")


func _test_loaded_death_and_dead_add_do_not_occupy() -> void:
	var source := _make_board(4, 1)
	var live := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	var dead := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0))
	dead.vitals.apply_damage(999.0)
	source.add_unit(live)
	_check(source.add_unit(dead), "already dead unit can be registered")
	var source_mover := _make_unit(Faction.Type.PLAYER, Vector2i(2, 0))
	source.add_unit(source_mover)
	# can_enter скрывает мёртвого даже при ошибочной записи occupancy; проверяем реальный вход.
	_check(source.move_unit(source_mover, dead.cell), "adding dead unit leaves occupancy free")
	source.remove_unit(source_mover)
	var restored := BattleBoard.from_dict(source.to_dict())
	var restored_live := restored.get_unit_by_id(live.id)
	var restored_dead := restored.get_unit_by_id(dead.id)
	_check(restored_dead != null and not restored.is_occupied(restored_dead.cell), "loaded corpse does not occupy")
	_check(restored.can_enter(restored_dead.cell), "loaded corpse cell is enterable")
	var mover := _make_unit(Faction.Type.PLAYER, Vector2i(2, 0))
	_check(restored.add_unit(mover), "mover added beside loaded units")
	_check(restored.move_unit(mover, restored_dead.cell), "mover enters loaded corpse cell")
	var sink := RecordingEventSink.new()
	var attacker := _make_unit(Faction.Type.ENEMY, Vector2i(3, 0))
	_check(restored.add_unit(attacker), "attacker added for loaded death")
	var info := DamageCalculator.calculate(
		attacker, restored_live, attacker.cell, restored_live.cell, 999.0, 0.0, restored, 1
	)
	DamageCalculator.apply(info, sink)
	_check(not restored.is_occupied(restored_live.cell), "loaded live unit clears on death")
	_check(restored.move_unit(mover, restored_live.cell), "mover enters newly dead loaded unit cell")


func _test_board_removes_death_subscriptions() -> void:
	var board := _make_board(3, 1)
	var unit := _make_unit(Faction.Type.PLAYER, Vector2i(0, 0))
	_check(board.add_unit(unit), "unit added for subscription removal")
	_check(unit.vitals.died.get_connections().size() == 1, "one death subscription after add")
	board.remove_unit(unit)
	var version_after_remove := board.board_version
	_check(unit.vitals.died.get_connections().is_empty(), "remove disconnects death subscription")
	unit.vitals.apply_damage(999.0)
	_check(board.board_version == version_after_remove, "late death after remove leaves board unchanged")
	_check(board.add_unit(unit), "dead unit can be re-added")
	_check(unit.vitals.died.get_connections().size() == 1, "re-add creates one subscription")
	board.resize(3, 1)
	var version_after_resize := board.board_version
	_check(unit.vitals.died.get_connections().is_empty(), "resize disconnects death subscription")
	unit.vitals.revive()
	unit.vitals.apply_damage(999.0)
	_check(board.board_version == version_after_resize, "late death after resize leaves board unchanged")


# --- PushResolver ----------------------------------------------------------

## Толчок только по 4 осям — то же правило, что в pathfinding (без диагоналей).
func _test_push_direction_axis_only() -> void:
	var right := PushResolver.compute_push_direction(Vector2i(0, 0), Vector2i(3, 1))
	_check(right == Vector2i(1, 0), "dominant X -> push along X")

	var down := PushResolver.compute_push_direction(Vector2i(0, 0), Vector2i(1, 3))
	_check(down == Vector2i(0, 1), "dominant Y -> push along Y")

	var same := PushResolver.compute_push_direction(Vector2i(2, 2), Vector2i(2, 2))
	_check(same == Vector2i.ZERO, "no direction for same cell")


func _test_push_blocked_by_wall_and_height() -> void:
	var walls: Array[Vector2i] = [Vector2i(2, 0)]
	var provider := GridDataProvider.new(
		func(cell: Vector2i) -> bool: return not walls.has(cell),
		func(cell: Vector2i) -> int: return 3 if cell == Vector2i(0, 2) else 0,
		Callable()
	)

	var wall_result := PushResolver.validate_push(Vector2i(1, 0), Vector2i(2, 0), provider, 1)
	_check(not wall_result.success, "push into wall blocked")
	_check(wall_result.blocked_reason == PushResult.REASON_WALL, "reason = wall")
	_check(wall_result.final_cell == Vector2i(1, 0), "target stays in place")

	var height_result := PushResolver.validate_push(Vector2i(0, 1), Vector2i(0, 2), provider, 1)
	_check(not height_result.success, "push up a 3-level ledge blocked")
	_check(height_result.blocked_reason == PushResult.REASON_HEIGHT, "reason = height")

	var ok_result := PushResolver.validate_push(Vector2i(0, 0), Vector2i(1, 0), provider, 1)
	_check(ok_result.success, "free push succeeds")
	_check(ok_result.final_cell == Vector2i(1, 0), "target moves")


# --- BattleBoard: регрессия C-4 -------------------------------------------

func _make_board(w: int = 6, h: int = 6) -> BattleBoard:
	return BattleBoard.new(w, h)


## Доска — единственный источник правды: `unit.cell` и occupancy обязаны
## совпадать всегда, иначе pathfinding и толкание видят разные картины.
func _test_board_occupancy_single_source_of_truth() -> void:
	var board := _make_board()
	var unit := _make_unit(Faction.Type.PLAYER, Vector2i(2, 2))

	_check(board.add_unit(unit), "unit added to board")
	_check(board.occupant_at(Vector2i(2, 2)) == unit, "occupancy knows the unit")
	_check(board.is_occupied(Vector2i(2, 2)), "cell reported as occupied")
	_check(not board.can_enter(Vector2i(2, 2)), "others cannot enter occupied cell")
	_check(board.can_enter(Vector2i(2, 2), unit), "unit does not block itself (D-3.6)")

	# Вторым юнитом в ту же клетку встать нельзя — иначе occupancy и позиции
	# немедленно разошлись бы.
	var intruder := _make_unit(Faction.Type.ENEMY, Vector2i(2, 2))
	_check(not board.add_unit(intruder), "cannot add second unit to same cell")


func _test_board_move_keeps_occupancy_in_sync() -> void:
	var board := _make_board()
	var unit := _make_unit(Faction.Type.PLAYER, Vector2i(1, 1))
	board.add_unit(unit)
	board.set_height(Vector2i(3, 1), 2)

	_check(board.move_unit(unit, Vector2i(3, 1)), "move succeeded")
	_check(unit.cell == Vector2i(3, 1), "unit.cell updated")
	_check(unit.height == 2, "unit.height synced from board")
	_check(not board.is_occupied(Vector2i(1, 1)), "old cell freed")
	_check(board.occupant_at(Vector2i(3, 1)) == unit, "new cell occupied")

	var blocker := _make_unit(Faction.Type.ENEMY, Vector2i(4, 1))
	board.add_unit(blocker)
	_check(not board.move_unit(unit, Vector2i(4, 1)), "cannot move onto occupied cell")
	_check(unit.cell == Vector2i(3, 1), "position unchanged after failed move")


## board_version — ключ для кэша зоны хода (D-3.3). Если он не растёт при
## мутации, кэш вернёт устаревший flood-fill.
func _test_board_version_increments() -> void:
	var board := _make_board()
	var initial := board.board_version

	board.set_terrain(Vector2i(1, 1), TerrainType.Type.WALL)
	_check(board.board_version > initial, "version bumped on terrain change")

	var after_terrain := board.board_version
	var unit := _make_unit(Faction.Type.PLAYER, Vector2i(0, 0))
	board.add_unit(unit)
	_check(board.board_version > after_terrain, "version bumped on unit add")

	var after_add := board.board_version
	board.move_unit(unit, Vector2i(0, 1))
	_check(board.board_version > after_add, "version bumped on move")


## КЛЮЧЕВОЙ ТЕСТ C-4: pathfinder должен видеть юнитов. Раньше он работал с
## провайдером, который не знал об occupancy, поэтому зона хода включала
## клетки под врагами, и ИИ строил кандидатов на занятые клетки.
func _test_pathfinding_respects_occupancy() -> void:
	var board := _make_board(5, 1)
	var mover := _make_unit(Faction.Type.PLAYER, Vector2i(0, 0))
	var wall_unit := _make_unit(Faction.Type.ENEMY, Vector2i(2, 0))
	board.add_unit(mover)
	board.add_unit(wall_unit)

	var pathfinder := GridPathfinder.new()
	pathfinder.configure(board.get_bounds(), board.make_data_provider(mover), 1)

	var reachable := pathfinder.get_reachable_cells(mover.cell, 10.0)
	_check(reachable.has(Vector2i(1, 0)), "free cell reachable")
	_check(not reachable.has(Vector2i(2, 0)), "cell under enemy NOT reachable")
	# Полоса 5x1: враг в (2,0) полностью перекрывает проход.
	_check(not reachable.has(Vector2i(3, 0)), "cells behind the enemy blocked too")
	_check(reachable.has(Vector2i(0, 0)), "own cell always reachable")


## Труп не должен блокировать клетку — иначе после боя доска зарастает
## непроходимыми мёртвыми юнитами.
func _test_dead_unit_does_not_block() -> void:
	var board := _make_board(4, 1)
	var corpse := _make_unit(Faction.Type.ENEMY, Vector2i(1, 0))
	board.add_unit(corpse)

	_check(board.is_occupied(Vector2i(1, 0)), "alive unit blocks")
	corpse.vitals.apply_damage(999.0)
	_check(not board.is_occupied(Vector2i(1, 0)), "dead unit no longer blocks")
	_check(board.can_enter(Vector2i(1, 0)), "cell can be entered after death")
	_check(board.get_all_units().size() == 1, "corpse still in registry (for death effects)")
	_check(board.get_alive_units().is_empty(), "but not among the living")


# --- Исходы толкания: регрессия D-6.2 ------------------------------------

## ГЛАВНАЯ МЕХАНИКА ЖАНРА, которая была невыразима до шага 0.4: раньше
## резолвер не знал о юнитах и сообщал об УСПЕШНОМ перемещении в занятую
## клетку, поэтому "толкнул -> врезался -> оба получили урон" не существовало.
func _test_push_collision_with_unit() -> void:
	var board := _make_board(5, 1)
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(2, 0))
	var blocker := _make_unit(Faction.Type.PLAYER, Vector2i(3, 0))
	board.add_unit(target)
	board.add_unit(blocker)

	var result := PushResolver.resolve_push(board, target, target.cell, Vector2i(1, 0), 1)
	_check(result.outcome == PushResult.Outcome.COLLISION, "outcome = COLLISION")
	_check(result.blocker == blocker, "collision victim identified")
	_check(result.final_cell == Vector2i(2, 0), "target stays in place")
	_check(not result.moved(), "collision is not a move")
	_check(not result.is_lethal(), "collision is not lethal by itself")


func _test_push_into_hazard_is_lethal() -> void:
	var board := _make_board(5, 1)
	board.set_terrain(Vector2i(3, 0), TerrainType.Type.HAZARD)
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(2, 0))
	board.add_unit(target)

	var result := PushResolver.resolve_push(board, target, target.cell, Vector2i(1, 0), 1)
	_check(result.outcome == PushResult.Outcome.FELL, "outcome = FELL")
	_check(result.is_lethal(), "push into hazard is lethal")
	_check(result.final_cell == Vector2i(3, 0), "target ends up in the hazard")
	_check(result.blocked_reason == PushResult.REASON_HAZARD, "reason = hazard")


## Вылет за край доски: этой клетки нет ни в одном списке hazard'ов по
## определению, поэтому старая модель считала бы толчок обычным перемещением.
func _test_push_off_board_is_lethal() -> void:
	var board := _make_board(3, 1)
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(2, 0))
	board.add_unit(target)

	var result := PushResolver.resolve_push(board, target, target.cell, Vector2i(1, 0), 1)
	_check(result.outcome == PushResult.Outcome.FELL, "pushed off the edge = FELL")
	_check(result.blocked_reason == PushResult.REASON_BOUNDS, "reason = bounds")


## Толчок ВНИЗ с уступа разрешён (в отличие от толчка ВВЕРХ) и запоминает
## глубину падения для урона — односторонняя проверка высоты.
func _test_push_down_ledge_records_fall_height() -> void:
	var board := _make_board(4, 1)
	board.set_height(Vector2i(1, 0), 3)
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	board.add_unit(target)

	var down := PushResolver.resolve_push(board, target, target.cell, Vector2i(1, 0), 1)
	_check(down.outcome == PushResult.Outcome.MOVED, "push down the ledge allowed")
	_check(down.fall_height == 3, "fall height recorded for damage")

	# А вот вверх на тот же уступ — нельзя.
	var low := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0))
	board.add_unit(low)
	var up := PushResolver.resolve_push(board, low, low.cell, Vector2i(1, 0), 1)
	_check(up.outcome == PushResult.Outcome.BLOCKED, "push up a high ledge blocked")
	_check(up.blocked_reason == PushResult.REASON_HEIGHT, "reason = height")


## Превью обязано сообщать о столкновении ДО подтверждения (R-6), иначе
## игрок не увидит, что его толчок ударит по своим.
func _test_damage_info_exposes_collision_victim() -> void:
	var board := _make_board(6, 1)
	var attacker := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0), 3.0)
	var target := _make_unit(Faction.Type.PLAYER, Vector2i(1, 0))
	var bystander := _make_unit(Faction.Type.PLAYER, Vector2i(2, 0))
	board.add_unit(attacker)
	board.add_unit(target)
	board.add_unit(bystander)

	# impact_power >= BALANCE_MAX -> баланс ломается сразу, толчок считается.
	var info := DamageCalculator.calculate(
		attacker, target, attacker.cell, target.cell, 1.0, 200.0, board, 1
	)
	_check(info.would_break_balance, "balance breaks")
	_check(info.push_result != null, "push result computed")
	_check(info.get_collision_victim() == bystander, "preview names the collision victim")
	_check(info.push_blocked, "push reported as blocked (target did not move)")

	# Убираем свидетеля — толчок должен стать обычным перемещением.
	board.remove_unit(bystander)
	var info2 := DamageCalculator.calculate(
		attacker, target, attacker.cell, target.cell, 1.0, 200.0, board, 1
	)
	_check(info2.get_collision_victim() == null, "no victim once the cell is free")
	_check(not info2.push_blocked, "push now succeeds")
	_check(info2.push_target_cell == Vector2i(2, 0), "target would move to the free cell")


# --- InitiativeTimeline ----------------------------------------------------

## РЕГРЕССИЯ D-4.6. Раньше unregister_participant() вызывал recompute_order(),
## который сбрасывал _current_index = -1, из-за чего смерть юнита посреди
## раунда ПЕРЕЗАПУСКАЛА раунд и все уже ходившие получали ход снова.
func _test_death_does_not_restart_round() -> void:
	var timeline := InitiativeTimeline.new()
	var strategy := SimpleInitiativeStrategy.new()
	timeline.set_strategy(strategy)

	var units: Array[UnitState] = []
	for i in 4:
		var bag := _make_stats(10.0)
		# Разная инициатива -> детерминированный порядок без тай-брейков.
		bag.set_base_value(StatTypes.StatType.INITIATIVE, float(10 - i))
		var unit := UnitState.create(Faction.Type.ENEMY, Vector2i(i, 0), bag, "U%d" % i)
		units.append(unit)
		timeline.register_participant(unit)

	timeline.start_battle()
	_check(timeline.get_round_number() == 1, "battle starts at round 1")

	var first := timeline.advance_turn()
	var second := timeline.advance_turn()
	_check(first == units[0], "highest initiative goes first")
	_check(second == units[1], "second by initiative")
	_check(timeline.get_round_number() == 1, "still round 1")

	# Убиваем ТЕКУЩЕГО — худший случай для курсора.
	second.vitals.apply_damage(999.0)
	timeline.unregister_participant(second)

	_check(timeline.get_round_number() == 1, "round NOT restarted by death")

	var third := timeline.advance_turn()
	_check(third == units[2], "queue continues after the dead unit, not from start")
	_check(timeline.count_alive_of_faction(Faction.Type.ENEMY) == 3, "3 alive left")


## РЕГРЕССИЯ D-4.7: раньше границ раунда не существовало (advance_turn молча
## оборачивался через %), и tick-based статусы были нереализуемы.
func _test_round_boundary_signals() -> void:
	var timeline := InitiativeTimeline.new()
	timeline.set_strategy(SimpleInitiativeStrategy.new())

	for i in 2:
		var bag := _make_stats(10.0)
		bag.set_base_value(StatTypes.StatType.INITIATIVE, float(10 - i))
		timeline.register_participant(
			UnitState.create(Faction.Type.ENEMY, Vector2i(i, 0), bag, "R%d" % i)
		)

	var started: Array[int] = []
	var ended: Array[int] = []
	timeline.round_started.connect(func(n: int) -> void: started.append(n))
	timeline.round_ended.connect(func(n: int) -> void: ended.append(n))

	timeline.start_battle()
	timeline.advance_turn()
	timeline.advance_turn()
	# Третий вызов должен закрыть раунд 1 и открыть раунд 2.
	timeline.advance_turn()

	_check(timeline.get_round_number() == 2, "advanced to round 2")
	_check(ended.has(1), "round_ended(1) fired")
	_check(started.has(1) and started.has(2), "round_started fired for 1 and 2")


# --- Grid math -------------------------------------------------------------

## Базовый инвариант изометрии: grid -> screen -> grid должен вернуть
## исходную клетку. Идеальный кандидат в тест, т.к. глазами это не проверить.
func _test_grid_screen_roundtrip() -> void:
	var config := IsoGridConfig.new()
	var all_ok := true
	for x in range(-5, 6):
		for y in range(-5, 6):
			var cell := Vector2i(x, y)
			var world := IsoGridUtils.grid_to_screen(cell, config, 0)
			var back := IsoGridUtils.screen_to_grid_flat(world, config, 0)
			if back != cell:
				all_ok = false
				print("    roundtrip mismatch: %s -> %s -> %s" % [str(cell), str(world), str(back)])
	_check(all_ok, "grid->screen->grid roundtrip for 121 cells")

	# Высота смещает по экрану вверх, но не меняет логическую клетку.
	var elevated := IsoGridUtils.grid_to_screen(Vector2i(2, 2), config, 2)
	var flat := IsoGridUtils.grid_to_screen(Vector2i(2, 2), config, 0)
	_check_eq(flat.y - elevated.y, config.height_step * 2.0, "height shifts screen Y up")


# --- Pathfinder ------------------------------------------------------------

## ГЛАВНЫЙ ИНВАРИАНТ МОДУЛЯ 3 (ради него отказались от AStarGrid2D):
## find_path и get_reachable_cells обязаны подчиняться ОДНОМУ И ТОМУ ЖЕ
## правилу высоты. Если они разойдутся, зона хода покажет клетку, до которой
## юнит не сможет дойти.
func _test_path_and_reachable_agree_on_height_rule() -> void:
	var heights := {Vector2i(2, 0): 3}  # непреодолимый уступ
	var provider := GridDataProvider.new(
		func(_cell: Vector2i) -> bool: return true,
		func(cell: Vector2i) -> int: return heights.get(cell, 0),
		Callable()
	)
	var pathfinder := GridPathfinder.new()
	pathfinder.configure(Rect2i(0, 0, 5, 5), provider, 1)

	var reachable := pathfinder.get_reachable_cells(Vector2i(0, 0), 10.0)
	_check(not reachable.has(Vector2i(2, 0)), "3-level ledge excluded from move range")

	var path := pathfinder.find_path(Vector2i(0, 0), Vector2i(2, 0))
	_check(path.is_empty(), "find_path agrees: ledge unreachable")

	# Каждая клетка из зоны хода обязана иметь валидный путь.
	var all_consistent := true
	for key in reachable.keys():
		var cell: Vector2i = key
		if cell == Vector2i(0, 0):
			continue
		if pathfinder.find_path(Vector2i(0, 0), cell).is_empty():
			all_consistent = false
			print("    inconsistency: %s reachable but no path" % str(cell))
	_check(all_consistent, "every reachable cell has a path")


# --- AI scoring ------------------------------------------------------------

## РЕГРЕССИЯ S-3в. Раньше фактор, не имеющий мнения, возвращал 0.0, что при
## взвешенном среднем было голосом ПРОТИВ. Из-за этого в aggressor_profile
## любая атака была заведомо выше любого перемещения.
func _test_abstain_excluded_from_average() -> void:
	var profile := AIBehaviorProfile.new()
	profile.use_geometric_mean = false

	var always_high := _StubConsideration.new()
	always_high.fixed_score = 1.0
	always_high.weight = 1.0

	var always_abstain := _StubConsideration.new()
	always_abstain.fixed_score = AIConsideration.ABSTAIN
	always_abstain.weight = 1.0

	profile.considerations = [always_high, always_abstain]
	var action := AIAction.make_move(Vector2i(1, 1))
	var context := AIDecisionContext.new()

	# Если бы ABSTAIN считался как 0.0, было бы 0.5.
	_check_eq(profile.evaluate(action, context), 1.0, "ABSTAIN excluded from denominator")


func _test_veto_zeroes_candidate() -> void:
	var profile := AIBehaviorProfile.new()
	profile.use_geometric_mean = false

	var high := _StubConsideration.new()
	high.fixed_score = 1.0
	var veto := _StubConsideration.new()
	veto.fixed_score = AIConsideration.VETO

	profile.considerations = [high, veto]
	var score := profile.evaluate(AIAction.make_move(Vector2i(1, 1)), AIDecisionContext.new())
	_check_eq(score, 0.0, "VETO zeroes the candidate regardless of other factors")


## РЕГРЕССИЯ S-3г: решение ИИ обязано быть воспроизводимым, иначе реплеи и
## сиды роглайка не работают, а баг-репорты невозможно повторить.
func _test_ai_decision_is_deterministic() -> void:
	var profile: AIBehaviorProfile = load("res://resources/ai/aggressor_profile.tres")

	var first_cell := Vector2i.ZERO
	var first_type := AIAction.Type.IDLE
	var stable := true

	for attempt in 5:
		# Доска пересобирается заново каждый прогон — проверяем, что решение
		# зависит только от ситуации, а не от порядка обхода Dictionary.
		var board := _make_board(8, 8)
		var enemy := _make_unit(Faction.Type.ENEMY, Vector2i(5, 5), 3.0)
		var player := _make_unit(Faction.Type.PLAYER, Vector2i(3, 5), 0.0)
		board.add_unit(enemy)
		board.add_unit(player)

		var context := AIDecisionContext.build_from_board(enemy, board, 1)
		var pathfinder := GridPathfinder.new()
		pathfinder.configure(board.get_bounds(), context.data_provider, 1)

		var action := UtilityAIController.decide(enemy, profile, pathfinder, context, 1.0, 1)
		if attempt == 0:
			first_cell = action.final_cell
			first_type = action.action_type
		elif action.final_cell != first_cell or action.action_type != first_type:
			stable = false

	_check(stable, "same situation -> same decision across 5 runs")


## ИИ не должен выбирать клетки, занятые другими юнитами. До шага 0.4 это
## фильтровалось костылём в контроллере, который расходился с правилами
## pathfinding; теперь occupancy учтён в самом правиле проходимости.
func _test_ai_never_targets_occupied_cell() -> void:
	var board := _make_board(6, 6)
	var enemy := _make_unit(Faction.Type.ENEMY, Vector2i(0, 0), 3.0)
	var player := _make_unit(Faction.Type.PLAYER, Vector2i(3, 0), 0.0)
	var ally := _make_unit(Faction.Type.ENEMY, Vector2i(1, 0), 0.0)
	board.add_unit(enemy)
	board.add_unit(player)
	board.add_unit(ally)

	var context := AIDecisionContext.build_from_board(enemy, board, 1)
	var pathfinder := GridPathfinder.new()
	pathfinder.configure(board.get_bounds(), context.data_provider, 1)

	var profile: AIBehaviorProfile = load("res://resources/ai/aggressor_profile.tres")
	var action := UtilityAIController.decide(enemy, profile, pathfinder, context, 1.0, 1)

	_check(action.final_cell != player.cell, "AI does not step onto the player")
	_check(action.final_cell != ally.cell, "AI does not step onto its ally")
	_check(board.can_enter(action.final_cell, enemy), "chosen cell is actually enterable")


# --- Сериализация (R-4) ---------------------------------------------------

## Требование "Profile System + несколько слотов сохранений" невыполнимо, если
## состояние не round-trip'ится. Проверяем сразу, а не в конце проекта (G-2):
## иначе модуль сохранений превратился бы в переписывание боевых модулей.
func _test_board_roundtrip_serialization() -> void:
	var board := _make_board(5, 4)
	board.set_terrain(Vector2i(1, 1), TerrainType.Type.WALL)
	board.set_terrain(Vector2i(2, 2), TerrainType.Type.HAZARD)
	board.set_height(Vector2i(3, 1), 2)

	var unit := _make_unit(Faction.Type.PLAYER, Vector2i(0, 0), 5.0)
	unit.vitals.apply_damage(7.0)
	unit.vitals.add_impact(30.0)
	board.add_unit(unit)

	var restored := BattleBoard.from_dict(board.to_dict())

	_check(restored.width == 5 and restored.height == 4, "board size restored")
	_check(restored.get_terrain(Vector2i(1, 1)) == TerrainType.Type.WALL, "wall restored")
	_check(restored.get_terrain(Vector2i(2, 2)) == TerrainType.Type.HAZARD, "hazard restored")
	_check(restored.get_height(Vector2i(3, 1)) == 2, "height restored")

	var restored_unit := restored.get_unit_by_id(unit.id)
	_check(restored_unit != null, "unit restored by stable id")
	if restored_unit != null:
		_check(restored_unit.faction == Faction.Type.PLAYER, "faction restored")
		_check(restored_unit.cell == Vector2i(0, 0), "cell restored")
		_check_eq(restored_unit.vitals.get_hp(), unit.vitals.get_hp(), "current HP restored")
		_check_eq(
			restored_unit.vitals.get_balance(), unit.vitals.get_balance(),
			"current Balance restored"
		)
		_check_eq(
			restored_unit.get_stat(StatTypes.StatType.STRENGTH), 5.0,
			"stat base values restored"
		)
		# Occupancy восстанавливается ИЗ позиций юнитов, а не хранится вторым
		# списком — иначе два источника правды разошлись бы после загрузки.
		_check(restored.occupant_at(Vector2i(0, 0)) == restored_unit, "occupancy rebuilt")

	# Счётчик id обязан обогнать загруженные значения, иначе новый юнит
	# получит существующий id и перезапишет его в occupancy.
	_check(UnitId.get_counter() > unit.id, "UnitId counter advanced past loaded ids")


## Заглушка-фактор с фиксированной оценкой: позволяет тестировать САМУ
## агрегацию профиля, не завязываясь на конкретные тактические факторы.
class _StubConsideration extends AIConsideration:
	var fixed_score: float = 0.0

	func score(_action: AIAction, _context: AIDecisionContext) -> float:
		return fixed_score


class _NestedDamageSink extends RecordingEventSink:
	var nested_info: DamageInfo
	var _nested_applied: bool = false

	func unit_damaged(unit: UnitState, amount: float, source: Variant) -> void:
		super.unit_damaged(unit, amount, source)
		if not _nested_applied and nested_info != null:
			_nested_applied = true
			DamageCalculator.apply(nested_info, self)


class _BoardDeathSink extends RecordingEventSink:
	var board: BattleBoard
	var corpse: UnitState
	var mover: UnitState
	var saw_free_cell: bool = false
	var moved_other: bool = false

	func unit_died(unit: UnitState, source: Variant) -> void:
		super.unit_died(unit, source)
		saw_free_cell = board.can_enter(unit.cell)
		moved_other = board.move_unit(mover, unit.cell)

# Фрагмент P03a acceptance.
func _test_p03a_acceptance() -> void:
	_p3_definitions_and_occurrences()
	_p3_stat_pipeline()
	_p3_heal_ownership()
	_p3_identity_and_containers()
	_p3_validation()
	_p3_guards_and_teardown()
	_p3_legacy()
	_p3_demo_sink()
	_p3_board_boundary()
	_p3_preflight_edges()
	_p3_equipment_clear_order()


func _p3_unit(id_value: int = 1) -> UnitState:
	var unit := UnitState.new()
	unit.id = id_value
	unit.stats = StatsBag.from_base_values({StatTypes.StatType.HP_MAX: 10.0,
		StatTypes.StatType.STRENGTH: 3.0, StatTypes.StatType.BALANCE_MAX: 100.0})
	unit.vitals = Vitals.new(unit.stats)
	return unit


func _p3_def(id_value: StringName, effects: Array[ItemEffect]) -> ItemDef:
	var definition := ItemDef.new()
	definition.id = id_value
	definition.effects = effects
	return definition


func _p3_stat(value: float, operation: StatModifier.Operation = StatModifier.Operation.ADD_FLAT,
	stat_type: StatTypes.StatType = StatTypes.StatType.STRENGTH) -> StatModifierEffect:
	var effect := StatModifierEffect.new()
	effect.value = value
	effect.operation = operation
	effect.stat_type = stat_type
	return effect


func _p3_def_values(definition: ItemDef) -> Array:
	var values: Array = [definition.id, definition.display_name, definition.description,
		definition.effects.duplicate()]
	for effect in definition.effects:
		if effect is StatModifierEffect:
			var stat := effect as StatModifierEffect
			values.append([stat.stat_type, stat.operation, stat.value])
		elif effect is HealOnDamageEffect:
			var heal := effect as HealOnDamageEffect
			values.append([heal.trigger_event, heal.heal_amount])
	return values


func _p3_count(unit: UnitState, stat_type: StatTypes.StatType = StatTypes.StatType.STRENGTH) -> int:
	return (unit.stats._stats[stat_type] as Stat).get_modifier_count()


func _p3_damage(unit: UnitState, amount: float, sink: EventSink) -> void:
	var info := DamageInfo.new()
	info.target = unit
	info.final_damage = amount
	DamageCalculator.apply(info, sink)


func _p3_definitions_and_occurrences() -> void:
	var strength: ItemDef = load("res://resources/items/item_a_strength_boost.tres")
	var heal: ItemDef = load("res://resources/items/item_b_heal_on_damage.tres")
	_check(strength == load(strength.resource_path) and heal == load(heal.resource_path), "A01 cached real definitions")
	_check(strength is Item and heal is Item, "A01 legacy Item script compatibility")
	var before := [_p3_def_values(strength), _p3_def_values(heal)]
	var a := _p3_unit(1)
	var b := _p3_unit(2)
	var sa := ItemOwnerState.new(a)
	var sb := ItemOwnerState.new(b)
	var ia := InventoryState.new(sa)
	var ib := InventoryState.new(sb)
	var a1 := sa.create_item(strength)
	var a2 := sa.create_item(strength)
	var b1 := sb.create_item(strength)
	_check(a1 != a2 and a1 != b1 and a1.get_definition() == b1.get_definition(), "A01 shared def, independent instances")
	_check(a1.get_effects()[0] != a2.get_effects()[0] and a1.get_effects()[0] != b1.get_effects()[0], "A01 independent runtime identities")
	_check(ia.add_item(a1) and ia.add_item(a2) and ib.add_item(b1), "A02 copies activate")
	_check_eq(a.get_stat(StatTypes.StatType.STRENGTH), 7.0, "A02 A has two bonuses")
	_check_eq(b.get_stat(StatTypes.StatType.STRENGTH), 5.0, "A02 B has one bonus")
	var keys: Array[StringName] = []
	for item in [a1, a2, b1]:
		var runtime := item.get_effects()[0] as StatModifierEffectRuntime
		_check(not keys.has(runtime.get_source_key()), "A02 unique occurrence source")
		keys.append(runtime.get_source_key())
	_check(_p3_count(a) == 2 and _p3_count(b) == 1, "A02 modifier occurrence counts")
	_check(ia.remove_item(a1), "A02 remove first copy")
	_check_eq(a.get_stat(StatTypes.StatType.STRENGTH), 5.0, "A02 one A bonus remains")
	_check(_p3_count(a) == 1 and _p3_count(b) == 1, "A02 removal affects one occurrence")
	_check(ia.remove_item(a2), "A02 remove second copy")
	_check_eq(a.get_stat(StatTypes.StatType.STRENGTH), 3.0, "A02 A returns to base")
	_check_eq(b.get_stat(StatTypes.StatType.STRENGTH), 5.0, "A02 B unaffected")
	_check(ia.add_item(sa.create_item(heal)) and ib.add_item(sb.create_item(heal)), "A01 shared real heal definitions")
	sa.close()
	sb.close()
	_check(before == [_p3_def_values(strength), _p3_def_values(heal)], "A01 definitions unchanged after lifecycle")
	for definition in [strength, heal]:
		_check(not (&"item_id" in definition) and not (&"_owner" in definition), "A01 definition contains no owner identity")
		for effect in definition.effects:
			_check(not (&"item_id" in effect) and not (&"_bound_unit" in effect), "A01 effect contains no runtime owner")
	var shared := _p3_stat(2.0)
	var d1 := _p3_def(&"shared1", [shared, shared])
	var d2 := _p3_def(&"shared2", [shared])
	var s := ItemOwnerState.new(_p3_unit())
	var inv := InventoryState.new(s)
	var i1 := s.create_item(d1)
	var i2 := s.create_item(d2)
	var effects := i1.get_effects()
	_check(effects.size() == 2 and effects[0] != effects[1], "A03 repeated subresource creates two runtimes")
	_check(effects[0].get_effect_index() == 0 and effects[1].get_effect_index() == 1, "A03 effect index follows definition order")
	_check(effects[1].get_effect_instance_id() < i2.get_effects()[0].get_effect_instance_id(), "A03 effect ids cross item boundary monotonically")
	effects.clear()
	_check(i1.get_effects().size() == 2, "A03 runtime array is copied")
	_check(inv.add_item(i1) and inv.add_item(i2), "A03 shared effects activate")
	_check_eq(s.get_owner().get_stat(StatTypes.StatType.STRENGTH), 9.0, "A03 all three occurrences apply")
	inv.remove_item(i1)
	_check_eq(s.get_owner().get_stat(StatTypes.StatType.STRENGTH), 5.0, "A03 removing repeated item retains shared neighbour")
	s.close()


func _p3_stat_pipeline() -> void:
	var u := _p3_unit()
	var foreign := StatModifier.new(&"foreign", StatModifier.Operation.ADD_FLAT, 1.0)
	u.stats.add_modifier(StatTypes.StatType.STRENGTH, foreign)
	var state := ItemOwnerState.new(u)
	var eq := EquipmentState.new(state)
	var definition := _p3_def(&"pipeline", [_p3_stat(2.0),
		_p3_stat(0.5, StatModifier.Operation.ADD_PERCENT), _p3_stat(2.0, StatModifier.Operation.MULTIPLY),
		_p3_stat(-1.0, StatModifier.Operation.ADD_FLAT, StatTypes.StatType.ARMOR)])
	var item := state.create_item(definition)
	_check(eq.equip(EquipmentState.EquipSlot.WEAPON, item), "A04 all stat operations activate")
	_check_eq(u.get_stat(StatTypes.StatType.STRENGTH), 18.0, "A04 flat/percent/multiply pipeline")
	_check_eq(u.get_stat(StatTypes.StatType.ARMOR), -1.0, "A04 chosen stat and negative finite value")
	var snapshot := u.stats.to_snapshot_dict()
	_check(eq.equip(EquipmentState.EquipSlot.WEAPON, item), "A04 duplicate equip succeeds")
	_check(snapshot == u.stats.to_snapshot_dict(), "A04 duplicate equip preserves slots/counter/evaluation order")
	eq.unequip(EquipmentState.EquipSlot.WEAPON)
	_check_eq(u.get_stat(StatTypes.StatType.STRENGTH), 4.0, "A04 foreign modifier survives")
	_check(_p3_count(u) == 1 and (u.stats._stats[StatTypes.StatType.STRENGTH] as Stat)._modifiers[0] == foreign, "A04 foreign modifier identity preserved")
	_check_eq(u.stats.get_base_value(StatTypes.StatType.STRENGTH), 3.0, "A04 base unchanged")
	state.close()
	var order_state := ItemOwnerState.new(_p3_unit())
	var inv := InventoryState.new(order_state)
	var ordered := _p3_def(&"float-order", [_p3_stat(1.0e16), _p3_stat(-1.0e16), _p3_stat(1.0)])
	inv.add_item(order_state.create_item(ordered))
	_check_eq(order_state.get_owner().get_stat(StatTypes.StatType.STRENGTH), 4.0, "A04 semantic effect order retained in float sum")
	order_state.close()


func _p3_heal_ownership() -> void:
	var definition := _p3_def(&"heal", [HealOnDamageEffect.new()])
	var a := _p3_unit(1)
	var b := _p3_unit(2)
	var sa := ItemOwnerState.new(a)
	var sb := ItemOwnerState.new(b)
	var ia := InventoryState.new(sa)
	var ib := InventoryState.new(sb)
	var first := sa.create_item(definition)
	var second := sa.create_item(definition)
	var a_hp_listeners := a.vitals.hp_changed.get_connections().size()
	var b_hp_listeners := b.vitals.hp_changed.get_connections().size()
	ia.add_item(second)
	ia.add_item(first)
	ib.add_item(sb.create_item(definition))
	_check(a.vitals.hp_changed.get_connections().size() == a_hp_listeners and b.vitals.hp_changed.get_connections().size() == b_hp_listeners, "A05 core activation adds no local listeners")
	_check_eq(a.vitals.get_hp(), 10.0, "A05 equip alone does not heal or damage")
	var effects := sa.get_active_heal_effects()
	_check(effects.size() == 2 and effects[0].get_effect_instance_id() < effects[1].get_effect_instance_id(), "A05 active heals sorted by stable id")
	effects.clear()
	_check(sa.get_active_heal_effects().size() == 2, "A05 active heal array is copied")
	var ra := RecordingEventSink.new()
	var rb := RecordingEventSink.new()
	var sink_a := LegacyItemDemoSink.new(sa, ra)
	var sink_b := LegacyItemDemoSink.new(sb, rb)
	_p3_damage(a, 4.0, sink_a)
	_check_eq(a.vitals.get_hp(), 8.0, "A05 A heals twice")
	_check_eq(b.vitals.get_hp(), 10.0, "A05 B unaffected by A")
	_p3_damage(b, 4.0, sink_b)
	_check_eq(b.vitals.get_hp(), 7.0, "A05 B heals once")
	ia.remove_item(first)
	_p3_damage(a, 4.0, sink_a)
	_check_eq(a.vitals.get_hp(), 5.0, "A05 remaining A copy still reacts")
	_check(ra.count_of(&"unit_healed") == 3 and rb.count_of(&"unit_healed") == 1, "A05 independent reaction counts")
	sa.close()
	sb.close()


func _p3_identity_and_containers() -> void:
	var definition := _p3_def(&"identity", [_p3_stat(2.0)])
	var state := ItemOwnerState.new(_p3_unit())
	var inv := InventoryState.new(state)
	var eq := EquipmentState.new(state)
	var a := state.create_item(definition)
	var b := state.create_item(definition)
	var c := state.create_item(definition)
	_check(a.get_item_instance_id() == 1 and b.get_item_instance_id() == 2 and c.get_item_instance_id() == 3, "A06 item ids start at 1 monotonically")
	_check(a.get_effects()[0].get_effect_instance_id() == 1 and c.get_effects()[0].get_effect_instance_id() == 3, "A06 effect ids start at 1 monotonically")
	var events := [0]
	var added: Callable = func(_item: ItemInstance) -> void: events[0] += 1
	inv.item_added.connect(added)
	_check(inv.add_item(b) and inv.add_item(a), "A07 reverse-order add")
	_check(inv.get_items() == [b, a], "A07 add order retained")
	var stat_before := state.get_owner().stats.to_snapshot_dict()
	_check(inv.add_item(a) and events[0] == 2, "A07 duplicate add is silent true/no-op")
	_check(stat_before == state.get_owner().stats.to_snapshot_dict(), "A07 duplicate add preserves modifier state")
	_check(inv.count_of(definition.id) == 2 and inv.has_item(definition.id), "A07 count reflects copies")
	var copied := inv.get_items()
	copied.clear()
	_check(inv.size() == 2, "A07 item accessor copied")
	_check(not eq.equip(EquipmentState.EquipSlot.WEAPON, a), "A06 active inventory item cannot equip")
	inv.remove_item(a)
	_check(eq.equip(EquipmentState.EquipSlot.WEAPON, a) and a.get_item_instance_id() == 1, "A06 inventory to equipment preserves id")
	_check(not eq.equip(EquipmentState.EquipSlot.ARMOR, a), "A06 same item cannot occupy another slot")
	_check(not inv.remove_item(a), "A06 inventory cannot detach equipment item")
	var other := ItemOwnerState.new(_p3_unit())
	var foreign := other.create_item(definition)
	_check(not inv.add_item(foreign) and not eq.equip(EquipmentState.EquipSlot.WEAPON, foreign), "A06 equal numeric ids do not establish ownership")
	var manual := ItemInstance.new(definition, 1, 1, [])
	_check(not inv.add_item(manual) and not eq.equip(EquipmentState.EquipSlot.WEAPON, manual), "A06 manually created instance rejected")
	var duplicate := InventoryState.new(state)
	var duplicate_eq := EquipmentState.new(state)
	_check(duplicate.get_items().is_empty() and not duplicate.add_item(c), "A06 duplicate inventory cannot capture placements")
	_check(duplicate_eq.get_occupied_slots().is_empty() and not duplicate_eq.equip(EquipmentState.EquipSlot.TRINKET, c), "A06 duplicate equipment cannot capture placements")
	var slot_events := [0]
	var equipped: Callable = func(_slot: int, _item: ItemInstance) -> void: slot_events[0] += 1
	eq.item_equipped.connect(equipped)
	_check(eq.equip(EquipmentState.EquipSlot.WEAPON, a) and slot_events[0] == 0, "A07 duplicate equip silent")
	_check(eq.equip(EquipmentState.EquipSlot.WEAPON, c), "A07 valid replacement")
	_check(not a.is_active() and c.is_active() and b.is_active(), "A07 replacement only detaches old")
	stat_before = state.get_owner().stats.to_snapshot_dict()
	_check(not eq.equip(EquipmentState.EquipSlot.WEAPON, b), "A07 active replacement rejected")
	_check(eq.get_equipped(EquipmentState.EquipSlot.WEAPON) == c and stat_before == state.get_owner().stats.to_snapshot_dict() and slot_events[0] == 1, "A07 invalid replacement has no effects/signals")
	_check(eq.equip(EquipmentState.EquipSlot.TRINKET, a), "A07 populate out-of-order slot")
	inv.remove_item(b)
	_check(eq.equip(EquipmentState.EquipSlot.ARMOR, b), "A07 populate middle slot")
	var slots := eq.get_occupied_slots()
	_check(slots == [0, 1, 2], "A07 slots numerically ordered")
	slots.clear()
	_check(eq.get_occupied_slots() == [0, 1, 2], "A07 slots accessor copied")
	_check(eq.unequip(EquipmentState.EquipSlot.ARMOR) == b and inv.add_item(b), "A06 detach/re-add preserves instance")
	inv.item_added.disconnect(added)
	eq.item_equipped.disconnect(equipped)
	state.close()
	other.close()


class _P3UnknownEffect extends ItemEffect:
	pass


class _P3StatSubclass extends StatModifierEffect:
	pass


func _p3_validation() -> void:
	var state := ItemOwnerState.new(_p3_unit())
	var valid := _p3_def(&"valid", [_p3_stat(2.0)])
	var nan_stat := _p3_stat(NAN)
	var inf_stat := _p3_stat(INF)
	var bad_stat := _p3_stat(2.0)
	bad_stat.stat_type = 99 as StatTypes.StatType
	var bad_op := _p3_stat(2.0)
	bad_op.operation = 99 as StatModifier.Operation
	var negative_heal := HealOnDamageEffect.new()
	negative_heal.heal_amount = -1.0
	var nan_heal := HealOnDamageEffect.new()
	nan_heal.heal_amount = NAN
	var inf_heal := HealOnDamageEffect.new()
	inf_heal.heal_amount = INF
	var wrong_trigger := HealOnDamageEffect.new()
	wrong_trigger.trigger_event = TriggeredEffect.TriggerEvent.UNIT_HEALED
	var invalid: Array[ItemDef] = [null, _p3_def(&"", []), _p3_def(&"null", [null]),
		_p3_def(&"unknown", [_P3UnknownEffect.new()]), _p3_def(&"subclass", [_P3StatSubclass.new()]),
		_p3_def(&"nan", [nan_stat]), _p3_def(&"inf", [inf_stat]), _p3_def(&"stat", [bad_stat]),
		_p3_def(&"op", [bad_op]), _p3_def(&"negative", [negative_heal]), _p3_def(&"nanheal", [nan_heal]),
		_p3_def(&"infheal", [inf_heal]), _p3_def(&"trigger", [wrong_trigger]),
		_p3_def(&"last-invalid", [_p3_stat(2.0), null])]
	var before := state.get_owner().stats.to_snapshot_dict()
	for definition in invalid:
		_check(state.create_item(definition) == null, "A08 invalid definition rejected")
		_check(state._next_item_id == 1 and state._next_effect_id == 1, "A08 invalid create consumes no ids")
		_check(before == state.get_owner().stats.to_snapshot_dict(), "A08 invalid create leaves stats untouched")
	var first := state.create_item(valid)
	_check(first.get_item_instance_id() == 1, "A08 first successful id after failures")
	_check(state.create_item(_p3_def(&"valid", [_p3_stat(2.0)])) == null, "A08 different Resource with same definition id rejected")
	var empty := state.create_item(_p3_def(&"empty", []))
	_check(empty != null and empty.get_effects().is_empty(), "A08 empty effects accepted")
	var inv := InventoryState.new(state)
	var key := (first.get_effects()[0] as StatModifierEffectRuntime).get_source_key()
	state.get_owner().stats.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(key, StatModifier.Operation.ADD_FLAT, 11.0))
	before = state.get_owner().stats.to_snapshot_dict()
	_check(not inv.add_item(first), "A08 source collision rejects activation")
	_check(before == state.get_owner().stats.to_snapshot_dict() and not first.is_active(), "A08 collision leaves foreign modifier intact")
	state.close()
	_check(state.get_owner().stats.has_modifiers_from_source(key), "A08 collision foreign modifier survives close")
	for invalid_owner in [null, UnitState.new()]:
		var bad_owner_state := ItemOwnerState.new(invalid_owner)
		_check(bad_owner_state.create_item(valid) == null, "A08 invalid owner rejected")
		bad_owner_state.close()
	for broken_field in [&"id", &"stats", &"vitals"]:
		var broken := _p3_unit()
		broken.set(broken_field, 0 if broken_field == &"id" else null)
		var broken_state := ItemOwnerState.new(broken)
		_check(broken_state.create_item(valid) == null, "A08 incomplete owner rejected")
		broken_state.close()
	for exhausted_field in [&"_next_item_id", &"_next_effect_id"]:
		var exhausted := ItemOwnerState.new(_p3_unit())
		exhausted.set(exhausted_field, 9223372036854775807)
		_check(exhausted.create_item(valid) == null, "A08 exhausted counter rejected")
		_check(exhausted.get(exhausted_field) == 9223372036854775807, "A08 exhausted counter unchanged")
		exhausted.close()
	var edge := ItemOwnerState.new(_p3_unit())
	edge._next_item_id = 9223372036854775806
	edge._next_effect_id = 9223372036854775806
	_check(edge.create_item(_p3_def(&"too-many", [_p3_stat(1.0), _p3_stat(1.0)])) == null, "A08 whole effect allocation checked before overflow")
	var last := edge.create_item(valid)
	_check(last != null and last.get_item_instance_id() == 9223372036854775806 and last.get_effects()[0].get_effect_instance_id() == 9223372036854775806, "A08 final legal ids issued")
	_check(edge.create_item(valid) == null, "A08 exhaustion after final legal ids")
	edge.close()


func _p3_guards_and_teardown() -> void:
	var definition := _p3_def(&"guard", [_p3_stat(2.0), HealOnDamageEffect.new()])
	var u := _p3_unit()
	u.stats.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"outside", StatModifier.Operation.ADD_FLAT, 1.0))
	var state := ItemOwnerState.new(u)
	var inv := InventoryState.new(state)
	var eq := EquipmentState.new(state)
	var a := state.create_item(definition)
	var b := state.create_item(definition)
	var entered := [false]
	var added: Callable = func(item: ItemInstance) -> void:
		if entered[0]:
			return
		entered[0] = true
		_check(item == a and inv.get_items() == [a] and a.is_active(), "A09 item_added sees consistent final state")
		_check(state.create_item(definition) == null, "A09 nested create rejected")
		_check(not inv.add_item(b) and not inv.remove_item(a), "A09 nested inventory mutations rejected")
		_check(not eq.equip(EquipmentState.EquipSlot.WEAPON, b) and eq.unequip(EquipmentState.EquipSlot.WEAPON) == null, "A09 nested equipment mutations rejected")
		inv.clear()
		eq.clear()
		inv.close()
		eq.close()
		state.close()
		_check(inv.get_items() == [a] and not state.is_closed(), "A09 nested clear/close no-op")
	inv.item_added.connect(added)
	_check(inv.add_item(a), "A09 outer add succeeds")
	inv.item_added.disconnect(added)
	_check(inv.remove_item(a), "A09 guard released after item_added")
	_check(eq.equip(EquipmentState.EquipSlot.WEAPON, a), "A09 equip after guard")
	var removed: Callable = func(_slot: int, item: ItemInstance) -> void:
		_check(item == a and eq.get_equipped(EquipmentState.EquipSlot.WEAPON) == b, "A09 unequipped sees committed replacement")
		_check_eq(u.get_stat(StatTypes.StatType.STRENGTH), 6.0, "A09 replacement signals see final stats")
		_check(state.create_item(definition) == null and not inv.add_item(a), "A09 nested create/add from unequipped rejected")
		_check(not eq.equip(EquipmentState.EquipSlot.ARMOR, a) and not inv.remove_item(b), "A09 nested equip/remove from unequipped rejected")
		inv.clear()
		eq.clear()
		state.close()
		_check(not state.is_closed() and eq.get_equipped(EquipmentState.EquipSlot.WEAPON) == b, "A09 nested clear/close from unequipped rejected")
	eq.item_unequipped.connect(removed)
	_check(eq.equip(EquipmentState.EquipSlot.WEAPON, b), "A09 replacement operation")
	eq.item_unequipped.disconnect(removed)
	inv.add_item(a)
	var c := state.create_item(definition)
	inv.add_item(c)
	var cleared_ids: Array[int] = []
	var clear_notice: Callable = func(item: ItemInstance) -> void:
		cleared_ids.append(item.get_item_instance_id())
		_check(inv.get_items().is_empty(), "A09 clear signals see empty inventory")
		_check_eq(u.get_stat(StatTypes.StatType.STRENGTH), 6.0, "A09 clear signals see all inventory modifiers removed")
		_check(not inv.add_item(item), "A09 clear keeps guard through all notifications")
	inv.item_removed.connect(clear_notice)
	inv.clear()
	inv.clear()
	inv.item_removed.disconnect(clear_notice)
	_check(cleared_ids == [a.get_item_instance_id(), c.get_item_instance_id()], "A09 clear notifies in item-id order once")
	_check(inv.add_item(a), "A09 clear allows later reuse")
	var notices := [0]
	var inv_notice: Callable = func(_item: ItemInstance) -> void: notices[0] += 1
	var eq_notice: Callable = func(_slot: int, _item: ItemInstance) -> void: notices[0] += 1
	inv.item_removed.connect(inv_notice)
	eq.item_unequipped.connect(eq_notice)
	var held_runtime := b.get_effects()[1]
	state.close()
	_check(notices[0] == 0, "A09 owner.close emits no item signals")
	_check(inv.size() == 0 and inv.count_of(definition.id) == 0 and not inv.has_item(definition.id), "A09 closed inventory accessors empty")
	_check(eq.get_occupied_slots().is_empty() and not eq.is_slot_occupied(EquipmentState.EquipSlot.WEAPON) and eq.get_equipped(EquipmentState.EquipSlot.WEAPON) == null, "A09 closed equipment accessors empty")
	_check(inv.to_dict() == {"item_paths": []} and eq.to_dict() == {"slots": {}}, "A09 closed legacy DTOs empty")
	_check(not a.is_active() and not b.is_active() and not held_runtime.is_active(), "A09 held runtime references inactive")
	_check(not inv.add_item(c) and not eq.equip(EquipmentState.EquipSlot.WEAPON, c) and state.create_item(definition) == null, "A09 no reactivation after owner.close")
	inv.close()
	eq.close()
	state.close()
	_check(notices[0] == 0 and u.stats.has_modifiers_from_source(&"outside") and _p3_count(u) == 1, "A09 repeated teardown keeps foreign modifier and stays silent")
	inv.item_removed.disconnect(inv_notice)
	eq.item_unequipped.disconnect(eq_notice)
	var separate := ItemOwnerState.new(_p3_unit())
	var separate_inv := InventoryState.new(separate)
	var separate_eq := EquipmentState.new(separate)
	var i1 := separate.create_item(definition)
	var i2 := separate.create_item(definition)
	separate_inv.add_item(i1)
	separate_eq.equip(EquipmentState.EquipSlot.WEAPON, i2)
	separate_inv.close()
	_check(not i1.is_active() and i2.is_active() and separate_eq.get_equipped(EquipmentState.EquipSlot.WEAPON) == i2, "A09 container.close leaves other kind active")
	_check(not separate_inv.add_item(i1) and not InventoryState.new(separate).add_item(i1), "A09 retired kind cannot reopen")
	_check(separate_eq.unequip(EquipmentState.EquipSlot.WEAPON) == i2 and separate_eq.equip(EquipmentState.EquipSlot.ARMOR, i2), "A09 other kind remains mutable")
	separate.close()
	# Регистрация внутри stat_changed также является вложенной мутацией owner API.
	var construction := ItemOwnerState.new(_p3_unit())
	var initial_inv := InventoryState.new(construction)
	var attempted: Array[EquipmentState] = []
	var on_stat: Callable = func(_type: int, _old: float, _new: float) -> void:
		attempted.append(EquipmentState.new(construction))
	construction.get_owner().stats.stat_changed.connect(on_stat)
	initial_inv.add_item(construction.create_item(definition))
	construction.get_owner().stats.stat_changed.disconnect(on_stat)
	_check(attempted.size() == 1 and attempted[0].get_occupied_slots().is_empty(), "A09 nested constructor inert")
	var real_equipment := EquipmentState.new(construction)
	_check(real_equipment.equip(EquipmentState.EquipSlot.WEAPON, construction.create_item(definition)), "A09 nested constructor did not consume registration")
	construction.close()


func _p3_legacy() -> void:
	var strength: ItemDef = load("res://resources/items/item_a_strength_boost.tres")
	var heal: ItemDef = load("res://resources/items/item_b_heal_on_damage.tres")
	var state := ItemOwnerState.new(_p3_unit())
	var inv := InventoryState.from_dict({"item_paths": [strength.resource_path, strength.resource_path, heal.resource_path]}, state)
	_check(inv != null and inv.size() == 3 and inv.count_of(strength.id) == 2, "A10 legacy inventory retains duplicates")
	_check_eq(state.get_owner().get_stat(StatTypes.StatType.STRENGTH), 7.0, "A10 fresh equip applies bonuses once")
	_check(inv.get_items()[0] != inv.get_items()[1], "A10 duplicate paths become distinct instances")
	var fresh := ItemOwnerState.new(_p3_unit())
	var roundtrip := InventoryState.from_dict(inv.to_dict(), fresh)
	_check(roundtrip.to_dict() == inv.to_dict() and roundtrip.get_items()[0] != inv.get_items()[0], "A10 inventory roundtrip shape and new identities")
	_check_eq(fresh.get_owner().get_stat(StatTypes.StatType.STRENGTH), 7.0, "A10 inventory roundtrip no double bonus")
	_check(InventoryState.from_dict(inv.to_dict(), state) == null, "A10 second inventory load rejected")
	var slots_a := {"2": heal.resource_path, "0": strength.resource_path, "1": strength.resource_path}
	var slots_b := {"1": strength.resource_path, "2": heal.resource_path, "0": strength.resource_path}
	var eq1 := EquipmentState.from_dict({"slots": slots_a}, state)
	var eq2 := EquipmentState.from_dict({"slots": slots_b}, fresh)
	_check(eq1.get_occupied_slots() == [0, 1, 2] and eq2.get_occupied_slots() == [0, 1, 2], "A10 every equipment slot restored")
	_check(eq1.to_dict() == {"slots": slots_a} and eq1.to_dict() == eq2.to_dict(), "A10 equipment legacy shape")
	for raw_slot in [0, 1, 2]:
		var slot := raw_slot as EquipmentState.EquipSlot
		var one := eq1.get_equipped(slot)
		var two := eq2.get_equipped(slot)
		_check(one.get_item_instance_id() == two.get_item_instance_id() and one.get_effects()[0].get_effect_instance_id() == two.get_effects()[0].get_effect_instance_id(), "A10 slot insertion order does not affect ids")
	_check_eq(state.get_owner().get_stat(StatTypes.StatType.STRENGTH), 11.0, "A10 both kinds load in one state")
	_check(EquipmentState.from_dict({"slots": slots_a}, state) == null, "A10 second equipment load rejected")
	state.close()
	fresh.close()
	var bad_paths := ItemOwnerState.new(_p3_unit())
	var skipped := InventoryState.from_dict({"item_paths": ["res://missing-p03a.tres", "res://icon.svg", 123, strength.resource_path]}, bad_paths)
	_check(skipped.size() == 1 and skipped.get_items()[0].get_item_instance_id() == 1, "A10 missing path/wrong type consumes no inventory ids")
	bad_paths.close()
	var bad_slots := ItemOwnerState.new(_p3_unit())
	var skipped_eq := EquipmentState.from_dict({"slots": {"nonsense": strength.resource_path, "9": strength.resource_path,
		"0": "res://missing-p03a.tres", "1": "res://icon.svg", "2": heal.resource_path}}, bad_slots)
	_check(skipped_eq.get_occupied_slots() == [2] and skipped_eq.get_equipped(EquipmentState.EquipSlot.TRINKET).get_item_instance_id() == 1, "A10 invalid slot/path/type consumes no equipment ids")
	bad_slots.close()
	for equipment in [false, true]:
		var u := _p3_unit()
		u.stats.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"p03a/o1/i1/e1", StatModifier.Operation.ADD_FLAT, 11.0))
		var collision_state := ItemOwnerState.new(u)
		var accepted: ItemInstance
		if equipment:
			var loaded_eq := EquipmentState.from_dict({"slots": {"1": heal.resource_path, "0": strength.resource_path}}, collision_state)
			_check(loaded_eq.get_occupied_slots() == [1], "A10 colliding equipment record skipped")
			accepted = loaded_eq.get_equipped(EquipmentState.EquipSlot.ARMOR)
		else:
			var loaded_inv := InventoryState.from_dict({"item_paths": [strength.resource_path, heal.resource_path]}, collision_state)
			_check(loaded_inv.size() == 1, "A10 colliding inventory record skipped")
			if loaded_inv.size() == 1:
				accepted = loaded_inv.get_items()[0]
		_check(accepted != null and accepted.get_item_instance_id() == 1, "A10 rejected record did not spend item id")
		if accepted != null:
			_check(accepted.get_effects()[0].get_effect_instance_id() == 1, "A10 rejected record did not spend effect id")
		collision_state.close()
		_check(u.stats.has_modifiers_from_source(&"p03a/o1/i1/e1") and _p3_count(u) == 1, "A10 foreign source preserved after teardown")


class _P3HookSink extends RecordingEventSink:
	var after_healed: Callable
	var after_damaged: Callable
	func unit_healed(unit: UnitState, amount: float, source: Variant) -> void:
		super.unit_healed(unit, amount, source)
		if after_healed.is_valid():
			after_healed.call()
	func unit_damaged(unit: UnitState, amount: float, source: Variant) -> void:
		super.unit_damaged(unit, amount, source)
		if after_damaged.is_valid():
			after_damaged.call()


func _p3_demo_sink() -> void:
	var heal: ItemDef = load("res://resources/items/item_b_heal_on_damage.tres")
	var u := _p3_unit()
	var state := ItemOwnerState.new(u)
	var inv := InventoryState.new(state)
	var first := state.create_item(heal)
	var second := state.create_item(heal)
	inv.add_item(first)
	var records := RecordingEventSink.new()
	var sink := LegacyItemDemoSink.new(state, records)
	_p3_damage(u, 4.0, sink)
	_check_eq(u.vitals.get_hp(), 7.0, "A11 real DamageCalculator 10 -> 7")
	_check(records.event_sequence() == [&"unit_damaged", &"unit_healed"], "A11 damaged precedes healed")
	_check_eq(u.stats.get_base_value(StatTypes.StatType.HP_MAX), 10.0, "A11 HP_MAX base preserved")
	_check_eq(u.stats.get_base_value(StatTypes.StatType.STRENGTH), 3.0, "A11 STR base preserved")
	var source: Dictionary = records.records[1]["args"][2]
	_check(source == {"owner_unit_id": 1, "item_instance_id": 1, "effect_instance_id": 1, "definition_id": heal.id}, "A11 source contains value identity")
	source["item_instance_id"] = 999
	_check(first.get_item_instance_id() == 1, "A11 source DTO not runtime storage")
	inv.add_item(second)
	u.vitals.heal(100.0)
	records.clear()
	_p3_damage(u, 0.5, sink)
	_check_eq(u.vitals.get_hp(), 10.0, "A11 multiple heals clamp at maximum")
	_check(records.count_of(&"unit_healed") == 1 and records.records[1]["args"][1] == 0.5, "A11 only actual healing emits event")
	records.clear()
	_p3_damage(u, 0.0, sink)
	_check(records.records.is_empty(), "A11 zero damage apply has no events")
	u.vitals.apply_damage(2.0)
	sink.unit_damaged(u, 0.0, &"zero")
	_check_eq(u.vitals.get_hp(), 8.0, "A11 explicit zero event does not heal")
	_check(records.count_of(&"unit_damaged") == 1 and records.count_of(&"unit_healed") == 0, "A11 zero event is forwarded only")
	var foreign := _p3_unit(1)
	records.clear()
	_p3_damage(foreign, 4.0, sink)
	_check_eq(foreign.vitals.get_hp(), 6.0, "A11 same numeric owner id but different object does not heal")
	_check(records.count_of(&"unit_damaged") == 1 and records.count_of(&"unit_healed") == 0, "A11 foreign damaged forwarded without reaction")
	records.clear()
	_p3_damage(u, 100.0, sink)
	_check(not u.is_alive() and u.vitals.get_hp() == 0.0, "A11 lethal damage never resurrects")
	_check(records.count_of(&"unit_died") == 1 and records.count_of(&"unit_damaged") == 1 and records.count_of(&"unit_healed") == 0, "A11 lethal domain event counts")
	_p3_damage(u, 100.0, sink)
	_check(records.count_of(&"unit_died") == 1 and records.count_of(&"unit_damaged") == 1, "A11 repeated corpse apply has no duplicate events")
	records.clear()
	var marker := {"marker": 8}
	sink.unit_healed(u, 2.0, marker)
	sink.unit_died(u, marker)
	sink.unit_balance_changed(u, 1.0, 2.0)
	sink.unit_balance_broken(u)
	sink.unit_pushed(u, Vector2i(1, 2), Vector2i(2, 3))
	sink.unit_moved(u, Vector2i(3, 4), Vector2i(4, 5))
	sink.turn_started(u)
	sink.turn_ended(u)
	sink.round_started(12)
	sink.round_ended(12)
	_check(records.event_sequence() == [&"unit_healed", &"unit_died", &"unit_balance_changed", &"unit_balance_broken", &"unit_pushed", &"unit_moved", &"turn_started", &"turn_ended", &"round_started", &"round_ended"], "A11 every other EventSink method forwarded")
	_check(records.records[0]["args"] == [u, 2.0, marker] and records.records[4]["args"] == [u, Vector2i(1, 2), Vector2i(2, 3)] and records.records[9]["args"] == [12], "A11 forwarding preserves arguments")
	state.close()
	var zero := HealOnDamageEffect.new()
	zero.heal_amount = 0.0
	var zero_state := ItemOwnerState.new(_p3_unit())
	var zero_inv := InventoryState.new(zero_state)
	zero_inv.add_item(zero_state.create_item(_p3_def(&"zero", [zero])))
	var zero_records := RecordingEventSink.new()
	_p3_damage(zero_state.get_owner(), 4.0, LegacyItemDemoSink.new(zero_state, zero_records))
	_check(zero_state.get_owner().vitals.get_hp() == 6.0 and zero_records.count_of(&"unit_healed") == 0, "A11 zero heal produces no event")
	zero_state.close()
	for close_owner in [false, true]:
		var local := ItemOwnerState.new(_p3_unit())
		var local_inv := InventoryState.new(local)
		var one := local.create_item(heal)
		var two := local.create_item(heal)
		local_inv.add_item(one)
		local_inv.add_item(two)
		var hook := _P3HookSink.new()
		hook.after_healed = func() -> void:
			if close_owner:
				local.close()
			else:
				local_inv.remove_item(two)
		_p3_damage(local.get_owner(), 4.0, LegacyItemDemoSink.new(local, hook))
		_check(local.get_owner().vitals.get_hp() == 7.0 and hook.count_of(&"unit_healed") == 1, "A11 runtime active/closed rechecked between heals")
		hook.after_healed = Callable()
		local.close()


func _p3_board_boundary() -> void:
	var board := BattleBoard.new()
	board.resize(3, 3)
	var unit := _p3_unit()
	unit.cell = Vector2i(1, 1)
	unit.move_points_left = 2.5
	unit.has_attacked = true
	board.add_unit(unit)
	var before_version := board.board_version
	var before_allocator := UnitId.get_counter()
	var state := ItemOwnerState.new(unit)
	var inv := InventoryState.new(state)
	var definition := _p3_def(&"boundary", [_p3_stat(2.0), HealOnDamageEffect.new()])
	for _iteration in range(3):
		var item := state.create_item(definition)
		inv.add_item(item)
		var result := SimulationSnapshot.capture_board(board, [&"unit/1/items"])
		_check(result.code == BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED, "A12 item harness declares unsupported runtime")
		inv.remove_item(item)
	state.close()
	_check(UnitId.get_counter() == before_allocator, "A12 ownership never advances UnitId allocator")
	_check(unit.cell == Vector2i(1, 1) and board.board_version == before_version and board.occupant_at(unit.cell) == unit, "A12 ownership does not move units/change board version")
	_check(unit.move_points_left == 2.5 and unit.has_attacked, "A12 ownership leaves action resources untouched")
	_check(unit.vitals.get_hp() == 10.0, "A12 core ownership leaves vitals untouched")


func _p3_preflight_edges() -> void:
	# Коллизия должна проверяться для каждого stat occurrence, не только первого.
	var late_stat := _p3_def(&"late-stat", [HealOnDamageEffect.new(), _p3_stat(2.0)])
	var heal_only := _p3_def(&"after-late-collision", [HealOnDamageEffect.new()])
	var legacy_unit := _p3_unit()
	legacy_unit.stats.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(&"p03a/o1/i1/e2", StatModifier.Operation.ADD_FLAT, 9.0))
	var legacy_state := ItemOwnerState.new(legacy_unit)
	var legacy_inv := InventoryState.from_dict({"item_paths": [late_stat.resource_path]}, legacy_state)
	# Resource без пути сознательно не грузится legacy API; проверяем приватный
	# preflight через зарегистрированное определение с временным Resource path невозможно.
	_check(legacy_inv.size() == 0, "A10 pathless legacy entry skipped")
	var direct := legacy_state.create_item(late_stat)
	_check(direct != null and not legacy_inv.add_item(direct), "A10 last stat source collision rejects activation")
	_check(direct.get_item_instance_id() == 1 and direct.get_effects()[1].get_effect_instance_id() == 2, "A10 direct occurrence identities include last stat")
	legacy_state.close()

	var u := _p3_unit()
	var state := ItemOwnerState.new(u)
	var equipment := EquipmentState.new(state)
	var old := state.create_item(_p3_def(&"old", [_p3_stat(2.0)]))
	var replacement := state.create_item(_p3_def(&"replacement", [_p3_stat(3.0)]))
	_check(equipment.equip(EquipmentState.EquipSlot.WEAPON, old), "A07 preflight edge equips old item")
	var collision := (replacement.get_effects()[0] as StatModifierEffectRuntime).get_source_key()
	u.stats.add_modifier(StatTypes.StatType.STRENGTH, StatModifier.new(collision, StatModifier.Operation.ADD_FLAT, 11.0))
	var before := u.stats.to_snapshot_dict()
	_check(not equipment.equip(EquipmentState.EquipSlot.WEAPON, replacement), "A07 replacement collision rejected before detach")
	_check(equipment.get_equipped(EquipmentState.EquipSlot.WEAPON) == old and old.is_active() and not replacement.is_active() and before == u.stats.to_snapshot_dict(), "A07 rejected replacement preserves old placement and stats")
	state.close()


func _p3_equipment_clear_order() -> void:
	var unit := _p3_unit()
	unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	var state := ItemOwnerState.new(unit)
	var equipment := EquipmentState.new(state)
	var first := state.create_item(_p3_def(&"clear-one", [_p3_stat(2.0)]))
	var second := state.create_item(_p3_def(&"clear-two", [_p3_stat(3.0)]))
	_check(equipment.equip(EquipmentState.EquipSlot.TRINKET, first) and equipment.equip(EquipmentState.EquipSlot.WEAPON, second), "A09 clear order fixture")
	_check_eq(unit.get_stat(StatTypes.StatType.STRENGTH), 8.0, "A09 clear order starts stacked")
	var changed: Array[float] = []
	var notices: Array[int] = []
	var on_stat: Callable = func(_type: int, _old: float, new_value: float) -> void:
		changed.append(new_value)
	var on_notice: Callable = func(_slot: int, item: ItemInstance) -> void:
		notices.append(item.get_item_instance_id())
		_check(equipment.get_occupied_slots().is_empty() and unit.get_stat(StatTypes.StatType.STRENGTH) == 3.0, "A09 equipment clear notices see final state")
	unit.stats.stat_changed.connect(on_stat)
	equipment.item_unequipped.connect(on_notice)
	equipment.clear()
	equipment.clear()
	unit.stats.stat_changed.disconnect(on_stat)
	equipment.item_unequipped.disconnect(on_notice)
	_check(changed == [6.0, 3.0], "A09 equipment clear removes modifiers by item id")
	_check(notices == [1, 2], "A09 equipment clear notices by item id once")
	state.close()

# P03b: независимые oracle/boundary проверки ведущего, интегрируются в runner.
func _p03b_same_snapshot(a: ItemSimulationSnapshot, b: ItemSimulationSnapshot, label: String) -> void:
	_check(a.to_dict() == b.to_dict(), label + " DTO")
	_check(a.canonical_values() == b.canonical_values(), label + " values")
	_check(a.canonical_bytes() == b.canonical_bytes() and a.fingerprint() == b.fingerprint(), label + " bytes/hash")

func _p03b_minimal_dto() -> Dictionary:
	var board := BattleBoard.new(1, 1)
	var unit := _p02_unit(1, Vector2i.ZERO, _make_stats())
	board.add_unit(unit)
	return ItemSimulationSnapshot.capture(ItemSimulationState.new(board, [ItemOwnerState.new(unit)], [], []), []).snapshot.to_dict()

func _test_p03b_b11_codec() -> void:
	var f := _p03b_fixture()
	var snap := _p03b_capture(f).snapshot
	var data := snap.to_dict()
	data["owners"].reverse()
	for owner: Dictionary in data["owners"]:
		owner["definitions"].reverse()
		owner["items"].reverse()
		for item: Dictionary in owner["items"]: item["effects"].reverse()
	data["board_snapshot"]["board"]["units"].reverse()
	_p03b_same_snapshot(snap, ItemSimulationSnapshot.from_dict(data).snapshot, "B11 record permutations")
	data = snap.to_dict()
	data["owners"][0]["inventory_order"].reverse()
	var changed := ItemSimulationSnapshot.from_dict(data).snapshot
	_check(changed != null and changed.canonical_values() != snap.canonical_values() and changed.canonical_bytes() != snap.canonical_bytes(), "B11 semantic inventory order")
	data = snap.to_dict()
	data["owners"][0]["definitions"][0]["effects"].reverse()
	_check(ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B11 ordered definitions cannot drift from runtime")
	# Фикстура целого envelope вычислена отдельно по спецификации тегов, не через codec Godot.
	var empty := ItemSimulationSnapshot.capture(ItemSimulationState.new(BattleBoard.new(), [], [], []), []).snapshot
	var literal := "5030334201050400000000000000050200000000000000040e00000000000000626f6172645f736e617073686f74050300000000000000050200000000000000040500000000000000626f617264050800000000000000050200000000000000040d00000000000000626f6172645f76657273696f6e020100000000000000050200000000000000040600000000000000686569676874020000000000000000050200000000000000040700000000000000686569676874730500000000000000000502000000000000000409000000000000006f63637570616e6379050000000000000000050200000000000000040e00000000000000736368656d615f76657273696f6e0201000000000000000502000000000000000407000000000000007465727261696e050000000000000000050200000000000000040500000000000000756e6974730500000000000000000502000000000000000405000000000000007769647468020000000000000000050200000000000000040e00000000000000736368656d615f76657273696f6e02010000000000000005020000000000000004050000000000000073636f7065041600000000000000626f6172645f6f6e6c795f6e6f5f6974656d735f76310502000000000000000406000000000000006f776e657273050000000000000000050200000000000000040e00000000000000736368656d615f76657273696f6e02010000000000000005020000000000000004050000000000000073636f7065041a00000000000000626f6172645f6974656d735f74776f5f656666656374735f7631".hex_decode()
	_check(empty.canonical_bytes() == literal, "B11 independent literal outer envelope")
	data = _p03b_minimal_dto()
	data["owners"][0]["next_item_id"] = 9223372036854775807
	data["owners"][0]["next_effect_id"] = 9007199254740993
	data["board_snapshot"]["board"]["units"][0]["debug_name"] = "Я😀А"
	data["board_snapshot"]["board"]["units"][0]["move_points_left"] = -0.0
	var high := ItemSimulationSnapshot.from_dict(data).snapshot
	_check(high != null and high.to_dict()["owners"][0]["next_effect_id"] == 9007199254740993, "B11 high int64 stays exact")
	data["board_snapshot"]["board"]["units"][0]["move_points_left"] = 0.0
	_check(high.canonical_bytes() == ItemSimulationSnapshot.from_dict(data).snapshot.canonical_bytes(), "B11 negative zero canonical equality")
	var leaf: Array = [9223372036854775807, 9007199254740993, "Я😀А", -0.0, 1.5]
	var bytes := PackedByteArray()
	SimulationSnapshot._encode(leaf, bytes)
	var leaf_literal := "05050000000000000002ffffffffffffff7f020100000000002000040800000000000000d0aff09f9880d09003000000000000000003000000000000f83f".hex_decode()
	_check(bytes == leaf_literal, "B11 independent high-int Unicode float bytes")
	data = snap.to_dict()
	var mods: Array = []
	for entry: Dictionary in data["board_snapshot"]["board"]["units"][0]["stats"]["stats"]:
		if entry["stat_type"] == 3: mods = entry["stat"]["modifiers"]
	var order: int = mods[0]["evaluation_order"]
	mods[0]["evaluation_order"] = mods[1]["evaluation_order"]
	mods[1]["evaluation_order"] = order
	changed = ItemSimulationSnapshot.from_dict(data).snapshot
	_check(changed != null and changed.canonical_bytes() != snap.canonical_bytes(), "B11 P02 evaluation order remains semantic")

func _test_p03b_b12_ownership_limits() -> void:
	var f := _p03b_fixture()
	var input := _p03b_capture(f).snapshot.to_dict()
	var imported := ItemSimulationSnapshot.from_dict(input).snapshot
	var original := imported.canonical_bytes()
	input["owners"][0]["items"].clear()
	var copy := imported.to_dict()
	copy["owners"][0]["definitions"][0]["effects"].clear()
	var canonical := imported.canonical_values()
	canonical[0][1].clear()
	var bytes := imported.canonical_bytes()
	bytes[0] = 0
	_check(imported.canonical_bytes() == original, "B12 nested input/output/bytes mutation isolated")
	_p03b_same_snapshot(imported, ItemSimulationSnapshot.capture(imported.instantiate(_p03b_catalogue(f.definition)).state, []).snapshot, "B12 restore after DTO mutations")
	var diagnostic := ItemSimulationSnapshot.capture(f.state, [&"Я", &"A", &"Я"])
	var ids := diagnostic.unsupported_ids
	ids.clear()
	_check(diagnostic.unsupported_ids == [&"A", &"Я"], "B12 diagnostics copied sorted unique")
	var data := _p03b_minimal_dto()
	data["board_snapshot"]["board"]["units"][0]["debug_name"] = "А".repeat(2048)
	_check(ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.OK, "B12 UTF8 string exact 4096 bytes")
	data["board_snapshot"]["board"]["units"][0]["debug_name"] += "a"
	_check(ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B12 string bytes +1")
	for cap: String in ["items", "definitions", "effects", "definition_effects"]:
		data = _p03b_minimal_dto()
		var owner: Dictionary = data["owners"][0]
		var heal := {"kind": "heal_on_damage", "trigger_event": 0, "heal_amount": 0.0}
		var definition := {"id": "cap", "effects": []}
		owner["definitions"] = [definition]
		var item := {"item_instance_id": 1, "definition_id": "cap", "placement": 0, "active": false, "effects": []}
		if cap == "items":
			owner["next_item_id"] = 4098
			for i in 4096:
				var record: Dictionary = item.duplicate(true)
				record["item_instance_id"] = i + 1
				owner["items"].append(record)
		elif cap == "definitions":
			owner["definitions"] = []
			for i in 4096: owner["definitions"].append({"id": "d%d" % i, "effects": []})
		else:
			for i in 16384: definition["effects"].append(heal)
			if cap == "effects":
				owner["next_item_id"] = 2
				owner["next_effect_id"] = 16386
				owner["items"] = [item]
				for i in 16384: item["effects"].append({"effect_instance_id": i + 1, "effect_index": i, "active": false, "kind": "heal_on_damage", "trigger_event": 0, "heal_amount": 0.0})
		var accepted := ItemSimulationSnapshot.from_dict(data)
		_check(accepted.code == ItemSnapshotResult.Code.OK, "B12 exact cap " + cap, accepted.reason)
		if cap == "items": owner["items"].append(item)
		elif cap == "definitions": owner["definitions"].append({"id": "overflow", "effects": []})
		elif cap == "effects": item["effects"].append(item["effects"][0])
		else: definition["effects"].append(heal)
		var rejected := ItemSimulationSnapshot.from_dict(data)
		_check(rejected.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID and rejected.reason.ends_with("/limit"), "B12 cap +1 " + cap, rejected.reason)
	# Aliases разрешены: каждый occurrence считается, затем получает отдельную value-копию.
	data = _p03b_minimal_dto()
	data["owners"][0]["definitions"] = [{"id": "alias", "effects": [{"kind": "heal_on_damage", "trigger_event": 0, "heal_amount": 0.0}]}]
	var effect: Dictionary = data["owners"][0]["definitions"][0]["effects"][0]
	data["owners"][0]["definitions"][0]["effects"].append(effect)
	var alias_snapshot := ItemSimulationSnapshot.from_dict(data).snapshot
	copy = alias_snapshot.to_dict()
	copy["owners"][0]["definitions"][0]["effects"][0]["heal_amount"] = 1.0
	_check(copy["owners"][0]["definitions"][0]["effects"][1]["heal_amount"] == 0.0, "B12 aliased input expanded into independent values")
	data = _p03b_minimal_dto()
	data["cycle"] = data
	_check(ItemSimulationSnapshot.from_dict(data).reason.ends_with("/cycle"), "B12 dictionary cycle rejected")
	data.erase("cycle")
	var cycle: Array = []
	cycle.append(cycle)
	data["cycle"] = cycle
	_check(ItemSimulationSnapshot.from_dict(data).reason.ends_with("/cycle"), "B12 array cycle rejected")
	cycle.clear()
	data.erase("cycle")
	var deep: Variant = 0
	for i in 32: deep = [deep]
	var nodes: Array[int] = [0]
	_check(ItemSimulationSnapshot._walk(deep, 0, [], nodes, "raw").is_empty(), "B12 raw depth32 boundary")
	deep = [deep]
	nodes[0] = 0
	_check(ItemSimulationSnapshot._walk(deep, 0, [], nodes, "raw").ends_with("/depth"), "B12 raw depth33")
	data["deep"] = deep
	_check(ItemSimulationSnapshot.from_dict(data).reason.ends_with("/depth"), "B12 public raw depth rejection")
	var wide: Array = []
	wide.resize(1999999)
	wide.fill(0)
	nodes[0] = 0
	_check(ItemSimulationSnapshot._walk(wide, 0, [], nodes, "raw").is_empty() and nodes[0] == 2000000, "B12 exact 2M visited value nodes")
	wide.append(0)
	nodes[0] = 0
	_check(ItemSimulationSnapshot._walk(wide, 0, [], nodes, "raw").ends_with("/nodes"), "B12 nodes +1")
	_check(ItemSimulationSnapshot.from_dict({"wide": wide}).reason.ends_with("/nodes"), "B12 malformed huge array rejected in public preflight")
	wide.clear()
	data = _p03b_minimal_dto()
	var owner: Dictionary = data["owners"][0]
	data["owners"].resize(65536)
	data["owners"].fill(owner)
	_check(ItemSimulationSnapshot._structure(data).is_empty(), "B12 owner cap65536 passes structural limit; duplicates fail graph")
	data["owners"].append(owner)
	_check(ItemSimulationSnapshot._structure(data) == "owners/limit", "B12 owner cap +1")
	for size: Vector2i in [Vector2i(1024, 64), Vector2i(256, 256)]:
		var edge := ItemSimulationState.new(BattleBoard.new(size.x, size.y), [], [], [])
		_check(ItemSimulationSnapshot.capture(edge, []).code == ItemSnapshotResult.Code.OK, "B12 P02 side/cells boundary %s" % size)
	for size: Vector2i in [Vector2i(1025, 1), Vector2i(257, 256)]:
		data = ItemSimulationSnapshot.capture(ItemSimulationState.new(BattleBoard.new(), [], [], []), []).snapshot.to_dict()
		data["board_snapshot"]["board"]["width"] = size.x
		data["board_snapshot"]["board"]["height"] = size.y
		_check(ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B12 P02 dimension/cell overflow %s" % size)

func _test_p03b_b13_purity() -> void:
	var f := _p03b_fixture()
	var snap := _p03b_capture(f).snapshot
	var counter := UnitId.get_counter()
	var provider := f.board.make_data_provider()
	var signals: Array[int] = [0]
	f.inventories[0].item_added.connect(func(_item: ItemInstance) -> void: signals[0] += 1)
	f.owners[0].get_owner().vitals.hp_changed.connect(func(_old: float, _new: float) -> void: signals[0] += 1)
	var subscriptions := f.owners[0].get_owner().vitals.hp_changed.get_connections().size()
	var cache: Dictionary = {}
	for key: int in f.owners[0].get_owner().stats._stats:
		var stat: Stat = f.owners[0].get_owner().stats._stats[key]
		cache[key] = [stat._cache_dirty, stat._cached_value, stat._next_modifier_slot, stat._modifier_slots.duplicate()]
	for i in 8:
		var state := snap.instantiate(_p03b_catalogue(f.definition)).state
		var again := ItemSimulationSnapshot.capture(state, []).snapshot
		_p03b_same_snapshot(snap, again, "B13 repeated restore %d" % i)
		_check(again.to_dict()["board_snapshot"] == snap.to_dict()["board_snapshot"], "B13 exact modifier slots/evaluation_order and resources %d" % i)
		ItemReactionCollector.collect_damage(state, {"event_seq": 1, "target_unit_id": 101, "dealt": 1.0})
		ItemReactionCollector.collect_damage(f.state, {"event_seq": 1, "target_unit_id": 101, "dealt": 1.0})
	_check(UnitId.get_counter() == counter and signals[0] == 0 and not provider.cell_is_walkable(Vector2i.ZERO), "B13 no UnitId, signals or provider mutation")
	_check(f.owners[0].get_owner().vitals.hp_changed.get_connections().size() == subscriptions, "B13 no subscriptions added")
	for key: int in cache:
		var stat: Stat = f.owners[0].get_owner().stats._stats[key]
		_check(cache[key] == [stat._cache_dirty, stat._cached_value, stat._next_modifier_slot, stat._modifier_slots], "B13 live cache/slots untouched stat%d" % key)
	_check(snap.instantiate({}).state == null and ItemSimulationSnapshot.from_dict({}).state == null, "B13 no partial state on failure")

func _p03b_raw_stat(data: Dictionary, unit_id: int, stat_type: int) -> Dictionary:
	for unit: Dictionary in data["board_snapshot"]["board"]["units"]:
		if unit["id"] != unit_id: continue
		for entry: Dictionary in unit["stats"]["stats"]:
			if entry["stat_type"] == stat_type: return entry["stat"]
	return {}

func _p03b_link_failure(data: Dictionary, suffix: String, label: String) -> void:
	# P02 обязан принять фикстуру: иначе тест не достигает item linkage validator.
	_check(SimulationSnapshot.from_dict(data["board_snapshot"]).code == BoardSnapshotResult.Code.OK, label + " valid P02 projection")
	var counter := UnitId.get_counter()
	var result := ItemSimulationSnapshot.from_dict(data)
	_check(result.code == ItemSnapshotResult.Code.SNAPSHOT_INVALID and result.snapshot == null and result.state == null and result.reason.contains(suffix), label + " exact P03b rejection", result.reason)
	_check(UnitId.get_counter() == counter, label + " no allocation side effects")

func _test_p03b_review_boundaries() -> void:
	var fixture := _p03b_fixture()
	var snapshot := _p03b_capture(fixture).snapshot
	var data := snapshot.to_dict()
	var strength := _p03b_raw_stat(data, 101, 3)
	var orphan: Dictionary = strength["modifiers"][0].duplicate(true)
	orphan["source_id"] = "p03a/o101/i999/e999"
	orphan["local_slot"] = strength["next_modifier_slot"]
	orphan["evaluation_order"] = strength["modifiers"].size()
	strength["next_modifier_slot"] += 1
	strength["modifiers"].append(orphan)
	_p03b_link_failure(data, "/orphan_source/p03a/o101/i999/e999", "B05 reserved orphan with fresh slot/order")
	for field: String in ["operation", "value"]:
		data = snapshot.to_dict()
		strength = _p03b_raw_stat(data, 101, 3)
		# Меняется именно уже сохранённый modifier, runtime и definition согласованы.
		if field == "operation": strength["modifiers"][0][field] = 1
		else: strength["modifiers"][0][field] = 7.0
		_p03b_link_failure(data, "/item/1/effect/1/modifier_link", "B05 board modifier " + field + " differs from runtime")
	data = snapshot.to_dict()
	var detached: Dictionary = data["owners"][0]["items"][0]
	detached["placement"] = 0
	detached["active"] = false
	data["owners"][0]["inventory_order"].erase(1)
	for effect: Dictionary in detached["effects"]:
		effect["active"] = false
		if effect["kind"] == "stat_modifier": effect["modifier_link"] = []
	_p03b_link_failure(data, "/item/1/effect/1/inactive_source", "B05 consistent detached item retains forbidden board source")
	data = snapshot.to_dict()
	strength = _p03b_raw_stat(data, 101, 3)
	var hp := _p03b_raw_stat(data, 101, 0)
	var second: Dictionary = strength["modifiers"][0].duplicate(true)
	second["local_slot"] = hp["next_modifier_slot"]
	second["evaluation_order"] = hp["modifiers"].size()
	hp["next_modifier_slot"] += 1
	hp["modifiers"].append(second)
	_p03b_link_failure(data, "/item/1/effect/1/modifier_link", "B05 duplicate source in another stat with valid P02 slots")
	# Удаление одного из двух sources проверяется при корректных слотах чужого modifier.
	data = snapshot.to_dict()
	strength = _p03b_raw_stat(data, 101, 3)
	var foreign: Dictionary = strength["modifiers"][0].duplicate(true)
	foreign["source_id"] = "foreign"
	foreign["local_slot"] = strength["next_modifier_slot"]
	foreign["evaluation_order"] = strength["modifiers"].size()
	strength["next_modifier_slot"] += 1
	strength["modifiers"].append(foreign)
	var foreign_snapshot := ItemSimulationSnapshot.from_dict(data).snapshot
	var restored := foreign_snapshot.instantiate(_p03b_catalogue(fixture.definition)).state
	var owner := restored.get_owner(101)
	var inventory := restored.get_inventory(101)
	_check(inventory.remove_item(owner._items[1]) and owner._owner.stats.has_modifiers_from_source(&"foreign") and owner._owner.stats.has_modifiers_from_source(&"p03a/o101/i2/e4"), "B05 remove copy preserves neighbour and foreign source")
	# MAX_ID — только counter sentinel; MAX_ID-1 допустим у живого occurrence.
	var definition := ItemDef.new()
	definition.id = &"p03b_effect_boundary"
	definition.effects = [HealOnDamageEffect.new()]
	data = _p03b_minimal_dto()
	var record: Dictionary = data["owners"][0]
	record["next_item_id"] = 11
	record["next_effect_id"] = ItemOwnerState.MAX_ID
	record["definitions"] = [{"id": String(definition.id), "effects": [{"kind": "heal_on_damage", "trigger_event": 0, "heal_amount": 1.0}]}]
	record["items"] = [{"item_instance_id": 7, "definition_id": String(definition.id), "placement": 0, "active": false, "effects": [{"effect_instance_id": ItemOwnerState.MAX_ID - 1, "effect_index": 0, "active": false, "kind": "heal_on_damage", "trigger_event": 0, "heal_amount": 1.0}]}]
	var boundary := ItemSimulationSnapshot.from_dict(data)
	_check(boundary.code == ItemSnapshotResult.Code.OK, "B03 MAX-1 effect accepted", boundary.reason)
	var a := boundary.snapshot.instantiate({definition.id: definition}).state
	var b := boundary.snapshot.instantiate({definition.id: definition}).state
	_p03b_same_snapshot(boundary.snapshot, ItemSimulationSnapshot.capture(a, []).snapshot, "B03 MAX-1 effect roundtrip A")
	_p03b_same_snapshot(boundary.snapshot, ItemSimulationSnapshot.capture(b, []).snapshot, "B03 MAX-1 effect roundtrip B")
	owner = a.get_owner(1)
	_check(owner._items[7].get_effects()[0].get_effect_instance_id() == ItemOwnerState.MAX_ID - 1, "B03 exact restored high effect id")
	var before := ItemSimulationSnapshot.capture(a, []).snapshot
	_check(owner.create_item(definition) == null and owner._next_item_id == 11 and owner._next_effect_id == ItemOwnerState.MAX_ID, "B03 exhausted effects reject without spending item/effect counters")
	_p03b_same_snapshot(before, ItemSimulationSnapshot.capture(a, []).snapshot, "B03 exhausted failure is atomic")
	var empty := ItemDef.new()
	empty.id = &"p03b_empty_at_exhaustion"
	var next := owner.create_item(empty)
	var next_b := b.get_owner(1).create_item(empty)
	_check(next != null and next_b != null and next.get_item_instance_id() == 11 and next_b.get_item_instance_id() == 11 and next.get_effects().is_empty() and owner._next_item_id == 12 and owner._next_effect_id == ItemOwnerState.MAX_ID, "B03 empty effects remain creatable with exhausted effect counter")
	data["owners"][0]["items"][0]["effects"][0]["effect_instance_id"] = ItemOwnerState.MAX_ID
	_check(ItemSimulationSnapshot.from_dict(data).code == ItemSnapshotResult.Code.SNAPSHOT_INVALID, "B06 effect sentinel cannot be an occurrence id")


func _test_p04_fixture() -> Dictionary:
	var board := BattleBoard.new(2, 1)
	var stats := _make_stats(10.0, 100.0)
	stats.set_base_value(StatTypes.StatType.ARMOR, 2.0)
	var unit := _p02_unit(201, Vector2i.ZERO, stats)
	# P04-приёмка использует HP_MAX=10, тогда как старая P02-фабрика намеренно создаёт HP=17.
	unit.vitals.set_hp(10.0)
	board.add_unit(unit)
	var owner := ItemOwnerState.new(unit)
	var inventory := InventoryState.new(owner)
	var equipment := EquipmentState.new(owner)
	var state := ItemSimulationState.new(board, [owner], [inventory], [equipment])
	var rng := P04TestRng.new()
	var context := ActionContext.new(state, rng, ActionEventSink.new(), [])
	return {"state": state, "context": context, "rng": rng, "unit": unit, "owner": owner, "inventory": inventory, "equipment": equipment, "board": board}


func _p04_submit(fixture: Dictionary, command: Command) -> ActionReceipt:
	return ActionQueue.new().submit(command, fixture["context"])


func _test_p04_c01_damage_sources_and_armor() -> void:
	var f: Dictionary = _test_p04_fixture()
	var unit := f["unit"] as UnitState
	var source := DamageSource.new(&"cell", 7, Vector2i(2, 3), 0, 0)
	unit.stats.set_base_value(StatTypes.StatType.STRENGTH, 100.0)
	var balance_before := unit.vitals.get_balance()
	var move_before := unit.move_points_left
	var attacked_before := unit.has_attacked
	var flat := _p04_submit(f, DamageCommand.new(DamageRequest.new(201, 5.0, &"physical", &"flat", source)))
	_check(flat.status == &"APPLIED" and unit.vitals.get_hp() == 7.0 and flat.get_events()[0]["amount"] == 3.0, "C01 flat damage uses armor only, never STRENGTH")
	_check(flat.get_events().size() == 1 and flat.get_events()[0]["source"]["origin_cell"] == Vector2i(2, 3), "C01 source value preserved")
	_check(flat.get_events()[0]["source"]["kind"] == &"cell" and flat.get_events()[0]["source"]["instigator_unit_id"] == 0, "C01 cell source allows NONE ids")
	var bypass := _p04_submit(f, DamageCommand.new(DamageRequest.new(201, 2.0, &"physical", &"bypass", source)))
	_check(bypass.status == &"APPLIED" and unit.vitals.get_hp() == 5.0, "C01 bypass ignores armor")
	var overkill := _p04_submit(f, DamageCommand.new(DamageRequest.new(201, 99.0, &"physical", &"bypass", source)))
	_check(overkill.status == &"APPLIED" and overkill.get_events()[0]["amount"] == 5.0, "C01 actual overkill amount")
	_check(unit.vitals.get_balance() == balance_before and unit.move_points_left == move_before and unit.has_attacked == attacked_before, "C01 no balance or action resource mutation")
	var before: float = unit.vitals.get_hp()
	var bad := _p04_submit(f, DamageCommand.new(DamageRequest.new(201, NAN, &"physical", &"bypass", source)))
	_check(bad.status == &"REJECTED" and unit.vitals.get_hp() == before, "C01 invalid amount rejects atomically")


func _test_p04_c02_death_and_alive_at_zero() -> void:
	var f: Dictionary = _test_p04_fixture()
	var unit := f["unit"] as UnitState
	var board := f["board"] as BattleBoard
	var source := DamageSource.new(&"test")
	var died_count: Dictionary = {"value": 0}
	unit.vitals.died.connect(func() -> void: died_count["value"] = int(died_count["value"]) + 1)
	var version_before := board.board_version
	var damage := _p04_submit(f, DamageCommand.new(DamageRequest.new(201, 10.0, &"physical", &"bypass", source)))
	var events := damage.get_events()
	_check(damage.status == &"APPLIED" and events.size() == 2 and events[0]["kind"] == &"damaged" and events[1]["kind"] == &"died", "C02 damage then died order")
	_check(not unit.is_alive() and not board.is_occupied(unit.cell) and board.get_unit_by_id(201) == unit and int(died_count["value"]) == 1, "C02 one Vitals death clears occupancy and keeps corpse")
	var version_after := board.board_version
	board.clear_occupancy(unit)
	_check(board.board_version == version_after and version_after > version_before, "C02 cleanup is idempotent")
	var repeat := _p04_submit(f, DeathCommand.new(201, source))
	_check(repeat.status == &"REJECTED" and repeat.root_id == 0, "C02 corpse root rejected")
	var child_f: Dictionary = _test_p04_fixture()
	var child_root := P04Work.new(&"lethal_with_corpse_child", func(context: ActionContext) -> CommandStepResult:
		var step := ActionHpExecutor.damage(DamageRequest.new(201, 10.0, &"physical", &"bypass", source), context)
		step.mandatory.append(DeathCommand.new(201, source))
		return step)
	var child_result := _p04_submit(child_f, child_root)
	_check(child_result.status == &"APPLIED" and child_result.get_steps().size() == 2 and child_result.get_steps()[1]["status"] == &"SKIPPED" and child_result.get_steps()[1]["reason"] == &"dead_target", "C02 corpse HP child is skipped after one death")
	var zero_f: Dictionary = _test_p04_fixture()
	var zero_unit := zero_f["unit"] as UnitState
	zero_unit.vitals.set_hp(0.0)
	var lethal := _p04_submit(zero_f, DeathCommand.new(201, source))
	_check(lethal.status == &"APPLIED" and lethal.get_events().size() == 1 and lethal.get_events()[0]["kind"] == &"died", "C02 alive-at-zero death transition")


func _test_p04_c03_heal_boundaries_and_rejections() -> void:
	var f: Dictionary = _test_p04_fixture()
	var unit := f["unit"] as UnitState
	var context := f["context"] as ActionContext
	var rng := f["rng"] as P04TestRng
	var source := DamageSource.new(&"test")
	_p04_submit(f, DamageCommand.new(DamageRequest.new(201, 6.0, &"physical", &"bypass", source)))
	var partial := _p04_submit(f, HealCommand.new(201, 2.0, source))
	_check(partial.status == &"APPLIED" and unit.vitals.get_hp() == 6.0 and partial.get_events()[0]["amount"] == 2.0, "C03 partial heal reports actual amount")
	var heal := _p04_submit(f, HealCommand.new(201, 20.0, source))
	_check(heal.status == &"APPLIED" and unit.vitals.get_hp() == 10.0 and heal.get_events()[0]["amount"] == 4.0, "C03 heal reports actual clamp")
	var full := _p04_submit(f, HealCommand.new(201, 2.0, source))
	_check(full.status == &"APPLIED" and full.get_events().is_empty() and context.get_revision() == 3, "C03 full heal is no-op")
	var overmax_f: Dictionary = _test_p04_fixture()
	var overmax_unit := overmax_f["unit"] as UnitState
	overmax_unit.vitals = Vitals.from_dict({"hp": 15.0, "balance": 3.0, "is_alive": true}, overmax_unit.stats)
	var overmax := _p04_submit(overmax_f, HealCommand.new(201, 2.0, source))
	_check(overmax.status == &"APPLIED" and overmax_unit.vitals.get_hp() == 15.0 and overmax.get_events().is_empty(), "C03 over-max heal preserves HP as no-op")
	var dead: Dictionary = _test_p04_fixture()
	_p04_submit(dead, DeathCommand.new(201, source))
	var dead_heal := _p04_submit(dead, HealCommand.new(201, 2.0, source))
	_check(dead_heal.status == &"REJECTED" and (dead["unit"] as UnitState).vitals.get_hp() == 0.0, "C03 dead unit is not revived")
	var zero_damage: Dictionary = _test_p04_fixture()
	var zero := _p04_submit(zero_damage, DamageCommand.new(DamageRequest.new(201, 0.0, &"physical", &"bypass", source)))
	var zero_heal := _p04_submit(zero_damage, HealCommand.new(201, 0.0, source))
	_check(zero.status == &"APPLIED" and zero.get_events().is_empty() and zero_heal.get_events().is_empty(), "C03 zero damage and heal are no-op")
	var invalids: Array[Command] = [
		DamageCommand.new(DamageRequest.new(201, INF, &"physical", &"bypass", source)),
		HealCommand.new(201, NAN, source),
		DamageCommand.new(DamageRequest.new(201, 1.0, &"unknown", &"bypass", source)),
		DamageCommand.new(DamageRequest.new(201, 1.0, &"physical", &"unknown", source)),
		HealCommand.new(999, 1.0, source),
		DamageCommand.new(DamageRequest.new(0, 1.0, &"physical", &"bypass", source)),
		DamageCommand.new(DamageRequest.new(201, 1.0, &"physical", &"bypass", DamageSource.new(&"unknown")))
	]
	for candidate: Command in invalids:
		var hp_before := unit.vitals.to_dict()
		var stats_before := unit.stats.to_snapshot_dict()
		var rng_before := rng.to_dict()
		var counters_before := [context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision()]
		var rejected := _p04_submit(f, candidate)
		_check(rejected.status == &"REJECTED" and unit.vitals.to_dict() == hp_before and unit.stats.to_snapshot_dict() == stats_before and rng.to_dict() == rng_before and [context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision()] == counters_before, "C03 invalid payload preserves state, cache, counters and RNG")
	var negative_armor: Dictionary = _test_p04_fixture()
	(negative_armor["unit"] as UnitState).stats.set_base_value(StatTypes.StatType.ARMOR, -3.0)
	var negative_result := _p04_submit(negative_armor, DamageCommand.new(DamageRequest.new(201, 2.0, &"physical", &"flat", source)))
	_check(negative_result.status == &"APPLIED" and (negative_armor["unit"] as UnitState).vitals.get_hp() == 5.0, "C03 negative armor retains flat formula")
	var overflow_armor: Dictionary = _test_p04_fixture()
	(overflow_armor["unit"] as UnitState).stats.set_base_value(StatTypes.StatType.ARMOR, INF)
	var overflow := _p04_submit(overflow_armor, DamageCommand.new(DamageRequest.new(201, 2.0, &"physical", &"flat", source)))
	_check(overflow.status == &"REJECTED" and (overflow_armor["unit"] as UnitState).vitals.get_hp() == 10.0, "C03 non-finite armor rejects before mutator")


func _test_p04_c04_item_reactions() -> void:
	var f: Dictionary = _test_p04_reaction_fixture(1.5)
	var state := f["state"] as ItemSimulationState
	var first := f["first"] as UnitState
	var second := f["second"] as UnitState
	var first_owner := f["first_owner"] as ItemOwnerState
	var first_a := f["first_a"] as ItemInstance
	var first_b := f["first_b"] as ItemInstance
	var context := ActionContext.new(state, P04TestRng.new(), ActionEventSink.new(), [])
	var source := DamageSource.new(&"test")
	var next_ids := [first_owner._next_item_id, first_owner._next_effect_id]
	var strength_before := first.get_stat(StatTypes.StatType.STRENGTH)
	var receipt := ActionQueue.new().submit(DamageCommand.new(DamageRequest.new(201, 3.0, &"physical", &"bypass", source)), context)
	var events := receipt.get_events()
	var steps := receipt.get_steps()
	_check(receipt.status == &"APPLIED" and steps.size() == 3 and steps[1]["kind"] == &"heal" and steps[2]["kind"] == &"heal", "C04 exactly two queued heals for two item copies")
	_check(events.size() == 3 and events[0]["kind"] == &"damaged" and events[1]["kind"] == &"healed" and events[2]["kind"] == &"healed" and events[1]["parent_event_seq"] == events[0]["event_seq"] and events[2]["parent_event_seq"] == events[0]["event_seq"], "C04 damage then ordered heal events preserve parent sequence")
	_check(events[1]["source"]["source_instance_id"] == first_a.get_item_instance_id() and events[2]["source"]["source_instance_id"] == first_b.get_item_instance_id(), "C04 reaction order follows item/effect identity")
	_check(first.vitals.get_hp() == 10.0 and second.vitals.get_hp() == 10.0 and first.get_stat(StatTypes.StatType.STRENGTH) == strength_before and [first_owner._next_item_id, first_owner._next_effect_id] == next_ids, "C04 only damaged owner heals and modifiers/ids remain unchanged")
	var lethal_f: Dictionary = _test_p04_reaction_fixture(1.5)
	var lethal_context := ActionContext.new(lethal_f["state"] as ItemSimulationState, P04TestRng.new(), ActionEventSink.new(), [])
	var lethal := ActionQueue.new().submit(DamageCommand.new(DamageRequest.new(201, 99.0, &"physical", &"bypass", source)), lethal_context)
	_check(lethal.status == &"APPLIED" and lethal.get_steps().size() == 1 and lethal.get_events().size() == 2 and lethal.get_events()[1]["kind"] == &"died", "C04 lethal damage queues no healing reaction")
	var zero_f: Dictionary = _test_p04_reaction_fixture(0.0)
	var zero_context := ActionContext.new(zero_f["state"] as ItemSimulationState, P04TestRng.new(), ActionEventSink.new(), [])
	var zero := ActionQueue.new().submit(DamageCommand.new(DamageRequest.new(201, 1.0, &"physical", &"bypass", source)), zero_context)
	_check(zero.status == &"APPLIED" and zero.get_steps().size() == 3 and zero.get_steps()[1]["status"] == &"APPLIED" and zero.get_steps()[2]["status"] == &"APPLIED" and zero.get_events().size() == 1, "C04 zero-heal effects retain explicit no-op steps")


func _test_p04_reaction_fixture(heal_amount: float) -> Dictionary:
	var board := BattleBoard.new(2, 1)
	var first_stats := _make_stats(10.0, 100.0)
	first_stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	var second_stats := _make_stats(10.0, 100.0)
	second_stats.set_base_value(StatTypes.StatType.STRENGTH, 3.0)
	var first := _p02_unit(201, Vector2i.ZERO, first_stats)
	var second := _p02_unit(202, Vector2i(1, 0), second_stats)
	first.vitals.set_hp(10.0)
	second.vitals.set_hp(10.0)
	board.add_unit(first)
	board.add_unit(second)
	var definition := ItemDef.new()
	definition.id = &"p04_shared_reaction"
	var modifier := StatModifierEffect.new()
	modifier.stat_type = StatTypes.StatType.STRENGTH
	modifier.operation = StatModifier.Operation.ADD_FLAT
	modifier.value = 2.0
	var heal := HealOnDamageEffect.new()
	heal.trigger_event = TriggeredEffect.TriggerEvent.UNIT_DAMAGED
	heal.heal_amount = heal_amount
	definition.effects = [modifier, heal]
	var first_owner := ItemOwnerState.new(first)
	var second_owner := ItemOwnerState.new(second)
	var first_inventory := InventoryState.new(first_owner)
	var second_inventory := InventoryState.new(second_owner)
	var first_equipment := EquipmentState.new(first_owner)
	var second_equipment := EquipmentState.new(second_owner)
	var first_a := first_owner.create_item(definition)
	var first_b := first_owner.create_item(definition)
	var other := second_owner.create_item(definition)
	_check(first_a != null and first_b != null and other != null and first_inventory.add_item(first_a) and first_inventory.add_item(first_b) and second_inventory.add_item(other), "C04 fixture creates active shared-definition items")
	var state := ItemSimulationState.new(board, [first_owner, second_owner], [first_inventory, second_inventory], [first_equipment, second_equipment])
	return {"state": state, "first": first, "second": second, "first_owner": first_owner, "first_a": first_a, "first_b": first_b}


func _test_p04_c11_rng_port_isolation() -> void:
	var base := ActionRngPort.new()
	_check(base.next_int(&"combat", 2) == -1 and base.clone() == null and base.to_dict().is_empty() and not base.from_dict({}), "C11 base RNG fails closed")
	var rng := P04TestRng.new()
	var initial := rng.to_dict()
	_check(typeof(initial["streams"][0]["name"]) == TYPE_STRING and initial["streams"][0]["name"] == "combat" and typeof(initial["streams"][0]["cursor"]) == TYPE_INT, "C11 RNG DTO uses exact String names and integer cursors")
	_check(rng.next_int(&"combat", 4) == 0 and rng.next_int(&"loot", 4) == 0, "C11 deterministic streams")
	var clone := rng.clone() as P04TestRng
	var clone_before := clone.to_dict()
	clone.next_int(&"combat", 4)
	_check(clone != rng and clone_before == rng.to_dict() and clone.to_dict() != rng.to_dict(), "C11 clone owns independent mutable cursors")
	var shuffled: Dictionary = {"streams": [{"cursor": 4, "name": "loot"}, {"cursor": 3, "name": "combat"}], "schema_version": 1}
	_check(rng.from_dict(shuffled) and rng.to_dict()["streams"][0]["name"] == "combat" and rng.to_dict()["streams"][1]["name"] == "loot", "C11 valid shuffled import normalizes stream order")
	shuffled["streams"][0]["cursor"] = 99
	_check(rng.to_dict()["streams"][1]["cursor"] == 4, "C11 import never aliases caller DTO")
	var invalid_inputs: Array[Dictionary] = [
		{}, {"schema_version": 2, "streams": []}, {"schema_version": 1, "streams": [{"name": "combat", "cursor": 1}]},
		{"schema_version": 1, "extra": true, "streams": [{"name": "combat", "cursor": 1}, {"name": "loot", "cursor": 2}]},
		{"schema_version": 1, "streams": [{"name": "combat", "cursor": 1, "extra": true}, {"name": "loot", "cursor": 2}]},
		{"schema_version": 1, "streams": [{"name": "combat", "cursor": 1}, {"name": "combat", "cursor": 2}]},
		{"schema_version": 1, "streams": [{"name": "other", "cursor": 1}, {"name": "loot", "cursor": 2}]},
		{"schema_version": 1, "streams": [{"name": &"combat", "cursor": 1}, {"name": "loot", "cursor": 2}]},
		{"schema_version": 1, "streams": [{"name": "combat", "cursor": -1}, {"name": "loot", "cursor": 2}]},
		{"schema_version": 1, "streams": [{"name": "combat", "cursor": "1"}, {"name": "loot", "cursor": 2}]},
		{"schema_version": 1, "streams": [{"name": "combat", "cursor": ActionContext.MAX_ID}, {"name": "loot", "cursor": 2}]}
	]
	for malformed: Dictionary in invalid_inputs:
		var preserved := rng.to_dict()
		_check(not rng.from_dict(malformed) and rng.to_dict() == preserved, "C11 invalid import preserves state")
	var overflow_data: Dictionary = {"schema_version": 1, "streams": [{"name": "combat", "cursor": ActionContext.MAX_ID - 1}, {"name": "loot", "cursor": 2}]}
	_check(rng.from_dict(overflow_data) and rng.next_int(&"combat", 2) == -1 and rng.to_dict()["streams"][0]["cursor"] == ActionContext.MAX_ID - 1, "C11 overflow draw fails without mutation")
	var invalid_draw_before := rng.to_dict()
	_check(rng.next_int(&"missing", 2) == -1 and rng.next_int(&"loot", 0) == -1 and rng.to_dict() == invalid_draw_before, "C11 invalid draws do not mutate")
	var f: Dictionary = _test_p04_fixture()
	var f_context := f["context"] as ActionContext
	var f_rng := f["rng"] as P04TestRng
	f_rng.from_dict({"schema_version": 1, "streams": [{"name": "combat", "cursor": 1}, {"name": "loot", "cursor": 0}]})
	var receipt := ActionQueue.new().submit(P04RandomDamageCommand.new(201), f_context)
	_check(receipt.status == &"APPLIED" and receipt.get_steps().size() == 2 and f_rng.cursors[&"combat"] == 2 and f_rng.cursors[&"loot"] == 0 and (f["unit"] as UnitState).vitals.get_hp() == 9.0, "C11 random child consumes only combat and applies its draw")
	var no_draw_before := f_rng.to_dict()
	var normal := ActionQueue.new().submit(DamageCommand.new(DamageRequest.new(201, 0.0, &"physical", &"bypass", DamageSource.new(&"test"))), f_context)
	var rejected := ActionQueue.new().submit(DamageCommand.new(DamageRequest.new(201, NAN, &"physical", &"bypass", DamageSource.new(&"test"))), f_context)
	var skipped := ActionQueue.new().submit(P04Work.new(&"skip_rng", func(_context: ActionContext) -> CommandStepResult: return CommandStepResult.skipped(&"fixture_skip")), f_context)
	_check(normal.status == &"APPLIED" and rejected.status == &"REJECTED" and skipped.status == &"APPLIED" and f_rng.to_dict() == no_draw_before, "C11 HP/no-op/rejected/skipped commands do not draw")
	var p03 := _p03b_fixture()
	var captured := ItemSimulationSnapshot.capture(p03.state, [])
	var first := captured.snapshot.instantiate(_p03b_catalogue(p03.definition)).state
	var second := captured.snapshot.instantiate(_p03b_catalogue(p03.definition)).state
	var seed := P04TestRng.new()
	seed.from_dict({"schema_version": 1, "streams": [{"name": "combat", "cursor": 1}, {"name": "loot", "cursor": 7}]})
	var first_rng := seed.clone() as P04TestRng
	var second_rng := seed.clone() as P04TestRng
	var first_context := ActionContext.new(first, first_rng, ActionEventSink.new(), [])
	var second_context := ActionContext.new(second, second_rng, ActionEventSink.new(), [])
	var live_bytes := captured.snapshot.canonical_bytes()
	var live_hp := p03.state.get_board().get_unit_by_id(101).vitals.get_hp()
	var first_receipt := ActionQueue.new().submit(P04RandomDamageCommand.new(101), first_context)
	_check(ItemSimulationSnapshot.capture(second, []).snapshot.canonical_bytes() == live_bytes and second_rng.to_dict() == seed.to_dict(), "C11 first execution leaves second state and RNG untouched")
	var second_receipt := ActionQueue.new().submit(P04RandomDamageCommand.new(101), second_context)
	_check(first_receipt.status == &"APPLIED" and first_receipt.get_steps().size() > 1 and first_receipt.get_events()[0]["kind"] == &"damaged" and first_receipt.get_events() == second_receipt.get_events() and first_context.get_revision() == second_context.get_revision() and first_rng.to_dict() == second_rng.to_dict() and first_rng.to_dict()["streams"][1]["cursor"] == 7, "C11 cloned RNG drives equal random-child P03b outcomes without loot draw")
	_check(ItemSimulationSnapshot.capture(p03.state, []).snapshot.canonical_bytes() == live_bytes and p03.state.get_board().get_unit_by_id(101).vitals.get_hp() == live_hp, "C11 live P03b state remains unchanged")
	_check(ItemSimulationSnapshot.capture(first, []).snapshot.canonical_bytes() == ItemSimulationSnapshot.capture(second, []).snapshot.canonical_bytes() and first_receipt.get_steps() == second_receipt.get_steps() and [first_context._next_root_id, first_context._next_command_seq, first_context._next_event_seq] == [second_context._next_root_id, second_context._next_command_seq, second_context._next_event_seq], "C11 full outcome, step trace and all counters match")
	_test_p04_remaining_edges()


# P04: доверенная scheduler fixture хранит callbacks только локально, вне value DTO.
class P04Work extends Command:
	var label: StringName
	var action: Callable
	var validation: Callable
	var copying: Callable
	func _init(name: StringName = &"probe", body: Callable = Callable()) -> void:
		label = name
		action = body
	func get_kind() -> StringName: return label
	func copy_for_queue() -> Command:
		if copying.is_valid(): copying.call()
		var copy := P04Work.new(label, action)
		copy.validation = validation
		copy.copying = copying
		return copy
	func validate(context: ActionContext) -> StringName:
		return validation.call(context) if validation.is_valid() else &""
	func execute(context: ActionContext) -> CommandStepResult:
		return action.call(context) if action.is_valid() else CommandStepResult.applied()

class P04HookSink extends ActionEventSink:
	var events: Array[Dictionary] = []
	var hook: Callable
	func publish(event: Dictionary) -> void:
		events.append(event.duplicate(true))
		if hook.is_valid(): hook.call(event)

func _test_p04_hp(target: int = 201, amount: float = 1.0) -> DamageCommand:
	return DamageCommand.new(DamageRequest.new(target, amount, &"physical", &"bypass", DamageSource.new(&"cell")))

func _test_p04_with_heal() -> Dictionary:
	var f := _test_p04_fixture()
	var definition := _p3_def(&"p04_binding", [HealOnDamageEffect.new()])
	var owner: ItemOwnerState = f.owner
	var item := owner.create_item(definition)
	var inventory: InventoryState = f.inventory
	inventory.add_item(item)
	f["definition"] = definition
	f["item"] = item
	return f

func _test_p04_mutation(f: Dictionary, mode: String) -> void:
	var unit: UnitState = f.unit
	var board: BattleBoard = f.board
	var owner: ItemOwnerState = f.owner
	var item: ItemInstance = f.item
	var inventory: InventoryState = f.inventory
	var effect := item.get_effects()[0]
	match mode:
		"detach": inventory.remove_item(item)
		"reactivate":
			inventory.remove_item(item)
			inventory.add_item(item)
		"close_facade": inventory.close()
		"close_owner": owner.close()
		"kill": unit.vitals.apply_damage(100.0)
		"remove_unit": board.remove_unit(unit)
		"replace_unit":
			board.remove_unit(unit)
			var replacement := _p02_unit(unit.id, unit.cell, _make_stats(10.0, 100.0))
			board.add_unit(replacement)
		"remove_item": owner._items.erase(item.get_item_instance_id())
		"replace_item": owner._items[item.get_item_instance_id()] = ItemInstance.new(item.get_definition(), unit.id, item.get_item_instance_id(), item.get_effects())
		"remove_effect": item._effects.clear()
		"replace_effect": item._effects[0] = HealOnDamageEffectRuntime.new(unit.id, item.get_item_instance_id(), effect.get_effect_instance_id(), 0, 1.0, TriggeredEffect.TriggerEvent.UNIT_DAMAGED)
		"replace_definition": item._definition = _p3_def(&"p04_binding", [HealOnDamageEffect.new()])
		"mutate_definition": (f.definition.effects[0] as HealOnDamageEffect).heal_amount = 7.0
		"guard": owner._guard = true
		"ledger": owner._placements[item.get_item_instance_id()] = 999
		"duplicate_effect": item._effects.append(effect)
		"inactive": effect._set_active(false)

func _test_p04_c05_bindings() -> void:
	for mode: String in ["detach", "reactivate", "close_facade", "close_owner", "kill", "remove_unit", "replace_unit", "remove_item", "replace_item", "remove_effect", "replace_effect", "replace_definition", "mutate_definition", "guard", "ledger", "duplicate_effect", "inactive"]:
		var f := _test_p04_with_heal()
		var child := P04Work.new(&"mutation", func(_context: ActionContext) -> CommandStepResult:
			_test_p04_mutation(f, mode)
			return CommandStepResult.applied([], [], [], null, true))
		var root := P04Work.new(&"damage_fixture", func(context: ActionContext) -> CommandStepResult:
			var result := ActionHpExecutor.damage(_test_p04_hp().request, context)
			result.mandatory.append(child)
			return result)
		var receipt := ActionQueue.new().submit(root, f.context)
		var steps := receipt.get_steps()
		var fault := mode in ["mutate_definition", "guard", "ledger", "duplicate_effect"]
		_check(steps.size() == 3, "C05 pending binding reaches execute " + mode)
		if steps.size() == 3:
			_check(steps[2]["status"] == (&"FAULTED" if fault else (&"APPLIED" if mode == "reactivate" else &"SKIPPED")), "C05 stale versus invariant " + mode)
			if not fault and mode != "reactivate": _check(steps[2]["reason"] == &"stale_reaction", "C05 exact stale reason " + mode)
		_check(receipt.status == (&"FAULTED" if fault else &"APPLIED"), "C05 receipt " + mode)
		_check(receipt.get_events().size() == (2 if mode == "reactivate" else 1), "C05 no stale HP events " + mode)
		_check(f.rng.to_dict()["streams"][0]["cursor"] == 0, "C05 skipped/fault binding no draws " + mode)
		f.owner._guard = false
	# Прямой private seam: описание уже принято, caller не может заменить его amount.
	var f := _test_p04_with_heal()
	var descriptions := ItemReactionCollector.collect_damage(f.state, {"event_seq": 1, "target_unit_id": 201, "dealt": 1.0}).descriptions
	var bound := ItemReactionAdapter.bind(descriptions[0], f.context)
	descriptions[0]["heal_amount"] = 999.0
	_check(bound != null and bound.amount == 1.0 and ItemReactionAdapter.revalidate(bound._reaction_binding, f.context) == &"", "C05 private binding owns description")

func _test_p04_node(name: StringName, children: Array[Command] = [], reactions: Array[Command] = [], continuation: Command = null) -> P04Work:
	return P04Work.new(name, func(_context: ActionContext) -> CommandStepResult:
		return CommandStepResult.applied([], children, reactions, continuation))

func _test_p04_c06_scheduler() -> void:
	var a := _test_p04_node(&"A", [_test_p04_node(&"A1")])
	var r1 := _test_p04_node(&"R1", [_test_p04_node(&"R1a")])
	var root := _test_p04_node(&"root", [a, _test_p04_node(&"B")], [r1, _test_p04_node(&"R2")], _test_p04_node(&"K"))
	var f := _test_p04_fixture()
	var receipt := ActionQueue.new().submit(root, f.context)
	var trace: Array = []
	for step in receipt.get_steps(): trace.append(step["kind"])
	_check(receipt.status == &"APPLIED" and trace == [&"root", &"A", &"A1", &"B", &"R1", &"R1a", &"R2", &"K"], "C06 complete depth-first order")
	_check(receipt.revision_after == 0 and receipt.get_events().is_empty(), "C06 no-op tree does not change revision")
	var original := _p03b_fixture()
	var snapshot := _p03b_capture(original).snapshot
	var states: Array[ItemSimulationState] = [snapshot.instantiate(_p03b_catalogue(original.definition)).state, snapshot.instantiate(_p03b_catalogue(original.definition)).state]
	states[1]._owners.reverse()
	for owner in states[1].get_owners():
		var reversed: Dictionary = {}
		var keys := owner._items.keys()
		keys.reverse()
		for key: int in keys: reversed[key] = owner._items[key]
		owner._items = reversed
	var receipts: Array[ActionReceipt] = []
	for state in states:
		receipts.append(ActionQueue.new().submit(_test_p04_hp(101, 3.0), ActionContext.new(state, P04TestRng.new(), ActionEventSink.new(), [])))
	_check(receipts[0].get_steps() == receipts[1].get_steps() and receipts[0].get_events() == receipts[1].get_events(), "C06 shuffled owners/items have identical traces")

func _test_p04_c07_reentrancy() -> void:
	var f := _test_p04_fixture()
	var independent := _test_p04_fixture()
	var context: ActionContext = f.context
	var queue := ActionQueue.new()
	var other := ActionQueue.new()
	var seen: Array[StringName] = []
	var probe := func() -> void:
		seen.append(queue.submit(_test_p04_hp(), context).reason)
		seen.append(other.submit(_test_p04_hp(), context).reason)
	var root := P04Work.new(&"root", func(c: ActionContext) -> CommandStepResult:
		probe.call()
		var outside := other.submit(HealCommand.new(201, 0.0, DamageSource.new(&"test")), independent.context)
		_check(outside.status == &"APPLIED", "C07 independent context accepted while outer executes")
		return ActionHpExecutor.damage(_test_p04_hp().request, c))
	root.copying = probe
	root.validation = func(_c: ActionContext) -> StringName:
		probe.call()
		return &""
	var signal_hook := func(_before: float, _after: float) -> void: probe.call()
	f.unit.vitals.hp_changed.connect(signal_hook)
	var sink := P04HookSink.new()
	sink.hook = func(_event: Dictionary) -> void: probe.call()
	context._sink = sink
	var receipt := queue.submit(root, context)
	_check(seen.size() == 10, "C07 copy/validate/execute/Vitals/sink nested submits all tested")
	for status in seen: _check(status == &"BUSY", "C07 nested submit is BUSY")
	_check(receipt.status == &"APPLIED" and receipt.get_steps().size() == 1 and receipt.get_events().size() == 1 and context._next_root_id == 2 and context._next_command_seq == 2 and context._next_event_seq == 2, "C07 outer journal and counters intact")
	f.unit.vitals.hp_changed.disconnect(signal_hook)
	sink.hook = Callable()
	root.action = Callable()
	root.validation = Callable()
	root.copying = Callable()

func _test_p04_c08_dispatch_and_values() -> void:
	var f := _test_p04_with_heal()
	var queue := ActionQueue.new()
	var replay := P04Work.new(&"replay", func(context: ActionContext) -> CommandStepResult:
		_check(queue._dispatch_event({"event_seq": 1}, context).is_empty(), "C08 processed event replay is no-op")
		return CommandStepResult.applied())
	var root := P04Work.new(&"damage_fixture", func(context: ActionContext) -> CommandStepResult:
		var result := ActionHpExecutor.damage(_test_p04_hp().request, context)
		result.mandatory.append(replay)
		return result)
	var receipt := queue.submit(root, f.context)
	_check(receipt.status == &"APPLIED" and receipt.get_steps().size() == 3 and receipt.get_events().size() == 2, "C08 replay never schedules another heal")
	var next := queue.submit(_test_p04_hp(), f.context)
	_check(next.get_steps().size() == 2 and next.get_events()[1]["parent_event_seq"] == 3, "C08 new root/event triggers same effect")
	var one_root := _test_p04_with_heal()
	var two_damage_root := _test_p04_node(&"two_damage_roots", [_test_p04_hp(), _test_p04_hp()])
	var two_damage_receipt := ActionQueue.new().submit(two_damage_root, one_root.context)
	var two_damage_events := two_damage_receipt.get_events()
	_check(two_damage_receipt.status == &"APPLIED" and two_damage_receipt.get_steps().size() == 5 and two_damage_events.size() == 4 and two_damage_events[0]["kind"] == &"damaged" and two_damage_events[1]["kind"] == &"healed" and two_damage_events[2]["kind"] == &"damaged" and two_damage_events[3]["kind"] == &"healed" and two_damage_events[1]["parent_event_seq"] == two_damage_events[0]["event_seq"] and two_damage_events[3]["parent_event_seq"] == two_damage_events[2]["event_seq"], "C08 one effect fires once for each distinct damage event in one root")
	var duplicate_f := _test_p04_with_heal()
	var duplicate_queue := ActionQueue.new()
	var duplicate := P04Work.new(&"duplicate", func(context: ActionContext) -> CommandStepResult:
		var result := ActionHpExecutor.damage(_test_p04_hp().request, context)
		var d := ItemReactionCollector.collect_damage(context.get_state(), {"event_seq": 1, "target_unit_id": 201, "dealt": 1.0}).descriptions
		duplicate_queue._bind_batch([d[0], d[0]], 1, context)
		return result)
	var failed := duplicate_queue.submit(duplicate, duplicate_f.context)
	_check(failed.status == &"FAULTED" and failed.reason == &"duplicate_reaction_key" and failed.get_events().size() == 1, "C08 duplicate key in new batch faults with damage prefix")
	var values := _test_p04_fixture()
	var source := DamageSource.new(&"cell", 8, Vector2i(1, 2))
	var request := DamageRequest.new(201, 2.0, &"physical", &"bypass", source)
	var damage := DamageCommand.new(request)
	request.amount = 9.0
	source.kind = &"invalid"
	var mutate := P04Work.new(&"mutate_caller", func(_c: ActionContext) -> CommandStepResult:
		damage.request.amount = 9.0
		return CommandStepResult.applied())
	var sink := P04HookSink.new()
	sink.hook = func(event: Dictionary) -> void: event["source"]["kind"] = &"changed"
	values.context._sink = sink
	var value_receipt := ActionQueue.new().submit(_test_p04_node(&"root", [mutate, damage]), values.context)
	_check(values.unit.vitals.get_hp() == 8.0 and value_receipt.get_events()[0]["source"]["kind"] == &"cell", "C08 queued payload/source and sink copy isolated")
	var events := value_receipt.get_events()
	events[0]["source"]["kind"] = &"receipt_mutation"
	var steps := value_receipt.get_steps()
	steps[0]["kind"] = &"receipt_mutation"
	_check(value_receipt.get_events()[0]["source"]["kind"] == &"cell" and value_receipt.get_steps()[0]["kind"] == &"root" and sink.events[0]["source"]["kind"] == &"cell", "C08 receipt getters recursively copy events and steps")
	sink.hook = Callable()

func _test_p04_chain(length: int) -> Command:
	return P04Work.new(&"chain", func(_context: ActionContext) -> CommandStepResult:
		return CommandStepResult.applied([], [], [], _test_p04_chain(length - 1) if length != 1 else null))

func _test_p04_c09_limits() -> void:
	for length: int in [3, 4]:
		var f := _test_p04_fixture()
		var queue := ActionQueue.new(3, 8, 8)
		var r := queue.submit(_test_p04_chain(length), f.context)
		_check(r.status == (&"APPLIED" if length == 3 else &"FAULTED") and r.get_steps().size() == 3, "C09 command boundary/+1 %d" % length)
		if length == 4:
			_check(r.reason == &"command_limit" and queue._pending.is_empty() and not f.context.is_busy(), "C09 pending cleared and guards released")
			_check(ActionQueue.new().submit(_test_p04_hp(), f.context).reason == &"CONTEXT_FAULTED", "C09 other queue cannot bypass context latch")
			_check(queue.submit(_test_p04_hp(), _test_p04_fixture().context).reason == &"CONTEXT_FAULTED", "C09 queue latch survives context replacement")
	for length: int in [3, 4]:
		var r := ActionQueue.new(8, 8, 2).submit(_test_p04_chain(length), _test_p04_fixture().context)
		_check(r.status == (&"APPLIED" if length == 3 else &"FAULTED") and r.get_steps().size() == 3, "C09 root depth0 boundary/+1 %d" % length)
		if length == 4: _check(r.reason == &"depth_limit", "C09 depth fault reason")
	var cycle_f := _test_p04_fixture()
	var cycle := ActionQueue.new(4096, 8192, 3).submit(_test_p04_chain(0), cycle_f.context)
	_check(cycle.status == &"FAULTED" and cycle.reason == &"depth_limit" and cycle.get_steps().size() == 4, "C09 unbounded continuation terminates without recursion")
	for limit: int in [3, 4]:
		var skipped_f := _test_p04_fixture()
		var corpse_sequence := _test_p04_node(&"corpse_sequence", [DeathCommand.new(201, DamageSource.new(&"test")), DamageCommand.new(DamageRequest.new(201, 1.0, &"physical", &"bypass", DamageSource.new(&"test"))), HealCommand.new(201, 1.0, DamageSource.new(&"test"))])
		var skipped_limit := ActionQueue.new(limit, 8, 8).submit(corpse_sequence, skipped_f.context)
		_check(skipped_limit.status == (&"FAULTED" if limit == 3 else &"APPLIED") and skipped_limit.get_steps().size() == limit and skipped_limit.get_steps()[2]["status"] == &"SKIPPED", "C09 skipped corpse child consumes command budget %d" % limit)
	for event_limit: int in [1, 2]:
		var f := _test_p04_fixture()
		var sink := P04HookSink.new()
		f.context._sink = sink
		var r := ActionQueue.new(4, event_limit, 4).submit(_test_p04_hp(201, 100.0), f.context)
		_check(r.status == (&"FAULTED" if event_limit == 1 else &"APPLIED") and r.get_events().size() == 2 and r.get_steps().size() == 1 and r.revision_after == 1, "C09 atomic lethal event boundary/overshoot %d" % event_limit)
		_check(not f.unit.is_alive() and sink.events == r.get_events(), "C09 fault publishes full atomic prefix without rollback")
	var f := _test_p04_fixture()
	var r := ActionQueue.new(8, 2, 8).submit(_test_p04_node(&"root", [_test_p04_hp(), _test_p04_hp(), _test_p04_hp()]), f.context)
	_check(r.status == &"FAULTED" and r.reason == &"event_limit" and r.get_events().size() == 3 and f.unit.vitals.get_hp() == 7.0, "C09 event +1 retains preceding and offending atomic steps")
	for limits: Vector3i in [Vector3i(0, 1, 1), Vector3i(4097, 1, 1), Vector3i(1, 0, 1), Vector3i(1, 8193, 1), Vector3i(1, 1, 0), Vector3i(1, 1, 65)]:
		f = _test_p04_fixture()
		r = ActionQueue.new(limits.x, limits.y, limits.z).submit(_test_p04_hp(), f.context)
		_check(r.status == &"REJECTED" and r.reason == &"invalid_limits" and f.context._next_root_id == 1 and f.unit.vitals.get_hp() == 10.0, "C09 invalid limits reject before admission %s" % limits)

func _test_p04_c10_faults_and_counters() -> void:
	for mode: String in ["invalid", "unsupported", "busy"]:
		var f := _test_p04_fixture()
		if mode == "invalid": f.state._owners.clear()
		if mode == "unsupported": f.context._unsupported_runtime_ids.append(&"external_test")
		if mode == "busy": f.owner._guard = true
		var board_before: Dictionary = f.board.to_snapshot_dict()
		var r := ActionQueue.new().submit(_test_p04_hp(), f.context)
		_check(r.status == &"REJECTED" and r.root_id == 0 and r.get_events().is_empty() and f.context._next_root_id == 1 and f.context._next_command_seq == 1 and f.context._next_event_seq == 1 and f.context.get_revision() == 0, "C10 preflight rejection preserves counters " + mode)
		_check(board_before == f.board.to_snapshot_dict() and not f.context.is_busy(), "C10 preflight does not mutate board " + mode)
		if mode == "busy": _check(r.reason == &"BUSY", "C10 owner BUSY maps to BUSY")
		f.owner._guard = false
	var f := _test_p04_fixture()
	var unknown := ActionQueue.new().submit(Command.new(), f.context)
	_check(unknown.status == &"REJECTED" and unknown.root_id == 0, "C10 base Command is explicitly rejected")
	var root := P04Work.new(&"damage_fixture", func(c: ActionContext) -> CommandStepResult:
		var step := ActionHpExecutor.damage(_test_p04_hp().request, c)
		step.mandatory.append(Command.new())
		return step)
	var r := ActionQueue.new().submit(root, f.context)
	_check(r.status == &"FAULTED" and r.reason == &"invalid_child" and r.get_events().size() == 1 and f.unit.vitals.get_hp() == 9.0, "C10 invalid internal child preserves damage prefix")
	var child_flag: Dictionary = {"executed": false}
	var rejected_child := P04Work.new(&"rejected_child", func(_context: ActionContext) -> CommandStepResult:
		child_flag["executed"] = true
		return CommandStepResult.applied())
	rejected_child.validation = func(_context: ActionContext) -> StringName: return &"invalid_child_payload"
	var validation_root := _test_p04_node(&"validation_root", [rejected_child])
	r = ActionQueue.new().submit(validation_root, _test_p04_fixture().context)
	_check(r.status == &"FAULTED" and r.reason == &"invalid_child_payload" and r.get_steps().size() == 2 and not bool(child_flag["executed"]), "C10 internal child revalidation faults before execute")
	f = _test_p04_fixture()
	var collector_failure := P04Work.new(&"collector_failure", func(c: ActionContext) -> CommandStepResult:
		var step := ActionHpExecutor.damage(_test_p04_hp().request, c)
		c.get_state().get_owner(201)._guard = true
		return step)
	r = ActionQueue.new().submit(collector_failure, f.context)
	_check(r.status == &"FAULTED" and String(r.reason).begins_with("collector/") and r.get_events().size() == 1 and r.revision_after == 1, "C10 collector error after mutation faults with prefix")
	f.owner._guard = false
	var malformed := P04Work.new(&"malformed", func(_c: ActionContext) -> CommandStepResult:
		var step := CommandStepResult.new()
		step.status = &"UNKNOWN"
		return step)
	r = ActionQueue.new().submit(malformed, _test_p04_fixture().context)
	_check(r.status == &"FAULTED" and r.reason == &"malformed_step", "C10 malformed step explicit fault")
	for field: String in ["_next_root_id", "_next_command_seq", "_next_event_seq", "_revision"]:
		f = _test_p04_fixture()
		var context: ActionContext = f.context
		context.set(field, ActionContext.MAX_ID - 1)
		r = ActionQueue.new().submit(HealCommand.new(201, 0.0, DamageSource.new(&"test")), context)
		var accepted := field in ["_next_root_id", "_next_command_seq"]
		_check(r.status == (&"APPLIED" if accepted else &"REJECTED"), "C10 MAX-1 boundary " + field)
		_check(context.get(field) == (ActionContext.MAX_ID if accepted else ActionContext.MAX_ID - 1), "C10 counter never wraps " + field)
		if not accepted: _check(r.reason == &"sequence_exhausted" and r.root_id == 0, "C10 reserve two event ids and revision increment " + field)
		f = _test_p04_fixture()
		f.context.set(field, ActionContext.MAX_ID)
		r = ActionQueue.new().submit(_test_p04_hp(), f.context)
		_check(r.status == &"REJECTED" and r.reason == &"sequence_exhausted" and f.unit.vitals.get_hp() == 10.0, "C10 exhausted sentinel " + field)
	f = _test_p04_fixture()
	f.context._next_event_seq = ActionContext.MAX_ID - 2
	r = ActionQueue.new().submit(_test_p04_hp(201, 100.0), f.context)
	_check(r.status == &"APPLIED" and r.get_events()[0]["event_seq"] == ActionContext.MAX_ID - 2 and r.get_events()[1]["event_seq"] == ActionContext.MAX_ID - 1 and f.context._next_event_seq == ActionContext.MAX_ID, "C10 last two event ids retain int64 precision")
	for field: String in ["_next_command_seq", "_next_event_seq", "_revision"]:
		f = _test_p04_fixture()
		f.context.set(field, ActionContext.MAX_ID - (2 if field != "_next_command_seq" else 1))
		root = P04Work.new(&"last_step", func(c: ActionContext) -> CommandStepResult:
			var step := ActionHpExecutor.damage(_test_p04_hp().request, c)
			step.mandatory.append(_test_p04_hp())
			return step)
		r = ActionQueue.new().submit(root, f.context)
		_check(r.status == &"FAULTED" and r.reason == &"sequence_exhausted" and r.get_steps().size() == 1 and r.get_events().size() == 1 and f.unit.vitals.get_hp() == 9.0, "C10 post-admission exhaustion before next mutation " + field)

func _test_p04_remaining_edges() -> void:
	var f := _test_p04_fixture()
	var unit: UnitState = f.unit
	var context: ActionContext = f.context
	# Принудительно dirty, чтобы snapshot-сравнение не скрывало прогрев cache при отказе.
	var armor: Stat = unit.stats._stats[StatTypes.StatType.ARMOR]
	armor.set_base_value(3.0)
	var cache := [armor._cache_dirty, armor._cached_value, armor._modifier_slots.duplicate(), armor._next_modifier_slot]
	var state_before := ItemSimulationSnapshot.capture(f.state, []).snapshot.canonical_bytes()
	var source := DamageSource.new(&"cell")
	var commands: Array[Command] = []
	for amount: float in [-1.0, NAN, INF, -INF]:
		commands.append(DamageCommand.new(DamageRequest.new(201, amount, &"physical", &"flat", source)))
		commands.append(HealCommand.new(201, amount, source))
	for id: int in [-1, 0, ActionContext.MAX_ID, 999]: commands.append(DeathCommand.new(id, source))
	commands.append(_test_p04_node(&"reject_validate"))
	(commands.back() as P04Work).validation = func(_c: ActionContext) -> StringName: return &"invalid_fixture"
	for bad_source: DamageSource in [DamageSource.new(&"cell", -1), DamageSource.new(&"cell", 0, Vector2i.ZERO, -1), DamageSource.new(&"cell", 0, Vector2i.ZERO, 999), DamageSource.new(&"cell", 0, Vector2i.ZERO, 0, 999)]:
		commands.append(DamageCommand.new(DamageRequest.new(201, 1.0, &"physical", &"flat", bad_source)))
	for command in commands:
		var r := ActionQueue.new().submit(command, context)
		_check(r.status == &"REJECTED" and r.root_id == 0 and r.get_steps().is_empty() and r.get_events().is_empty() and [context._next_root_id, context._next_command_seq, context._next_event_seq, context._revision] == [1, 1, 1, 0], "C03 invalid numeric/source/id has no admission or counters")
	_check(cache == [armor._cache_dirty, armor._cached_value, armor._modifier_slots, armor._next_modifier_slot] and ItemSimulationSnapshot.capture(f.state, []).snapshot.canonical_bytes() == state_before and f.rng.to_dict()["streams"][0]["cursor"] == 0, "C03 rejected matrix preserves dirty cache/slots/state/RNG")
	var overflow := _test_p04_fixture()
	var overflow_unit: UnitState = overflow.unit
	overflow_unit.stats.set_base_value(StatTypes.StatType.ARMOR, -1.7e308)
	_check(ItemSimulationSnapshot.capture(overflow.state, []).code == ItemSnapshotResult.Code.OK, "C03 finite extreme armor passes composition gate")
	var overflow_result := ActionQueue.new().submit(DamageCommand.new(DamageRequest.new(201, 1.7e308, &"physical", &"flat", source)), overflow.context)
	_check(overflow_result.status == &"REJECTED" and overflow_result.reason == &"invalid_armor" and overflow_unit.vitals.get_hp() == 10.0, "C03 finite operands overflow rejected before HP mutator")
	var zero := _test_p04_fixture()
	zero.unit.vitals.set_hp(0.0)
	var zero_result := ActionQueue.new().submit(_test_p04_hp(), zero.context)
	_check(zero_result.status == &"APPLIED" and zero_result.get_events().size() == 1 and zero_result.get_events()[0]["kind"] == &"died", "C02 positive damage at alive-zero emits only died")
	var rng := P04TestRng.new()
	var valid := rng.to_dict()
	for malformed: Dictionary in [{"schema_version": 1.0, "streams": valid["streams"]}, {&"schema_version": 1, "streams": valid["streams"]}, {"schema_version": 1, "streams": [{&"name": "combat", "cursor": 0}, {"name": "loot", "cursor": 0}]}]:
		_check(not rng.from_dict(malformed) and rng.to_dict() == valid, "C11 exact version and key types reject atomically")
	valid["streams"][0]["cursor"] = 77
	_check(rng.next_int(&"combat", ActionContext.MAX_ID) == 0 and rng.to_dict()["streams"][0]["cursor"] == 1, "C11 output DTO isolated; positive int64 upper supported")
	var malformed_events := P04Work.new(&"malformed_events", func(c: ActionContext) -> CommandStepResult:
		var step := ActionHpExecutor.damage(_test_p04_hp().request, c)
		step.events.append(step.events[0].duplicate(true))
		step.events.append(step.events[0].duplicate(true))
		return step)
	var fault := ActionQueue.new().submit(malformed_events, _test_p04_fixture().context)
	_check(fault.status == &"FAULTED" and fault.reason == &"malformed_step" and fault.revision_after == 1, "C09 more than two drafts is explicit invariant fault")

# P07 проверяет наблюдаемую арифметику и очередь независимо от внутреннего Binding.
func _p07_fixture(blocker_hp: float = -1.0, direction: Vector2i = Vector2i.RIGHT) -> Dictionary:
	var board := BattleBoard.new(5, 5)
	var actor := _p06_unit()
	var target := _p06_unit()
	actor.cell = Vector2i(2, 2) - direction
	target.cell = Vector2i(2, 2)
	actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 6.0)
	actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 4.0)
	actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 5.0)
	actor.stats.set_base_value(StatTypes.StatType.MAIN_ACTIONS_MAX, 4.0)
	target.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
	target.stats.set_base_value(StatTypes.StatType.ARMOR, 3.0)
	target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 5.0)
	target.vitals.set_hp(100.0)
	var units: Array[UnitState] = [actor, target]
	var blocker: UnitState = null
	if blocker_hp >= 0.0:
		blocker = _p06_unit()
		blocker.cell = target.cell + direction
		blocker.stats.set_base_value(StatTypes.StatType.HP_MAX, 100.0)
		blocker.stats.set_base_value(StatTypes.StatType.ARMOR, 2.0)
		blocker.vitals.set_hp(blocker_hp)
		units.append(blocker)
	var owners: Array[ItemOwnerState] = []
	var inventories: Array[InventoryState] = []
	var equipment: Array[EquipmentState] = []
	for unit in units:
		board.add_unit(unit)
		var owner := ItemOwnerState.new(unit)
		owners.append(owner)
		inventories.append(InventoryState.new(owner))
		equipment.append(EquipmentState.new(owner))
	actor.enable_action_resources()
	actor.try_refill_turn_resources()
	target.enable_action_resources()
	target.try_refill_turn_resources()
	var state := ItemSimulationState.new(board, owners, inventories, equipment)
	var definition := AttackDefinition.new()
	definition.id = &"p07_balance"
	definition.profile = &"flat_melee_balance_v1"
	var rules := AttackRules.new([actor.id], [{"actor_unit_id": actor.id, "target_unit_id": target.id}], [definition])
	var context := ActionContext.new(state, P04TestRng.new(), ActionEventSink.new(), [], null, rules)
	return {"board": board, "actor": actor, "target": target, "blocker": blocker, "state": state, "definition": definition, "rules": rules, "context": context, "destination": target.cell + direction}

func _p07_submit(f: Dictionary, queue: ActionQueue = null) -> ActionReceipt:
	return (queue if queue != null else ActionQueue.new()).submit(_p06_attack(f), f.context)

func _p07_kinds(receipt: ActionReceipt) -> Array[StringName]:
	var kinds: Array[StringName] = []
	for event in receipt.get_events(): kinds.append(event.kind)
	return kinds

func _p07_events(receipt: ActionReceipt, kind: StringName) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for event in receipt.get_events():
		if event.kind == kind: found.append(event)
	return found

func _p07_heal(f: Dictionary, unit: UnitState) -> ItemDef:
	var definition := ItemDef.new()
	definition.id = &"p07_heal"
	var effect := HealOnDamageEffect.new()
	effect.heal_amount = 2.0
	definition.effects = [effect]
	var state: ItemSimulationState = f.state
	var item := state.get_owner(unit.id).create_item(definition)
	state.get_inventory(unit.id).add_item(item)
	return definition

func _test_p07_a01_profiles() -> void:
	var f := _p07_fixture()
	var exposed: AttackDefinition = f.context.get_attack_rules().get_definition(f.definition.id)
	exposed.profile = &"unknown"
	f.definition.profile = &"unknown"
	f.rules._definitions.clear()
	var receipt := _p07_submit(f)
	_check(receipt.status == &"APPLIED" and f.target.cell == f.destination, "P07 A01 copied profile survives input/getter mutation", receipt.reason)
	_check(f.actor.action_resources.get_main_left() == 3 and f.actor.action_resources.get_bonus_left() == 1 and f.actor.move_points_left == 3.0, "P07 A01 one main only; no refill")
	var bad := AttackDefinition.new(); bad.id = &"unknown"; bad.profile = &"unknown"
	_check(AttackRules.new([], [], [bad]).validate() == &"attack/invalid_rules", "P07 A01 unknown profile rejected")
	var legacy := _p07_fixture()
	legacy.definition.profile = &"flat_melee_v1"
	legacy.context._attack_rules = AttackRules.new([legacy.actor.id], [{"actor_unit_id": legacy.actor.id, "target_unit_id": legacy.target.id}], [legacy.definition])
	_check(_p07_kinds(_p07_submit(legacy)) == [&"attacked", &"damaged"] and legacy.target.vitals.get_balance() == 0.0, "P07 A01 old profile remains HP-only")

func _test_p07_a02_balance() -> void:
	var f := _p07_fixture()
	for values: Array in [[2.0, 2.0], [2.0, 4.0], [1.0, 0.0]]:
		f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, values[0])
		var r := _p07_submit(f)
		_check(r.status == &"APPLIED" and f.target.vitals.get_balance() == values[1] and _p07_events(r, &"moved").size() == (1 if values[1] == 0.0 else 0), "P07 A02 accumulated 2+2+1: %s" % str(values), r.reason)
	for values: Array in [[12.0, 5.0, 0.0, 0.0, 1], [5.0, 5.0, 0.0, 0.0, 1], [0.0, 5.0, 9.0, 9.0, 0], [5.0, 0.0, 9.0, 9.0, 0], [5.0, -1.0, 9.0, 9.0, 0], [0.25, 5.0, 0.125, 0.375, 0], [0.5, 5.0, 9.0, 0.0, 1]]:
		var local := _p07_fixture()
		local.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, values[0])
		local.target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, values[1])
		local.target.vitals.set_balance(values[2])
		var r := _p07_submit(local)
		_check(r.status == &"APPLIED" and local.target.vitals.get_balance() == values[3] and _p07_events(r, &"balance_broken").size() == values[4] and _p07_events(r, &"moved").size() == values[4], "P07 A02 break/immune/fraction/over-max %s" % str(values), r.reason)
		if values[2] == 0.0 and values[4] == 1:
			_check(_p07_events(r, &"balance_changed").is_empty() and r.revision_after == 4, "P07 A02 0-to-0 break has revision without changed")

func _test_p07_a03_lethal_hit() -> void:
	for hp: float in [7.0, 0.0]:
		var f := _p07_fixture()
		f.target.vitals.set_hp(hp)
		var bases: Dictionary = f.target.stats.to_dict()
		var r := _p07_submit(f)
		var expected: Array[StringName] = [&"attacked"]
		if hp > 0.0: expected.append(&"damaged")
		expected.append(&"died")
		_check(r.status == &"APPLIED" and _p07_kinds(r) == expected and not f.target.is_alive() and f.board.occupant_at(f.target.cell) == null and f.board.get_unit_by_id(f.target.id) == f.target and f.target.stats.to_dict() == bases, "P07 A03 hit death/alive-at-zero skips Balance and preserves bases", r.reason)

func _test_p07_a04_directions() -> void:
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var f := _p07_fixture(-1.0, direction)
		f.target.height = 97
		var signals: Array = []
		var hook := func(unit: UnitState, from: Vector2i, to: Vector2i) -> void: signals.append([unit.id, from, to])
		f.board.unit_position_changed.connect(hook)
		var version: int = f.board.board_version
		var r := _p07_submit(f)
		f.board.unit_position_changed.disconnect(hook)
		var moved := _p07_events(r, &"moved")
		_check(r.status == &"APPLIED" and signals.size() == 1 and moved.size() == 1 and f.target.cell == f.destination and f.target.height == 0 and f.board.board_version == version + 1, "P07 A04 exactly one authoritative move " + str(direction), r.reason)
		_check(moved.size() == 1 and moved[0].movement_kind == &"push" and moved[0].move_cost == 0.0 and moved[0].move_before == 3.0 and moved[0].move_after == 3.0 and f.target.action_resources.get_main_left() == 2 and f.target.action_resources.get_bonus_left() == 1, "P07 A04 forced move preserves target resources")
	for mode: String in ["diagonal", "height", "range"]:
		var f := _p07_fixture()
		if mode == "diagonal": f.board.move_unit(f.actor, Vector2i(1, 1))
		elif mode == "height": f.board.set_height(f.actor.cell, 1)
		else: f.actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE, 2.0)
		_check(_p07_submit(f).status == &"REJECTED" and f.actor.action_resources.get_main_left() == 4, "P07 A04 unchanged P06 reach " + mode)

func _test_p07_a05_blocked() -> void:
	for reason: StringName in [&"wall", &"height"]:
		var f := _p07_fixture(100.0)
		if reason == &"wall": f.board.set_terrain(f.destination, TerrainType.Type.WALL)
		else: f.board.set_height(f.destination, 1)
		var version: int = f.board.board_version
		var r := _p07_submit(f)
		_check(r.status == &"APPLIED" and _p07_kinds(r) == [&"attacked", &"damaged", &"balance_broken", &"push_blocked", &"damaged"] and f.target.vitals.get_hp() == 86.0 and f.blocker.vitals.get_hp() == 100.0 and f.target.cell == Vector2i(2, 2) and f.board.board_version == version, "P07 A05 blocked " + reason, r.reason)
		_check(_p07_events(r, &"push_blocked").size() == 1 and _p07_events(r, &"push_blocked")[0].reason == reason, "P07 A05 exact blocked marker")
	var lethal := _p07_fixture()
	lethal.target.vitals.set_hp(10.0)
	lethal.board.set_terrain(lethal.destination, TerrainType.Type.WALL)
	var death := _p07_submit(lethal)
	_check(death.status == &"APPLIED" and not lethal.target.is_alive() and lethal.board.occupant_at(lethal.target.cell) == null and _p07_events(death, &"moved").is_empty(), "P07 A05 wall death cleans occupancy without move")

func _test_p07_a06_collision() -> void:
	for target_hp: float in [100.0, 9.0]:
		var f := _p07_fixture(100.0)
		f.target.vitals.set_hp(target_hp)
		var r := _p07_submit(f)
		var damage := _p07_events(r, &"damaged")
		_check(r.status == &"APPLIED" and f.target.vitals.get_hp() == maxf(0.0, target_hp - 14.0) and f.blocker.vitals.get_hp() == 92.0 and _p07_events(r, &"moved").is_empty() and f.target.cell == Vector2i(2, 2) and f.blocker.cell == f.destination, "P07 A06 collision independent HP and no chain", r.reason)
		_check(damage.size() == 3 and damage[1].amount == minf(7.0, target_hp - 7.0) and damage[2].amount == 8.0 and damage[1].command_seq == damage[2].command_seq and damage[1].source.kind == &"collision" and damage[2].source.origin_cell == f.destination and damage[2].source.credit_unit_id == f.actor.id and _p07_events(r, &"balance_broken").size() == 1, "P07 A06 one collision step; source and no collateral impact")

func _test_p07_a07_healing() -> void:
	var f := _p07_fixture(100.0)
	_p07_heal(f, f.target); _p07_heal(f, f.blocker)
	var r := _p07_submit(f)
	var heals := _p07_events(r, &"healed")
	_check(r.status == &"APPLIED" and _p07_kinds(r) == [&"attacked", &"damaged", &"balance_broken", &"collision", &"damaged", &"damaged", &"healed", &"healed", &"healed"] and f.target.vitals.get_hp() == 90.0 and f.blocker.vitals.get_hp() == 94.0, "P07 A07 both collision HP before real item healing", r.reason)
	_check(heals.size() == 3 and heals[0].hp_before == 86.0 and heals[1].hp_before == 92.0 and heals[2].hp_before == 88.0 and heals[0].parent_event_seq == r.get_events()[4].event_seq and heals[2].parent_event_seq == r.get_events()[1].event_seq, "P07 A07 healing order and parent event binding")
	for blocker_hp: float in [8.0, 100.0]:
		var dead := _p07_fixture(blocker_hp)
		dead.target.vitals.set_hp(9.0)
		_p07_heal(dead, dead.target); _p07_heal(dead, dead.blocker)
		var result := _p07_submit(dead)
		_check(result.status == &"APPLIED" and not dead.target.is_alive() and dead.target.vitals.get_hp() == 0.0 and _p07_events(result, &"healed").size() == (0 if blocker_hp == 8.0 else 1) and _p07_events(result, &"died").size() == (2 if blocker_hp == 8.0 else 1) and _p07_events(result, &"moved").is_empty(), "P07 A07 collision death never revived by pending heal", result.reason)

func _test_p07_a08_arithmetic() -> void:
	for values: Array in [[10.0, 1000.0, 1000.0, 1.0, 1.0], [0.0, 0.0, 0.0, 1.0, 1.0], [-5.0, 0.0, -9.0, 1.0, 4.0]]:
		var f := _p07_fixture(100.0)
		f.actor.stats.set_base_value(StatTypes.StatType.STRENGTH, values[0])
		f.actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
		f.target.stats.set_base_value(StatTypes.StatType.ARMOR, values[1])
		f.blocker.stats.set_base_value(StatTypes.StatType.ARMOR, values[2])
		var r := _p07_submit(f)
		_check(r.status == &"APPLIED" and f.target.vitals.get_hp() == 100.0 - 2.0 * values[3] and f.blocker.vitals.get_hp() == 100.0 - values[4], "P07 A08 min1 and signed raw B %s" % str(values), r.reason)
	for mode: String in ["impact_negative", "impact_nan", "impact_inf", "balance_sum", "collision_overflow", "fall_overflow"]:
		var f := _p07_fixture(100.0 if mode == "collision_overflow" else -1.0)
		if mode == "impact_negative": f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, -1.0)
		elif mode == "impact_nan": f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, NAN)
		elif mode == "impact_inf": f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, INF)
		elif mode == "balance_sum":
			f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 1e308); f.target.vitals.set_balance(1e308)
		elif mode == "collision_overflow":
			f.actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 1e308); f.target.stats.set_base_value(StatTypes.StatType.ARMOR, 1e308); f.blocker.stats.set_base_value(StatTypes.StatType.ARMOR, -1e308)
		else:
			f.target.stats.set_base_value(StatTypes.StatType.HP_MAX, 1e308); f.board.set_height(f.destination, -10)
		var hp: float = f.target.vitals.get_hp()
		var r := _p07_submit(f)
		_check(r.status == &"REJECTED" and r.root_id == 0 and r.get_events().is_empty() and f.actor.action_resources.get_main_left() == 4 and f.target.vitals.get_hp() == hp, "P07 A08 nonfinite arithmetic rejects before payment " + mode, r.reason)

func _test_p07_a09_drop() -> void:
	for values: Array in [[0, 100.0, 3.0, 93.0], [1, 100.0, 3.0, 71.0], [2, 100.0, 3.0, 46.0], [3, 100.0, 3.0, 21.0], [1, 100.0, 1000.0, 98.0]]:
		var f := _p07_fixture()
		f.board.set_height(f.destination, -int(values[0]))
		f.target.stats.set_base_value(StatTypes.StatType.ARMOR, values[2])
		var r := _p07_submit(f)
		_check(r.status == &"APPLIED" and f.target.vitals.get_hp() == values[3] and f.target.cell == f.destination and _p07_events(r, &"damaged").size() == (1 if values[0] == 0 else 2), "P07 A09 exact fall oracle %s" % str(values), r.reason)
		if values[0] > 0:
			var events := _p07_events(r, &"damaged")
			_check(events.size() == 2 and events[1].source.kind == &"fall" and events[1].source.origin_cell == f.destination, "P07 A09 fall source")
	var fraction := _p07_fixture()
	fraction.actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 0.0); fraction.actor.stats.set_base_value(StatTypes.StatType.WEAPON_DAMAGE, 0.0)
	fraction.target.stats.set_base_value(StatTypes.StatType.HP_MAX, 10.0); fraction.target.stats.set_base_value(StatTypes.StatType.ARMOR, 0.0); fraction.target.vitals.set_hp(10.0)
	fraction.board.set_height(fraction.destination, -1)
	var r := _p07_submit(fraction)
	_check(r.status == &"APPLIED" and fraction.target.vitals.get_hp() == 6.5 and _p07_events(r, &"damaged")[1].amount == 2.5, "P07 A09 fractional damage does not round", r.reason)
	var modified := _p07_fixture()
	modified.target.stats.add_modifier(StatTypes.StatType.HP_MAX, StatModifier.new(&"p07_max", StatModifier.Operation.ADD_FLAT, 100.0))
	modified.board.set_height(modified.destination, -1)
	_check(_p07_submit(modified).status == &"APPLIED" and modified.target.vitals.get_hp() == 46.0, "P07 A09 fall reads modified maximum, not current HP")

func _test_p07_a10_lethal_push() -> void:
	for terrain: TerrainType.Type in [TerrainType.Type.HAZARD, TerrainType.Type.VOID]:
		var f := _p07_fixture()
		f.board.set_terrain(f.destination, terrain)
		f.target.stats.set_base_value(StatTypes.StatType.ARMOR, 1000.0)
		_p07_heal(f, f.target)
		var r := _p07_submit(f)
		var moved := _p07_events(r, &"moved"); var died := _p07_events(r, &"died")
		_check(r.status == &"APPLIED" and not f.target.is_alive() and f.target.cell == f.destination and moved.size() == 1 and died.size() == 1 and moved[0].command_seq == died[0].command_seq and f.board.occupant_at(f.destination) == null and _p07_events(r, &"healed").is_empty(), "P07 A10 lethal terrain move/death atomic before healing", r.reason)
	var edge := _p07_fixture()
	edge.board.move_unit(edge.target, Vector2i(4, 2)); edge.board.move_unit(edge.actor, Vector2i(3, 2))
	edge.target.height = 12345
	var r := _p07_submit(edge)
	var fell := _p07_events(r, &"fell"); var died := _p07_events(r, &"died")
	_check(r.status == &"APPLIED" and _p07_events(r, &"moved").is_empty() and fell.size() == 1 and died.size() == 1 and fell[0].command_seq == died[0].command_seq and fell[0].attempted_cell == Vector2i(5, 2) and edge.target.cell == Vector2i(4, 2) and edge.target.height == 12345 and edge.board.occupant_at(edge.target.cell) == null, "P07 A10 bounds keeps in-bounds corpse cell and independent height", r.reason)
	var snapshot := SimulationSnapshot.capture_board(edge.board, [])
	_check(snapshot.code == BoardSnapshotResult.Code.OK and snapshot.snapshot.instantiate_board().get_unit_by_id(edge.target.id).height == 12345, "P07 A10/A15 bounds corpse snapshot")

func _p07_assert_rejected(f: Dictionary, expected: StringName, label: String) -> void:
	var context: ActionContext = f.context
	var before: Array = [f.actor.action_resources.get_main_left(), f.target.vitals.to_dict(), f.board.board_version, context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision(), context.get_rng().to_dict(), UnitId.get_counter()]
	var actor_stats: Dictionary = f.actor.stats.to_snapshot_dict()
	var target_stats: Dictionary = f.target.stats.to_snapshot_dict()
	var r := _p07_submit(f)
	_check(r.status == &"REJECTED" and (expected == &"" or r.reason == expected) and r.root_id == 0 and r.get_events().is_empty() and before == [f.actor.action_resources.get_main_left(), f.target.vitals.to_dict(), f.board.board_version, context._next_root_id, context._next_command_seq, context._next_event_seq, context.get_revision(), context.get_rng().to_dict(), UnitId.get_counter()] and actor_stats == f.actor.stats.to_snapshot_dict() and target_stats == f.target.stats.to_snapshot_dict(), "P07 A11 pure rejection " + label, r.reason)

func _test_p07_a11_admission() -> void:
	for mode: String in ["missing_impact", "missing_balance", "stale_cache", "negative_impact", "stale_revision"]:
		var f := _p07_fixture()
		var expected: StringName = &""
		if mode == "missing_impact": f.actor.stats._stats.erase(StatTypes.StatType.IMPACT_POWER); expected = &"balance/missing_stat"
		elif mode == "missing_balance": f.target.stats._stats.erase(StatTypes.StatType.BALANCE_MAX); expected = &"balance/missing_stat"
		elif mode == "negative_impact": f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, -1.0); expected = &"balance/invalid_stat"
		elif mode == "stale_cache":
			var stat: Stat = f.target.stats._stats[StatTypes.StatType.BALANCE_MAX]
			stat.get_value(); stat._cached_value = 99.0
		else:
			var old := _p06_attack(f)
			f.context._revision = 1
			_check(ActionQueue.new().submit(old, f.context).reason == &"attack/stale_revision" and f.actor.action_resources.get_main_left() == 4, "P07 A11 stale revision before payment")
			continue
		_p07_assert_rejected(f, expected, mode)
	var f := _p07_fixture()
	for pair: Array in [[BalanceCommand.new(), &"balance/internal_command"], [PushCommand.new(), &"push/internal_command"], [PushCommand.after_collision(null), &"push/internal_command"], [PushDamageCommand.new(), &"push/internal_damage"], [CollisionDamageCommand.new(), &"push/internal_collision"], [P07CollisionSubclass.new(), &"push/internal_collision"]]:
		var r := ActionQueue.new().submit(pair[0], f.context)
		_check(r.reason == pair[1] and r.root_id == 0 and r.get_events().is_empty() and f.actor.action_resources.get_main_left() == 4, "P07 A11 internal roots denied " + String(pair[1]), r.reason)
	for mode: String in ["kill", "immune", "no_break", "blocker_survives"]:
		var local := _p07_fixture(100.0)
		local.board.set_height(local.destination, -1)
		local.target.stats._stats.erase(StatTypes.StatType.HP_MAX)
		if mode == "kill": local.target.vitals._hp = 1.0
		elif mode == "immune": local.target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 0.0)
		elif mode == "no_break": local.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 1.0)
		var r := _p07_submit(local)
		_check(r.status == &"APPLIED", "P07 A11 unused fall maximum does not reject " + mode, r.reason)

class P07CollisionSubclass extends CollisionDamageCommand:
	func copy_for_queue() -> Command: return P07CollisionSubclass.new()

# Обёртка сохраняет реальные HP children: exact collision capacity нельзя имитировать.
class P07TreeHook extends Command:
	var inner: Command
	var after_kind: StringName
	var hook: Callable
	func _init(command: Command, kind: StringName, callback: Callable) -> void:
		inner = command; after_kind = kind; hook = callback
	func get_kind() -> StringName: return inner.get_kind()
	func copy_for_queue() -> Command: return P07TreeHook.new(inner.copy_for_queue(), after_kind, hook)
	func validate(context: ActionContext) -> StringName: return inner.validate(context)
	func execute(context: ActionContext) -> CommandStepResult:
		var result := inner.execute(context)
		if result.status != &"APPLIED": return result
		if inner.get_kind() == after_kind: hook.call(context, result)
		for i in result.mandatory.size():
			if not result.mandatory[i] is CollisionDamageCommand:
				result.mandatory[i] = P07TreeHook.new(result.mandatory[i], after_kind, hook)
		return result

func _test_p07_a13_limits() -> void:
	for limit in range(1, 7):
		var f := _p07_fixture(8.0)
		f.board.set_height(f.destination, -1)
		var r := _p07_submit(f, ActionQueue.new(limit))
		var expected_hp: float = 100.0 if limit == 1 else (93.0 if limit < 5 else 86.0)
		_check(r.status == &"FAULTED" and r.reason == &"command_limit" and r.get_steps().size() == limit and f.actor.action_resources.get_main_left() == 3 and f.target.vitals.get_hp() == expected_hp and f.target.cell == (f.destination if limit == 6 else Vector2i(2, 2)) and f.blocker.is_alive() == (limit < 5), "P07 A13/A17 command boundary %d preserves exact prefix" % limit, r.reason)
	for depth in range(1, 6):
		var f := _p07_fixture(8.0)
		f.board.set_height(f.destination, -1)
		var r := _p07_submit(f, ActionQueue.new(64, 512, depth))
		_check(r.status == &"FAULTED" and r.reason == &"depth_limit" and r.get_steps().size() == depth + 1 and f.target.cell == (f.destination if depth == 5 else Vector2i(2, 2)), "P07 A13 depth boundary %d" % depth, r.reason)
	var both := _p07_fixture(8.0); both.target.vitals.set_hp(9.0)
	var r := _p07_submit(both, ActionQueue.new(64, 5))
	var damage := _p07_events(r, &"damaged"); var died := _p07_events(r, &"died")
	_check(r.status == &"FAULTED" and r.reason == &"event_limit" and r.get_events().size() == 8 and died.size() == 2 and damage.size() == 3 and died[0].command_seq == died[1].command_seq and not both.target.is_alive() and not both.blocker.is_alive(), "P07 A13 cap4 keeps complete double death beyond event budget", r.reason)
	for offset: int in [4, 3]:
		var f := _p07_fixture(8.0); f.target.vitals.set_hp(9.0)
		var hook := func(c: ActionContext, _result: CommandStepResult) -> void: c._next_event_seq = ActionContext.MAX_ID - offset - 1
		var receipt := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(f), &"push", hook), f.context)
		_check(receipt.status == (&"APPLIED" if offset == 4 else &"FAULTED") and (not f.target.is_alive() if offset == 4 else f.target.vitals.get_hp() == 2.0) and f.blocker.vitals.get_hp() == (0.0 if offset == 4 else 8.0) and receipt.get_steps().size() == (5 if offset == 4 else 4), "P07 A13 exact collision event reserve MAX-%d" % offset, receipt.reason)
	var queue := ActionQueue.new()
	_check(queue._event_capacity(CollisionDamageCommand.new()) == 4 and queue._event_capacity(P07CollisionSubclass.new()) == 2 and queue._event_capacity(P04Work.new()) == 2, "P07 A13 capacity4 restricted to exact class")
	for touches: int in [0, 1, 3]:
		for spare: int in [0, 1]:
			var f := _p07_fixture(8.0 if touches == 3 else -1.0)
			if touches == 0: f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
			if touches == 3: f.board.set_terrain(f.destination, TerrainType.Type.HAZARD)
			f.board.board_version = ActionContext.MAX_ID - touches + spare if touches > 0 else ActionContext.MAX_ID
			var receipt := _p07_submit(f)
			_check(receipt.status == (&"REJECTED" if touches > 0 and spare == 1 else &"APPLIED") and f.board.board_version == (ActionContext.MAX_ID - touches + spare if touches > 0 and spare == 1 else ActionContext.MAX_ID), "P07 A13 board reserve touches%d spare%d" % [touches, spare], receipt.reason)
	for budget in [3, 4]:
		var f := _p07_fixture(); f.board.set_terrain(f.destination, TerrainType.Type.HAZARD)
		var receipt := _p07_submit(f, ActionQueue.new(64, budget))
		_check(receipt.status == &"FAULTED" and not f.target.is_alive() and _p07_events(receipt, &"moved").size() == 1 and _p07_events(receipt, &"died").size() == 1, "P07 A13 lethal entry remains atomic across event limit")

func _test_p07_a14_events_busy() -> void:
	var f := _p07_fixture(); f.target.vitals.set_balance(1.0); f.board.set_terrain(f.destination, TerrainType.Type.HAZARD)
	var queue := ActionQueue.new(); var other := ActionQueue.new()
	var results: Array[ActionReceipt] = []
	var probe := func() -> void:
		results.append(queue.submit(P04Work.new(&"p07_busy"), f.context))
		results.append(other.submit(P04Work.new(&"p07_busy"), f.context))
	var numbers := func(_before: float, _after: float) -> void: probe.call()
	f.target.vitals.balance_changed.connect(numbers)
	f.target.vitals.balance_broken.connect(probe)
	f.target.vitals.hp_changed.connect(numbers)
	f.target.vitals.died.connect(probe)
	f.board.board_changed.connect(probe)
	var sink := P04HookSink.new(); sink.hook = func(_event: Dictionary) -> void: probe.call()
	f.context._sink = sink
	var r := _p07_submit(f, queue)
	f.target.vitals.balance_changed.disconnect(numbers)
	f.target.vitals.balance_broken.disconnect(probe)
	f.target.vitals.hp_changed.disconnect(numbers)
	f.target.vitals.died.disconnect(probe)
	f.board.board_changed.disconnect(probe)
	sink.hook = Callable()
	var all_busy := results.size() >= 12
	for result in results: all_busy = all_busy and result.reason == &"BUSY" and result.get_events().is_empty()
	_check(r.status == &"APPLIED" and all_busy, "P07 A14 balance/HP/death/board/sink guards on both queues", r.reason)
	var drafts: Array[Dictionary] = [
		{"kind": &"balance_changed", "actor_unit_id": 1, "target_unit_id": 2, "balance_before": 1.0, "balance_after": 3.0, "balance_max": 5.0, "impact": 2.0, "broke": false},
		{"kind": &"balance_broken", "actor_unit_id": 1, "target_unit_id": 2, "balance_before": 0.0, "balance_after": 0.0, "balance_max": 5.0, "impact": 5.0, "broke": true},
		{"kind": &"moved", "actor_unit_id": 1, "target_unit_id": 2, "from_cell": Vector2i.ZERO, "to_cell": Vector2i.RIGHT, "movement_kind": &"push", "move_cost": 0.0, "move_before": 3.0, "move_after": 3.0},
		{"kind": &"push_blocked", "actor_unit_id": 1, "target_unit_id": 2, "from_cell": Vector2i.ZERO, "attempted_cell": Vector2i.RIGHT, "reason": &"wall"},
		{"kind": &"collision", "actor_unit_id": 1, "target_unit_id": 2, "from_cell": Vector2i.ZERO, "attempted_cell": Vector2i.RIGHT, "blocker_unit_id": 3},
		{"kind": &"fell", "actor_unit_id": 1, "target_unit_id": 2, "from_cell": Vector2i.ZERO, "attempted_cell": Vector2i.LEFT, "reason": &"bounds"}]
	for draft in drafts:
		_check(ActionQueue._valid_draft(draft), "P07 A14 valid strict schema " + String(draft.kind))
		for key in draft.keys():
			var malformed := draft.duplicate(true); malformed[key] = null
			_check(not ActionQueue._valid_draft(malformed), "P07 A14 exact type " + String(draft.kind) + "/" + key)
		var extra := draft.duplicate(true); extra["extra"] = 0
		var string_kind := draft.duplicate(true); string_kind.kind = String(draft.kind)
		_check(not ActionQueue._valid_draft(extra) and not ActionQueue._valid_draft(string_kind), "P07 A14 extra keys/String refused")
		var malformed := draft.duplicate(true); malformed.target_unit_id = malformed.actor_unit_id
		var invalid_root := P04Work.new(&"p07_schema", func(_c: ActionContext) -> CommandStepResult: return CommandStepResult.applied([malformed]))
		var local := _p07_fixture(); var q := ActionQueue.new()
		var result := q.submit(invalid_root, local.context)
		_check(result.status == &"FAULTED" and result.reason == &"malformed_event" and ActionQueue.new().submit(_p06_attack(local), local.context).reason == &"CONTEXT_FAULTED", "P07 A14 malformed schema faults and latches context")
	for hp: float in [0.0, 8.0]:
		var local := _p07_fixture(hp)
		var result := _p07_submit(local)
		_check(result.status == &"APPLIED" and not local.blocker.is_alive() and local.target.cell == local.destination and _p07_events(result, &"died").size() == 1, "P07 A14 collision cap is maximum; alive-at-zero works", result.reason)

func _test_p07_a15_snapshots() -> void:
	var f := _p07_fixture(8.0)
	f.target.vitals.set_balance(1.0)
	var definition := _p07_heal(f, f.target)
	f.target.stats.add_modifier(StatTypes.StatType.BALANCE_MAX, StatModifier.new(&"p07_balance_mod", StatModifier.Operation.ADD_FLAT, 1.0))
	var captured := ItemSimulationSnapshot.capture(f.state, [])
	_check(captured.code == ItemSnapshotResult.Code.OK, "P07 A15 source capture", captured.reason)
	if captured.snapshot == null: return
	var allocator := UnitId.get_counter()
	var states: Array[ItemSimulationState] = []
	var receipts: Array[ActionReceipt] = []
	var contexts: Array[ActionContext] = []
	for i in 2:
		var restored := captured.snapshot.instantiate({definition.id: definition})
		_check(restored.code == ItemSnapshotResult.Code.OK, "P07 A15 independent restore %d" % i, restored.reason)
		if restored.state == null: return
		states.append(restored.state)
		var actor := restored.state.get_board().get_unit_by_id(f.actor.id)
		var target := restored.state.get_board().get_unit_by_id(f.target.id)
		var context := ActionContext.new(restored.state, P04TestRng.new(), ActionEventSink.new(), [], null, f.rules)
		contexts.append(context)
		receipts.append(ActionQueue.new().submit(AttackCommand.new(actor.id, target.id, actor.cell, target.cell, f.definition.id, 0), context))
	_check(receipts[0].status == &"APPLIED" and receipts[1].status == &"APPLIED" and receipts[0].get_events() == receipts[1].get_events() and receipts[0].get_steps() == receipts[1].get_steps() and receipts[0].revision_after == receipts[1].revision_after and contexts[0]._next_event_seq == contexts[1]._next_event_seq and contexts[0].get_rng().to_dict() == contexts[1].get_rng().to_dict() and UnitId.get_counter() == allocator, "P07 A15 identical real commands, receipts, counters and RNG without allocator")
	var first := ItemSimulationSnapshot.capture(states[0], []); var second := ItemSimulationSnapshot.capture(states[1], [])
	_check(first.code == ItemSnapshotResult.Code.OK and second.code == ItemSnapshotResult.Code.OK and first.snapshot.fingerprint() == second.snapshot.fingerprint() and ItemSimulationSnapshot.capture(f.state, []).snapshot.canonical_bytes() == captured.snapshot.canonical_bytes(), "P07 A15 equal post-push fingerprints and unchanged original")
	var twin: UnitState = states[0].get_board().get_unit_by_id(f.target.id)
	twin.vitals.set_balance(19.0)
	states[1].get_board().get_unit_by_id(f.actor.id).action_resources.try_spend_main(1)
	_check(states[1].get_board().get_unit_by_id(f.target.id).vitals.get_balance() == 0.0 and f.target.vitals.get_balance() == 1.0 and states[0].get_board().get_unit_by_id(f.actor.id).action_resources.get_main_left() == 3 and f.actor.action_resources.get_main_left() == 4, "P07 A15 bidirectional isolation")
	for unit: UnitState in [f.actor, _p06_unit()]:
		unit.vitals.set_balance(9.25)
		var dto := unit.to_snapshot_dict()
		var restored := UnitState.from_snapshot_dict(dto)
		_check(restored != null and restored.vitals.get_balance() == 9.25 and (restored.action_resources == null) == (unit.action_resources == null), "P07 A15 Unit v1/v2 over-max balance and ledger round-trip")
	var corpse := _p07_fixture(8.0)
	_p07_submit(corpse)
	var board_snapshot := SimulationSnapshot.capture_board(corpse.board, [])
	var restored_board := board_snapshot.snapshot.instantiate_board() if board_snapshot.snapshot != null else null
	_check(restored_board != null and restored_board.get_unit_by_id(corpse.blocker.id).cell == corpse.destination and restored_board.occupant_at(corpse.destination) != null and restored_board.occupant_at(corpse.destination).id == corpse.target.id, "P07 A15 P02 corpse/live same cell round-trip")

func _test_p07_a16_entry() -> void:
	for mode: String in ["flat", "drop", "hazard", "void"]:
		var f := _p07_fixture(8.0)
		if mode == "drop": f.board.set_height(f.destination, -1)
		elif mode == "hazard": f.board.set_terrain(f.destination, TerrainType.Type.HAZARD)
		elif mode == "void": f.board.set_terrain(f.destination, TerrainType.Type.VOID)
		if mode in ["hazard", "void"]: _p07_heal(f, f.target)
		var version: int = f.board.board_version
		var r := _p07_submit(f)
		var hp: float = 86.0 if mode == "flat" else (64.0 if mode == "drop" else 0.0)
		_check(r.status == &"APPLIED" and f.target.vitals.get_hp() == hp and not f.blocker.is_alive() and f.board.get_unit_by_id(f.blocker.id) == f.blocker and f.target.cell == f.destination and f.blocker.cell == f.destination and _p07_events(r, &"moved").size() == 1 and _p07_events(r, &"collision").size() == 1 and f.board.board_version == version + (3 if hp == 0.0 else 2), "P07 A16 blocker death then one entry " + mode, r.reason)
		_check(f.board.occupant_at(f.destination) == (null if hp == 0.0 else f.target) and _p07_events(r, &"healed").is_empty(), "P07 A16 entry consequences before pending heal " + mode)
	var blocked := _p07_fixture(100.0); blocked.board.set_height(blocked.destination, -1)
	var r := _p07_submit(blocked)
	_check(r.status == &"APPLIED" and blocked.target.vitals.get_hp() == 86.0 and _p07_events(r, &"moved").is_empty() and _p07_events(r, &"damaged").size() == 3, "P07 A16 surviving blocker prevents entry and fall")

func _test_p07_a17_prefix() -> void:
	for mode: String in ["wall", "replacement"]:
		var f := _p07_fixture(8.0)
		var replacement := _p06_unit(); replacement.cell = f.destination
		var replacement_owner := ItemOwnerState.new(replacement)
		var replacement_inventory := InventoryState.new(replacement_owner)
		var replacement_equipment := EquipmentState.new(replacement_owner)
		var hook := func() -> void:
			if mode == "wall": f.board.set_terrain(f.destination, TerrainType.Type.WALL)
			else:
				f.board.add_unit(replacement)
				f.state._owners.append(replacement_owner)
				f.state._inventories.append(replacement_inventory)
				f.state._equipment.append(replacement_equipment)
		f.blocker.vitals.died.connect(hook)
		var r := _p07_submit(f)
		f.blocker.vitals.died.disconnect(hook)
		_check(r.status == &"FAULTED" and r.reason == &"push/entry_obstructed" and f.target.vitals.get_hp() == 86.0 and not f.blocker.is_alive() and f.target.cell == Vector2i(2, 2) and _p07_events(r, &"moved").is_empty() and _p07_events(r, &"damaged").size() == 3 and replacement.vitals.get_hp() == 10.0, "P07 A17 obstructed entry retains pair HP " + mode, r.reason)
	var f := _p07_fixture(100.0)
	var replacement := _p06_unit(); replacement.cell = f.destination; replacement.id = f.blocker.id
	var hook := func(_before: float, after: float) -> void:
		if after != 86.0: return
		f.board.remove_unit(f.blocker)
		f.board.add_unit(replacement)
	f.target.vitals.hp_changed.connect(hook)
	var r := _p07_submit(f)
	f.target.vitals.hp_changed.disconnect(hook)
	_check(r.status == &"FAULTED" and f.target.vitals.get_hp() == 86.0 and f.blocker.vitals.get_hp() == 100.0 and replacement.vitals.get_hp() == 10.0 and _p07_events(r, &"damaged").size() == 2 and r.revision_after == 4, "P07 A17 first collision HP prefix survives blocker replacement callback", r.reason)

func _test_p07_a12_bindings() -> void:
	for stage: StringName in [&"attack", &"attack_hit", &"balance"]:
		for mode: StringName in [&"actor_missing", &"actor_dead", &"actor_moved", &"actor_replaced", &"target_missing", &"target_dead", &"target_moved", &"target_replaced", &"actor_stats", &"target_stats", &"actor_vitals", &"target_vitals", &"actor_owner", &"target_owner", &"ledger", &"paid", &"target_hp", &"balance", &"balance_max"]:
			var f := _p07_fixture()
			var replacement := _p06_unit()
			var hook := func(c: ActionContext, _result: CommandStepResult) -> void:
				var board := c.get_state().get_board()
				var actor: UnitState = f.actor; var target: UnitState = f.target
				match mode:
					&"actor_missing": board.remove_unit(actor)
					&"actor_dead": actor.vitals.apply_damage(1000.0)
					&"actor_moved": board.move_unit(actor, Vector2i(1, 1))
					&"actor_replaced":
						board.remove_unit(actor); replacement.id = actor.id; replacement.cell = actor.cell; board.add_unit(replacement)
					&"target_missing": board.remove_unit(target)
					&"target_dead": target.vitals.apply_damage(1000.0)
					&"target_moved": board.move_unit(target, Vector2i(2, 1))
					&"target_replaced":
						board.remove_unit(target); replacement.id = target.id; replacement.cell = target.cell; board.add_unit(replacement)
					&"actor_stats": actor.stats = StatsBag.from_snapshot_dict(actor.stats.to_snapshot_dict()); actor.vitals._stats = actor.stats
					&"target_stats": target.stats = StatsBag.from_snapshot_dict(target.stats.to_snapshot_dict()); target.vitals._stats = target.stats
					&"actor_vitals": actor.vitals = Vitals.from_dict(actor.vitals.to_dict(), actor.stats)
					&"target_vitals": target.vitals = Vitals.from_dict(target.vitals.to_dict(), target.stats)
					&"actor_owner": c.get_state()._owners[0] = ItemOwnerState.new(actor)
					&"target_owner": c.get_state()._owners[1] = ItemOwnerState.new(target)
					&"ledger": actor.action_resources = ActionResources.from_snapshot_dict(actor.action_resources.to_snapshot_dict(), actor.id)
					&"paid": actor.action_resources.try_spend_main(1)
					&"target_hp": target.vitals.set_hp(80.0)
					&"balance": target.vitals.set_balance(1.0)
					&"balance_max": target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 99.0)
			var r := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(f), stage, hook), f.context)
			_check(r.status == &"FAULTED" and r.get_events().size() == (1 if stage == &"attack" else (2 if stage == &"attack_hit" else 3)) and _p07_events(r, &"moved").is_empty() and replacement.vitals.get_hp() == 10.0 and f.actor.action_resources.get_main_left() <= 3, "P07 A12 stale %s after %s preserves prefix" % [mode, stage], r.reason)
	for field: String in ["raw_attack", "impact", "main_after", "target_id", "actor_cell", "phase", "expected_hp", "binding_null"]:
		var f := _p07_fixture()
		var hook := func(_c: ActionContext, result: CommandStepResult) -> void:
			var hit: AttackHitCommand = result.mandatory[0]
			if field == "binding_null":
				hit._p07_binding = null
				return
			var values: Dictionary = hit._p07_binding.values
			if field == "actor_cell": values[field] = Vector2i.ZERO
			elif field == "phase": values[field] = &"forged"
			else: values[field] = values.get(field, 0) + 1
		var r := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(f), &"attack", hook), f.context)
		_check(r.status == &"FAULTED" and f.target.vitals.get_hp() == 100.0 and r.get_events().size() == 1, "P07 A12 binding value seal survives copies: " + field, r.reason)
	for mutation: StringName in [&"amount", &"target", &"armor_mode", &"origin", &"credit", &"source_null"]:
		var f := _p07_fixture()
		var r := ActionQueue.new().submit(P06AttackHitHook.new(_p06_attack(f), mutation), f.context)
		_check(r.status == &"FAULTED" and f.target.vitals.get_hp() == 100.0 and r.get_events().size() == 1, "P07 A12 existing request/source seal: " + mutation)
	for mode: String in ["wall", "blocker"]:
		var f := _p07_fixture(100.0 if mode == "blocker" else -1.0)
		if mode == "blocker": f.board.move_unit(f.blocker, Vector2i(4, 4))
		var hook := func(c: ActionContext, _result: CommandStepResult) -> void:
			if mode == "wall": c.get_state().get_board().set_terrain(f.destination, TerrainType.Type.WALL)
			else: c.get_state().get_board().move_unit(f.blocker, f.destination)
		var r := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(f), &"balance", hook), f.context)
		_check(r.status == &"APPLIED" and f.target.vitals.get_hp() == 86.0 and f.target.cell == Vector2i(2, 2) and (mode == "wall" or f.blocker.vitals.get_hp() == 92.0), "P07 A12 current destination topology resolved after Balance " + mode, r.reason)
	var frozen := _p07_fixture(100.0)
	var freeze_hook := func(_c: ActionContext, _result: CommandStepResult) -> void:
		frozen.actor.stats.set_base_value(StatTypes.StatType.STRENGTH, 1000.0)
		frozen.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	var frozen_result := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(frozen), &"attack", freeze_hook), frozen.context)
	_check(frozen_result.status == &"APPLIED" and frozen.target.vitals.get_hp() == 86.0 and frozen.blocker.vitals.get_hp() == 92.0 and _p07_events(frozen_result, &"balance_broken").size() == 1, "P07 A12 B and impact freeze at payment", frozen_result.reason)

func _test_p07_extended_boundaries() -> void:
	var balance := {"kind": &"balance_changed", "actor_unit_id": 1, "target_unit_id": 2, "balance_before": 1.0, "balance_after": 3.0, "balance_max": 5.0, "impact": 2.0, "broke": false}
	for pair: Array in [["actor_unit_id", ActionContext.MAX_ID], ["target_unit_id", ActionContext.MAX_ID], ["balance_after", 4.0], ["balance_before", -1.0], ["balance_max", 0.0], ["impact", 0.0], ["impact", INF], ["broke", true], ["kind", &"balance_broken"]]:
		var draft := balance.duplicate(true); draft[pair[0]] = pair[1]
		_check(not ActionQueue._valid_draft(draft), "P07 A14 balance schema semantic rejection " + str(pair))
	var overflow := balance.duplicate(true); overflow.balance_before = 1e308; overflow.impact = 1e308; overflow.balance_after = 0.0; overflow.broke = true
	_check(not ActionQueue._valid_draft(overflow), "P07 A14 event balance sum overflow")
	var unchanged := balance.duplicate(true); unchanged.balance_before = 0.0; unchanged.balance_after = 0.0; unchanged.impact = 5.0; unchanged.broke = true
	_check(not ActionQueue._valid_draft(unchanged), "P07 A14 changed requires actual numeric delta")
	for kind: StringName in [&"push_blocked", &"fell", &"collision", &"moved"]:
		var valid := {"kind": kind, "actor_unit_id": 1, "target_unit_id": 2, "from_cell": Vector2i.ZERO}
		var destination_key: String = "to_cell" if kind == &"moved" else "attempted_cell"
		valid[destination_key] = Vector2i.RIGHT
		if kind == &"moved": valid.merge({"movement_kind": &"push", "move_cost": 0.0, "move_before": 3.0, "move_after": 3.0})
		elif kind == &"collision": valid.blocker_unit_id = 3
		else: valid.reason = &"wall" if kind == &"push_blocked" else &"bounds"
		for cell: Vector2i in [Vector2i.ZERO, Vector2i(1, 1), Vector2i(2, 0)]:
			var draft := valid.duplicate(true); draft[destination_key] = cell
			_check(not ActionQueue._valid_draft(draft), "P07 A14 one edge " + kind + str(cell))
		for bad_id: int in [0, -1, ActionContext.MAX_ID]:
			var draft := valid.duplicate(true); draft.actor_unit_id = bad_id
			_check(not ActionQueue._valid_draft(draft), "P07 A14 bounded actor id " + kind)
		if kind == &"collision":
			for bad_id: int in [0, 1, 2, ActionContext.MAX_ID]:
				var draft := valid.duplicate(true); draft.blocker_unit_id = bad_id
				_check(not ActionQueue._valid_draft(draft), "P07 A14 blocker distinct bounded ID")
		elif kind == &"moved":
			for pair: Array in [["move_cost", 1.0], ["move_after", 2.0], ["move_before", -1.0], ["movement_kind", &"other"]]:
				var draft := valid.duplicate(true); draft[pair[0]] = pair[1]
				_check(not ActionQueue._valid_draft(draft), "P07 A14 forced movement semantics")
		else:
			var draft := valid.duplicate(true); draft.reason = &"occupied"
			_check(not ActionQueue._valid_draft(draft), "P07 A14 exact terrain reason " + kind)
	for mode: String in ["missing_hpmax", "negative_hpmax", "overflow_entry"]:
		var f := _p07_fixture(8.0)
		f.board.set_height(f.destination, -10 if mode == "overflow_entry" else -1)
		if mode == "missing_hpmax": f.target.stats._stats.erase(StatTypes.StatType.HP_MAX)
		elif mode == "negative_hpmax": f.target.stats.set_base_value(StatTypes.StatType.HP_MAX, -1.0)
		else: f.target.stats.set_base_value(StatTypes.StatType.HP_MAX, 1e308)
		_p07_assert_rejected(f, &"", "P07 A11/A16 future entry fall " + mode)
	for mode: String in ["immune", "zero"]:
		var f := _p07_fixture()
		f.target.vitals.set_balance(1e308)
		f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 1e308 if mode == "immune" else 0.0)
		if mode == "immune": f.target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 0.0)
		_check(_p07_submit(f).status == &"APPLIED" and f.target.vitals.get_balance() == 1e308, "P07 A02 unused immune sum not evaluated " + mode)
	for blocked: bool in [false, true]:
		var f := _p07_fixture()
		var from_height: int = -2147483648 if blocked else 2147483647
		var to_height: int = 2147483647 if blocked else -2147483648
		f.board.set_height(f.actor.cell, from_height); f.board.set_height(f.target.cell, from_height); f.board.set_height(f.destination, to_height)
		var r := _p07_submit(f)
		_check(r.status == &"APPLIED" and (_p07_events(r, &"push_blocked").size() == 1 if blocked else not f.target.is_alive()) and f.target.cell == (Vector2i(2, 2) if blocked else f.destination), "P07 A09 int32 extremes use int64 height delta", r.reason)
	# После move внешний callback может испортить участника: prefix обязан содержать moved.
	var moved := _p07_fixture(); moved.board.set_terrain(moved.destination, TerrainType.Type.HAZARD)
	var original: Vitals = moved.target.vitals
	var move_hook := func(unit: UnitState, _from: Vector2i, _to: Vector2i) -> void:
		if unit == moved.target: unit.vitals = Vitals.from_dict(unit.vitals.to_dict(), unit.stats)
	moved.board.unit_position_changed.connect(move_hook)
	var moved_result := _p07_submit(moved)
	moved.board.unit_position_changed.disconnect(move_hook)
	_check(moved_result.status == &"FAULTED" and _p07_events(moved_result, &"moved").size() == 1 and moved.target.cell == moved.destination and moved.target.is_alive() and original.get_hp() == 93.0, "P07 A17 fault after move retains moved; replacement vitals untouched", moved_result.reason)

func _test_p07_collateral_guards() -> void:
	for mode: StringName in [&"first_amount", &"second_amount", &"second_source", &"blocker_missing", &"blocker_dead", &"blocker_moved", &"blocker_replaced", &"blocker_hp", &"blocker_stats", &"blocker_vitals", &"blocker_owner"]:
		var f := _p07_fixture(100.0)
		var replacement := _p06_unit(); replacement.cell = f.destination
		var hook := func(c: ActionContext, result: CommandStepResult) -> void:
			var collision: CollisionDamageCommand = result.mandatory[0]
			var blocker: UnitState = f.blocker
			match mode:
				&"first_amount": collision._first.amount += 1.0
				&"second_amount": collision._second.amount += 1.0
				&"second_source": collision._second.source.credit_unit_id = 0
				&"blocker_missing": f.board.remove_unit(blocker)
				&"blocker_dead": blocker.vitals.apply_damage(1000.0)
				&"blocker_moved": f.board.move_unit(blocker, Vector2i(4, 4))
				&"blocker_replaced": f.board.remove_unit(blocker); replacement.id = blocker.id; f.board.add_unit(replacement)
				&"blocker_hp": blocker.vitals.set_hp(99.0)
				&"blocker_stats": blocker.stats = StatsBag.from_snapshot_dict(blocker.stats.to_snapshot_dict()); blocker.vitals._stats = blocker.stats
				&"blocker_vitals": blocker.vitals = Vitals.from_dict(blocker.vitals.to_dict(), blocker.stats)
				&"blocker_owner": c.get_state()._owners[2] = ItemOwnerState.new(blocker)
		var r := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(f), &"push", hook), f.context)
		_check(r.status == &"FAULTED" and f.target.vitals.get_hp() == 93.0 and r.get_events().size() == 4 and replacement.vitals.get_hp() == 10.0, "P07 A12 both collateral bindings validated before first HP " + mode, r.reason)
	for wall: bool in [false, true]:
		for mode: StringName in [&"amount", &"source"]:
			var f := _p07_fixture()
			if wall: f.board.set_terrain(f.destination, TerrainType.Type.WALL)
			else: f.board.set_height(f.destination, -1)
			var hook := func(_c: ActionContext, result: CommandStepResult) -> void:
				var damage: PushDamageCommand = result.mandatory[0]
				if mode == &"amount": damage.request.amount += 1.0
				else: damage.request.source.origin_cell = Vector2i.ZERO
			var r := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(f), &"push", hook), f.context)
			_check(r.status == &"FAULTED" and f.target.vitals.get_hp() == 93.0 and f.target.cell == (Vector2i(2, 2) if wall else f.destination), "P07 A12 wall/fall request seal and prefix", r.reason)
	for mode: StringName in [&"hp", &"stats", &"vitals", &"owner"]:
		var f := _p07_fixture(100.0)
		var hook := func(_before: float, after: float) -> void:
			if after != 86.0: return
			var blocker: UnitState = f.blocker
			if mode == &"hp": blocker.vitals.set_hp(99.0)
			elif mode == &"stats": blocker.stats = StatsBag.from_snapshot_dict(blocker.stats.to_snapshot_dict()); blocker.vitals._stats = blocker.stats
			elif mode == &"vitals": blocker.vitals = Vitals.from_dict(blocker.vitals.to_dict(), blocker.stats)
			else: f.state._owners[2] = ItemOwnerState.new(blocker)
		f.target.vitals.hp_changed.connect(hook)
		var r := _p07_submit(f)
		f.target.vitals.hp_changed.disconnect(hook)
		_check(r.status == &"FAULTED" and f.target.vitals.get_hp() == 86.0 and f.blocker.vitals.get_hp() == (99.0 if mode == &"hp" else 100.0) and _p07_events(r, &"damaged").size() == 2 and r.revision_after == 4, "P07 A17 revalidate blocker after first HP " + mode, r.reason)

func _test_p07_version_preflight() -> void:
	for mode: String in ["wall_death", "both_deaths", "fall_death", "entry_fall_death", "wall_survives", "pair_survives"]:
		var required: int = 1 if mode == "wall_death" else (2 if mode in ["both_deaths", "fall_death"] else (3 if mode == "entry_fall_death" else 0))
		for insufficient: bool in [false, true]:
			var f := _p07_fixture(8.0 if mode in ["both_deaths", "entry_fall_death"] else (100.0 if mode == "pair_survives" else -1.0))
			if mode in ["wall_death", "both_deaths"]: f.target.vitals.set_hp(9.0)
			if mode in ["wall_death", "wall_survives"]: f.board.set_terrain(f.destination, TerrainType.Type.WALL)
			if mode in ["fall_death", "entry_fall_death"]: f.board.set_height(f.destination, -4)
			f.board.board_version = ActionContext.MAX_ID - required + (1 if insufficient and required > 0 else 0)
			var before_hp: float = f.target.vitals.get_hp()
			var r := _p07_submit(f)
			var rejected: bool = insufficient and required > 0
			_check(r.status == (&"REJECTED" if rejected else &"APPLIED") and (f.target.vitals.get_hp() == before_hp and f.actor.action_resources.get_main_left() == 4 if rejected else f.board.board_version == ActionContext.MAX_ID), "P07 A13 complete chain reserve " + mode + str(insufficient), r.reason)
	for mode: String in ["move", "wall_death", "both_deaths", "fall_death"]:
		var f := _p07_fixture(8.0 if mode == "both_deaths" else -1.0)
		if mode in ["wall_death", "both_deaths"]: f.target.vitals.set_hp(9.0)
		if mode == "wall_death": f.board.set_terrain(f.destination, TerrainType.Type.WALL)
		if mode == "fall_death": f.board.set_height(f.destination, -4)
		var hook := func(_c: ActionContext, _result: CommandStepResult) -> void: f.board.board_version = ActionContext.MAX_ID
		var stage: StringName = &"balance" if mode == "move" else &"push"
		var r := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(f), stage, hook), f.context)
		_check(r.status == &"FAULTED" and r.reason == &"push/board_version_exhausted" and f.target.is_alive() and f.target.vitals.get_hp() == (2.0 if mode in ["wall_death", "both_deaths"] else 93.0) and f.target.cell == (f.destination if mode == "fall_death" else Vector2i(2, 2)), "P07 A13 recheck board reserve at child boundary " + mode, r.reason)

func _test_p07_api_preflight() -> void:
	var f := _p07_fixture(100.0)
	var prepared := BalancePushRules.prepare_attack(f.context, f.actor, f.target, 10.0, 7.0, 3)
	_check(prepared.size() == 2 and prepared.has("reason") and prepared.has("binding") and prepared.reason == &"" and prepared.binding != null, "P07 A11 prepare_attack exact result shape")
	if prepared.binding == null: return
	var binding: BalancePushRules.Binding = prepared.binding
	var values := binding.values.duplicate(true)
	var pushed := BalancePushRules.prepare_push(binding, f.context, true)
	_check(pushed.size() == 10 and pushed.reason == &"" and pushed.binding != binding and binding.values == values and binding.blocker == null and binding.first == null and binding.second == null, "P07 A11 admission resolve is pure and copies stage binding")
	var unpaid := BalancePushRules.prepare_push(binding, f.context, false)
	_check(unpaid.reason != &"" and unpaid.binding == null and unpaid.first == null and unpaid.second == null and unpaid.from_cell == Vector2i.ZERO and unpaid.attempted_cell == Vector2i.ZERO and unpaid.board_touches == 0, "P07 A11 post-payment resolve rejects unpaid stage with neutral result")
	for mode: String in ["ledger", "state", "target_hp", "target_cell", "target_owner"]:
		var local := _p07_fixture()
		var root := BalancePushRules.prepare_attack(local.context, local.actor, local.target, 10.0, 7.0, 3)
		if root.binding == null:
			_check(false, "P07 API fixture binding", root.reason); continue
		if mode == "ledger": local.actor.action_resources.try_spend_main(1)
		elif mode == "state": local.context._state = ItemSimulationState.new(local.board, local.state.get_owners(), local.state.get_inventories(), local.state.get_equipment_facades())
		elif mode == "target_hp": local.target.vitals.set_hp(99.0)
		elif mode == "target_cell": local.board.move_unit(local.target, Vector2i(2, 1))
		else: local.state._owners[1] = ItemOwnerState.new(local.target)
		var result := BalancePushRules.prepare_push(root.binding, local.context, true)
		_check(result.reason != &"" and result.binding == null and result.first == null and result.second == null and result.from_cell == Vector2i.ZERO and result.attempted_cell == Vector2i.ZERO and result.board_touches == 0, "P07 A11 direct admission binding guard " + mode)
	var invalid := BalancePushRules.prepare_attack(null, f.actor, f.target, 10.0, 7.0, 3)
	_check(invalid.size() == 2 and invalid.reason != &"" and invalid.binding == null, "P07 A11 null prepare_attack returns exact failure")
	for mode: String in ["flat", "lethal"]:
		var local := _p07_fixture()
		var hook := func(_c: ActionContext, _result: CommandStepResult) -> void: local.target.stats._stats.erase(StatTypes.StatType.ARMOR)
		if mode == "lethal": local.board.set_terrain(local.destination, TerrainType.Type.HAZARD)
		var result := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(local), &"balance", hook), local.context)
		_check(result.status == &"APPLIED" and local.target.cell == local.destination and local.target.is_alive() == (mode == "flat"), "P07 A11 unused armor after topology preflight " + mode, result.reason)
	var cache := _p07_fixture()
	var live_stat: Stat = cache.target.stats._stats[StatTypes.StatType.BALANCE_MAX]
	live_stat._cache_dirty = true; live_stat._cached_value = -123.0
	cache.board.board_version = ActionContext.MAX_ID
	var rejected := _p07_submit(cache)
	_check(rejected.status == &"REJECTED" and rejected.reason == &"push/board_version_exhausted" and live_stat._cache_dirty and live_stat._cached_value == -123.0, "P07 A11 root rejection preserves actual dirty cache and cached value", rejected.reason)

func _p08_fixture(blocker_hp: float = -1.0) -> Dictionary:
	var f := _p07_fixture(blocker_hp)
	f.definition.profile = AttackRules.SPATIAL_PROFILE
	f.rules = AttackRules.new([f.actor.id], [{"actor_unit_id": f.actor.id, "target_unit_id": f.target.id}], [f.definition])
	f.context = ActionContext.new(f.state, P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([f.actor.id, f.target.id], 1, &"spatial_move_v1"), f.rules)
	return f

func _p08_cleanup(f: Dictionary) -> void:
	f.board.resize(0, 0)

func _test_p08_commands() -> void:
	for shape: String in ["flat", "half", "wall", "fall", "hazard", "bounds", "collision_alive", "collision_dead", "collision_both", "collision_fall"]:
		var f := _p08_fixture(100.0 if shape == "collision_alive" else (8.0 if shape.begins_with("collision") else -1.0))
		if shape == "half": f.board.set_height_steps(f.destination, 1)
		if shape == "wall": f.board.set_terrain(f.destination, TerrainType.Type.WALL)
		if shape in ["fall", "collision_fall"]: f.board.set_height_steps(f.destination, -3)
		if shape == "hazard": f.board.set_terrain(f.destination, TerrainType.Type.HAZARD)
		if shape == "bounds":
			f.board.move_unit(f.target, Vector2i(4,2)); f.board.move_unit(f.actor, Vector2i(3,2))
		if shape == "collision_both": f.target.vitals.set_hp(9.0)
		var origin_version: int = f.board.board_version
		var r := _p07_submit(f)
		_check(r.status == &"APPLIED", "P08 S12/S13 normal " + shape, r.reason)
		_check(f.actor.action_resources.get_main_left() == 3, "P08 paid exactly one main " + shape)
		var expected_hp := 93.0
		if shape == "wall": expected_hp = 86.0
		if shape == "fall": expected_hp = 71.0
		if shape.begins_with("collision"): expected_hp = 64.0 if shape == "collision_fall" else (0.0 if shape == "collision_both" else 86.0)
		if shape in ["hazard", "bounds"]: expected_hp = 0.0
		_check(f.target.vitals.get_hp() == expected_hp, "P08 exact HP " + shape, str(f.target.vitals.get_hp()))
		var touches := 1 if shape in ["flat", "half", "fall", "bounds"] else (2 if shape in ["hazard", "collision_dead", "collision_both", "collision_fall"] else 0)
		_check(f.board.board_version == origin_version + touches, "P08 known touches " + shape)
		_p08_cleanup(f)

func _p08_mutate(f: Dictionary, role: String, mode: String) -> void:
	var u: UnitState = f[role]
	match mode:
		"hp": u.vitals._hp += 0.125
		"alive": u.vitals._is_alive = not u.vitals._is_alive
		"balance": u.vitals._balance += 0.125
		"move": u.move_points_left += 0.125
		"main": u.action_resources._main_left += 1
		"bonus": u.action_resources._bonus_left += 1
		"cell": u.cell += Vector2i.UP
		"cache_height": u.height += 1
		"height": f.board.set_height_steps(u.cell, f.board.get_height_steps(u.cell) + 1)
		"same_height": f.board.set_height(u.cell, f.board.get_height(u.cell))
		"stats": u.stats = StatsBag.from_snapshot_dict(u.stats.to_snapshot_dict())
		"vitals_stats": u.vitals._stats = StatsBag.from_snapshot_dict(u.stats.to_snapshot_dict())
		"vitals":
			u.vitals = Vitals.from_dict({"hp": 77.0, "balance": 2.0, "is_alive": true}, u.stats)
			f["watch"] = u.vitals
		"resources":
			u.action_resources = ActionResources.new(u.id, 2, 3)
			f["watch_resources"] = u.action_resources
		"registry":
			var replacement := UnitState.from_snapshot_dict(u.to_snapshot_dict())
			replacement.vitals._hp = 77.0; replacement.vitals._is_alive = true; replacement.vitals._balance = 2.0
			f.board._units[u.id] = replacement
			f["watch"] = replacement.vitals
		"context": f.context._state = ItemSimulationState.new(f.board, f.state._owners, f.state._inventories, f.state._equipment)
		"board": f.state._board = BattleBoard.new(5,5)
		"owner":
			var owner: ItemOwnerState = f.state.get_owner(u.id)
			f.state._owners[f.state._owners.find(owner)] = ItemOwnerState.new(u)
		"owner_unit": f.state.get_owner(u.id)._owner = UnitState.from_snapshot_dict(u.to_snapshot_dict())
		"owner_closed": f.state.get_owner(u.id)._closed = true
		"inventory_closed": f.state.get_inventory(u.id)._closed = true
		"inventory_removed": f.state._inventories.erase(f.state.get_inventory(u.id))
		"inventory_attachment": f.state.get_inventory(u.id)._state = ItemOwnerState.new(u)
		"equipment_closed": f.state.get_equipment(u.id)._closed = true
		"equipment_attachment": f.state.get_equipment(u.id)._state = ItemOwnerState.new(u)
		"inventory_flag": f.state.get_owner(u.id)._inventory_retired = true
		"equipment_flag": f.state.get_owner(u.id)._equipment_registered = false

func _test_p08_refs() -> void:
	for scenario: String in ["hit", "balance_changed", "balance_broken", "wall", "fall", "collision_first", "collision_second", "push_move", "move", "movefall", "death"]:
		for role: String in (["actor", "target", "blocker"] if scenario.begins_with("collision") else (["target"] if scenario in ["move", "movefall"] else ["actor", "target"])):
			for mode: String in ["hp", "alive", "balance", "move", "main", "bonus", "cell", "cache_height", "height", "same_height", "stats", "vitals_stats", "vitals", "resources", "registry", "context", "board", "owner", "owner_unit", "owner_closed", "inventory_closed", "inventory_removed", "inventory_attachment", "equipment_closed", "equipment_attachment", "inventory_flag", "equipment_flag"]:
				var f := _p08_fixture(100.0 if scenario.begins_with("collision") else -1.0)
				if role == "blocker": f.blocker.enable_action_resources(); f.blocker.try_refill_turn_resources()
				if scenario in ["hit", "death"]: f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
				if scenario == "death": f.target.vitals.set_hp(2.0)
				if scenario == "balance_changed": f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 1.0)
				if scenario == "wall": f.board.set_terrain(f.destination, TerrainType.Type.WALL)
				if scenario in ["fall", "movefall"]: f.board.set_height_steps(f.destination, -3)
				var called := [false]
				var count := [0]
				var hp := func(_a: float, _b: float) -> void:
					count[0] += 1
					if count[0] == (2 if scenario in ["wall", "fall", "collision_first"] else 1):
						called[0] = true; _p08_mutate(f, role, mode)
				var simple := func() -> void: called[0] = true; _p08_mutate(f, role, mode)
				var move := func(_u: UnitState, _a: Vector2i, _b: Vector2i) -> void: called[0] = true; _p08_mutate(f, role, mode)
				var vitals: Vitals = f.blocker.vitals if scenario == "collision_second" else f.target.vitals
				if scenario == "balance_changed": vitals.balance_changed.connect(hp)
				elif scenario == "balance_broken": vitals.balance_broken.connect(simple)
				elif scenario == "death": vitals.died.connect(simple)
				elif scenario in ["push_move", "move"]: f.board.unit_position_changed.connect(move)
				else: vitals.hp_changed.connect(hp)
				var r := ActionQueue.new().submit(MoveCommand.new(f.target.id, [f.target.cell, f.destination], 0), f.context) if scenario in ["move", "movefall"] else _p07_submit(f)
				if vitals.hp_changed.is_connected(hp): vitals.hp_changed.disconnect(hp)
				if vitals.balance_changed.is_connected(hp): vitals.balance_changed.disconnect(hp)
				if vitals.balance_broken.is_connected(simple): vitals.balance_broken.disconnect(simple)
				if vitals.died.is_connected(simple): vitals.died.disconnect(simple)
				if f.board.unit_position_changed.is_connected(move): f.board.unit_position_changed.disconnect(move)
				var label := scenario + "/" + role + "/" + mode
				_check(called[0] and r.status == &"FAULTED", "P08 S14f/g pinned " + label, r.reason)
				if f.has("watch"):
					_check(f.watch.get_hp() == 77.0 and f.watch.is_alive() and f.watch.get_balance() == 2.0, "P08 replacement untouched " + label)
				if f.has("watch_resources"):
					_check(f.watch_resources.get_main_left() == 2 and f.watch_resources.get_bonus_left() == 3, "P08 replacement resources untouched " + label)
				var events := r.get_events()
				var seq := 1
				var ordered := true
				for event: Dictionary in events:
					ordered = ordered and event.event_seq == seq and event.root_id == 1 and event.parent_event_seq == 0
					seq += 1
				_check(ordered and not events.is_empty(), "P08 S15 ordered ids " + label)
				_p08_cleanup(f)

func _p08_set_lifecycle(f: Dictionary, inventory_mode: int, equipment_mode: int) -> void:
	for owner: ItemOwnerState in f.state._owners:
		var inventory: InventoryState = f.state.get_inventory(owner._owner.id)
		var equipment: EquipmentState = f.state.get_equipment(owner._owner.id)
		if inventory_mode != 1:
			f.state._inventories.erase(inventory)
			owner._inventory_registered = false; owner._inventory_retired = inventory_mode == 2
		if equipment_mode != 1:
			f.state._equipment.erase(equipment)
			owner._equipment_registered = false; owner._equipment_retired = equipment_mode == 2

func _test_p08_lifecycle_replay() -> void:
	for inventory_mode: int in [0,1,2]:
		for equipment_mode: int in [0,1,2]:
			for faulted: bool in [false,true]:
				var f := _p08_fixture()
				_p08_set_lifecycle(f, inventory_mode, equipment_mode)
				var catalogue: Dictionary = {}
				if inventory_mode == 1:
					var definition := _p07_heal(f, f.target)
					catalogue[definition.id] = definition
				f.board.set_height_steps(f.destination, -3)
				var source_capture := ItemSimulationSnapshot.capture(f.state, [])
				_check(source_capture.code == ItemSnapshotResult.Code.OK, "P08 S16 lifecycle snapshot")
				if source_capture.snapshot == null: continue
				var original := source_capture.snapshot.canonical_bytes()
				var source_ids := UnitId.get_counter()
				var outcomes: Array = []
				for repeat: int in range(3):
					var restored: ItemSimulationState = source_capture.snapshot.instantiate(catalogue).state
					var actor := restored._board.get_unit_by_id(f.actor.id)
					var target := restored._board.get_unit_by_id(f.target.id)
					var context := ActionContext.new(restored, P04TestRng.new(), ActionEventSink.new(), [], MoveRules.new([actor.id],1,&"spatial_move_v1"), f.rules)
					var queue := ActionQueue.new()
					var all_events: Array = []
					var all_steps: Array = []
					for raw_path: Array in [[actor.cell,actor.cell + Vector2i.UP],[actor.cell + Vector2i.UP,actor.cell]]:
						var path: Array[Vector2i] = []
						path.assign(raw_path)
						var move := queue.submit(MoveCommand.new(actor.id,path,context.get_revision()),context)
						_check(move.status == &"APPLIED", "P08 S16 restored Move lifecycle")
						all_events.append_array(move.get_events()); all_steps.append_array(move.get_steps())
					var hook := func(_a: float, _b: float) -> void: restored._board.set_height(Vector2i.ZERO,0)
					if faulted: target.vitals.hp_changed.connect(hook,CONNECT_ONE_SHOT)
					var attack := queue.submit(AttackCommand.new(actor.id,target.id,actor.cell,target.cell,f.definition.id,context.get_revision()),context)
					_check(attack.status == (&"FAULTED" if faulted else &"APPLIED"), "P08 S16 restored Attack lifecycle", attack.reason)
					if inventory_mode == 1:
						_check(_p07_events(attack,&"healed").size() == (0 if faulted else 2) and target.vitals.get_hp() == (93.0 if faulted else 75.0), "P08 S16 influencing item executes after mandatory cascade only")
					all_events.append_array(attack.get_events()); all_steps.append_array(attack.get_steps())
					var final_capture := ItemSimulationSnapshot.capture(restored,[])
					_check(final_capture.code == ItemSnapshotResult.Code.OK, "P08 S16 resulting state snapshot")
					outcomes.append([final_capture.snapshot.canonical_bytes(),all_events,all_steps,context._next_command_seq,context._next_event_seq,context._next_root_id,context.get_revision(),context.get_rng().to_dict()])
					restored._board.resize(0,0)
				_check(outcomes[0] == outcomes[1] and outcomes[1] == outcomes[2], "P08 S16 exact replay lifecycle %d/%d fault%s" % [inventory_mode,equipment_mode,str(faulted)])
				_check(ItemSimulationSnapshot.capture(f.state,[]).snapshot.canonical_bytes() == original and UnitId.get_counter() == source_ids and f.context.get_revision() == 0 and not f.context.is_faulted(), "P08 S16 source untouched")
				_p08_cleanup(f)
	for drop: int in [1,2,3,4,5]:
		var f := _p08_fixture()
		var mover: UnitState = f.target
		f.board.set_height_steps(Vector2i(3,2), -drop)
		var before: float = mover.move_points_left
		var r := ActionQueue.new().submit(MoveCommand.new(mover.id, [Vector2i(2,2),Vector2i(3,2)], 0), f.context)
		_check(r.status == &"APPLIED" and mover.vitals.get_hp() == (100.0 if drop <= 2 else (78.0 if drop == 3 else 53.0)), "P08 S07 Move fall " + str(drop), r.reason)
		_check(mover.move_points_left == before - 1.0, "P08 Move prepaid " + str(drop))
		_p08_cleanup(f)
	_test_p08_callbacks()

func _test_p08_callbacks() -> void:
	for scenario: String in ["hit0", "immunity", "lethal_hit", "balance", "break_changed", "break_broken", "wall", "pushfall", "collision_first", "collision_second", "collision_first_dead", "collision_second_dead", "pushmove", "pushhazard", "pushbounds", "move", "movefall", "movehazard"]:
		var f := _p08_fixture(8.0 if scenario == "collision_second_dead" else (100.0 if scenario.begins_with("collision") else -1.0))
		if scenario == "hit0": f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
		if scenario == "immunity": f.target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX, 0.0)
		if scenario == "lethal_hit": f.target.vitals.set_hp(2.0)
		if scenario == "balance": f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 1.0)
		if scenario == "break_changed": f.target.vitals.set_balance(1.0)
		if scenario == "wall": f.board.set_terrain(f.destination, TerrainType.Type.WALL)
		if scenario == "pushfall": f.board.set_height_steps(f.destination, -3)
		if scenario == "pushhazard": f.board.set_terrain(f.destination, TerrainType.Type.HAZARD)
		if scenario == "pushbounds":
			f.board.move_unit(f.target, Vector2i(4,2)); f.board.move_unit(f.actor, Vector2i(3,2))
		if scenario == "collision_first_dead": f.target.vitals.set_hp(9.0)
		var moving: bool = scenario.begins_with("move")
		var mover: UnitState = f.target if moving else f.actor
		if scenario == "movefall": f.board.set_height_steps(f.destination, -3)
		if scenario == "movehazard": f.board.set_terrain(f.destination, TerrainType.Type.HAZARD)
		var fired := [false]
		var hp_count := [0]
		var callback := func(_old: float, _new: float) -> void:
			hp_count[0] += 1
			var threshold := 2 if scenario in ["wall", "pushfall", "collision_first", "collision_first_dead", "pushhazard", "pushbounds"] else 1
			if hp_count[0] == threshold and not fired[0]:
				fired[0] = true; f.board.set_height(Vector2i.ZERO, f.board.get_height(Vector2i.ZERO))
		var broken_callback := func() -> void:
			fired[0] = true; f.board.set_height(Vector2i.ZERO, f.board.get_height(Vector2i.ZERO))
		var moved_callback := func(_u: UnitState, _from: Vector2i, _to: Vector2i) -> void:
			fired[0] = true; f.board.set_height(Vector2i.ZERO, f.board.get_height(Vector2i.ZERO))
		var vitals: Vitals = f.blocker.vitals if scenario in ["collision_second", "collision_second_dead"] else f.target.vitals
		if scenario in ["balance", "break_changed"]: vitals.balance_changed.connect(callback)
		elif scenario == "break_broken": vitals.balance_broken.connect(broken_callback)
		elif scenario in ["pushmove", "move"]: f.board.unit_position_changed.connect(moved_callback)
		else: vitals.hp_changed.connect(callback)
		var r := ActionQueue.new().submit(MoveCommand.new(mover.id, [mover.cell, f.destination], 0), f.context) if moving else _p07_submit(f)
		if vitals.hp_changed.is_connected(callback): vitals.hp_changed.disconnect(callback)
		if vitals.balance_changed.is_connected(callback): vitals.balance_changed.disconnect(callback)
		if vitals.balance_broken.is_connected(broken_callback): vitals.balance_broken.disconnect(broken_callback)
		if f.board.unit_position_changed.is_connected(moved_callback): f.board.unit_position_changed.disconnect(moved_callback)
		_check(fired[0] and r.status == &"FAULTED", "P08 S14 terminal callback " + scenario, r.reason)
		var expected_reason: StringName = &"push/invalid_binding"
		if scenario in ["hit0", "immunity", "lethal_hit"]: expected_reason = &"attack/invalid_hit"
		if scenario in ["balance", "break_changed", "break_broken"]: expected_reason = &"balance/invalid_binding"
		if scenario == "move": expected_reason = &"move/invalid_runtime"
		if scenario in ["movefall", "movehazard"]: expected_reason = &"move/fall_binding"
		_check(r.reason == expected_reason, "P08 S14 exact reason " + scenario, r.reason)
		var kinds: Array = [&"attacked", &"damaged"]
		if scenario in ["balance", "break_changed"]: kinds.append(&"balance_changed")
		elif scenario == "break_broken": kinds.append(&"balance_broken")
		elif scenario == "wall": kinds.append_array([&"balance_broken", &"push_blocked", &"damaged"])
		elif scenario in ["pushfall", "pushhazard"]: kinds.append_array([&"balance_broken", &"moved", &"damaged"])
		elif scenario == "pushbounds": kinds.append_array([&"balance_broken", &"fell", &"damaged"])
		elif scenario.begins_with("collision"):
			kinds.append_array([&"balance_broken", &"collision", &"damaged"])
			if scenario in ["collision_second", "collision_second_dead"]: kinds.append(&"damaged")
		elif scenario == "pushmove": kinds.append_array([&"balance_broken", &"moved"])
		elif moving: kinds = [&"moved"] if scenario == "move" else [&"moved", &"damaged"]
		_check(_p07_kinds(r) == kinds, "P08 S14 ordered prefix " + scenario, str(_p07_kinds(r)))
		_check(f.actor.action_resources.get_main_left() == (4 if moving else 3), "P08 S14 paid main retained " + scenario)
		if scenario in ["lethal_hit", "collision_first_dead", "collision_second_dead", "movehazard", "pushhazard", "pushbounds"]:
			_check(vitals.get_hp() == 0.0 and vitals.is_alive() and not _p07_kinds(r).has(&"died"), "P08 S14 HP written before death checkpoint " + scenario)
		_p08_cleanup(f)

func _test_p08_receipts_and_seals() -> void:
	for mode: String in ["heal", "set_hp", "nested", "revive"]:
		var f := _p08_fixture()
		f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER,0.0)
		if mode != "nested": f.target.vitals.set_hp(2.0)
		var target: UnitState = f.target
		var before := target.vitals.get_hp()
		var callback := func(_a: float, _b: float) -> void:
			if mode == "heal": target.vitals.heal(5.0)
			elif mode == "set_hp": target.vitals.set_hp(5.0)
			else: target.vitals.apply_damage(1.0)
		var revive := func() -> void: target.vitals.revive()
		if mode == "revive": target.vitals.died.connect(revive,CONNECT_ONE_SHOT)
		else: target.vitals.hp_changed.connect(callback,CONNECT_ONE_SHOT)
		var r := _p07_submit(f)
		var events := r.get_events()
		var expected: Array[Dictionary] = [{"kind": &"attacked", "actor_unit_id": f.actor.id,"target_unit_id":target.id,"attack_definition_id":f.definition.id,"actor_cell":f.actor.cell,"target_cell":target.cell,"main_cost":1,"main_before":4,"main_after":3,"event_seq":1,"root_id":1,"command_seq":1,"parent_event_seq":0}]
		var hp_after := maxf(0.0,before - 7.0)
		var source := {"kind":&"attack","source_instance_id":0,"origin_cell":f.actor.cell,"instigator_unit_id":f.actor.id,"credit_unit_id":f.actor.id}
		expected.append({"kind":&"damaged","actor_unit_id":f.actor.id,"target_unit_id":target.id,"source":source,"hp_before":before,"hp_after":hp_after,"amount":before-hp_after,"alive_before":true,"alive_after":mode != "revive","event_seq":2,"root_id":1,"command_seq":2,"parent_event_seq":0})
		if mode == "revive":
			var died := expected[1].duplicate(true); died.kind = &"died"; died.amount = 0.0; died.event_seq = 3
			expected.append(died)
		_check(r.status == &"FAULTED" and r.reason == &"attack/invalid_hit" and events == expected, "P08 S14i full receipt " + mode, str(events))
		_check(target.vitals.get_hp() == (100.0 if mode == "revive" else (92.0 if mode == "nested" else 5.0)) and target.is_alive(), "P08 S14i external write retained " + mode)
		_p08_cleanup(f)
	for before_listener: bool in [false,true]:
		for different_cell: bool in [false,true]:
			for replacement_alive: bool in [false,true]:
				var f := _p08_fixture()
				f.actor.stats.set_base_value(StatTypes.StatType.IMPACT_POWER,0.0); f.target.vitals.set_hp(2.0)
				var target: UnitState = f.target
				var replacement := UnitState.from_snapshot_dict(target.to_snapshot_dict())
				replacement.vitals._hp = 77.0; replacement.vitals._is_alive = replacement_alive
				if different_cell: replacement.cell = Vector2i(4,4)
				var old_vitals := target.vitals
				var hook := func() -> void:
					f.board.remove_unit(target); f.board.add_unit(replacement)
				if before_listener: f.board._disconnect_death_callback(target.id)
				old_vitals.died.connect(hook,CONNECT_ONE_SHOT)
				if before_listener: f.board._register_death_callback(target)
				var version: int = f.board.board_version
				var r := _p07_submit(f)
				_check(r.status == &"FAULTED" and _p07_kinds(r) == [&"attacked",&"damaged",&"died"], "P08 S14h own death prefix")
				_check(f.board.get_unit_by_id(target.id) == replacement and replacement.vitals.get_hp() == 77.0 and replacement.is_alive() == replacement_alive and f.board._occupancy.get(replacement.cell,0) == (replacement.id if replacement_alive else 0), "P08 S14h replacement identity occupancy")
				_check(f.board.board_version == version + (2 if before_listener else 3), "P08 S14h no cleanup credit for replacement")
				_p08_cleanup(f)
	for stage: StringName in [&"attack",&"attack_hit",&"balance",&"push"]:
		for field: String in ["board_origin_version","expected_board_version","actor_height_steps","target_height_steps","spatial","multiplier","impact","direction","ref","guard_hp","guard_main","guard_bonus","guard_move"]:
			var f := _p08_fixture()
			f.board.set_terrain(f.destination,TerrainType.Type.WALL)
			var hook := func(_c: ActionContext, result: CommandStepResult) -> void:
				if result.mandatory.is_empty(): return
				var child: Command = result.mandatory[0]
				var binding: BalancePushRules.Binding = child.get("_p07_binding") if child is AttackHitCommand else child.get("_binding")
				if field == "ref": binding.actor_vitals = Vitals.from_dict(binding.actor_vitals.to_dict(),binding.actor_stats)
				elif field.begins_with("guard_"):
					binding.spatial_guard.values["participants"][binding.values["actor_id"]][field.trim_prefix("guard_")] += 1
				elif field == "spatial": binding.values[field] = false
				elif field == "direction": binding.values[field] = Vector2i.LEFT
				else: binding.values[field] += 1
			var r := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(f),stage,hook),f.context)
			_check(r.status == &"FAULTED" and f.actor.action_resources.get_main_left() == 3 and f.target.vitals.get_hp() == (100.0 if stage == &"attack" else 93.0), "P08 S14j sealed phase " + str(stage) + "/" + field,r.reason)
			_p08_cleanup(f)

func _test_p08_terminal_matrix() -> void:
	var cases: Array[String] = ["immunity:hp", "hit_lethal:hp", "hit_lethal:died", "hit_lethal:board", "wall_lethal:hp", "wall_lethal:died", "wall_lethal:board", "height:hp", "height_lethal:hp", "height_lethal:died", "fall_lethal:hp", "fall_lethal:died", "fall_lethal:board_death", "pair_first:hp", "pair_first:died", "pair_first:board", "pair_second:hp", "pair_second:died", "pair_second:board", "pair_both:hp", "pair_both:died", "pair_both:board", "flat:board", "fall:position", "fall:board", "hazard:position", "hazard:board", "hazard:hp", "hazard:died", "hazard:board_death", "void:hp", "void:died", "bounds:hp", "bounds:died", "bounds:board", "move:board", "movefall_lethal:hp", "movefall_lethal:died", "movefall_lethal:board_death", "movehazard:position", "movehazard:board", "movehazard:hp", "movehazard:died", "movehazard:board_death"]
	for entry: String in cases:
		var pieces := entry.split(":")
		var shape := pieces[0]; var point := pieces[1]
		var moving := shape.begins_with("move")
		var pair := shape.begins_with("pair")
		var roles: Array = ["target"] if moving else (["actor","target","blocker"] if pair else ["actor","target"])
		for role: String in roles:
			for mode: String in ["hp","alive","balance","move","main","bonus","cell","cache_height","height","same_height","stats","vitals_stats","vitals","resources","registry","context","board","owner","owner_unit","owner_closed","inventory_closed","inventory_removed","inventory_attachment","equipment_closed","equipment_attachment","inventory_flag","equipment_flag"]:
				var f := _p08_fixture(8.0 if shape in ["pair_second","pair_both"] else (100.0 if pair else -1.0))
				if pair: f.blocker.enable_action_resources(); f.blocker.try_refill_turn_resources()
				if shape == "immunity": f.target.stats.set_base_value(StatTypes.StatType.BALANCE_MAX,0.0)
				if shape == "hit_lethal": f.target.vitals.set_hp(2.0)
				if shape in ["wall_lethal","height_lethal","pair_first","pair_both"]: f.target.vitals.set_hp(9.0)
				if shape == "fall_lethal": f.target.vitals.set_hp(14.0)
				if shape == "movefall_lethal": f.target.vitals.set_hp(10.0)
				if shape.begins_with("wall"): f.board.set_terrain(f.destination,TerrainType.Type.WALL)
				if shape.begins_with("height"): f.board.set_height_steps(f.destination,2)
				if shape in ["fall","fall_lethal","movefall_lethal"]: f.board.set_height_steps(f.destination,-3)
				if shape in ["hazard","movehazard"]: f.board.set_terrain(f.destination,TerrainType.Type.HAZARD)
				if shape == "void": f.board.set_terrain(f.destination,TerrainType.Type.VOID)
				if shape == "bounds": f.board.move_unit(f.target,Vector2i(4,2)); f.board.move_unit(f.actor,Vector2i(3,2))
				var snapshot := ItemSimulationSnapshot.capture(f.state,[]).snapshot
				var restored := snapshot.instantiate({}).state
				var normal_context := ActionContext.new(restored,P04TestRng.new(),ActionEventSink.new(),[],f.context.get_move_rules(),f.rules)
				var normal_actor := restored._board.get_unit_by_id(f.actor.id)
				var normal_target := restored._board.get_unit_by_id(f.target.id)
				var normal := ActionQueue.new().submit(MoveCommand.new(normal_target.id,[normal_target.cell,f.destination],0),normal_context) if moving else ActionQueue.new().submit(AttackCommand.new(normal_actor.id,normal_target.id,normal_actor.cell,normal_target.cell,f.definition.id,0),normal_context)
				var called := [false]; var count := [0]
				var threshold := 1
				var second_victim := shape in ["pair_second","pair_both"]
				if point == "hp" and not moving and shape not in ["immunity","hit_lethal"] and not second_victim: threshold = 2
				if point == "board_death" or (shape == "pair_both" and point == "board"): threshold = 2
				var fire := func() -> void:
					count[0] += 1
					if not called[0] and count[0] == threshold:
						called[0] = true; _p08_mutate(f,role,mode)
				var hp := func(_a: float,_b: float) -> void: fire.call()
				var position := func(_u: UnitState,_a: Vector2i,_b: Vector2i) -> void: fire.call()
				var vitals: Vitals = f.blocker.vitals if second_victim else f.target.vitals
				if point == "hp": vitals.hp_changed.connect(hp)
				elif point == "died": vitals.died.connect(fire)
				elif point == "position": f.board.unit_position_changed.connect(position)
				else: f.board.board_changed.connect(fire)
				var r := ActionQueue.new().submit(MoveCommand.new(f.target.id,[f.target.cell,f.destination],0),f.context) if moving else _p07_submit(f)
				if vitals.hp_changed.is_connected(hp): vitals.hp_changed.disconnect(hp)
				if vitals.died.is_connected(fire): vitals.died.disconnect(fire)
				if f.board.unit_position_changed.is_connected(position): f.board.unit_position_changed.disconnect(position)
				if f.board.board_changed.is_connected(fire): f.board.board_changed.disconnect(fire)
				var label := entry + "/" + role + "/" + mode
				_check(called[0] and r.status == &"FAULTED" and normal.status in [&"APPLIED",&"INTERRUPTED"],"P08 S14 expanded checkpoint " + label,r.reason)
				var expected: Array[Dictionary] = []
				var victim: int = f.blocker.id if second_victim else f.target.id
				var death_point := point in ["died","board_death"] or (point == "board" and shape in ["hit_lethal","wall_lethal","pair_first","pair_second","pair_both","bounds"])
				var stop_kind: StringName = &"damaged" if point == "hp" else (&"died" if death_point else &"moved")
				var explicit_death := shape in ["hazard","void","bounds","movehazard"]
				var occurrence := 2 if point == "hp" and threshold == 2 and not explicit_death else 1
				for event: Dictionary in normal.get_events():
					var draft := event.duplicate(true)
					if point == "hp" and explicit_death and draft.kind == &"died" and draft.target_unit_id == victim:
						draft.kind = &"damaged"; draft.amount = draft.hp_before - draft.hp_after
					elif point == "hp" and explicit_death and draft.kind == &"damaged":
						expected.append(draft); continue
					var stop: bool = draft.kind == stop_kind and draft.target_unit_id == victim
					if stop: occurrence -= 1
					if stop and occurrence == 0 and point == "hp": draft.alive_after = true
					expected.append(draft)
					if stop and occurrence == 0: break
				_check(r.get_events() == expected,"P08 S14 exact complete prefix " + label,str(_p07_kinds(r)))
				if f.has("watch"): _check(f.watch.get_hp() == 77.0 and f.watch.is_alive() and f.watch.get_balance() == 2.0,"P08 S14 replacement untouched " + label)
				if f.has("watch_resources"): _check(f.watch_resources.get_main_left() == 2 and f.watch_resources.get_bonus_left() == 3,"P08 S14 resource replacement untouched " + label)
				restored._board.resize(0,0)
				_p08_cleanup(f)
func _test_p08_move_binding_limits() -> void:
	for lethal: bool in [false,true]:
		for field: String in ["valid","mode","source","request","request_seal","board_origin_version","expected_board_version"]:
			var f := _p08_fixture()
			if lethal: f.board.set_terrain(f.destination,TerrainType.Type.HAZARD)
			else: f.board.set_height_steps(f.destination,-3)
			var mover: UnitState = f.target
			var root := MoveCommand.new(mover.id,[mover.cell,f.destination],0)
			var moved := root.execute(f.context)
			_check(moved.status == &"APPLIED" and moved.mandatory.size() == 1, "P08 S15c bound fixture")
			if moved.mandatory.is_empty(): continue
			var child: Command = moved.mandatory[0]
			var binding: MoveFallCommand.Binding = child.get("_spatial_binding") if lethal else child.get("_binding")
			var public_result := ActionQueue.new().submit(child,f.context)
			_check(public_result.status == &"REJECTED" and public_result.reason == (&"move/internal_death" if lethal else &"move/internal_fall") and public_result.root_id == 0, "P08 S15c public root rejected")
			if field == "mode": binding.values.mode = &"fall" if lethal else &"cell_death"
			elif field == "source":
				if lethal: (child as DeathCommand).source.origin_cell = Vector2i.ZERO
				else: binding.source.kind = &"cell"
			elif field == "request": binding.request = DamageRequest.new(mover.id,1.0,&"physical",&"bypass",binding.source) if lethal else null
			elif field == "request_seal": binding.request_seal = DamageRequest.new(mover.id,1.0,&"physical",&"bypass",binding.source) if lethal else null
			elif field != "valid": binding.values[field] += 1
			var copied := child.copy_for_queue()
			var hp := mover.vitals.get_hp()
			var result := copied.execute(f.context)
			_check(result.status == (&"APPLIED" if field == "valid" else &"FAULTED") and (mover.vitals.get_hp() < hp if field == "valid" else mover.vitals.get_hp() == hp), "P08 S15c copy exact forms " + str(lethal) + "/" + field,result.reason)
			_p08_cleanup(f)

func _test_p08_boundaries() -> void:
	var board := BattleBoard.new(2,1)
	var version := board.board_version
	_check(board.set_height_steps(Vector2i.ZERO,-1) and board.board_version == version + 1,"P08 S01 one setter touch")
	_check(board.set_height_steps(Vector2i.ZERO,-1) and board.board_version == version + 2,"P08 S01 same value touch")
	board.set_height(Vector2i.ZERO,-1)
	_check(board.get_height_steps(Vector2i.ZERO) == -2 and not board.has_half_heights() and board.to_snapshot_dict().schema_version == 1,"P08 S01 last bit resets schema1")
	board.board_version = ActionContext.MAX_ID
	var before := board.to_snapshot_dict()
	_check(not board.set_height_steps(Vector2i.ZERO,1) and board.to_snapshot_dict() == before,"P08 S01 MAX version no mutation")
	board.board_version = 0; board.set_height_steps(Vector2i.ZERO,1); board.resize(2,1)
	_check(not board.has_half_heights() and board.get_height_steps(Vector2i.ZERO) == 0,"P08 S01 resize bits zero")
	var f := _p08_fixture()
	f.board.set_height_steps(Vector2i.ZERO,1)
	f.actor.height = -9223372036854775807 - 1
	f.target.height = 9223372036854775807
	var captured := ItemSimulationSnapshot.capture(f.state,[]).snapshot
	var dto := captured.to_dict()
	var a := captured.instantiate({}).state; var b := captured.instantiate({}).state
	var original := captured.canonical_bytes()
	a._board.set_height_steps(Vector2i.ZERO,3)
	_check(b._board.get_height_steps(Vector2i.ZERO) == 1 and f.board.get_height_steps(Vector2i.ZERO) == 1 and captured.canonical_bytes() == original,"P08 S02 isolated halves arrays")
	_check(b._board.get_unit_by_id(f.actor.id).height == f.actor.height and b._board.get_unit_by_id(f.target.id).height == f.target.height,"P08 S02 independent int64 unit cache")
	for mutation: String in ["float","bool","negative","two","short","long","zero","missing","extra","version_bool","unknown3"]:
		var bad := dto.duplicate(true)
		var raw: Dictionary = bad.board_snapshot.board
		if mutation == "float": raw.height_half_steps[0] = 1.0
		elif mutation == "bool": raw.height_half_steps[0] = true
		elif mutation == "negative": raw.height_half_steps[0] = -1
		elif mutation == "two": raw.height_half_steps[0] = 2
		elif mutation == "short": raw.height_half_steps.pop_back()
		elif mutation == "long": raw.height_half_steps.append(0)
		elif mutation == "zero": raw.height_half_steps.fill(0)
		elif mutation == "missing": raw.erase("height_half_steps")
		elif mutation == "extra": raw["extra"] = 1
		elif mutation == "version_bool": raw.schema_version = true
		else: raw.schema_version = 3
		var item_result := ItemSimulationSnapshot.from_dict(bad)
		var board_result := SimulationSnapshot.from_dict(bad.board_snapshot)
		_check(item_result.code == (ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED if mutation == "unknown3" else ItemSnapshotResult.Code.SNAPSHOT_INVALID) and board_result.code == (BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED if mutation == "unknown3" else BoardSnapshotResult.Code.SNAPSHOT_INVALID),"P08 S03 exact shape classification " + mutation,item_result.reason + "/" + board_result.reason)
	a._board.resize(0,0); b._board.resize(0,0); _p08_cleanup(f)
	for direction: Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
		for distance: int in [2,3]:
			var ranged := _p08_fixture()
			ranged.board.remove_unit(ranged.actor); ranged.board.remove_unit(ranged.target)
			ranged.actor.cell = Vector2i(0 if direction.x > 0 else (4 if direction.x < 0 else 2),0 if direction.y > 0 else (4 if direction.y < 0 else 2))
			ranged.target.cell = ranged.actor.cell + direction * distance
			ranged.board.add_unit(ranged.actor); ranged.board.add_unit(ranged.target)
			ranged.actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE,float(distance))
			var target_cell: Vector2i = ranged.target.cell
			var result := _p07_submit(ranged)
			_check(result.status == &"APPLIED" and ranged.target.cell == target_cell + direction and ranged.target.vitals.get_hp() == 93.0,"P08 S09/S12 ranged axis push one",result.reason)
			_p08_cleanup(ranged)
	for invalid: float in [0.0,1.5,NAN,INF,4097.0]:
		var invalid_f := _p08_fixture()
		var ids := UnitId.get_counter()
		invalid_f.actor.stats.set_base_value(StatTypes.StatType.ATTACK_RANGE,invalid)
		var r := _p07_submit(invalid_f)
		_check(r.status == &"REJECTED" and r.root_id == 0 and r.get_events().is_empty() and invalid_f.actor.action_resources.get_main_left() == 4 and UnitId.get_counter() == ids,"P08 S09 invalid range clean reject")
		_p08_cleanup(invalid_f)
	var route := _p08_fixture()
	var actor: UnitState = route.actor
	var start := actor.cell
	var half := start + Vector2i.UP
	var full := half + Vector2i.UP
	route.board.set_height_steps(half,1); route.board.set_height_steps(full,2)
	var move := ActionQueue.new().submit(MoveCommand.new(actor.id,[start,half,full],0),route.context)
	_check(move.status == &"APPLIED" and actor.move_points_left == 1.0 and actor.cell == full,"P08 S05/S06 two half rises cost two",move.reason)
	_p08_cleanup(route)
	for depth: int in range(1,7):
		var q := _p08_fixture(8.0); q.board.set_height_steps(q.destination,-3)
		var r := _p07_submit(q,ActionQueue.new(64,512,depth))
		_check(r.status == (&"APPLIED" if depth == 6 else &"FAULTED") and r.get_steps().size() == depth + 1 and (r.reason == &"depth_limit" if depth < 6 else r.reason == &""),"P08 S15b depth exact " + str(depth),r.reason)
		_p08_cleanup(q)
	for offset: int in [4,3]:
		var q := _p08_fixture(8.0); q.target.vitals.set_hp(9.0)
		var hook := func(c: ActionContext,_result: CommandStepResult) -> void: c._next_event_seq = ActionContext.MAX_ID-offset-1
		var r := ActionQueue.new().submit(P07TreeHook.new(_p06_attack(q),&"push",hook),q.context)
		_check(r.status == (&"APPLIED" if offset == 4 else &"FAULTED") and q.target.vitals.get_hp() == (0.0 if offset == 4 else 2.0) and q.blocker.vitals.get_hp() == (0.0 if offset == 4 else 8.0),"P08 S15b collision cap4 seqreserve",r.reason)
		_p08_cleanup(q)
	var both := _p08_fixture(8.0); both.target.vitals.set_hp(9.0)
	var limited := _p07_submit(both,ActionQueue.new(64,5))
	_check(limited.status == &"FAULTED" and limited.reason == &"event_limit" and limited.get_events().size() == 8 and _p07_events(limited,&"died").size() == 2 and not both.target.is_alive() and not both.blocker.is_alive(),"P08 S15b cap4 atomic prefix beyond limit",limited.reason)
	_p08_cleanup(both)
func _test_p08_lifecycle_mutations() -> void:
	for inventory_mode: int in [0,1,2]:
		for equipment_mode: int in [0,1,2]:
			for mode: String in ["inventory_add","inventory_remove","inventory_close","inventory_replace","inventory_flags","equipment_add","equipment_remove","equipment_close","equipment_replace","equipment_flags","owner_replace","owner_close"]:
				var selected_mode := inventory_mode if mode.begins_with("inventory") else equipment_mode
				if selected_mode != 1 and (mode.ends_with("remove") or mode.ends_with("close") or mode.ends_with("replace")) and not mode.begins_with("owner"): continue
				var source := _p08_fixture()
				_p08_set_lifecycle(source,inventory_mode,equipment_mode)
				var snapshot := ItemSimulationSnapshot.capture(source.state,[]).snapshot
				var outcomes: Array = []
				for repeat: int in [0,1]:
					var state := snapshot.instantiate({}).state
					var board := state._board
					var actor := board.get_unit_by_id(source.actor.id)
					var target := board.get_unit_by_id(source.target.id)
					var owner := state.get_owner(target.id)
					var context := ActionContext.new(state,P04TestRng.new(),ActionEventSink.new(),[],null,source.rules)
					var hook := func(_a: float,_b: float) -> void:
						if mode == "owner_replace":
							state._owners[state._owners.find(owner)] = ItemOwnerState.new(target)
						elif mode == "owner_close": owner._closed = true
						else:
							var inventory := mode.begins_with("inventory")
							var facades: Array = state._inventories if inventory else state._equipment
							var facade: RefCounted = state.get_inventory(target.id) if inventory else state.get_equipment(target.id)
							if mode.ends_with("remove"): facades.erase(facade)
							elif mode.ends_with("close"): facade.set("_closed",true)
							elif mode.ends_with("flags"):
								if inventory: owner._inventory_retired = not owner._inventory_retired
								else: owner._equipment_retired = not owner._equipment_retired
							else:
								if mode.ends_with("replace"): facades.erase(facade)
								var replacement_owner := ItemOwnerState.new(target)
								var replacement: RefCounted = InventoryState.new(replacement_owner) if inventory else EquipmentState.new(replacement_owner)
								facades.append(replacement)
					target.vitals.hp_changed.connect(hook,CONNECT_ONE_SHOT)
					var receipt := ActionQueue.new().submit(AttackCommand.new(actor.id,target.id,actor.cell,target.cell,source.definition.id,0),context)
					_check(receipt.status == &"FAULTED" and receipt.reason == &"attack/invalid_hit" and _p07_kinds(receipt) == [&"attacked",&"damaged"] and target.vitals.get_hp() == 93.0 and actor.action_resources.get_main_left() == 3 and target.cell == source.target.cell, "P08 S14f restored facade mutation %d/%d/%s" % [inventory_mode,equipment_mode,mode],receipt.reason)
					outcomes.append([receipt.get_events(),receipt.get_steps(),context._next_command_seq,context._next_event_seq,context.get_revision(),context.get_rng().to_dict(),board.board_version])
					board.resize(0,0)
				_check(outcomes[0] == outcomes[1] and ItemSimulationSnapshot.capture(source.state,[]).snapshot.canonical_bytes() == snapshot.canonical_bytes(), "P08 S16 lifecycle fault replay and source isolation")
				_p08_cleanup(source)

func _test_p08_paths() -> void:
	var board := BattleBoard.new(4,4)
	var finder := GridPathfinder.new()
	finder.configure(board.get_bounds(),board.make_spatial_data_provider(),1,&"spatial_move_v1")
	for invalid: float in [-1.0,NAN,INF]:
		_check(finder.get_reachable_cells(Vector2i.ZERO,invalid).is_empty(), "P08 S05 invalid spatial reachable budget")
	var expected: Array[Vector2i] = [Vector2i.ZERO,Vector2i(1,0),Vector2i(1,1)]
	for repeat: int in range(4): _check(finder.find_path(Vector2i.ZERO,Vector2i(1,1)) == expected, "P08 S06 deterministic equal paths")
	for length: int in [2,3,33,34]:
		var f := _p08_fixture()
		var actor: UnitState = f.actor
		actor.move_points_left = 100.0
		var path: Array[Vector2i] = []
		for i: int in range(length): path.append(actor.cell if i%2 == 0 else actor.cell+Vector2i.UP)
		var before := ItemSimulationSnapshot.capture(f.state,[]).snapshot.canonical_bytes()
		var command := MoveCommand.new(actor.id,path,0)
		command.validate(f.context)
		_check(ItemSimulationSnapshot.capture(f.state,[]).snapshot.canonical_bytes() == before, "P08 S06 root inspect pure")
		var receipt := ActionQueue.new().submit(command,f.context)
		_check(receipt.status == (&"REJECTED" if length == 34 else &"APPLIED") and actor.move_points_left == (100.0 if length == 34 else 101.0-length), "P08 S06 path size/revisit exact debit")
		_p08_cleanup(f)
	# Отдельная admission continuation обязана видеть законное изменение после ребра.
	var f := _p08_fixture()
	var actor: UnitState = f.actor
	var path: Array[Vector2i] = [actor.cell,actor.cell+Vector2i.UP,actor.cell+Vector2i.UP*2]
	var root := MoveCommand.new(actor.id,path,0)
	var first := root.execute(f.context)
	var paid: float = actor.move_points_left
	f.board.set_height_steps(path[2],3)
	var second := first.continuation.execute(f.context)
	_check(second.status == &"INTERRUPTED" and second.reason == &"move/path_height" and actor.move_points_left == paid and actor.cell == path[1], "P08 S06 continuation current geometry without second debit")
	_p08_cleanup(f)

func _test_p08_command_reserves() -> void:
	for limit: int in range(1,8):
		var f := _p08_fixture(8.0); f.board.set_height_steps(f.destination,-3)
		var r := _p07_submit(f,ActionQueue.new(limit))
		_check(r.status == (&"APPLIED" if limit == 7 else &"FAULTED") and r.get_steps().size() == limit and f.actor.action_resources.get_main_left() == 3, "P08 S15b command boundary " + str(limit),r.reason)
		_p08_cleanup(f)
	for touches: int in [0,1,2,3]:
		for missing: bool in [false,true]:
			var f := _p08_fixture(8.0 if touches == 3 else -1.0)
			if touches == 0: f.board.set_terrain(f.destination,TerrainType.Type.WALL)
			if touches == 2: f.board.set_height_steps(f.destination,-8)
			if touches == 3: f.board.set_terrain(f.destination,TerrainType.Type.HAZARD)
			f.board.board_version = ActionContext.MAX_ID - touches + (1 if missing and touches > 0 else 0)
			var r := _p07_submit(f)
			_check(r.status == (&"REJECTED" if missing and touches > 0 else &"APPLIED"), "P08 S15a exact reserve %d/%s" % [touches,str(missing)],r.reason)
			_p08_cleanup(f)

func _test_p08_final_closure() -> void:
	for scenario: String in ["both_dead","blocker_dead_fall","fall_dead","hazard","fall_dead_fault","hazard_fault","wall_fault","fall_fault","flat_fault"]:
		var faulted := scenario.ends_with("_fault")
		var shape := scenario.trim_suffix("_fault")
		var source := _p08_fixture(8.0 if shape in ["both_dead","blocker_dead_fall"] else -1.0)
		if shape == "both_dead": source.target.vitals.set_hp(9.0)
		if shape == "fall_dead": source.target.vitals.set_hp(20.0)
		if shape in ["blocker_dead_fall","fall_dead","fall"]: source.board.set_height_steps(source.destination,-3)
		if shape == "hazard": source.board.set_terrain(source.destination,TerrainType.Type.HAZARD)
		if shape == "wall": source.board.set_terrain(source.destination,TerrainType.Type.WALL)
		var heal := _p07_heal(source,source.target)
		var snapshot := ItemSimulationSnapshot.capture(source.state,[]).snapshot
		var source_bytes := snapshot.canonical_bytes()
		var ids := UnitId.get_counter()
		var outcomes: Array = []
		for repeat: int in [0,1]:
			var state := snapshot.instantiate({heal.id:heal}).state
			var actor := state._board.get_unit_by_id(source.actor.id)
			var target := state._board.get_unit_by_id(source.target.id)
			var context := ActionContext.new(state,P04TestRng.new(),ActionEventSink.new(),[],MoveRules.new([actor.id],1,&"spatial_move_v1"),source.rules)
			var queue := ActionQueue.new()
			var events: Array = []; var steps: Array = []
			for delta: Vector2i in [Vector2i.UP,Vector2i.DOWN]:
				var receipt := queue.submit(MoveCommand.new(actor.id,[actor.cell,actor.cell+delta],context.get_revision()),context)
				_check(receipt.status == &"APPLIED","P08 S16 cleanup replay Move")
				events.append_array(receipt.get_events()); steps.append_array(receipt.get_steps())
			var calls: Array[int] = [0]
			var hp_hook := Callable()
			if faulted:
				if shape in ["fall_dead","hazard"]:
					target.vitals.died.connect(func() -> void: state._board.set_height(Vector2i(4,4),0),CONNECT_ONE_SHOT)
				elif shape == "flat":
					state._board.unit_position_changed.connect(func(_u: UnitState,_from: Vector2i,_to: Vector2i) -> void: state._board.set_height(Vector2i(4,4),0),CONNECT_ONE_SHOT)
				else:
					hp_hook = func(_a: float,_b: float) -> void:
						calls[0] += 1
						if calls[0] == 2: state._board.set_height(Vector2i(4,4),0)
					target.vitals.hp_changed.connect(hp_hook)
			var attack := queue.submit(AttackCommand.new(actor.id,target.id,actor.cell,target.cell,source.definition.id,context.get_revision()),context)
			if hp_hook.is_valid(): target.vitals.hp_changed.disconnect(hp_hook)
			var expected_deaths := 0 if shape in ["wall","fall","flat"] else (2 if shape == "both_dead" else 1)
			_check(attack.status == (&"FAULTED" if faulted else &"APPLIED") and _p07_events(attack,&"died").size() == expected_deaths,"P08 S16 cleanup/terminal replay "+scenario,attack.reason)
			if faulted: _check(_p07_events(attack,&"healed").is_empty() and actor.action_resources.get_main_left() == 3,"P08 S16 terminal fault preserves payment without reactions")
			events.append_array(attack.get_events()); steps.append_array(attack.get_steps())
			var result := ItemSimulationSnapshot.capture(state,[])
			_check(result.code == ItemSnapshotResult.Code.OK,"P08 S16 canonical corpses")
			outcomes.append([result.snapshot.canonical_bytes(),events,steps,context._next_root_id,context._next_command_seq,context._next_event_seq,context.get_revision(),context.get_rng().to_dict()])
			state._board.resize(0,0)
		_check(outcomes[0] == outcomes[1] and ItemSimulationSnapshot.capture(source.state,[]).snapshot.canonical_bytes() == source_bytes and UnitId.get_counter() == ids and source.context.get_revision() == 0,"P08 S16 exact cleanup replay/source items isolation "+scenario)
		_p08_cleanup(source)
	for direction: Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
		for rise: int in [-5,-4,-3,-2,0,1,2,3]:
			for hazard: bool in [false,true]:
				var f := _p08_fixture()
				f.board.move_unit(f.actor,Vector2i(0,0))
				var mover: UnitState = f.target
				var from := mover.cell; var to := from+direction
				f.board.set_height_steps(to,rise)
				if hazard: f.board.set_terrain(to,TerrainType.Type.HAZARD)
				var cost := (3.0 if hazard else 1.0)+(1.0 if rise == 2 else 0.0)
				mover.move_points_left = cost
				var path: Array[Vector2i] = [from,to]
				var inspected := MovePathCheck.inspect(f.board,mover,path,1,cost,&"spatial_move_v1")
				var finder := GridPathfinder.new()
				finder.configure(f.board.get_bounds(),f.board.make_spatial_data_provider(mover),1,&"spatial_move_v1")
				var reachable := finder.get_reachable_cells(from,cost)
				_check((inspected.get_reason() == &"move/height_step" and not reachable.has(to) and finder.find_path(from,to).is_empty()) if rise == 3 else (inspected.get_reason() == &"" and inspected.get_costs() == [cost] and reachable.get(to) == cost and finder.find_path(from,to) == path),"P08 S05 axes path/reachable/edge exact cost")
				var receipt := ActionQueue.new().submit(MoveCommand.new(mover.id,path,0),f.context)
				_check((receipt.status == &"REJECTED" and mover.move_points_left == cost and mover.cell == from) if rise == 3 else (receipt.status == (&"INTERRUPTED" if hazard else &"APPLIED") and mover.move_points_left == 0.0 and mover.cell == to),"P08 S05 axes Move exact budget "+str(rise),receipt.reason)
				_p08_cleanup(f)
	var board := BattleBoard.new(3,1)
	board.set_height_steps(Vector2i(2,0),1)
	for provider: GridDataProvider in [board.make_data_provider(),board.make_terrain_only_provider()]:
		var finder := GridPathfinder.new(); finder.configure(board.get_bounds(),provider)
		_check(finder.find_path(Vector2i.ZERO,Vector2i(1,0)).is_empty() and finder.get_reachable_cells(Vector2i.ZERO,100.0).is_empty(),"P08 S04 direct legacy providers both paths fail closed")

func _test_p08_unknown_malformed_priority() -> void:
	for half: bool in [false,true]:
		var f := _p08_fixture()
		if half: f.board.set_height_steps(Vector2i.ZERO,1)
		var original := ItemSimulationSnapshot.capture(f.state,[]).snapshot.to_dict()
		var ids := UnitId.get_counter()
		for mutation: String in ["valid","height_short","height_long","height_float","height_bool","terrain_short","terrain_long","terrain_float","terrain_bool","terrain_type","board_version","units_type","unit_type","occupancy_type","occupant_type","unit_version"]:
			var raw := original.duplicate(true)
			var board: Dictionary = raw.board_snapshot.board
			board.schema_version = 3
			match mutation:
				"height_short": board.heights = []
				"height_long": board.heights.append(0)
				"height_float": board.heights[0] = 0.0
				"height_bool": board.heights[0] = false
				"terrain_short": board.terrain = []
				"terrain_long": board.terrain.append(0)
				"terrain_float": board.terrain[0] = 0.0
				"terrain_bool": board.terrain[0] = false
				"terrain_type": board.terrain = "bad"
				"board_version": board.board_version = 0.0
				"units_type": board.units = "bad"
				"unit_type": board.units[0] = "bad"
				"occupancy_type": board.occupancy = "bad"
				"occupant_type": board.occupancy[0] = "bad"
				"unit_version": board.units[0].schema_version = 99
			var copy := raw.duplicate(true)
			var board_result := SimulationSnapshot.from_dict(raw.board_snapshot)
			var item_result := ItemSimulationSnapshot.from_dict(raw)
			var unsupported := mutation in ["valid","unit_version"]
			_check(board_result.code == (BoardSnapshotResult.Code.SNAPSHOT_UNSUPPORTED if unsupported else BoardSnapshotResult.Code.SNAPSHOT_INVALID) and item_result.code == (ItemSnapshotResult.Code.SNAPSHOT_UNSUPPORTED if unsupported else ItemSnapshotResult.Code.SNAPSHOT_INVALID),"P08 S03 malformed outranks unknown board %s/%s" % [str(half),mutation],board_result.reason+"/"+item_result.reason)
			_check(raw == copy and UnitId.get_counter() == ids,"P08 S03 classification no input mutation/allocator")
		_p08_cleanup(f)
