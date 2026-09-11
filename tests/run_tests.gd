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

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- Инфраструктура --------------------------------------------------------

func _suite(name: String) -> void:
	_current_suite = name
	print("[%s]" % name)


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
