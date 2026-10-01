extends SceneTree

const Formatter = preload("res://scripts/demo/battle_compact_forecast.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		printerr("FAIL COMPACT FORECAST: " + label)

func row(hp: float, armor: float = 0.0, balance: float = 0.0, cell: Vector2i = Vector2i.ZERO) -> Dictionary:
	return {"hp": hp, "hp_max": 20.0, "armor_current": armor, "armor_max": 5.0, "balance": balance, "balance_max": 10.0, "alive": true, "cell": cell, "main": 1, "bonus": 1, "move": 2, "guard_stance": false, "combat_perks": {}, "control": {}, "elemental": {}, "bleeding": {}}

func run() -> void:
	var partial := {1: {"before": row(20), "after": row(0)}}
	for status: StringName in [&"REJECTED", &"FAULTED"]:
		var hidden := Formatter.build("Удар", status, "сбой", partial, [], 1, {1: "Страж"})
		check(not hidden.text.contains("ОЗ") and hidden.affected_ids.is_empty(), String(status) + " hides partial values")
	var pending := Formatter.build("Удар", &"APPLIED", "", partial, [], 1, {1: "Страж"}, true)
	check(pending.text.contains("Расчёт…") and not pending.text.contains("ОЗ") and pending.affected_ids.is_empty(), "pending hides values")
	var interrupted := Formatter.build("Движение", &"INTERRUPTED", "смерть актёра", partial, [], 1, {1: "Страж"})
	check(interrupted.text.contains("Путь прерван: смерть актёра") and interrupted.text.contains("ОЗ 20→0"), "interrupted result labels its committed prefix")
	var mixed := {1: {"before": row(15, 2, 8), "after": row(12, 4, 6)}}
	var result := Formatter.build("Удар", &"APPLIED", "", mixed, [], 1, {1: "Страж"})
	check(result.text.contains("ОЗ 15→12") and result.text.contains("броня 2→4") and result.text.contains("запас равновесия 2/10→4/10"), "forecast reports remaining reserve, not accumulated disruption")
	var break_before := row(20, 0, 0)
	var break_after := row(20, 0, 0)
	break_before["balance_max"] = 12.0
	break_after["balance_max"] = 12.0
	var broken := Formatter.build("Удар", &"APPLIED", "", {1: {"before": break_before, "after": break_after}}, [{"kind": &"balance_broken", "target_unit_id": 1}], 1, {1: "Страж"})
	check(broken.text.contains("запас равновесия 12/12→12/12") and broken.text.contains("Потеря равновесия"), "event proves loss even when the reset leaves a full final reserve")
	var old_threshold := row(20, 0, 18)
	var new_threshold := row(20, 0, 18)
	old_threshold["balance_max"] = 24.0
	new_threshold["balance_max"] = 12.0
	var threshold_only := Formatter.build("Ход", &"APPLIED", "", {1: {"before": old_threshold, "after": new_threshold}}, [], 1, {1: "Страж"})
	check(threshold_only.text.contains("запас равновесия 6/24→0/12") and not threshold_only.text.contains("Потеря равновесия"), "threshold decrease recomputes each side reserve without inferring a break")
	var full := Formatter.build("Удар", &"APPLIED", "", {1: {"before": row(20, 0, 10), "after": row(20, 0, 10)}}, [], 1, {1: "Страж"})
	check(not full.text.contains("Потеря равновесия"), "empty reserve alone is not a break")
	var chain_events := [{"kind": &"chain_link", "from_unit_id": 1, "target_unit_id": 2, "broke": false}, {"kind": &"collision", "actor_unit_id": 1, "target_unit_id": 2, "blocker_unit_id": 3}]
	var chain_rows := {1: {"before": row(20), "after": row(20)}, 2: {"before": row(20, 0, 10), "after": row(20, 0, 10)}}
	var chain_before := chain_events.duplicate(true)
	var chained := Formatter.build("Толчок", &"APPLIED", "", chain_rows, chain_events, 1, {1: "А", 2: "Б", 3: "В"})
	check(chained.text.contains("Импульс передан") and chained.text.contains("Цепь остановлена · устоял") and chained.affected_ids == [1, 2, 3], "chain participants and collision blocker appear without state delta")
	check(not chained.text.contains("клетка ?") and chain_events == chain_before, "events do not invent movement or mutate input")
	var chain_broke := Formatter.build("Толчок", &"APPLIED", "", {1: {"before": row(20), "after": row(20)}, 2: {"before": row(20, 0, 0), "after": row(20, 0, 0)}}, [{"kind": &"chain_link", "from_unit_id": 1, "target_unit_id": 2, "broke": true}, {"kind": &"balance_broken", "target_unit_id": 2}], 1, {1: "А", 2: "Б"})
	check(chain_broke.text.contains("Потеря равновесия"), "broken chain derives loss from the event")
	var multi_chain_events := [{"kind": &"chain_link", "from_unit_id": 1, "target_unit_id": 2, "broke": true}, {"kind": &"balance_broken", "target_unit_id": 2}, {"kind": &"chain_link", "from_unit_id": 2, "target_unit_id": 3, "broke": false}]
	var multi_chain := Formatter.build("Толчок", &"APPLIED", "", {1: {"before": row(20), "after": row(20)}, 2: {"before": row(20, 0, 0), "after": row(20, 0, 0)}, 3: {"before": row(20), "after": row(20)}}, multi_chain_events, 1, {1: "А", 2: "Б", 3: "В"})
	check(multi_chain.text.contains("Импульс передан") and multi_chain.text.contains("Цепь остановлена · устоял") and multi_chain.text.split("Потеря равновесия").size() == 2, "middle chain unit reports outgoing link without duplicating its incoming loss")
	var wall := Formatter.build("Толчок", &"APPLIED", "", {2: {"before": row(20), "after": row(20)}}, [{"kind": &"push_blocked", "target_unit_id": 2, "reason": &"wall"}], 1, {2: "Б"})
	var height := Formatter.build("Толчок", &"APPLIED", "", {2: {"before": row(20), "after": row(20)}}, [{"kind": &"push_blocked", "target_unit_id": 2, "reason": &"height"}], 1, {2: "Б"})
	var other_block := Formatter.build("Толчок", &"APPLIED", "", {2: {"before": row(20), "after": row(20)}}, [{"kind": &"push_blocked", "target_unit_id": 2, "reason": &"terrain"}], 1, {2: "Б"})
	check(wall.text.contains("толчок остановлен: стена") and height.text.contains("толчок остановлен: высота") and other_block.text.contains("толчок остановлен: прочее"), "blocked push reason is stated precisely")
	var statue_before := row(20, 0, 0)
	var statue_after := row(20, 0, 0)
	statue_before["balance_max"] = 0.0
	statue_after["balance_max"] = 0.0
	var immune_chain := Formatter.build("Толчок", &"APPLIED", "", {2: {"before": statue_before, "after": statue_after}}, [{"kind": &"chain_link", "from_unit_id": 1, "target_unit_id": 2, "broke": false}], 1, {1: "А", 2: "Статуя"})
	check(immune_chain.text.contains("Цепь остановлена · невосприимчив"), "zero balance maximum is shown as immunity")
	statue_after["balance"] = 1.0
	var immune_value := Formatter.build("Удар", &"APPLIED", "", {2: {"before": statue_before, "after": statue_after}}, [], 2, {2: "Статуя"})
	check(immune_value.text.contains("запас равновесия невосприимчив→невосприимчив"), "zero balance maximum uses the dedicated immunity label")
	var exhausted := row(20, 0, 18)
	exhausted["balance_max"] = 12.0
	var recovering := exhausted.duplicate(true)
	recovering["balance"] = 17.0
	var depleted := Formatter.build("Ход", &"APPLIED", "", {1: {"before": exhausted, "after": recovering}}, [], 1, {1: "Страж"})
	check(depleted.text.contains("запас равновесия 0/12→0/12"), "over-threshold recovery keeps the reserve empty")
	var many: Dictionary = {}
	var names: Dictionary = {}
	for id: int in [1, 5, 3, 4, 2]:
		many[id] = {"before": row(20), "after": row(19)}
		names[id] = "Боец%d" % id
	var overflow := Formatter.build("Атака", &"APPLIED", "", many, [], 1, names)
	check(overflow.affected_ids == [1, 2, 3, 4, 5] and overflow.text.contains("Ещё 2"), "stable primary plus three lines and overflow")
	check(overflow.details.contains("Боец5") and not overflow.details.contains("Ещё"), "details contain every full line")
	var helper_after := row(9)
	helper_after["pending"] = true
	var fresh := Formatter.build("Призыв", &"APPLIED", "", {7: {"before": null, "after": helper_after}}, [], 7, {7: "Скаут"})
	check(fresh.text.contains("Скаут") and fresh.text.contains("появляется") and fresh.text.contains("со следующего хода") and fresh.text.contains("ОЗ 9") and not fresh.text.contains("0→9"), "new helper uses caller name, pending time, and actual hp")
	var dead_values := {1: {"before": row(4), "after": row(0)}}
	var dead := Formatter.build("Удар", &"APPLIED", "", dead_values, [{"kind": &"died", "target_unit_id": 1, "source": {"kind": &"fall"}}], 1, {1: "Страж"})
	check(dead.text.contains("Падение") and dead.text.contains("ОЗ 4→0"), "fall death shows actual final hp and cause")
	var no_death_event := {"before": row(4), "after": row(0)}
	no_death_event["after"]["alive"] = false
	var inferred_death := Formatter.build("Удар", &"APPLIED", "", {1: no_death_event}, [], 1, {1: "Страж"})
	check(inferred_death.text.contains("погиб"), "published alive delta still communicates death without journal event")
	var costs_before := row(20)
	var costs_after := row(20)
	costs_after["main"] = 0
	costs_after["bonus"] = 0
	costs_after["move"] = 0
	costs_after["guard_stance"] = true
	costs_after["combat_perks"] = {"reaction_left": 0}
	var costs := Formatter.build("Действие", &"APPLIED", "", {1: {"before": costs_before, "after": costs_after}}, [], 1, {1: "Страж"})
	check(costs.text.contains("основное 1→0") and costs.text.contains("дополнительное 1→0") and costs.text.contains("движение 2→0") and costs.text.contains("стойка включена") and costs.text.contains("перки изменятся"), "action resources and guard/perks deltas are visible")
	var unchanged := Formatter.build("Атака", &"APPLIED", "", {1: {"before": row(20), "after": row(19)}, 2: {"before": row(20), "after": row(20)}}, [], 1, {1: "Страж", 2: "Тень"})
	check(unchanged.affected_ids == [1] and not unchanged.text.contains("Тень"), "unchanged secondary unit is omitted")
	var immutable := mixed.duplicate(true)
	Formatter.build("Удар", &"APPLIED", "", mixed, [{"kind": &"balance_broken", "target_unit_id": 1}], 1, {1: "Страж"})
	check(mixed == immutable, "input dictionaries and events are not mutated")
	print("COMPACT FORECAST RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
