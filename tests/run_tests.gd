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

	_suite("PushResolver (D-6.1)")
	_test_push_direction_axis_only()
	_test_push_blocked_by_wall_and_height()

	_suite("BattleBoard (C-4)")
	_test_board_occupancy_single_source_of_truth()
	_test_board_move_keeps_occupancy_in_sync()
	_test_board_version_increments()
	_test_pathfinding_respects_occupancy()
	_test_dead_unit_does_not_block()

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

	_suite("P03a Item ownership")
	_test_p03a_item_ownership()
	_test_p03a_acceptance()

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


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


func _make_stats(hp_max: float = 10.0, balance_max: float = 100.0) -> StatsBag:
	var bag := StatsBag.new()
	bag.set_base_value(StatTypes.StatType.HP_MAX, hp_max)
	bag.set_base_value(StatTypes.StatType.BALANCE_MAX, balance_max)
	return bag


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
