extends "res://tests/test_counterattack.gd"

## Общая фикстура и полный parity K12; здесь проверяем единый источник оплаты и H1.
func run() -> void:
	codec_and_budget()
	legacy_payment()
	shared_budget()
	foreign_budget_guard()
	refill_without_perks()
	await hub_turn_and_hud()
	print("REACTION BONUS RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)

func codec_and_budget() -> void:
	var s := fixture()
	var unit := s.units[1]
	unit.action_resources._set_for_refill(0, 2)
	var data := unit.to_snapshot_dict()
	check(data.combat_perks.schema_version == 7 and data.combat_perks.has("reaction_left") and data.combat_perks.reaction_left == 0 and data.combat_perks.definition.size() == 8, "new snapshot stores all perk flags with zero legacy reserve")
	var restored := UnitState.from_snapshot_dict(data)
	check(restored != null and restored.to_snapshot_dict() == data and restored.action_resources != unit.action_resources, "unit roundtrip preserves bonus and detached ownership")
	if restored != null:
		check(restored.action_resources.try_spend_bonus(1) and restored.action_resources.get_bonus_left() == 1 and unit.action_resources.get_bonus_left() == 2, "detached debit cannot spend live bonus")
	var perks: Dictionary = data.combat_perks
	var bad_reserve := perks.duplicate(true)
	bad_reserve.reaction_left = 1
	check(not CombatPerksState.valid(bad_reserve), "bonus mode rejects a nonzero legacy reserve")
	var extra := perks.duplicate(true)
	extra.extra = 0
	check(not CombatPerksState.valid(extra), "schema7 rejects unknown field")
	for key: String in perks.definition:
		var bad := perks.duplicate(true)
		bad.definition[key] = 0
		check(not CombatPerksState.valid(bad), "strict bool " + key)
	var no_perk := perks.duplicate(true)
	no_perk.definition.counterattack = false
	check(not CombatPerksState.valid(no_perk), "mode still requires perk")
	unit.combat_perks.reaction_left = 1
	check(unit.to_snapshot_dict().is_empty(), "new runtime rejects a second reserve")
	unit.combat_perks.reaction_left = 0
	# Runtime-режим с legacy charge сохраняется отдельно от запаса бонусных действий.
	unit.combat_perks.uses_bonus_actions = false
	unit.combat_perks.reaction_left = 0
	var legacy := unit.to_snapshot_dict()
	var old_unit := UnitState.from_snapshot_dict(legacy)
	check(old_unit != null and old_unit.to_snapshot_dict() == legacy and old_unit.action_resources.get_bonus_left() == 2 and MeleeThreat.reaction_points(old_unit) == 0, "legacy conflicting reserves roundtrip without migration or refill")
	var resources := ActionResources.new(unit.id, 1, 1)
	check(not resources.try_spend_bonus(0) and not resources.try_spend_bonus(-1) and not resources.try_spend_bonus(2), "invalid bonus debit is atomic")
	check(resources.try_spend_bonus(1) and resources.get_bonus_left() == 0 and resources.get_main_left() == 1 and not resources.try_spend_bonus(1), "bonus debit preserves main and cannot overdraw")
	s.close()

func legacy_payment() -> void:
	var s := fixture()
	var defender := s.units[1]
	defender.combat_perks.uses_bonus_actions = false
	defender.combat_perks.reaction_left = 1
	defender.action_resources._set_for_refill(0, 0)
	var receipt := parity(s, command(s), "legacy payment remains exact")
	var costs := events(receipt, &"reaction_used")
	check(receipt.status == ActionReceipt.APPLIED and costs.size() == 1 and defender.combat_perks.reaction_left == 0 and defender.action_resources.get_bonus_left() == 0, "legacy snapshot executes old charge without migration")
	if costs.size() == 1: check(costs[0].has("charge_before") and not costs[0].has("bonus_before"), "legacy event shape preserved")
	s.close()

func shared_budget() -> void:
	var s := fixture()
	var defender := s.units[1]
	defender.action_resources._set_for_refill(0, 2)
	s.units[0].action_resources._set_for_refill(3, 1)
	for expected: int in [1, 0]:
		var receipt := parity(s, command(s), "bonus pays counter " + str(expected))
		var costs := events(receipt, &"reaction_used")
		check(receipt.status == ActionReceipt.APPLIED and costs.size() == 1 and defender.action_resources.get_bonus_left() == expected and defender.action_resources.get_main_left() == 0, "one additional per real reaction, no hidden one-charge cap")
		if costs.size() == 1:
			check(costs[0].bonus_after == expected and not costs[0].has("charge_after"), "event reports actual shared debit")
			var draft := {"kind": &"reaction_used", "actor_unit_id": defender.id, "target_unit_id": s.units[0].id, "mode": 3, "bonus_before": expected + 1, "bonus_after": expected, "bonus_cost": 1}
			check(ActionEventValidator.valid_draft(draft), "new payment event accepted")
			draft.bonus_cost = 2
			check(not ActionEventValidator.valid_draft(draft), "event cannot claim wrong payment")
			draft.bonus_cost = 1
			draft.charge_after = 0
			check(not ActionEventValidator.valid_draft(draft), "event cannot mix reserves")
	var receipt := parity(s, command(s), "empty bonus prevents reply")
	check(events(receipt, &"counterattacked").is_empty() and defender.guard_stance, "no extra reply when additional actions spent; stance remains")
	s.close()
	s = fixture()
	defender = s.units[1]
	check(defender.action_resources.try_spend_bonus(1), "spend same point before reaction")
	receipt = parity(s, command(s), "no separate reaction reserve")
	check(events(receipt, &"counterattacked").is_empty(), "other bonus expenditure prevents reaction")
	s.close()

func foreign_budget_guard() -> void:
	var s := fixture()
	var third := s.units[4]
	var callback := func(_old: float, _new: float) -> void: third.action_resources.try_spend_bonus(1)
	s.units[1].vitals.hp_changed.connect(callback)
	var receipt := s._queue.submit(command(s), s.context)
	check(receipt.status == ActionReceipt.FAULTED and s.context.is_faulted(), "foreign callback bonus tampering faults entire cascade")
	s.units[1].vitals.hp_changed.disconnect(callback)
	s.close()

func refill_without_perks() -> void:
	var s := BattleTacticalSession.new()
	for unit: UnitState in s.units:
		check(unit.combat_perks == null, "legacy tactical fixture has no perk checkpoint")
		unit.action_resources.try_spend_bonus(1)
	var receipt := s._queue.submit(BattleTurnRefill.new(s.living_ids(Faction.Type.PLAYER), s.context.get_revision(), Faction.Type.PLAYER), s.context)
	check(receipt.status == ActionReceipt.APPLIED and not s.context.is_faulted(), "ordinary no-perk battle refill does not emit invalid delta")
	for id: int in s.living_ids(Faction.Type.PLAYER):
		check(s.board.get_unit_by_id(id).action_resources.get_bonus_left() == 1, "no-perk bonus refills")
	s.close()

func hub_turn_and_hud() -> void:
	var hub := HeroHubState.create()
	hub.party = [1, 2, 4]
	check(hub.start_battle(), "H1 mixed party starts")
	var bundle := HeroHubBattleFactory.create(hub)
	check(not bundle.is_empty(), "H1 factory accepts new snapshot shape")
	if bundle.is_empty(): return
	var s: BattleCoreReactionsSession = bundle.session
	check(BattleExecutionWorker.can_transfer(s), "H1 new resource graph is transferable")
	var warrior := s.board.get_unit_by_id(bundle.hero_units[1])
	for unit: UnitState in s.units:
		unit.stats.set_base_value(StatTypes.StatType.HP_MAX, 1000.0)
		unit.vitals.set_hp(1000.0)
		unit.stats.set_base_value(StatTypes.StatType.IMPACT_POWER, 0.0)
	check(s.start_battle(), "H1 starts with enemy team")
	for i: int in 80:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		s.step_enemy()
	check(s.can_player_act() and warrior.action_resources.get_bonus_left() == 1, "actual H1 enemy cycle refills warrior")
	var demo := HeroHubBattleView.new()
	demo.supplied_session = s
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 850)
	root.add_child(viewport)
	viewport.add_child(demo)
	demo.set_process(false)
	s.select_unit(warrior.id)
	# Ровная изолированная площадка гарантирует реальный выход из угрозы Оппортуниста.
	for i: int in s.units.size(): s.board.move_unit(s.units[i], Vector2i(i, 0))
	s.board.move_unit(warrior, Vector2i(2, 3))
	var enemy := s.board.get_unit_by_id(s.living_ids(Faction.Type.ENEMY)[0])
	s.board.move_unit(enemy, Vector2i(3, 3))
	check(s.set_reaction_guard(CombatPerksState.Mode.OPPORTUNIST).status == ActionReceipt.APPLIED, "H1 warrior pays main for Opportunist")
	check(s.end_player_turn(), "H1 hands turn to enemy before its movement")
	var path: Array[Vector2i] = [enemy.cell, Vector2i(4, 3)]
	var receipt := parity(s, MoveCommand.new(enemy.id, path, s.context.get_revision()), "H1 real opportunist")
	check(receipt.status == ActionReceipt.INTERRUPTED and warrior.action_resources.get_bonus_left() == 0, "H1 Opportunist spends additional action")
	demo._refresh()
	check(demo.board_view._presentation_visual(warrior.id).action_resources_view.bonus == 0 and demo.board_view.displayed_unit_details(warrior.id).contains("доп. 0"), "H1 HUD and inspection show same spent point")
	check(s.phase == BattleTacticalSession.Phase.ENEMY_TURN, "spent reaction remains empty during enemy turn")
	for i: int in 80:
		if s.phase != BattleTacticalSession.Phase.ENEMY_TURN: break
		s.step_enemy()
	check(s.can_player_act() and warrior.action_resources.get_bonus_left() == 1 and not warrior.guard_stance, "next actual H1 turn restores additional action and expires stance")
	demo._refresh()
	var visual := demo.board_view._presentation_visual(warrior.id)
	check(visual.action_resources_view.bonus == 1 and visual.reaction_view.charge == 1 and not visual.reaction_view.ready, "refilled point visible even with inactive remembered Opportunist")
	check(not demo.board_view.displayed_unit_details(warrior.id).contains("Общий заряд"), "modern inspection has no separate charge")
	var published := ActionPresentationState.capture(s.state)
	demo.board_view.show_presentation_state(published)
	warrior.action_resources.try_spend_bonus(1)
	check(demo.board_view._presentation_visual(warrior.id).action_resources_view.bonus == 1, "HUD holds published values without live reads")
	demo.board_view.show_presentation_state(ActionPresentationState.capture(s.state))
	check(demo.board_view._presentation_visual(warrior.id).action_resources_view.bonus == 0, "atomic after publishes shared bonus")
	viewport.free()
	await process_frame
