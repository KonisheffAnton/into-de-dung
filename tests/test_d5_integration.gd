extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL D5: " + label)

func snapshot(s: BattleEnvironmentSession) -> Dictionary:
	var captured := ItemSimulationSnapshot.capture(s.state, [])
	check(captured.code == ItemSnapshotResult.Code.OK, "capture " + captured.reason)
	return captured.snapshot.to_dict() if captured.snapshot != null else {}

func naked(s: BattleEnvironmentSession, unit: UnitState) -> void:
	for item: ItemInstance in s.state.get_owner(unit.id)._items.values(): item.armor_remaining = 0

func arena() -> BattleEnvironmentSession:
	var s := BattleEnvironmentSession.new()
	for y in s.board.height:
		for x in s.board.width:
			s.board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
			s.board.set_height_steps(Vector2i(x, y), 0)
	s.state.environment.fires.clear()
	s.state.environment.ignite(Vector2i(3, 3))
	s.board.move_unit(s.units[0], Vector2i(1, 3))
	s.board.move_unit(s.units[1], Vector2i(2, 3))
	return s

func parity(s: BattleEnvironmentSession, label: String) -> ActionReceipt:
	var before := snapshot(s)
	var rng := s.context.get_rng().to_dict().duplicate(true)
	var counters := s.context.simulation_counters()
	var f := s.preview_attack(s.units[1].id)
	check(f.status == ActionReceipt.APPLIED, label + " forecast " + String(f.reason))
	check(before == snapshot(s) and rng == s.context.get_rng().to_dict() and counters == s.context.simulation_counters(), label + " live isolation")
	var r := s.attack_unit(s.units[1].id)
	check(r.status == ActionReceipt.APPLIED, label + " execute " + String(r.reason))
	check(r.get_events() == f.events and r.get_steps() == f.steps, label + " event/step parity")
	check(f.snapshot_after == snapshot(s) and f.rng_after == s.context.get_rng().to_dict() and f.counters_after == s.context.simulation_counters(), label + " state/RNG/counter parity")
	return r

func count_kind(receipt: ActionReceipt, kind: StringName) -> int:
	var count := 0
	for event: Dictionary in receipt.get_events():
		if event["kind"] == kind: count += 1
	return count

func check_helper_death_snapshot(s: BattleEnvironmentSession, captured: Dictionary, helper_id: int, label: String) -> void:
	var decoded := ItemSimulationSnapshot.from_dict(captured)
	check(decoded.code == ItemSnapshotResult.Code.OK and decoded.snapshot != null, label + " decode")
	check(s.state.environment.processed_deaths.has(helper_id) and s.state.environment.corpses.filter(func(record: Dictionary) -> bool: return record["source_unit_id"] == helper_id).is_empty(), label + " environment records")
	if decoded.code != ItemSnapshotResult.Code.OK or decoded.snapshot == null: return
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var restored := decoded.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK and restored.state != null, label + " instantiate")
	if restored.code == ItemSnapshotResult.Code.OK and restored.state != null:
		var recaptured := ItemSimulationSnapshot.capture(restored.state, [])
		check(recaptured.code == ItemSnapshotResult.Code.OK and recaptured.snapshot != null and recaptured.snapshot.to_dict() == captured, label + " roundtrip")
		AttackForecast._close(restored.state)

func run() -> void:
	var s := BattleEnvironmentSession.new()
	check(not s.context.is_faulted() and s.state.environment.corpses.size() == 1, "initial corpse through queue")
	var seed := snapshot(s)
	check(seed.get("schema_version") == 5, "new envelope only D5")
	var definitions: Dictionary = {}
	for owner: ItemOwnerState in s.state.get_owners():
		for id: StringName in owner._definitions: definitions[id] = (owner._definitions[id] as ItemDef).duplicate(true)
	var captured := ItemSimulationSnapshot.from_dict(seed)
	var restored := captured.snapshot.instantiate(definitions)
	check(restored.code == ItemSnapshotResult.Code.OK, "instantiate D5")
	if restored.state != null:
		check(ItemSimulationSnapshot.capture(restored.state, []).snapshot.to_dict() == seed, "canonical roundtrip")
		restored.state.environment.consume_corpse(1)
		check(snapshot(s) == seed, "restore environment isolation")
		AttackForecast._close(restored.state)
	for mode: String in ["missing", "extra", "live_source", "missing_source", "void_fire", "bad_kind_type", "duplicate", "counter", "processed_live"]:
		var bad := seed.duplicate(true)
		match mode:
			"missing": bad.erase("environment")
			"extra": bad["environment"]["extra"] = 0
			"live_source": bad["environment"]["corpses"][0]["source_unit_id"] = s.units[0].id
			"missing_source": bad["environment"]["processed_deaths"].append(999)
			"void_fire": bad["environment"]["fires"][0]["cell"] = Vector2i(7, 7)
			"bad_kind_type": bad["environment"]["corpses"][0]["creature_kind"] = 3
			"duplicate": bad["environment"]["corpses"].append(bad["environment"]["corpses"][0].duplicate(true))
			"counter": bad["environment"]["next_corpse_id"] = 1
			"processed_live": bad["environment"]["processed_deaths"].append(s.units[0].id)
		check(ItemSimulationSnapshot.from_dict(bad).code != ItemSnapshotResult.Code.OK, "reject " + mode)
	var legacy := BattleBleedingSession.new()
	check(ItemSimulationSnapshot.capture(legacy.state, []).snapshot.to_dict()["schema_version"] == 4, "D3 v4 preserved")
	legacy.close()
	var actor := s.units[0]
	var original_dead := s.board.get_unit_by_id(s.state.environment.corpses[0]["source_unit_id"])
	var raised := s.raise_corpse(Vector2i(0, 3))
	var helper := s.state.active_summon(actor.id)
	check(raised.status == ActionReceipt.APPLIED and count_kind(raised, &"corpse_raised") == 1, "raise applied")
	check(helper != null and helper.id != original_dead.id and not original_dead.is_alive() and s.state.environment.corpses.is_empty(), "new helper consumes corpse")
	if helper != null:
		check(helper.vitals.get_hp() == 16 and helper.faction == actor.faction and s.state.is_summon_pending(helper.id), "helper stats and faction")
		check(helper.action_resources.get_main_left() == 0 and helper.move_points_left == 0 and actor.action_resources.get_main_left() == 0, "pending helper and cost")
		var after_raise := snapshot(s)
		check(s.raise_corpse(Vector2i(0, 3)).status == ActionReceipt.REJECTED and snapshot(s) == after_raise, "repeat rejection no mutation")
		var refill := s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context)
		check(refill.status == ActionReceipt.APPLIED and not s.state.is_summon_pending(helper.id) and helper.action_resources.get_main_left() == 1 and helper.move_points_left == 4, "team refill activates helper")
		check(s.context.get_move_rules().allows(helper.id) and s.context.get_attack_rules()._actors.has(helper.id), "helper admission")
		s.select_unit(helper.id)
		check(s.raise_reason() == &"summon/helper_cannot_summon", "helper cannot raise")
		var died := s._queue.submit(DeathCommand.new(helper.id, DamageSource.new(&"test", 0, helper.cell)), s.context)
		check(died.status == ActionReceipt.APPLIED and s.state.environment.corpses.is_empty() and s.state.environment.processed_deaths.has(helper.id), "helper death no recyclable body")
		check(s.state.environment.record_death(original_dead.id, original_dead.cell, original_dead.faction, "humanoid").is_empty(), "consumed death cannot recreate corpse")
	s.close()

	s = arena()
	naked(s, s.units[1])
	var receipt := parity(s, "push fire")
	check(s.units[1].cell == Vector2i(3, 3) and s.units[1].vitals.get_hp() == 8, "push fire damage with two item heals")
	check(count_kind(receipt, &"hit_resolved") == 2, "attack and fire separate hits")
	s.close()
	s = arena()
	naked(s, s.units[1]); s.units[1].vitals.set_hp(24)
	receipt = parity(s, "lethal fire")
	check(not s.units[1].is_alive() and s.state.environment.corpses_at(Vector2i(3, 3)).size() == 1, "fire creates body on landing")
	check(count_kind(receipt, &"died") == 1 and count_kind(receipt, &"corpse_created") == 1, "one death one corpse")
	s.close()
	s = arena()
	naked(s, s.units[1]); s.units[1].vitals.set_hp(10)
	receipt = parity(s, "direct death")
	check(s.state.environment.corpses_at(Vector2i(2, 3)).size() == 1 and count_kind(receipt, &"hit_resolved") == 1, "direct death no push/fire")
	s.close()
	for terrain: TerrainType.Type in [TerrainType.Type.VOID, TerrainType.Type.HAZARD, TerrainType.Type.FLOOR]:
		s = arena()
		s.state.environment.fires.clear()
		s.board.set_terrain(Vector2i(3, 3), terrain)
		if terrain == TerrainType.Type.FLOOR:
			s.board.move_unit(s.units[0], Vector2i(6, 3)); s.board.move_unit(s.units[1], Vector2i(7, 3))
		receipt = parity(s, "lethal terrain " + str(terrain))
		check(not s.units[1].is_alive() and s.state.environment.corpses.size() == 1, "fall no body retained on origin")
		s.close()

	s = arena()
	s.board.move_unit(s.units[1], Vector2i(5, 3))
	s.board.move_unit(s.units[0], Vector2i(2, 3)); naked(s, s.units[0])
	var path: Array[Vector2i] = [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]
	s.units[0].vitals.set_hp(6)
	receipt = s._queue.submit(MoveCommand.new(s.units[0].id, path, s.context.get_revision()), s.context)
	check(receipt.status != ActionReceipt.FAULTED and not s.units[0].is_alive() and s.units[0].cell == Vector2i(3, 3), "lethal fire stops path " + String(receipt.reason))
	check(s.state.environment.corpses_at(Vector2i(3, 3)).size() == 1 and not s.board.is_occupied(Vector2i(3, 3)), "death frees occupancy")
	s.close()
	s = BattleEnvironmentSession.new()
	var moved := s.move_to(Vector2i(3, 2))
	check(moved.status == ActionReceipt.APPLIED, "original map approach")
	parity(s, "original map slope/fire")
	s.close()
	# Поднятый участник доступен в снимке и прогнозе уже в pending-фазе.
	s = BattleEnvironmentSession.new()
	s.raise_corpse(Vector2i(0, 3))
	helper = s.state.active_summon(s.units[0].id)
	s.board.move_unit(s.units[1], Vector2i(1, 3))
	var enemy := s.units[1]
	var attack := AttackCommand.new(enemy.id, helper.id, enemy.cell, helper.cell, &"demo_strike", s.context.get_revision())
	var forecast := AttackForecast.build(s.context, s._queue, attack)
	var before_helper_attack := snapshot(s)
	receipt = s._queue.submit(attack, s.context)
	check(forecast.status == ActionReceipt.APPLIED and receipt.get_events() == forecast.events and snapshot(s) == forecast.snapshot_after, "pending helper forecast parity")
	check(not helper.is_alive() and s.state.environment.corpses.is_empty() and before_helper_attack != forecast.snapshot_after, "killed helper leaves no corpse")
	s.close()
	# Реальный вход поднятого помощника в огонь обязан сохранить правило summon без тела.
	s = arena()
	var raised_by_fire := s.raise_corpse(Vector2i(0, 3))
	var fire_helper := s.state.active_summon(s.units[0].id)
	check(raised_by_fire.status == ActionReceipt.APPLIED and fire_helper != null, "raise helper for move death")
	if fire_helper != null:
		var fire_helper_id := fire_helper.id
		s.board.move_unit(s.units[0], Vector2i(0, 0))
		s.board.move_unit(s.units[1], Vector2i(7, 3))
		var fire_refill := s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context)
		check(fire_refill.status == ActionReceipt.APPLIED and not s.state.is_summon_pending(fire_helper_id), "move death helper refill")
		naked(s, fire_helper)
		fire_helper.vitals.set_hp(1)
		var fire_death := s._queue.submit(MoveCommand.new(fire_helper_id, [Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)], s.context.get_revision()), s.context)
		check(fire_death.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED], "helper fire move status " + String(fire_death.reason))
		check(not fire_helper.is_alive() and count_kind(fire_death, &"died") == 1 and count_kind(fire_death, &"corpse_created") == 0, "helper fire death has no body")
		check(not s.board.is_occupied(Vector2i(3, 3)), "helper fire death frees occupancy")
		var fire_after := snapshot(s)
		check_helper_death_snapshot(s, fire_after, fire_helper_id, "helper fire death snapshot")
		var repeated_fire_death := s._queue.submit(DeathCommand.new(fire_helper_id, DamageSource.new(&"test", 0, fire_helper.cell)), s.context)
		check(repeated_fire_death.status == ActionReceipt.REJECTED and snapshot(s) == fire_after, "repeat helper fire death is stable")
	s.close()
	# Кровотечение проходит через ту же регистрацию смерти; помощник также не становится телом.
	s = BattleEnvironmentSession.new()
	var raised_by_bleeding := s.raise_corpse(Vector2i(0, 3))
	var bleeding_helper := s.state.active_summon(s.units[0].id)
	check(raised_by_bleeding.status == ActionReceipt.APPLIED and bleeding_helper != null, "raise helper for bleeding death")
	if bleeding_helper != null:
		var bleeding_helper_id := bleeding_helper.id
		var bleeding_refill := s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context)
		check(bleeding_refill.status == ActionReceipt.APPLIED and not s.state.is_summon_pending(bleeding_helper_id), "bleeding death helper refill")
		bleeding_helper.vitals.set_hp(1)
		bleeding_helper.bleeding.ticks_left = 1
		bleeding_helper.bleeding.source = DamageSource.new(&"attack", 0, s.units[0].cell, s.units[0].id, s.units[0].id).to_dict()
		bleeding_helper.bleeding.hit_id = "d5-helper-death"
		var bleeding_death := s._queue.submit(BleedingTurnCommand.new(Faction.Type.PLAYER, s.context.get_revision()), s.context)
		check(bleeding_death.status == ActionReceipt.APPLIED, "helper bleeding death applied " + String(bleeding_death.reason))
		check(not bleeding_helper.is_alive() and count_kind(bleeding_death, &"died") == 1 and count_kind(bleeding_death, &"corpse_created") == 0, "helper bleeding death has no body")
		check(not s.board.is_occupied(bleeding_helper.cell), "helper bleeding death frees occupancy")
		var bleeding_after := snapshot(s)
		check_helper_death_snapshot(s, bleeding_after, bleeding_helper_id, "helper bleeding death snapshot")
		var repeated_bleeding_death := s._queue.submit(DeathCommand.new(bleeding_helper_id, DamageSource.new(&"test", 0, bleeding_helper.cell)), s.context)
		check(repeated_bleeding_death.status == ActionReceipt.REJECTED and snapshot(s) == bleeding_after, "repeat helper bleeding death is stable")
	s.close()
	# Синхронный callback после появления не может незаметно подменить среду.
	s = BattleEnvironmentSession.new()
	var target_environment := s.state.environment
	var callback := func() -> void: target_environment.ignite(Vector2i(4, 4))
	s.board.board_changed.connect(callback)
	receipt = s.raise_corpse(Vector2i(0, 3))
	s.board.board_changed.disconnect(callback)
	check(receipt.status == ActionReceipt.FAULTED and s.state.environment.corpses.is_empty() and s.units[0].action_resources.get_main_left() == 0, "raise callback faults with paid prefix")
	s.close()
	for protected: bool in [false, true]:
		s = arena()
		s.board.move_unit(s.units[1], Vector2i(5, 3)); s.board.move_unit(s.units[0], Vector2i(2, 3))
		if not protected: naked(s, s.units[0])
		receipt = s._queue.submit(MoveCommand.new(s.units[0].id, [Vector2i(2, 3), Vector2i(3, 3)], s.context.get_revision()), s.context)
		check(receipt.status == ActionReceipt.APPLIED and s.units[0].vitals.get_hp() == (32 if protected else 24), "entry respects armor " + str(protected))
		var hp := s.units[0].vitals.get_hp()
		s.select_unit(s.units[2].id); s.select_unit(s.units[0].id)
		check(s.units[0].vitals.get_hp() == hp, "selection no fire tick")
		s.close()
	# Два последовательных погибших делят клетку, не дублируя occupancy.
	s = arena()
	var cell := Vector2i(4, 4)
	for unit: UnitState in [s.units[1], s.units[3]]:
		s.board.move_unit(unit, cell)
		s._queue.submit(DeathCommand.new(unit.id, DamageSource.new(&"test", 0, cell)), s.context)
	check(s.state.environment.corpses_at(cell).size() == 2 and not s.board.is_occupied(cell), "two corpses one cell")
	s.board.move_unit(s.units[0], Vector2i(3, 4))
	var first: int = s.state.environment.corpses_at(cell)[0]["id"]
	var second: int = s.state.environment.corpses_at(cell)[1]["id"]
	receipt = s.raise_corpse(cell)
	check(receipt.status == ActionReceipt.APPLIED and s.state.environment.corpses_at(cell).size() == 1 and s.state.environment.corpses_at(cell)[0]["id"] == second, "raises oldest only " + str(first))
	s.close()
	edge_cases()
	print("D5 INTEGRATION RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func edge_cases() -> void:
	for mode: String in ["occupied", "fire", "height", "distant", "no_main", "wrong_kind", "stale"]:
		var s := BattleEnvironmentSession.new()
		var cell := Vector2i(0, 3)
		match mode:
			"occupied": s.board.move_unit(s.units[2], cell)
			"fire": s.state.environment.ignite(cell)
			"height": s.board.set_height_steps(cell, 2)
			"distant": s.board.move_unit(s.units[0], Vector2i(0, 0))
			"no_main": s.units[0].action_resources.try_spend_main(1)
			"wrong_kind": s.state.environment.corpses[0]["creature_kind"] = "beast"
		var before := snapshot(s)
		var command := RaiseCorpseCommand.new(s.units[0].id, 1, s.context.get_revision() + (1 if mode == "stale" else 0))
		var r := s._queue.submit(command, s.context)
		check(r.status == ActionReceipt.REJECTED and before == snapshot(s), "raise refusal no payment " + mode)
		s.close()
	# Естественная защита и перк >100% используют тот же D2 executor.
	for resistance: int in [50, 150]:
		var s := arena()
		var actor := s.units[0]
		s.board.move_unit(s.units[1], Vector2i(5, 3)); s.board.move_unit(actor, Vector2i(2, 3))
		naked(s, actor); actor.vitals.set_hp(20)
		actor.armor.natural["fire"] = resistance * 100
		if resistance == 150: actor.armor.perks.append({"id": "fire-cap", "type": "fire", "branch": "both", "bonus": 10000})
		var r := s._queue.submit(MoveCommand.new(actor.id, [Vector2i(2, 3), Vector2i(3, 3)], s.context.get_revision()), s.context)
		check(r.status == ActionReceipt.APPLIED and actor.vitals.get_hp() == (16 if resistance == 50 else 24), "fire resistance " + str(resistance))
		check(actor.bleeding.ticks_left == 0, "fire never adds bleeding")
		s.close()
	var s := arena()
	var actor := s.units[0]
	s.board.move_unit(s.units[1], Vector2i(5, 3)); s.board.move_unit(actor, Vector2i(2, 3))
	naked(s, actor)
	s._queue.submit(MoveCommand.new(actor.id, [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)], s.context.get_revision()), s.context)
	var r := s._queue.submit(MoveCommand.new(actor.id, [Vector2i(4, 3), Vector2i(3, 3)], s.context.get_revision()), s.context)
	check(r.status == ActionReceipt.APPLIED and actor.vitals.get_hp() == 16, "repeat entry hits again")
	var hp := actor.vitals.get_hp()
	s._queue.submit(BleedingTurnCommand.new(Faction.Type.PLAYER, s.context.get_revision()), s.context)
	check(actor.vitals.get_hp() == hp, "team boundary no fire tick")
	s.close()
	# Транзит через занятую союзником клетку не создаёт временной общей occupancy.
	s = arena(); actor = s.units[0]
	s.board.move_unit(s.units[1], Vector2i(5, 3)); s.board.move_unit(actor, Vector2i(2, 3)); s.board.move_unit(s.units[2], Vector2i(3, 3))
	naked(s, actor)
	r = s._queue.submit(MoveCommand.new(actor.id, [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)], s.context.get_revision()), s.context)
	check(r.status == ActionReceipt.APPLIED and actor.cell == Vector2i(4, 3) and actor.vitals.get_hp() == 24 and s.units[2].vitals.get_hp() == 32, "ally transit fire applies to mover only")
	s.close()
	# Огненная смерть от blood tick также проходит через общий died.
	s = arena()
	var target := s.units[1]
	target.vitals.set_hp(1)
	target.bleeding.ticks_left = 1
	target.bleeding.source = DamageSource.new(&"attack", 0, s.units[0].cell, s.units[0].id, s.units[0].id).to_dict()
	target.bleeding.hit_id = "d5-test"
	r = s._queue.submit(BleedingTurnCommand.new(Faction.Type.ENEMY, s.context.get_revision()), s.context)
	check(r.status == ActionReceipt.APPLIED and count_kind(r, &"corpse_created") == 1, "bleeding death body")
	var repeated := s._queue.submit(DeathCommand.new(target.id, DamageSource.new(&"test", 0, target.cell)), s.context)
	check(repeated.status == ActionReceipt.REJECTED and s.state.environment.corpses_at(target.cell).size() == 1, "repeat death no extra body")
	s.close()
	# Изменение слоя среды синхронным callback прерывает guarded шаг.
	s = arena()
	actor = s.units[0]
	s.board.move_unit(s.units[1], Vector2i(5, 3)); s.board.move_unit(actor, Vector2i(2, 3))
	var environment := s.state.environment
	var mutate := func(_kind: StringName, _key: int, _before: int, _after: int) -> void: environment.ignite(Vector2i(4, 4))
	actor.armor.changed.connect(mutate)
	r = s._queue.submit(MoveCommand.new(actor.id, [Vector2i(2, 3), Vector2i(3, 3)], s.context.get_revision()), s.context)
	check(r.status == ActionReceipt.FAULTED and s.context.is_faulted(), "callback environment mutation faults")
	actor.armor.changed.disconnect(mutate)
	s.close()
	s = arena()
	var direct := EnvironmentCommand.for_entry(s.units[0].id, Vector2i(3, 3), s.context)
	var before := snapshot(s)
	r = s._queue.submit(direct, s.context)
	check(r.status == ActionReceipt.REJECTED and r.reason == &"environment/internal_command" and before == snapshot(s), "internal command root rejected")
	s.state.environment.fires[0].erase("id")
	check(ItemSimulationSnapshot.capture(s.state, []).code != ItemSnapshotResult.Code.OK, "malformed runtime returns failure")
	s.close()
	s = arena(); actor = s.units[0]
	for other: UnitState in [s.units[2], s.units[4]]:
		s._queue.submit(DeathCommand.new(other.id, DamageSource.new(&"test", 0, other.cell)), s.context)
	s.board.move_unit(s.units[1], Vector2i(5, 3)); s.board.move_unit(actor, Vector2i(2, 3))
	naked(s, actor); actor.vitals.set_hp(1)
	r = s._submit(MoveCommand.new(actor.id, [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)], s.context.get_revision()))
	check(r.status == ActionReceipt.INTERRUPTED and s.phase == BattleTacticalSession.Phase.DEFEAT, "last ally fire death finishes battle")
	check(not actor.armor.in_battle, "interrupted lethal path finalizes armor battle")
	s.close()
