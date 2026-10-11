extends RefCounted
class_name BattleEventText

static func format_event(event: Dictionary, names: Dictionary[int, String], core_reactions: bool, bleeding_mode: bool, item_label: String) -> String:
	var actor := _name_for(names, int(event.get("actor_unit_id", 0)))
	var target := _name_for(names, int(event.get("target_unit_id", 0)))
	match StringName(event.get("kind", &"")):
		&"bleeding_changed":
			var ticks: int = event["after"]["ticks_left"]
			if event["reason"] == &"burned": return "%s: кровотечение снято горением." % target
			if event["reason"] == &"tick" and bool(event["after"].get("stacked", false)):
				var tick_text := "срок истёк" if ticks == 0 else bleeding_summary(event["after"])
				return "%s: тик кровотечения; %s." % [target, tick_text]
			if event["reason"] == &"tick":
				var remaining := "срок истёк" if ticks == 0 else "осталось тиков: %d" % ticks
				return "%s: тик кровотечения; %s." % [target, remaining]
			var change := "наложено" if event["reason"] == &"applied" else "продлено"
			if not bool(event["after"].get("stacked", false)):
				return "%s: кровотечение %s — тиков: %d." % [target, change, ticks]
			return "%s: кровотечение %s — %s." % [target, change, bleeding_summary(event["after"])]
		&"elemental_changed":
			var after: Dictionary = event.get("after", {})
			var reason: StringName = event.get("reason", &"")
			var label := "Тик горения" if reason == &"burn_tick" else ("Истечение статусов" if reason == &"turn_end" else elemental_effect_label(reason))
			return "%s: %s — %s." % [target, label, elemental_summary(after)]
		&"trap_armed":
			return "Ловушка-шипы подготовлена на %s." % cell_name(event.get("cell", Vector2i(-1, -1)))
		&"trap_fired":
			var result := " по " + target if int(event.get("target_unit_id", 0)) > 0 else " вхолостую"
			return "Ловушка-шипы сработала%s на %s." % [result, cell_name(event.get("cell", Vector2i(-1, -1)))]
		&"mage_cast":
			return "Маг: %s → %s; мана %d → %d; откат %d." % [
				elemental_effect_label(StringName(event.spell_id)), target,
				event.mana_before, event.mana_after, event.cooldown_after,
			]
		&"mage_card_played":
			var definition := MageCardCatalog.get_card(String(event.type_id))
			var destination := cell_name(event.target_cell) if definition != null and definition.target_policy in ["valid_cell", "corpse_cell"] else target
			return "Маг разыграл «%s» (#%d) → %s; мана %d → %d." % [
				definition.name if definition != null else String(event.type_id),
				event.card_instance_id, destination, event.mana_before, event.mana_after,
			]
		&"deck_changed":
			return "Колода: %s; рука %d, добор %d, сыграно %d." % [
				String(event.reason), event.after.hand_ids.size(),
				event.after.draw_ids.size(), event.after.spent_ids.size(),
			]
		&"elemental_cast":
			return "%s применяет «%s» к %s; основные действия %d → %d." % [
				actor, elemental_effect_label(event.get("effect", &"")), target,
				int(event.get("main_before", 0)), int(event.get("main_after", 0)),
			]
		&"attacked":
			var suffix := ""
			var modifiers: Dictionary = event.get("modifiers", {})
			if int(modifiers.get("sneak_percent", 0)) == 50:
				var threats := ", ".join(names_for_ids(names, modifiers.get("threat_ids", [])))
				suffix += " Скрытая атака +50%% физической базы (угроза: %s)." % threats
			if int(modifiers.get("backstab_percent", 0)) > 0 and not core_reactions: suffix += " Удар в спину +%d%%." % modifiers["backstab_percent"]
			if modifiers.get("critical", false): suffix += " Крит ×2."
			return "%s атакует %s.%s" % [actor, target, suffix]
		&"reaction_used":
			var used_mode: int = int(event.get("mode", 0))
			var mode_name := "Прикрытие"
			if used_mode == CombatPerksState.Mode.OPPORTUNIST:
				mode_name = "Оппортунист"
			elif used_mode == CombatPerksState.Mode.COUNTERATTACK:
				mode_name = "Контратака"
			if event.has("bonus_before"):
				return "%s: режим «%s» срабатывает на %s; дополнительные действия %d → %d." % [
					actor, mode_name, target, int(event.bonus_before), int(event.bonus_after),
				]
			return "%s: режим «%s» срабатывает на %s; общий заряд реакции %d → %d." % [
				actor, mode_name, target, int(event.get("charge_before", 1)),
				int(event.get("charge_after", 0)),
			]
		&"opportunity_attacked":
			return "%s прерывает движение %s атакой Оппортуниста без основного действия." % [actor, target]
		&"counterattacked": return "%s контратакует %s без толчка." % [actor, target]
		&"control_changed":
			if event["reason"] == &"entangled":
				return "%s: наложены путы до конца ближайшего хода команды цели." % target
			if event["reason"] == &"refreshed": return "%s: путы сохранены; срок не накапливается." % target
			if event["reason"] == &"stunned": return "%s: оглушён до конца ближайшего хода команды цели." % target
			if event["reason"] == &"stun_refreshed": return "%s: оглушение сохранено; срок не накапливается." % target
			return "%s: путы сняты толчком." % target if event["reason"] == &"push" else "%s: срок состояния контроля истёк." % target
		&"guarded":
			var reaction_modes := [
				CombatPerksState.Mode.OPPORTUNIST,
				CombatPerksState.Mode.COVER,
				CombatPerksState.Mode.COUNTERATTACK,
			]
			if event.has("reaction_mode") and int(event["reaction_mode"]) in reaction_modes:
				var reaction_mode: int = int(event["reaction_mode"])
				var mode_name := "Оппортунист"
				if reaction_mode == CombatPerksState.Mode.COUNTERATTACK:
					mode_name = "Контратака"
				elif reaction_mode == CombatPerksState.Mode.COVER:
					mode_name = "Прикрытие → " + _name_for(names, int(event.get("cover_target_id", 0)))
				return "%s включает режим «%s» за 1 основное действие; запас для реакций не пополняется." % [actor, mode_name]
			return "%s занимает охранную стойку (1 основное действие)." % actor
		&"item_used":
			return "%s использует %s (%d основное; зарядов осталось: %d)." % [actor, item_label, int(event["main_cost"]), int(event["charges_after"])]
		&"summoned": return "%s призывает: %s. Действия со следующего хода команды." % [actor, target]
		&"mage_summoned":
			var action := "поднял тело" if int(event.corpse_id) > 0 else "призывает"
			var owner_text := ""
			if int(event.owner_unit_id) != 0:
				owner_text = "Владелец — %s; " % _name_for(names, int(event.owner_unit_id))
			return "Маг %s: %s. %sДействия со следующего хода команды." % [action, target, owner_text]
		&"corpse_created": return "Тело: %s, гуманоид." % cell_name(event["corpse"]["cell"])
		&"support_collapsed": return "Обвал: %s стала пропастью." % cell_name(event["cell"])
		&"environment_turn":
			var threat_text := "новых угроз нет."
			if not event["marked"].is_empty():
				threat_text = "%s обрушится в следующую фазу окружения." % cell_name(event["marked"][0])
			return "Окружение %d: %s" % [event["turn"], threat_text]
		&"corpse_raised": return "%s поднял тело: %s (16 HP), ожидает следующего хода." % [actor, target]
		&"damaged":
			var source: Dictionary = event.get("source", {})
			var cause := ""
			if source.get("kind", &"") == &"fall":
				cause = " от падения"
			elif bleeding_mode and source.get("kind", &"") == &"status":
				cause = " от эффекта"
			elif source.get("kind", &"") == &"cell":
				cause = " от шипов (8)"
			return "%s: −%.1f HP%s." % [target, float(event.get("amount", 0)), cause]
		&"healed":
			var heal_source: StringName = event.get("source", {}).get("kind", &"")
			var heal_cause := " от предмета"
			if heal_source == &"cell":
				heal_cause = " от сопротивления урону шипов"
			elif heal_source in [&"attack", &"collision", &"fall"] or (bleeding_mode and heal_source == &"status"):
				heal_cause = " от сопротивления"
			elif heal_source == &"mage":
				heal_cause = " от мага"
			return "%s: +%.1f HP%s." % [target, float(event.get("amount", 0)), heal_cause]
		&"armor_changed": return "%s: запас брони изменился." % target
		&"hit_resolved":
			var shattered := " · добивание замороженной цели" if event["hit"].get("shattered", false) else ""
			return "%s: попадание завершено, HP %d → %d%s." % [
				target, event["hit"]["hp_before"], event["hit"]["hp_after"], shattered,
			]
		&"balance_changed":
			var balance_text := BattleBalanceDisplay.value_text(
				float(event.get("balance_after", 0)),
				float(event.get("balance_max", 0)),
			)
			return "%s: равновесие %s." % [target, balance_text]
		&"balance_broken": return "%s теряет равновесие; запас после пробоя восстановлен." % target
		&"moved":
			var pushed: bool = event.get("movement_kind", &"") == &"push"
			if event.get("movement_kind", &"") == &"safe_retreat":
				return "%s отходит: %s → %s · %d основное, %.1f движения." % [
					actor, cell_name(event["from_cell"]), cell_name(event["to_cell"]),
					int(event.get("main_cost", 0)), float(event["move_cost"]),
				]
			return "%s %s %s → %s." % [target if pushed else actor, "отброшен:" if pushed else "идёт:", cell_name(event["from_cell"]), cell_name(event["to_cell"])]
		&"push_blocked": return "%s врезается в препятствие." % target
		&"chain_link":
			var result := "равновесие потеряно" if event.get("broke", false) else "цепь остановлена"
			return "Цепь: %s → %s, сила %s — %s." % [
				_name_for(names, int(event.get("from_unit_id", 0))), target,
				str(event.get("impulse", 0.0)), result,
			]
		&"collision": return "%s сталкивается с %s." % [target, _name_for(names, int(event.get("blocker_unit_id", 0)))]
		&"fell": return "%s падает с уступа." % target
		&"died": return "%s погиб. Клетка свободна." % target
	return "%s: %s" % [target, String(event.get("kind", "событие"))]

static func _name_for(names: Dictionary[int, String], id: int) -> String:
	return names.get(id, "Окружение")

static func names_for_ids(names: Dictionary[int, String], ids: Array) -> PackedStringArray:
	var result: PackedStringArray = []
	for id: Variant in ids:
		if typeof(id) == TYPE_INT: result.append(_name_for(names, id))
	return result

static func cell_name(cell: Vector2i) -> String:
	return String.chr(65 + cell.x) + str(cell.y + 1)

static func elemental_effect_label(effect: StringName) -> String:
	match effect:
		&"mage.test_burning": return "Поджог"
		&"mage.test_wet": return "Вода"
		&"mage.test_freeze": return "Заморозка"
		&"mage.test_stun": return "Оглушение"
		&"mage.test_roots": return "Корни"
		&"mage.test_bleeding": return "Кровотечение"
		&"mage.test_heal": return "Тест: лечение"
		&"mage.test_summon": return "Тест: призыв"
		&"mage.shield": return "Щит · 6 HP"
		&"mage.test_raise": return "Тест: поднятие"
	if effect == &"mage.fire": return "Огненный импульс"
	if effect == &"mage.heal": return "Лечение мага"
	match effect:
		&"burning": return "Поджечь"
		&"wet": return "Облить"
		&"freeze": return "Заморозить"
	return "Элементальное действие"

static func elemental_summary(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY: return "нет"
	var data: Dictionary = value
	var parts: PackedStringArray = []
	if int(data.get("burning_stacks", 0)) > 0: parts.append("горение %d ст. / %d т." % [data["burning_stacks"], data["burning_ticks"]])
	if int(data.get("wet_turns", 0)) > 0: parts.append("мокрый %d х." % data["wet_turns"])
	if int(data.get("frozen_turns", 0)) > 0: parts.append("заморозка %d х." % data["frozen_turns"])
	if int(data.get("acid_ticks", 0)) > 0: parts.append("В кислоте · %d ход." % int(data["acid_ticks"]))
	if parts.is_empty(): return "нет"
	return ", ".join(parts)

static func bleeding_summary(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY: return "нет"
	var data: Dictionary = value
	var ticks: int = int(data.get("ticks_left", 0))
	if ticks <= 0: return "нет"
	if bool(data.get("stacked", false)):
		var stacks: int = int(data.get("stacks", 0))
		var movement_damage := str(stacks * BleedingState.MOVE_DAMAGE) if stacks <= 4611686018427387903 else "за пределом расчёта"
		return "%d ст. · %d т. · %d/тик · %s/клетку" % [stacks, ticks, stacks, movement_damage]
	return "%d т. · 4/тик" % ticks
