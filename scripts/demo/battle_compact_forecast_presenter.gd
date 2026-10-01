extends RefCounted
class_name BattleCompactForecastPresenter

## Адаптер уже опубликованных прогнозов. Здесь нет нового исполнения или захвата runtime.
static func publish(demo: BattleDemo) -> void:
	if not demo.core_reactions_mode or demo.is_execution_pending(): return
	var board := demo.board_view
	if board == null or board.compact_forecast == null: return
	var value: RefCounted
	var title := ""
	var pending := false
	var attack := false
	var primary := board.displayed_selected_id
	var cell := board._view_unit_cell(primary)
	if demo._environment_forecast_pending or demo._environment_forecast != null:
		title = "Окружение · при нынешней расстановке"
		value = demo._environment_forecast
		pending = demo._environment_forecast_pending
		primary = UnitId.NONE
		cell = Vector2i(-1, -1)
	elif demo._turn_forecast_pending or demo._turn_forecast != null:
		title = "Конец хода · до действий противника"
		value = demo._turn_forecast
		pending = demo._turn_forecast_pending
		primary = UnitId.NONE
		cell = Vector2i(-1, -1)
	elif demo._action_forecast_pending:
		title = _action_title(demo._action_forecast_kind)
		pending = true
		if demo._action_forecast_target_id > 0: primary = demo._action_forecast_target_id
		cell = demo._action_forecast_cell if demo._action_forecast_cell.x >= 0 else board._view_unit_cell(primary)
	elif demo._armor_forecast != null:
		title = "Восстановление брони"
		value = demo._armor_forecast
	elif demo._elemental_forecast != null:
		title = demo._elemental_effect_label(demo._action_forecast_effect)
		value = demo._elemental_forecast
		primary = demo._action_forecast_target_id
		cell = board._view_unit_cell(primary)
	elif demo._guard_forecast != null:
		title = "Стойка"
		value = demo._guard_forecast
		if demo._guard_forecast_target > 0: primary = demo._guard_forecast_target
		cell = board._view_unit_cell(primary)
	elif demo._raise_forecast != null:
		title = "Поднять тело"
		value = demo._raise_forecast
		cell = demo._raise_forecast_cell
	elif demo._move_forecast_pending or demo._move_forecast != null:
		title = "Безопасный отход" if demo._move_forecast_retreat else "Движение"
		value = demo._move_forecast
		pending = demo._move_forecast_pending
		cell = demo._move_forecast_cell
	elif demo._item_forecast != null:
		title = "Призыв" if demo._item_forecast_kind == &"summon" else "Лечение"
		value = demo._item_forecast
		if demo._item_forecast_kind == &"summon": cell = demo._item_forecast_cell
	elif demo._attack_forecast_pending or demo._forecast != null:
		attack = true
		title = {&"entangle": "Опутывающий удар", &"rune": "Кровавая руна", &"stun": "Оглушающий удар"}.get(demo._attack_forecast_variant, "Атака")
		value = demo._forecast
		pending = demo._attack_forecast_pending
		primary = demo._forecast_target_id
		cell = demo._forecast_cell
	if title.is_empty():
		board.compact_forecast.publish({}, cell, board)
		return
	var names := board.displayed_names()
	if attack: title += " · %s → %s" % [names.get(demo._attack_forecast_actor, "Боец"), names.get(primary, "Цель")]
	elif names.has(primary): title += " · " + String(names[primary])
	var units: Dictionary = {}
	var events: Array = []
	var status: StringName = &""
	var reason: StringName = &""
	if value != null and not pending:
		status = value.get("status")
		reason = value.get("reason")
		events = value.get("events")
		if value is ForecastSimulation or value is TurnForecast:
			var before: Dictionary = value.get("units_before")
			var after: Dictionary = value.get("units_after")
			for id: int in before: units[id] = {"before": before[id], "after": after.get(id)}
			for id: int in after:
				if not units.has(id): units[id] = {"before": null, "after": after[id]}
		else: units = value.get("units")
		for id: int in units:
			var after: Variant = units[id].get("after")
			if after is Dictionary and after.has("name"): names[id] = after.name
	var model := BattleCompactForecast.build(title, status, demo._reason_text(reason), units, events, primary, names, pending)
	if value is TurnForecast and status == ActionReceipt.APPLIED:
		var phases := {BattleTacticalSession.Phase.ENEMY_TURN: "Ход противника", BattleTacticalSession.Phase.VICTORY: "Победа", BattleTacticalSession.Phase.DEFEAT: "Поражение", BattleTacticalSession.Phase.MUTUAL_DESTRUCTION: "Обе команды погибли"}
		model.text += "\n" + String(phases.get(value.phase_after, "Переход завершён"))
	board.compact_forecast.publish(model, cell, board)

static func _action_title(kind: StringName) -> String:
	return {&"armor": "Восстановление брони", &"elemental": "Способность", &"guard": "Стойка", &"raise": "Поднять тело", &"summon": "Призыв", &"heal": "Лечение"}.get(kind, "Действие")
