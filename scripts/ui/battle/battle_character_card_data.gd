extends RefCounted
class_name BattleCharacterCardData

# Сборка синхронна: за границу UI уходят значения и ресурс портрета, не runtime.
static func live(unit: UnitState, state: ItemSimulationState, loadout: Dictionary, options: BattleInspectionText.Options) -> Dictionary:
	var armor: Dictionary = ArmorRuntime.totals(ArmorRuntime.capture(state.get_owner(unit.id))) if unit.armor != null else {}
	var row := {
		"id": unit.id, "name": unit.debug_name, "faction": int(unit.faction), "alive": unit.is_alive(),
		"hp": unit.vitals.get_hp(), "hp_max": unit.get_stat(StatTypes.StatType.HP_MAX),
		"balance": unit.vitals.get_balance(), "balance_max": ControlRules.balance_maximum(unit, unit.get_stat(StatTypes.StatType.BALANCE_MAX)),
		"armor": armor, "main": unit.action_resources.get_main_left(), "bonus": unit.action_resources.get_bonus_left(),
		"move": unit.move_points_left, "guard": unit.guard_stance, "pending": state.is_summon_pending(unit.id),
		"control": unit.control.to_dict() if unit.control != null else {},
		"elemental": unit.elemental.to_dict() if unit.elemental != null else {},
		"bleeding": unit.bleeding.to_dict() if unit.bleeding != null else {},
		"shield": unit.armor.shield if unit.armor != null else {},
		"raised_shield": unit.armor.raised_shield if unit.armor != null else {},
		"reaction_view": ActionPresentationState.capture_reaction_view(state, unit),
	}
	var class_id := StringName(loadout.get("class_id", &""))
	var definition := HeroCatalog.class_definition(class_id) if class_id != &"" else null
	var is_troglodyte := unit.archetype_id == &"tamed_troglodyte" or class_id == &"tamed_troglodyte"
	var identity := {
		"class_label": "Прирученный троглодит" if is_troglodyte else (definition.display_name if definition != null else ("Помощник" if state.is_summon(unit.id) else "Боец")),
		"is_troglodyte": is_troglodyte,
		"portrait": HubSkeletonCard.hero_texture(class_id, StringName(loadout.get("skin_id", &""))) if class_id != &"" else null,
	}
	var data := frame(row, identity)
	data.published = false
	var attributes: PackedStringArray = []
	for type: StatTypes.StatType in [StatTypes.StatType.POWER, StatTypes.StatType.DEXTERITY, StatTypes.StatType.ENDURANCE, StatTypes.StatType.INTELLECT, StatTypes.StatType.MASTERY]:
		attributes.append("%s  %s" % [StatTypes.to_display_name(type), _amount(unit.get_stat(type)) if unit.stats.has_stat(type) else "—"])
	attributes.append("Оружие  %s  ·  Дальность  %s" % [_amount(unit.get_stat(StatTypes.StatType.WEAPON_DAMAGE)), _amount(unit.get_stat(StatTypes.StatType.ATTACK_RANGE))])
	data.attributes_text = "\n".join(attributes)
	var details: PackedStringArray = []
	if is_troglodyte:
		details.append("Плотный воин ближнего боя")
		details.append("Толстая кожа — прямой урон меньше на 2 (один раз за попадание); не действует на периодический урон, падения и ловушки.")
		details.append("Каннибализм — 1 основное действие; пожирает свежий труп на своей или соседней по стороне клетке, восстанавливая 50% недостающего здоровья. Кости не подходят.")
	var owner := state.get_owner(unit.id)
	if owner != null:
		for item: ItemInstance in owner._items.values():
			if item.is_active(): details.append(item.get_definition().display_name)
	var properties := BattleInspectionText._control_text(unit, options).strip_edges()
	if not properties.is_empty(): details.append(properties)
	details.append_array(BattleInspectionText._item_descriptions(unit, state, options))
	data.details_text = "\n\n".join(details) if not details.is_empty() else "Нет снаряжения и дополнительных свойств."
	return data

static func frame(row: Dictionary, identity: Dictionary) -> Dictionary:
	if row.is_empty(): return {}
	var is_troglodyte := bool(identity.get("is_troglodyte", identity.get("class_label", "") == "Прирученный троглодит"))
	var hp := float(row.get("hp", 0.0))
	var maximum := float(row.get("hp_max", 0.0))
	var armor: Dictionary = row.get("armor", {})
	var armor_current := float(armor.get("current", 0.0))
	var armor_maximum := float(armor.get("maximum", 0.0))
	var extra := float(armor.get("extra", 0.0))
	# maximum описывает предметную броню; временный запас входит только в current.
	var armor_capacity := armor_maximum + extra
	var balance := float(row.get("balance", 0.0))
	var balance_max := float(row.get("balance_max", 0.0))
	var entries := BattleStatusPresentation.entries(row)
	var extra_statuses := _extra_statuses(row)
	var statuses := BattleStatusPresentation.details(entries) if not entries.is_empty() else ""
	var status_bbcode := BattleStatusPresentation.details_bbcode(entries, 32) if not entries.is_empty() else ""
	for extra_status: Dictionary in extra_statuses:
		statuses += "\n" + String(extra_status.title)
		if not status_bbcode.is_empty(): status_bbcode += "\n"
		var icon_id: StringName = extra_status.id
		status_bbcode += (BattleConditionIcons.bbcode(icon_id, 32) + " " if icon_id != &"" else "") + "[color=#e0ddcb]%s[/color]" % BattleStatusPresentation.escape_bbcode(extra_status.title)
	var reaction: Dictionary = row.get("reaction_view", {})
	var reaction_id := BattleConditionPresentation.reaction_icon(reaction)
	if reaction_id != &"":
		var reaction_text := BattleReactionPresentation.mode_name(int(reaction.get("mode", 0))) + (" · готова" if bool(reaction.get("ready", false)) else " · не готова")
		statuses += "\n" + reaction_text
		status_bbcode += ("\n" if not status_bbcode.is_empty() else "") + BattleConditionIcons.bbcode(reaction_id, 32) + " " + BattleStatusPresentation.escape_bbcode(reaction_text)
	if not bool(row.get("alive", true)):
		statuses = "Погиб\n" + statuses
		status_bbcode = BattleConditionIcons.bbcode(&"corpse", 32) + " [color=#e0ddcb]Погиб[/color]" + ("\n" + status_bbcode if not status_bbcode.is_empty() else "")
	statuses = statuses.strip_edges()
	if statuses.is_empty():
		statuses = "Состояний нет."
		status_bbcode = BattleStatusPresentation.escape_bbcode(statuses)
	if is_troglodyte:
		var thick_skin := "Толстая кожа — прямой урон меньше на 2 (один раз за попадание); не действует на периодический урон, падения и ловушки."
		var cannibalism := "Каннибализм — 1 основное действие; пожирает свежий труп на своей или соседней по стороне клетке, восстанавливая 50% недостающего здоровья. Кости не подходят."
		statuses += "\n" + thick_skin + "\n" + cannibalism
		status_bbcode += "\n[img=32x32]res://assets/ui/abilities/troglodyte_thick_skin.svg[/img] [color=#e0ddcb]%s[/color]" % BattleStatusPresentation.escape_bbcode(thick_skin)
		status_bbcode += "\n[img=32x32]res://assets/ui/abilities/troglodyte_cannibalism.svg[/img] [color=#e0ddcb]%s[/color]" % BattleStatusPresentation.escape_bbcode(cannibalism)
	var details_text := "Снаряжение и свойства доступны после действия."
	if is_troglodyte:
		details_text = "Плотный воин ближнего боя\n\nТолстая кожа — прямой урон меньше на 2 (один раз за попадание); не действует на периодический урон, падения и ловушки.\n\nКаннибализм — 1 основное действие; пожирает свежий труп на своей или соседней по стороне клетке, восстанавливая 50% недостающего здоровья. Кости не подходят."
	return {
		"id": int(row.get("id", 0)), "name": String(row.get("name", "")),
		"class_label": String(identity.get("class_label", "Боец")), "portrait": identity.get("portrait"),
		"faction_label": "Союзник" if int(row.get("faction", 0)) == int(Faction.Type.PLAYER) else "Противник" if int(row.get("faction", 0)) == int(Faction.Type.ENEMY) else "Нейтральный",
		"hp_text": "%s / %s" % [_amount(hp), _amount(maximum)], "hp_ratio": _ratio(hp, maximum),
		"armor_text": "%s / %s" % [_amount(armor_current), _amount(armor_capacity)] + ("  (+%s врем.)" % _amount(extra) if extra > 0.0 else ""),
		"armor_ratio": _ratio(armor_current, armor_capacity),
		"balance_text": BattleBalanceDisplay.value_text(balance, balance_max), "balance_ratio": BattleBalanceDisplay.ratio(balance, balance_max),
		"actions_text": "Основное  %d   ·   Доп.  %d\nДвижение  %s" % [int(row.get("main", 0)), int(row.get("bonus", 0)), _amount(float(row.get("move", 0.0)))],
		"attributes_text": "Характеристики доступны после действия.", "status_text": statuses, "status_bbcode": status_bbcode,
		"details_text": details_text, "published": true,
	}

static func _extra_statuses(row: Dictionary) -> Array[Dictionary]:
	var extras: Array[Dictionary] = []
	if bool(row.get("guard", false)): extras.append({"id": &"", "title": "Охранная стойка"})
	if bool(row.get("pending", false)): extras.append({"id": &"pending", "title": "Действия со следующего хода команды"})
	if bool(row.get("raised_shield", {}).get("active", false)): extras.append({"id": &"raised_shield", "title": "Поднятые щиты: −90% первой атаки"})
	return extras

static func _amount(value: float) -> String:
	return BattleEventText.amount_text(value)

static func _ratio(value: float, maximum: float) -> float:
	return clampf(value / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
