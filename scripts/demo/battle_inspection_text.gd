extends RefCounted
class_name BattleInspectionText

# Для форматирования передаются только значения: builder не удерживает live runtime.
class Options extends RefCounted:
	var height_steps: int = 0
	var core_reactions: bool = false
	var control_mode: bool = false
	var bleeding_session: bool = false
	var summoning_supported: bool = true
	var cover_target_name: String = ""
	var summon_owner_name: String = ""

static func build_live(unit: UnitState, state: ItemSimulationState, options: Options) -> String:
	var text := _base_text(unit, options)
	var control_text := _control_text(unit, options)
	var piercing := unit.get_stat(StatTypes.StatType.PHYSICAL_PIERCING_PERCENT)
	if piercing > 0.0:
		text += "\nПробивание %.0f%% физической базы: броня обходится, естественная защита действует." % piercing
	if not control_text.is_empty(): text = text.insert(text.find("\n") + 1, control_text)
	if state.is_summon(unit.id):
		text += (
			"\nПомощник верховного мага: до гибели / конца боя."
			if state.is_mage_summon(unit.id)
			else "\nПомощник: до гибели / конца боя; владелец " + options.summon_owner_name
		)
		text += "\nДействия со следующего хода своей команды." if state.is_summon_pending(unit.id) else "\nГотов действовать."
	if unit.armor != null and not unit.armor.raised_shield.is_empty():
		text += "\nПоднять щиты: " + ("активно · −90% урона первой атаки" if unit.armor.raised_shield.active else "не активно")
	if unit.armor != null and not unit.armor.shield.is_empty():
		text += "\nЩит: %d HP · осталось попаданий: %d. Поглощает любой урон до защит и брони." % [int(unit.armor.shield.hp), int(unit.armor.shield.hits_left)]
	text = _append_status_and_armor(text, unit, state, options)
	var descriptions := _item_descriptions(unit, state, options)
	if unit.guard_stance:
		text += "\nОхранная стойка: прямой урон −30%, воздействие −50% до следующего хода команды; движение и атака снимают стойку."
	text += "\nЭффекты: " + ("нет активных." if descriptions.is_empty() else "\n" + "\n".join(descriptions))
	return text


static func _base_text(unit: UnitState, options: Options) -> String:
	var balance_text := BattleBalanceDisplay.value_text(
		unit.vitals.get_balance(),
		ControlRules.balance_maximum(unit, unit.get_stat(StatTypes.StatType.BALANCE_MAX)),
	)
	var text_template := (
		"%s · %s · высота %+.1f\nHP: %.1f / %.1f\nРавновесие: %s\n"
		+ "Движение: %.1f / %.1f · Основное: %d · Бонус: %d\n"
		+ "Броня: %.1f · Оружие: %.1f урона\nСила: %.1f · Воздействие: %.1f\n"
		+ "Атака: 1 основное · Дальность: %.1f"
	)
	var text := text_template % [
		unit.debug_name, BattleEventText.cell_name(unit.cell),
		float(options.height_steps) / 2.0, unit.vitals.get_hp(),
		unit.get_stat(StatTypes.StatType.HP_MAX), balance_text,
		unit.move_points_left, unit.get_stat(StatTypes.StatType.MOVE_RANGE),
		unit.action_resources.get_main_left(), unit.action_resources.get_bonus_left(),
		unit.get_stat(StatTypes.StatType.ARMOR),
		unit.get_stat(StatTypes.StatType.WEAPON_DAMAGE),
		unit.get_stat(StatTypes.StatType.STRENGTH),
		unit.get_stat(StatTypes.StatType.IMPACT_POWER),
		unit.get_stat(StatTypes.StatType.ATTACK_RANGE),
	]
	return text

static func _control_text(unit: UnitState, options: Options) -> String:
	var control_text := ""
	if options.core_reactions and unit.combat_perks != null:
		if unit.combat_perks.definition.sneak_attack:
			control_text += "Перк «Скрытая атака»: +50% физической базы, если цели угрожают минимум двое. Оружие ближнего боя любое.\n"
		if unit.combat_perks.definition.stunning_strike:
			control_text += "Перк «Оглушающий удар»: накладывает оглушение после положительного физического урона HP. Без кровотечения.\n"
		if unit.combat_perks.definition.burning_bypass_hp_gate: control_text += "Перк «Поджог»: горение накладывается без положительного огненного урона HP.\n"
		if unit.combat_perks.definition.counterattack:
			control_text += (
				"Перк «Контратака»: стойка отвечает одним ударом на прямую ближнюю атаку; "
				+ "без толчка, по замороженной цели — крит. Стойка сохраняется, "
				+ "тратится 1 дополнительное действие.\n"
			)
		if unit.combat_perks.definition.stun_immune: control_text += "Иммунитет к оглушению: полученный удар и толчок сохраняются.\n"
		if unit.combat_perks.definition.entangle_immune: control_text += "Иммунитет к путам: полученный удар и толчок сохраняются.\n"
		if MeleeThreat.has_reactions(unit):
			var mode_text := "Оппортунист (пассивный)" if MeleeThreat.has_passive_opportunist(unit) else "нет"
			if unit.combat_perks.mode == CombatPerksState.Mode.OPPORTUNIST: mode_text = "Оппортунист"
			elif unit.combat_perks.mode == CombatPerksState.Mode.COVER: mode_text = "Прикрытие: " + options.cover_target_name
			elif unit.combat_perks.mode == CombatPerksState.Mode.COUNTERATTACK: mode_text = "Контратака"
			control_text += "Режим реакции: %s · %s: %d. Восстановление в начале хода своей команды.\n" % [
				mode_text,
				"дополнительных действий" if unit.combat_perks.uses_bonus_actions else "общий заряд",
				MeleeThreat.reaction_points(unit),
			]
			if MeleeThreat.has_passive_opportunist(unit):
				control_text += (
					"Выход врага из ближней угрозы: удар и остановка за 1 дополнительное действие. "
					+ "Без включения стойки; безопасный отход и принудительное движение "
					+ "не вызывают реакцию.\n"
				)
		if unit.combat_perks.movement_stopped: control_text += "Движение остановлено Оппортунистом до следующего пополнения команды цели.\n"
	if options.control_mode and not options.core_reactions:
		var rear := AttackModifiers.rear_offset(unit.faction)
		if rear != Vector2i.ZERO: control_text += "Тыл: %s · соседняя клетка, +50%% базы\n" % BattleEventText.cell_name(unit.cell + rear)
	if unit.control != null:
		if unit.control.stunned_turns > 0: control_text += "Оглушён: добровольные действия недоступны; входящий крит ×2.\n"
		if unit.control.entangled_turns > 0:
			var maximum := ControlRules.balance_maximum(
				unit, unit.get_stat(StatTypes.StatType.BALANCE_MAX),
			)
			control_text += "Опутан: движение недоступно; максимум равновесия ×2 = %.1f.\nФактический толчок снимает путы; входящий крит ×2.\n" % maximum
		if unit.control.stunned_turns > 0 or unit.control.entangled_turns > 0: control_text += "Срок: до конца ближайшего хода этой команды.\n"
	return control_text

static func _append_status_and_armor(text: String, unit: UnitState, state: ItemSimulationState, options: Options) -> String:
	if unit.bleeding != null:
		var condition := "Кровотечение: тиков — %d · 4 до защиты" % unit.bleeding.ticks_left
		if options.bleeding_session and unit.faction == Faction.Type.PLAYER:
			condition += "\nПерк: Кровавая руна · атака клавишей 5"
		if unit.bleeding.stacked: condition = "Кровотечение: " + BattleEventText.bleeding_summary(unit.bleeding.to_dict())
		if unit.bleeding.immune: condition += "\nИммунитет к кровотечению"
		var first_line := text.find("\n")
		text = text.insert(first_line + 1, condition + "\n")
	if unit.elemental != null:
		var effects: PackedStringArray = []
		if unit.elemental.burning_stacks > 0:
			effects.append("Горение: %d ст. · %d тиков · %d огненного урона за тик" % [
				unit.elemental.burning_stacks, unit.elemental.burning_ticks,
				unit.elemental.burning_stacks,
			])
		if unit.elemental.wet_turns > 0: effects.append("Мокрый: %d своих ходов" % unit.elemental.wet_turns)
		if unit.elemental.frozen_turns > 0: effects.append("Заморожен: %d своих ходов · входящий удар критический" % unit.elemental.frozen_turns)
		if unit.elemental.freeze_immune: effects.append("Иммунитет к заморозке")
		if effects.is_empty(): effects.append("Элементальные статусы отсутствуют")
		var first_line := text.find("\n")
		text = text.insert(first_line + 1, "\n".join(effects) + "\n")
	if unit.armor != null:
		var armor := ArmorRuntime.totals(ArmorRuntime.capture(state.get_owner(unit.id)))
		if not armor.is_empty():
			text = text.replace(
				"Броня: %.1f" % unit.get_stat(StatTypes.StatType.ARMOR),
				"Броня: %d / %d (временная: %d)" % [
					armor["current"], armor["maximum"], armor["extra"],
				],
			)
	return text

static func _item_descriptions(unit: UnitState, state: ItemSimulationState, options: Options) -> Array[String]:
	var descriptions: Array[String] = []
	if state != null:
		var owner := state.get_owner(unit.id)
		if owner != null:
			for item: ItemInstance in owner._items.values():
				if not item.is_active(): continue
				var action := item.get_use_action()
				if action != null and action.get_target_mode() == ItemUseAction.TargetMode.ADJACENT_CELL:
					if not options.summoning_supported:
						descriptions.append("Печать: призыв недоступен в сценарии брони.")
					else:
						descriptions.append("Печать: помощник с %s HP за %s; осталось %d/%d. Один на владельца, действует со следующего хода команды, до гибели / конца боя." % [
							summon_hp_text(item), item_cost_text(action),
							item.get_charges_left(), action.get_max_charges(),
						])
				elif action != null:
					descriptions.append("%s: лечение себя до +%.1f HP за %s; осталось %d/%d. Стойка сохраняется." % [
						item.get_definition().display_name, action.get_heal_amount(),
						item_cost_text(action), item.get_charges_left(),
						action.get_max_charges(),
					])
				for effect in item.get_effects():
					if not effect.is_active(): continue
					if effect is HealOnDamageEffectRuntime:
						descriptions.append("Лечение +%.1f HP после урона; пока предмет активен." % (effect as HealOnDamageEffectRuntime).get_heal_amount())
					elif effect is StatModifierEffectRuntime:
						var modifier := effect as StatModifierEffectRuntime
						var amount := "%+.1f" % modifier.get_value()
						if modifier.get_stat_type() == StatTypes.StatType.PHYSICAL_PIERCING_PERCENT: amount += " п.п."
						if modifier.get_operation() == StatModifier.Operation.ADD_PERCENT: amount = "%+.1f%%" % (modifier.get_value() * 100.0)
						elif modifier.get_operation() == StatModifier.Operation.MULTIPLY: amount = "×%.2f" % modifier.get_value()
						descriptions.append("%s %s; пока предмет активен." % [stat_name(modifier.get_stat_type()), amount])
					else: descriptions.append("Неизвестный активный эффект; описание недоступно.")
	return descriptions

static func stat_name(type: StatTypes.StatType) -> String:
	var names := [
		"Макс. HP", "Инициатива", "Макс. равновесие", "Сила", "Воздействие",
		"Движение", "Броня", "Основные действия", "Бонусные действия",
		"Урон оружия", "Дальность атаки", "Пробивание физической базы",
	]
	return names[int(type)] if int(type) >= 0 and int(type) < names.size() else "Характеристика"

static func item_cost_text(action: ItemUseAction) -> String:
	return "%d основное и %d заряд" % [action.get_main_cost(), action.get_charge_cost()] if action != null else "применение недоступно"

static func summon_hp_text(item: ItemInstance) -> String:
	# Подсказка использует определение команды и не изменяет предмет.
	var action := item.get_use_action() if item != null else null
	var definition := action.get_summon_definition() if action != null else null
	var hp := definition.hp_max if definition != null else SummonDefinition.DEFAULT_HP_MAX
	return String.num(hp).trim_suffix(".0")
