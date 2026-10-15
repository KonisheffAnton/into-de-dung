extends RefCounted
class_name BattleForecastText

# Формирует строки только из отсоединённых значений прогноза; UI и живое состояние остаются у BattleDemo.

class ManaTextValues extends RefCounted:
	var valid: bool = false
	var before: int = 0
	var after: int = 0
	var cooldown_turns: int = 0
	var remaining: int = 0

static func spell_mana_values(forecast: ForecastSimulation, effect: StringName) -> ManaTextValues:
	var values := ManaTextValues.new()
	var before_state := BattleAbilityState.from_dict(forecast.snapshot_before.get("abilities", {}))
	var after_state := BattleAbilityState.from_dict(forecast.snapshot_after.get("abilities", {}))
	var definition: AbilityDefinition = before_state.definition(effect) if before_state != null else null
	if before_state == null or after_state == null or definition == null: return values
	values.valid = true
	values.before = before_state.mana
	values.after = after_state.mana
	values.cooldown_turns = definition.cooldown_turns
	values.remaining = after_state.remaining(effect)
	return values

static func card_mana_values(forecast: ForecastSimulation) -> ManaTextValues:
	var values := ManaTextValues.new()
	var before_state := BattleAbilityState.from_dict(forecast.snapshot_before.get("abilities", {}))
	var after_state := BattleAbilityState.from_dict(forecast.snapshot_after.get("abilities", {}))
	if before_state == null or after_state == null: return values
	values.valid = true
	values.before = before_state.mana
	values.after = after_state.mana
	return values

static func control_skip_text(reason: StringName) -> String:
	match reason:
		&"control/dead_target": return "цель погибла"
		&"control/stun_immune": return "иммунитет к оглушению"
		&"control/entangle_immune": return "иммунитет к путам"
		_: return "нет положительного физического урона HP"

static func reason_text(reason: StringName, tactical_mode: bool) -> String:
	match reason:
		&"raise_shields/cooldown": return "Поднять щиты восстанавливается: следующий свой ход нужно пропустить."
		&"raise_shields/already_active": return "Щиты уже подняты до первой атаки или следующего своего хода."
		&"raise_shields/insufficient_main": return "Нужно 1 основное действие."
		&"raise_shields/not_owned": return "У бойца нет способности Поднять щиты."
		&"mage/cooldown": return "Заклинание восстанавливается до конца следующих своих ходов."
		&"mage/insufficient_mana": return "Недостаточно маны мага."
		&"mage/full_hp": return "Для лечения нужен раненый живой союзник."
		&"mage/invalid_target": return "Огонь — по живому противнику; лечение — по живому союзнику."
		&"mage/invalid_summon_owner": return "Для тестового призыва или поднятия выберите живого союзника."
		&"mage/window_closed", &"mage/terminal": return "Маг действует между завершёнными действиями вашего хода."
	match reason:
		&"perks/stunning_strike_required": return "этот персонаж не владеет Оглушающим ударом."
		&"perks/not_owned": return "этот персонаж не владеет выбранным режимом реакции."
		&"guard/already_active": return "эта охранная стойка уже активна."
		&"guard/insufficient_main": return "не хватает основного действия, чтобы включить режим реакции."
		&"control/stun_immune": return "цель невосприимчива к оглушению; урон и толчок сохраняются."
		&"control/entangle_immune": return "цель невосприимчива к путам; урон и толчок сохраняются."
		&"control/stunned": return "персонаж оглушён и не может выполнять добровольные действия."
		&"control/frozen": return "персонаж заморожен и не может выполнять добровольные действия."
		&"status/insufficient_main": return "для этого действия нужно 1 основное действие."
		&"status/dead_target": return "живой цели больше нет на поле."
		&"status/not_admitted": return "сейчас этот персонаж не может действовать."
		&"status/stale_revision": return "состояние боя изменилось; наведите курсор заново."
		&"status/capability_required": return "эти эффекты доступны в основном бою."
		&"control/entangled": return "персонаж опутан и не может двигаться; остальные действия доступны."
		&"control/capability_required": return "эта цель не поддерживает состояния контроля."
		&"armor/summon_unsupported": return "призыв недоступен в сценарии брони."
		&"armor/zero_restore": return "нечего восстанавливать."
		&"armor/full": return "обычная броня уже восстановлена."
		&"attack/insufficient_main":
			if tactical_mode: return "основные действия закончились; выберите другого персонажа или завершите ход."
			return "основные действия закончились; выберите другого персонажа или сбросьте бой."
		&"battle/input_locked": return "сейчас нельзя действовать."
		&"battle/friendly_target": return "выберите противника."
		&"move/insufficient_move": return "не хватает очков движения."
		&"move/insufficient_main": return "для безопасного отхода нужно 1 основное действие."
		&"move/actor_dead": return "персонаж погибнет на пути."
		&"move/actor_displaced": return "персонаж будет смещён с маршрута."
		&"move/path_blocked": return "продолжение пути будет перекрыто."
		&"move/budget_exhausted": return "очки движения закончатся на пути."
		&"attack/out_of_reach", &"attack/not_aligned": return "цель вне досягаемости прямого удара."
		&"move/unreachable": return "нет проходимого маршрута к этой клетке."
		&"move/no_selected_unit", &"attack/no_selected_unit": return "выберите живого персонажа."
		&"attack/self_target": return "нельзя атаковать самого себя."
		&"attack/line_blocked": return "линию атаки перекрывает стена или противник."
		&"attack/terrain_shape_unsupported": return "рельеф не допускает прямой удар."
		&"attack/stale_revision": return "состояние боя изменилось; наведите курсор заново."
		&"attack/missing_target", &"attack/invalid_target", &"attack/dead_target": return "живой цели больше нет на поле."
		&"BUSY": return "дождитесь завершения действия."
		&"CONTEXT_FAULTED": return "бой остановлен; выполните сброс."
		&"guard/already_active": return "охранная стойка уже активна."
		&"summon/active_helper": return "у этого владельца уже есть живой помощник."
		&"summon/invalid_cell": return "нужна соседняя свободная безопасная клетка той же высоты."
		&"environment/no_corpse": return "нет доступного гуманоида на соседней свободной клетке."
		&"environment/invalid_raise_cell": return "тело нельзя поднять на клетке с шипами, занятой или другой высоты."
		&"summon/helper_cannot_summon": return "помощник не может поднимать другие тела."
		&"item/full_hp": return "здоровье уже полное."
		&"item/no_charges": return "заряды предмета закончились."
		&"item/insufficient_main": return "недостаточно основных действий."
		&"item/not_owned": return "нет доступного предмета."
		&"item/inactive": return "предмет не активен."
		&"item/not_usable": return "этот предмет нельзя использовать."
		&"item/no_selected_unit": return "выберите живого персонажа."
		&"item/not_admitted": return "персонаж не может использовать предмет."
		&"item/stale_revision": return "состояние боя изменилось; повторите попытку."
		&"item/invalid_runtime", &"item/invalid_mutation": return "состояние боя повреждено; начните заново."
		&"guard/insufficient_main": return "недостаточно основных действий."
		&"guard/no_selected_unit": return "выберите живого персонажа."
		&"guard/not_admitted": return "персонаж не может занять стойку."
		&"guard/stale_revision": return "состояние боя изменилось; повторите попытку."
		&"guard/invalid_runtime": return "состояние персонажа повреждено; сбросьте бой."
		&"attack/no_reachable_position": return "не хватает движения или нет доступной позиции для обычной атаки."
		&"perks/not_owned": return "этот персонаж не владеет преимуществом."
		&"perks/invalid_cover_target": return "выберите допустимого соседнего союзника."
		&"perks/movement_stopped": return "движение уже остановлено Оппортунистом до пополнения команды."
		&"perks/opportunist_stopped": return "Оппортунист прервёт выход из зоны угрозы."
		&"perks/invalid_mode": return "режим реакции недоступен."
		&"preview/rng_not_cloneable", &"preview/rng_state_mismatch", &"preview/unsupported_worker_rng", &"preview/unsupported_rng": return "случайный эффект пока не поддерживает точный прогноз."
		&"turn/unsupported_session", &"turn/unsupported_runtime": return "этот вариант боя пока не поддерживает точный прогноз перехода."
		&"turn/unsupported_phase", &"turn/not_transitioned": return "завершение хода сейчас недоступно."
		&"turn/faulted": return "переход хода не завершится; точный итог недоступен."
		&"preview/worker_unavailable": return "расчёт временно недоступен; наведите курсор ещё раз."
		&"command_limit", &"event_limit", &"depth_limit", &"sequence_exhausted": return "цепь последствий не завершилась; точный итог недоступен."
	return "Эта комбинация пока не поддерживается: " + String(reason)

static func bleeding_skip_text(reason: StringName) -> String:
	match reason:
		&"bleeding/immune": return "иммунитет"
		&"bleeding/dead_target": return "цель погибла"
		&"bleeding/burning": return "горение блокирует кровотечение"
	return "нет физического HP-урона"

static func attack(
	forecast: AttackForecast, actor_name: String, target_name: String, target_id: int,
	names: Dictionary[int, String], event_lines: PackedStringArray,
	core_reactions: bool, tactical_mode: bool
) -> String:
	var status: StringName = forecast.status
	var reason: StringName = forecast.reason
	var text := "[font_size=16][color=#f7c97d]%s → %s[/color][/font_size]\n" % [actor_name, target_name]
	if status != &"APPLIED":
		return text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + reason_text(reason, tactical_mode)
	# Краткий итог цепи виден до подробных строк брони и HP.
	var chain_links: PackedStringArray = []
	for event: Dictionary in forecast.events:
		if event.get("kind") == &"chain_link":
			chain_links.append("%s: %s%s" % [_name_for(names, int(event.target_unit_id)), str(event.impulse), "" if event.broke else " (удержал)"])
	if not chain_links.is_empty():
		text += "[color=#f7c97d]Цепь · сила: %s[/color]\n" % " → ".join(chain_links)
		text += "Пунктир — импульс; стрелка — сдвиг.\n"
	var units: Dictionary = forecast.units
	var target_after: Dictionary = units.get(target_id, {}).get("after", {})
	for step: Dictionary in forecast.steps:
		if step["kind"] == &"stun_apply":
			if step["status"] == &"APPLIED": text += "Оглушение: до конца ближайшего хода команды цели.\n"
			elif step["status"] == &"SKIPPED": text += "Оглушение пропущено: " + control_skip_text(step["reason"]) + ".\n"
			continue
		if step["kind"] != &"entangle_apply": continue
		if step["status"] == &"APPLIED":
			text += "Путы: до конца ближайшего хода команды цели. Движение запрещено; следующий толчок снимает путы.\n"
		elif step["status"] == &"SKIPPED": text += "Путы не наложены: " + control_skip_text(step["reason"]) + ".\n"
	if target_after.has("bleeding"):
		if bool(target_after["bleeding"].get("stacked", false)):
			text += "Кровотечение после атаки: %s\n" % BattleEventText.bleeding_summary(target_after["bleeding"])
		else:
			text += "Кровотечение: %d тика после атаки\n" % target_after["bleeding"]["ticks_left"]
		for step: Dictionary in forecast.steps:
			if step["kind"] == &"bleeding_apply" and step["status"] == &"SKIPPED":
				text += "Не наложено: " + bleeding_skip_text(step["reason"]) + ".\n"
	for id_variant in units:
		var id := int(id_variant)
		var entry: Dictionary = units[id]
		var before: Dictionary = entry.get("before", {})
		var after: Dictionary = entry.get("after", {})
		if before == after: continue
		var hp_before := float(before.get("hp", 0.0))
		var hp_after := float(after.get("hp", 0.0))
		var hp_color := "#f29b9b" if hp_after < hp_before else "#65dfcc"
		if hp_before != hp_after or id == target_id:
			text += "%s: HP [color=%s]%.1f → %.1f%s[/color]\n" % [_name_for(names, id), hp_color, hp_before, hp_after, " · ГИБЕЛЬ" if not after["alive"] else ""]
		if before["balance"] != after["balance"] or before.get("balance_max") != after.get("balance_max"):
			var before_balance := BattleBalanceDisplay.value_text(float(before["balance"]), float(before["balance_max"]))
			var after_balance := BattleBalanceDisplay.value_text(float(after["balance"]), float(after["balance_max"]))
			text += "%s: равновесие %s → %s\n" % [_name_for(names, id), before_balance, after_balance]
		if before.has("armor_current"):
			text += "%s: броня %s → %s / %s\n" % [_name_for(names, id), BattleEventText.amount_text(before["armor_current"]), BattleEventText.amount_text(after["armor_current"]), BattleEventText.amount_text(after["armor_max"])]
		if before.has("bleeding") and (id == target_id or before["bleeding"] != after["bleeding"]):
			if bool(before["bleeding"].get("stacked", false)):
				text += "%s: кровотечение %s → %s\n" % [_name_for(names, id), BattleEventText.bleeding_summary(before["bleeding"]), BattleEventText.bleeding_summary(after["bleeding"])]
			else:
				text += "%s: кровотечение %d → %d тика\n" % [_name_for(names, id), before["bleeding"]["ticks_left"], after["bleeding"]["ticks_left"]]
		if before.get("elemental", {}) != after.get("elemental", {}):
			text += "%s: %s → %s\n" % [_name_for(names, id), BattleEventText.elemental_summary(before.get("elemental", {})), BattleEventText.elemental_summary(after.get("elemental", {}))]
		if before.has("control") and before["control"] != after["control"]:
			if before["control"]["entangled_turns"] > after["control"]["entangled_turns"]: text += "%s: путы будут сняты.\n" % _name_for(names, id)
			if after["control"]["stunned_turns"] > before["control"]["stunned_turns"]: text += "%s: оглушение будет наложено.\n" % _name_for(names, id)
		if before["main"] != after["main"]:
			text += "%s: основные действия %d → %d\n" % [_name_for(names, id), before["main"], after["main"]]
	var events: Array[Dictionary] = forecast.events
	for event: Dictionary in events:
		if event.get("kind") == &"attacked" and event.has("modifiers"):
			var modifiers: Dictionary = event["modifiers"]
			if int(modifiers.get("surround_percent", 0)) > 0:
				var attributes: Dictionary = modifiers.get("character_attributes", {})
				if attributes.is_empty():
					text += "\n[color=#f7c97d]Окружение +%d%% всего прямого урона[/color] · союзники: %s\n" % [modifiers["surround_percent"], ", ".join(BattleEventText.names_for_ids(names, modifiers.get("surround_ally_ids", [])))]
				else:
					var base_percent := float(modifiers["surround_percent"])
					var scaled_percent := base_percent * CharacterAttributeRules.position_bonus_multiplier(float(attributes.get("mastery", 10.0)))
					text += "\n[color=#f7c97d]Окружение +%s%% к сумме бонусов[/color] (база %s%%) · союзники: %s\n" % [BattleEventText.amount_text(scaled_percent), BattleEventText.amount_text(base_percent), ", ".join(BattleEventText.names_for_ids(names, modifiers.get("surround_ally_ids", [])))]
			if modifiers.has("sneak_percent") and modifiers["sneak_percent"] == 50:
				var threat_names: PackedStringArray = []
				for threat_id: int in modifiers.get("threat_ids", []): threat_names.append(_name_for(names, threat_id))
				text += "\n[color=#f7c97d]Скрытая атака +50%% физической базы[/color] · угрожают: %s\n" % ", ".join(threat_names)
			if int(modifiers.get("backstab_percent", 0)) > 0 and not core_reactions: text += "\n[color=#f7c97d]Удар в спину +%d%% базы[/color]\n" % modifiers["backstab_percent"]
			if modifiers.get("critical", false):
				var attributes: Dictionary = modifiers.get("character_attributes", {})
				if attributes.is_empty():
					text += "[color=#f29b9b]Крит ×2: прямой урон и воздействие[/color]\n"
				else:
					text += "[color=#f29b9b]%s[/color]\n" % BattleEventText.critical_detail(event)
	for event: Dictionary in events:
		if event.get("kind") != &"hit_resolved": continue
		var hit: Dictionary = event["hit"]
		var hit_source: Dictionary = event.get("source", {})
		if hit_source.get("kind", &"") == &"cell":
			text += "[color=#f29b9b]Шипы на %s: 8 урона при входе[/color]\n" % BattleEventText.cell_name(hit_source.get("origin_cell", Vector2i.ZERO))
		text += "\n[color=#f7c97d]%s · броня −%s[/color]\n" % [_name_for(names, event["target_unit_id"]), BattleEventText.amount_text(hit["armor_spent"])]
		text += "В HP до защиты: %s/%s · урон %s · лечение %s\n" % [BattleEventText.amount_text(hit["p_num"]), BattleEventText.amount_text(hit["p_den"]), BattleEventText.amount_text(hit["total_damage"]), BattleEventText.amount_text(hit["total_healing"])]
		for row: Dictionary in hit["rows"]:
			var damage_label := "Физический" if row["type"] == &"physical" else "Огонь"
			if row["policy"] == &"hp_only_natural": damage_label += " · в обход брони"
			elif row["policy"] == &"hp_only_unresisted": damage_label += " · без защит"
			text += "%s: вход %s → броня %s / HP %s / лечение %s\n" % [damage_label, BattleEventText.amount_text(row["D"]), BattleEventText.amount_text(row["armor_spent"]), BattleEventText.amount_text(row["hp_damage"]), BattleEventText.amount_text(row["healing"])]
		if hit.has("bleeding"):
			var gate: Dictionary = hit["bleeding"]
			var gate_text := "есть физический HP-урон до лечения" if gate["eligible"] else "нет физического HP-урона"
			if gate["policy"] == &"bypass_hp_gate":
				gate_text = "Перк «Кровавая руна» обходит требование физического HP-урона"
			text += "Кровотечение: " + gate_text + ".\n"
	for step: Dictionary in forecast.steps:
		if step["kind"] != &"bleeding_apply" or step["status"] != &"SKIPPED": continue
		text += "Кровотечение не наложено: " + bleeding_skip_text(step["reason"]) + ".\n"
	if events.is_empty(): text += "Событий последствий нет.\n"
	else:
		text += "\n[color=#a5b3c5]Последствия:[/color]\n"
		for event_index in events.size():
			text += "• " + event_lines[event_index] + "\n"
	return text

static func move(
	forecast: MoveForecast, cell: Vector2i, retreat: bool, pending: bool,
	has_pending_path: bool, names: Dictionary[int, String],
	event_lines: PackedStringArray, tactical_mode: bool
) -> String:
	var text := "[font_size=16][color=#f7c97d]%s к %s[/color][/font_size]\n" % ["Безопасный отход" if retreat else "Движение", BattleEventText.cell_name(cell)]
	if retreat: text += "Оппортунист не перехватывает этот маршрут. Опасности сохраняются.\n"
	if pending:
		return text + ("Пунктир — выбранный маршрут.\nРассчитываем последствия…" if has_pending_path else "Расчёт прогноза…")
	if forecast.status not in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		return text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + reason_text(forecast.reason, tactical_mode)
	if forecast.status == ActionReceipt.INTERRUPTED:
		text += "[color=#f29b9b]Маршрут прервётся: %s[/color]\n" % reason_text(forecast.reason, tactical_mode)
		if forecast.reason == &"perks/opportunist_stopped": text += "Оппортунист остановит движение до выхода на следующую клетку; будет потрачено 1 дополнительное действие.\n"
	for id: int in forecast.units:
		var row: Dictionary = forecast.units[id]
		var before: Dictionary = row["before"]
		var after: Dictionary = row["after"]
		if id != forecast.actor_id and before == after: continue
		text += "%s: %s → %s\n" % [_name_for(names, id), BattleEventText.cell_name(before["cell"]), BattleEventText.cell_name(after["cell"])]
		text += "HP %.1f → %.1f%s\n" % [before["hp"], after["hp"], " · ГИБЕЛЬ" if not after["alive"] else ""]
		if id == forecast.actor_id:
			text += "Движение %.1f → %.1f · расход %.1f ОД\n" % [before["move"], after["move"], float(before["move"]) - float(after["move"])]
			text += "Основные %d → %d · бонусные %d → %d\n" % [before["main"], after["main"], before["bonus"], after["bonus"]]
		if before.has("armor_current") and before["armor_current"] != after["armor_current"]:
			text += "Броня %s → %s / %s\n" % [BattleEventText.amount_text(before["armor_current"]), BattleEventText.amount_text(after["armor_current"]), BattleEventText.amount_text(after["armor_max"])]
		if before["guard_stance"] and not after["guard_stance"]: text += "Стойка будет снята.\n"
	text += "\n[color=#a5b3c5]Последствия:[/color]\n"
	for event_index in event_lines.size():
		text += "• " + event_lines[event_index] + "\n"
	return text

static func guard(forecast: GuardForecast, actor_name: String, action_kind: StringName, tactical_mode: bool) -> String:
	var text := "[font_size=16][color=#f7c97d]%s · %s[/color][/font_size]\n" % ["Поднять щиты" if action_kind == &"raise_shields" else "Охранная стойка", actor_name]
	if forecast.status != ActionReceipt.APPLIED:
		return text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + reason_text(forecast.reason, tactical_mode)
	var row: Dictionary = forecast.units[forecast.actor_id]
	var before: Dictionary = row["before"]
	var after: Dictionary = row["after"]
	text += "Основные: %d → %d (расход %d)\nБонусные: %d → %d\nДвижение: %.1f → %.1f\n" % [
		before["main"], after["main"], int(before["main"]) - int(after["main"]),
		before["bonus"], after["bonus"], before["move"], after["move"],
	]
	if action_kind == &"raise_shields":
		return text + "90% урона первой атаки до начала следующего своего хода.\nДвижение и Оппортунист сохраняются. Откат: 1 полный следующий свой ход."
	text += "Стойка: %s → %s\n" % ["включена" if before["guard_stance"] else "выключена", "включена" if after["guard_stance"] else "выключена"]
	text += "До следующего хода команды; добровольные движение и атака снимают стойку.\nКлик или клавиша 2 — занять стойку."
	return text

static func reaction_guard(forecast: GuardForecast, actor_id: int, actor_name: String, target_name: String, mode: int, tactical_mode: bool) -> String:
	var mode_name := "Оппортунист" if mode == CombatPerksState.Mode.OPPORTUNIST else ("Контратака" if mode == CombatPerksState.Mode.COUNTERATTACK else "Прикрытие")
	var text := "[font_size=16][color=#f7c97d]%s · %s[/color][/font_size]\n" % [mode_name, actor_name]
	if mode == CombatPerksState.Mode.COVER: text += "Союзник: %s\n" % target_name
	if forecast.status != ActionReceipt.APPLIED:
		return text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + reason_text(forecast.reason, tactical_mode)
	var row: Dictionary = forecast.units.get(actor_id, {})
	var before: Dictionary = row.get("before", {})
	var after: Dictionary = row.get("after", {})
	text += "Основные: %d → %d (расход 1)\n" % [before.get("main", 0), after.get("main", 0)]
	var perks: Dictionary = after.get("combat_perks", {})
	if bool(perks.get("uses_bonus_actions", false)) and not bool(perks.get("definition", {}).get("passive_opportunist", false)):
		text += "Дополнительные: %d → %d (реакция расходует 1)\n" % [before.get("bonus", 0), after.get("bonus", 0)]
	else:
		text += "Общий заряд реакции: %d → %d\n" % [before.get("combat_perks", {}).get("reaction_left", 0), perks.get("reaction_left", 0)]
	text += "Клик — занять стойку за 1 основное действие. Реакция сработает при подходящем событии и наличии запаса для её оплаты."
	return text

static func item(forecast: ItemUseForecast, kind: StringName, cell: Vector2i, cost_text: String, tactical_mode: bool) -> String:
	var text := "[font_size=16][color=#f7c97d]"
	if kind == &"healing": text += "Прогноз лечения"
	else: text += "Прогноз призыва · %s" % BattleEventText.cell_name(cell)
	text += "[/color][/font_size]\n"
	if forecast.status != &"APPLIED":
		text += "Цена: %s.\n[color=#f29b9b]Прогноз недоступен[/color]\n" % cost_text + reason_text(forecast.reason, tactical_mode)
		return text
	var item_actor_id: int = -1
	for item_id_variant in forecast.items:
		var owner_row: Dictionary = forecast.items[item_id_variant]
		item_actor_id = int(owner_row.get("actor_id", -1))
	for id_variant in forecast.units:
		var id := int(id_variant)
		var entry: Dictionary = forecast.units[id]
		var before_value: Variant = entry.get("before")
		var after: Dictionary = entry.get("after", {})
		if kind == &"healing" and id != item_actor_id: continue
		if kind == &"summon" and before_value != null: continue
		var label := String(after.get("name", "Участник %d" % id))
		if before_value == null:
			# Призванный помощник не имеет состояния до появления и не считается погибшим.
			var after_cell: Vector2i = after.get("cell", Vector2i.ZERO)
			var helper_status := "ожидает следующего хода" if bool(after.get("pending", false)) else "готов"
			text += "%s · ID %d · помощник\nКлетка: %s · владелец: %d\nСтатус: %s\n" % [
				label, int(after.get("id", id)), BattleEventText.cell_name(after_cell),
				int(after.get("owner_unit_id", 0)), helper_status,
			]
			text += "HP: %.1f / %.1f\nДействия: %d основных, %d бонусных, %.1f движения\n" % [
				float(after.get("hp", 0.0)), float(after.get("hp_max", 0.0)),
				int(after.get("main", 0)), int(after.get("bonus", 0)), float(after.get("move", 0.0)),
			]
		else:
			var before: Dictionary = before_value
			text += "%s: HP %.1f → %.1f / %.1f\n" % [label, float(before.get("hp", 0.0)), float(after.get("hp", 0.0)), float(after.get("hp_max", 0.0))]
			text += "Действия: основные %d → %d\n" % [int(before.get("main", 0)), int(after.get("main", 0))]
	for item_id_variant in forecast.items:
		var item_row: Dictionary = forecast.items[item_id_variant]
		var item_before: Dictionary = item_row.get("before", {})
		var item_after: Dictionary = item_row.get("after", {})
		text += "Заряды: %d → %d\n" % [int(item_before.get("charges", 0)), int(item_after.get("charges", 0))]
	text += "Цена: %s.\n" % cost_text
	if kind == &"summon": text += "Помощник не действует до следующего хода своей команды."
	return text

static func raise_corpse(forecast: RaiseCorpseForecast, cell: Vector2i, tactical_mode: bool) -> String:
	var text := "[font_size=16][color=#f7c97d]Поднятие тела · %s[/color][/font_size]\n" % BattleEventText.cell_name(cell)
	if forecast.status != ActionReceipt.APPLIED:
		return text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + reason_text(forecast.reason, tactical_mode)
	for id: int in forecast.corpses:
		var row: Dictionary = forecast.corpses[id]
		if row["after"] == null:
			var corpse: Dictionary = row["before"]
			text += "Тело #%d на %s будет использовано.\n" % [id, BattleEventText.cell_name(corpse["cell"])]
	for id: int in forecast.units:
		var row: Dictionary = forecast.units[id]
		var after: Dictionary = row["after"]
		if row["before"] == null:
			# Новый ID отличает помощника от погибшего, чьё тело расходуется.
			text += "%s · ID %d · помощник\nКлетка: %s · владелец: %d\n" % [
				after["name"], id, BattleEventText.cell_name(after["cell"]), after["owner_unit_id"],
			]
			text += "HP: %.1f / %.1f\nДействия: %d основных, %d бонусных, %.1f движения\n" % [
				after["hp"], after["hp_max"], after["main"], after["bonus"], after["move"],
			]
			text += "Статус: %s\n" % ("ожидает следующего хода" if after["pending"] else "готов")
		elif id == forecast.actor_id:
			var before: Dictionary = row["before"]
			text += "%s: основные %d → %d (расход %d)\nБонус: %d → %d · Движение: %.1f → %.1f\n" % [
				after["name"], before["main"], after["main"], before["main"] - after["main"],
				before["bonus"], after["bonus"], before["move"], after["move"],
			]
	return text

static func armor(forecast: ForecastSimulation, actor_id: int, actor_name: String, tactical_mode: bool) -> String:
	var text := "[font_size=16][color=#f7c97d]Восстановление брони · %s[/color][/font_size]\n" % actor_name
	if forecast.status != ActionReceipt.APPLIED:
		return text + "Прогноз недоступен: " + reason_text(forecast.reason, tactical_mode)
	var before: Dictionary = forecast.units_before[actor_id]
	var after: Dictionary = forecast.units_after[actor_id]
	text += "Броня: %s → %s\nОсновные: %d → %d (расход 1)\n" % [BattleEventText.amount_text(before["armor_current"]), BattleEventText.amount_text(after["armor_current"]), before["main"], after["main"]]
	for event: Dictionary in forecast.events:
		if event["kind"] != &"armor_changed": continue
		for item: Dictionary in event["items"]: text += "Вещь #%d: %s → %s\n" % [item["id"], BattleEventText.amount_text(item["before"]), BattleEventText.amount_text(item["after"])]
		for grant: Dictionary in event["grants"]: text += "Временная броня: +%s до конца боя\n" % BattleEventText.amount_text(float(grant["after"]) - float(grant["before"]))
	text += "Стойка сохраняется. Клик или клавиша 4 — восстановить броню."
	return text

static func elemental(
	forecast: ForecastSimulation, effect: StringName, target_id: int, actor_id: int,
	cell: Vector2i, target_name: String, mana: ManaTextValues,
	event_lines: PackedStringArray, tactical_mode: bool
) -> String:
	var text := "[font_size=16][color=#f7c97d]%s → %s · дальность 3[/color][/font_size]\n" % [BattleEventText.elemental_effect_label(effect), target_name]
	if AbilityDefinition.mage_source_id(effect) > 0:
		text = "[font_size=16]%s → %s · вся доска[/font_size]\n" % [BattleEventText.elemental_effect_label(effect), target_name]
		if AbilityDefinition.is_cell_spell(effect):
			text = "[font_size=16]%s → %s · в зоне союзников[/font_size]\n" % [
				BattleEventText.elemental_effect_label(effect), BattleEventText.cell_name(cell),
			]
	if forecast.status != ActionReceipt.APPLIED:
		return text + "Прогноз недоступен: " + reason_text(forecast.reason, tactical_mode)
	if AbilityDefinition.mage_source_id(effect) > 0:
		if mana == null or not mana.valid:
			return text + "Прогноз недоступен: данные отката повреждены."
		text += "Мана %d → %d · откат: длительность %d ходов, после действия осталось %d\n" % [
			mana.before, mana.after, mana.cooldown_turns, mana.remaining,
		]
	var actor_before: Dictionary = forecast.units_before.get(actor_id, {})
	var actor_after: Dictionary = forecast.units_after.get(actor_id, {})
	if not actor_before.is_empty() and not actor_after.is_empty():
		text += "Основные действия: %d → %d\n" % [actor_before.get("main", 0), actor_after.get("main", 0)]
	var before: Dictionary = forecast.units_before.get(target_id, {})
	var after: Dictionary = forecast.units_after.get(target_id, {})
	if not before.is_empty() and not after.is_empty():
		text += "%s: HP %.1f → %.1f\n" % [target_name, before.get("hp", 0.0), after.get("hp", 0.0)]
		text += "Элементальные статусы: %s → %s\n" % [BattleEventText.elemental_summary(before.get("elemental", {})), BattleEventText.elemental_summary(after.get("elemental", {}))]
		text += "Кровотечение: %s → %s\n" % [BattleEventText.bleeding_summary(before.get("bleeding", {})), BattleEventText.bleeding_summary(after.get("bleeding", {}))]
	if forecast.events.is_empty():
		text += "Событий последствий нет.\n"
	else:
		text += "\n[color=#a5b3c5]Последствия:[/color]\n"
		for event_index in event_lines.size(): text += "• " + event_lines[event_index] + "\n"
	return text

static func card(
	forecast: ForecastSimulation, card_name: String, target_text: String, card_id: int,
	mana: ManaTextValues, event_lines: PackedStringArray, tactical_mode: bool
) -> String:
	var text := "[font_size=16][color=#f7c97d]%s → %s[/color][/font_size]\n" % [card_name, target_text]
	if forecast.status != ActionReceipt.APPLIED:
		return text + "Прогноз недоступен: " + reason_text(forecast.reason, tactical_mode)
	if mana == null or not mana.valid:
		return text + "Прогноз недоступен: данные маны повреждены."
	text += "Мана %d → %d · карта #%d уйдёт в сыгранные.\n" % [mana.before, mana.after, card_id]
	for event_index in event_lines.size(): text += "• " + event_lines[event_index] + "\n"
	return text

static func environment(forecast: ForecastSimulation, pending: bool, names: Dictionary[int, String], event_lines: PackedStringArray, tactical_mode: bool) -> String:
	var text := "[font_size=16][color=#f7c97d]Фаза окружения[/color][/font_size]\nЕсли она начнётся при нынешней расстановке. Будущие действия могут изменить результат.\n\n"
	if pending:
		return text + "Рассчитываем последствия…"
	if forecast.status != ActionReceipt.APPLIED:
		return text + "Прогноз недоступен: " + reason_text(forecast.reason, tactical_mode)
	for event_index in event_lines.size(): text += event_lines[event_index] + "\n"
	for id: int in forecast.units_after:
		if forecast.units_before[id].alive and not forecast.units_after[id].alive:
			text += "[color=#f29b9b]%s: погибнет в пропасти.[/color]\n" % _name_for(names, id)
	return text

static func turn(forecast: TurnForecast, pending: bool, names: Dictionary[int, String], event_lines: PackedStringArray, tactical_mode: bool) -> String:
	var text := "[font_size=16][color=#f7c97d]Завершение командного хода[/color][/font_size]\nДо первого действия противника.\n"
	if pending:
		return text + "Рассчитываем последствия перехода…"
	if forecast.status != ActionReceipt.APPLIED:
		return text + "[color=#f29b9b]Прогноз недоступен[/color]\n" + reason_text(forecast.reason, tactical_mode)
	var phases := {
		BattleTacticalSession.Phase.ENEMY_TURN: "Начнётся ход противника.",
		BattleTacticalSession.Phase.VICTORY: "Победа до действий противника.",
		BattleTacticalSession.Phase.DEFEAT: "Поражение до действий противника.",
		BattleTacticalSession.Phase.MUTUAL_DESTRUCTION: "Обе команды погибнут. Бой завершится.",
	}
	text += "[color=#f7c97d]%s[/color]\n" % phases.get(forecast.phase_after, "Переход завершён.")
	for event_line: String in event_lines:
		text += event_line + "\n"
	var ids: Array = forecast.units_before.keys()
	ids.sort()
	for id: int in ids:
		var before: Dictionary = forecast.units_before[id]
		var after: Dictionary = forecast.units_after.get(id, {})
		if after.is_empty(): continue
		var changes: PackedStringArray = []
		for pair: Array in [["hp", "HP"], ["armor_current", "Броня"], ["main", "Основные"], ["bonus", "Бонусные"], ["move", "Движение"]]:
			var key: String = pair[0]
			if before.has(key) and after.has(key) and before[key] != after[key]: changes.append("%s: %s → %s" % [pair[1], str(before[key]), str(after[key])])
		if before.get("alive", true) and not after.get("alive", true): changes.append("Погибнет")
		if before.get("guard_stance", false) != after.get("guard_stance", false): changes.append("Охранная стойка снята" if not after.guard_stance else "Охранная стойка включена")
		if before.get("pending", false) and not after.get("pending", false): changes.append("Помощник готов действовать")
		if before.get("bleeding", {}) != after.get("bleeding", {}):
			var bleeding_before := BattleEventText.bleeding_summary(before.get("bleeding", {}))
			var bleeding_after := BattleEventText.bleeding_summary(after.get("bleeding", {}))
			changes.append("Кровотечение: %s → %s" % [bleeding_before, bleeding_after])
		if before.get("elemental", {}) != after.get("elemental", {}):
			var status_before := BattleEventText.elemental_summary(before.get("elemental", {}))
			var status_after := BattleEventText.elemental_summary(after.get("elemental", {}))
			changes.append("Статусы: %s → %s" % [status_before, status_after])
		for entry: Array in [["control", "stunned_turns", "Оглушение, ходов"], ["control", "entangled_turns", "Путы, ходов"], ["combat_perks", "reaction_left", "Общий заряд реакции"]]:
			var old_value: int = before.get(entry[0], {}).get(entry[1], 0)
			var new_value: int = after.get(entry[0], {}).get(entry[1], 0)
			if old_value != new_value: changes.append("%s: %d → %d" % [entry[2], old_value, new_value])
		if before.get("combat_perks", {}).get("movement_stopped", false) and not after.get("combat_perks", {}).get("movement_stopped", false): changes.append("Остановка движения снята")
		if not changes.is_empty(): text += "\n[color=#f7c97d]%s[/color]\n%s\n" % [before.get("name", _name_for(names, id)), "\n".join(changes)]
	return text

static func _name_for(names: Dictionary[int, String], id: int) -> String:
	return names.get(id, "Окружение")
