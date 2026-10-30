extends RefCounted
class_name BattleActionDescriptors

static func build(
	session: BattleDemoSession,
	battle: BattleTacticalSession,
	locked: bool,
	environment_mode: bool,
	reason_text: Callable
) -> Array[Dictionary]:
	# Runtime читается синхронно только под guard вызывающего _refresh; ссылки не удерживаются, кэша нет.
	var descriptors: Array[Dictionary] = []
	if session is BattleCoreReactionsSession and WarriorKit.enabled(session.selected_unit()):
		for id: StringName in [WarriorKit.CLEAVE, WarriorKit.KICK]:
			var reason := (session as BattleCoreReactionsSession).warrior_reason(id)
			var kick := id == WarriorKit.KICK
			descriptors.append({"action_id": id, "label": "Пинок ногой" if kick else "Рассекающий удар",
				"cost": "1 дополнительное · без отката" if kick else "1 основное · откат 1",
				"disabled": locked or reason != &"",
				"tooltip": ("Соседняя цель: базовый физический урон 2 × Мощь; урон балансу Мощь / 4. Оружие не прибавляется." if kick else "Обычный удар по соседней цели и 1 стак кровотечения, даже через броню. Иммунитет сохраняется. Откат: пропуск следующего своего хода.") + ("\n" + String(reason_text.call(reason)) if reason != &"" else "")})
	var healing_item := battle.healing_item() if battle != null else null
	var healing_reason := battle.healing_hint_reason() if battle != null else &"battle/input_locked"
	descriptors.append(item(healing_item, &"healing_item", healing_reason, reason_text))
	var seal := battle.summoning_item() if battle != null else null
	if session is BattleArmorSession:
		var reason := (session as BattleArmorSession).restore_armor_reason()
		descriptors.append({
			"action_id": &"restore_armor",
			"label": "Броня +20",
			"cost": "1 основное",
			"disabled": reason != &"",
			"tooltip": (
				"Восстановить 20 брони по недостаче вещей. "
				+ "Избыток становится временной бронёй до конца боя.\n"
				+ (
					String(reason_text.call(reason))
					if reason != &""
					else "Стойка сохраняется."
				)
			),
		})
	elif seal != null:
		var reason := battle.summoning_hint_reason()
		descriptors.append(item(seal, &"summoning_item", reason, reason_text))
	if (
		session is BattleBleedingSession
		and (
			not session is BattleCoreReactionsSession
			or (session as BattleCoreReactionsSession).allows_loadout_action(&"blood_rune")
		)
	):
		descriptors.append({
			"action_id": &"blood_rune",
			"label": "Кровавая руна",
			"cost": "Перк · 1 основное",
			"disabled": locked or session.selected_unit() == null or not session.selected_unit().can_attack(),
			"tooltip": (
				"Перк персонажа «Кровавая руна»: эта атака накладывает кровотечение "
				+ "даже без физического урона HP. Иммунитет сохраняется. "
				+ (
					"Добавляет стак урона и обновляет срок до 3 тиков; 1 за стак "
					+ "в начале хода, 2 за клетку, с учётом естественной защиты."
					if session is BattleCoreReactionsSession
					else "Каждое успешное наложение добавляет 2 тика по 4 с учётом естественной защиты."
				)
			),
		})
	if environment_mode and session is BattleEnvironmentSession:
		var raise_reason := (session as BattleEnvironmentSession).raise_hint_reason()
		descriptors.append({
			"action_id": &"raise_corpse",
			"label": "Поднять тело",
			"cost": "1 основное",
			"disabled": locked or raise_reason != &"",
			"tooltip": (
				"Выберите соседнюю свободную клетку без шипов той же высоты. "
				+ "Помощник: 16 HP, действует со следующего хода команды.\n"
				+ (
					String(reason_text.call(raise_reason))
					if raise_reason != &""
					else "Тело расходуется после успешного поднятия."
				)
			),
		})
	if (
		session is BattleCoreCombinationSession
		and (
			not session is BattleCoreReactionsSession
			or (session as BattleCoreReactionsSession).allows_loadout_action(&"entangling_strike")
		)
	):
		descriptors.append({
			"action_id": &"entangling_strike",
			"label": "Опутывающий удар",
			"cost": "1 основное",
			"disabled": (
				locked
				or session.selected_unit() == null
				or not session.selected_unit().can_attack()
				or ControlRules.action_reason(session.selected_unit()) != &""
			),
			"tooltip": (
				"Обычный урон и толчок, затем путы при физическом HP-уроне. "
				+ "Без кровотечения. Движение цели запрещено до конца её ближайшего "
				+ "хода; следующий фактический толчок снимает путы. Повтор не накапливает срок."
			),
		})
		descriptors.append(item(seal, &"summoning_item", battle.summoning_hint_reason(), reason_text))
	if (
		battle != null
		and session.selected_unit() != null
		and session.selected_unit().armor != null
		and not session.selected_unit().armor.raised_shield.is_empty()
	):
		var shield_reason := battle.raise_shields_reason()
		descriptors.append({
			"action_id": &"raise_shields",
			"label": "Поднять щиты",
			"cost": "1 основное · откат 1",
			"disabled": locked or shield_reason != &"",
			"tooltip": (
				"Блокирует 90% прямого урона первой атаки до начала следующего своего хода. "
				+ "Все попадания этой атаки; движение и Оппортунист сохраняют защиту. "
				+ "Не защищает от тиков, падения и контроля.\n"
				+ (
					String(reason_text.call(shield_reason))
					if shield_reason != &""
					else "Следующий свой ход недоступно, затем можно повторить."
				)
			),
		})
	if (
		session is BattleCoreReactionsSession
		and session.selected_unit() != null
		and session.selected_unit().combat_perks != null
		and session.selected_unit().combat_perks.definition.tank_reactions
	):
		var reaction_session := session as BattleCoreReactionsSession
		var opportunity_reason := reaction_session.reaction_reason(CombatPerksState.Mode.OPPORTUNIST)
		var eligible_cover_targets := reaction_session.cover_targets()
		var cover_reason := cover_choice_reason(reaction_session, eligible_cover_targets)
		descriptors.append({
			"action_id": &"opportunity_guard",
			"label": "Оппортунист",
			"cost": "1 основное",
			"disabled": locked or opportunity_reason != &"",
			"tooltip": (
				"До следующего пополнения своей команды останавливать врага, "
				+ "покидающего вашу угрозу. Каждое срабатывание прекращает его "
				+ "перемещение и расходует 1 дополнительное действие.\n"
				+ (
					String(reason_text.call(opportunity_reason))
					if opportunity_reason != &""
					else "Наведение показывает прогноз. Клик ставит режим за 1 основное действие."
				)
			),
		})
		descriptors.append({
			"action_id": &"cover_guard",
			"label": "Прикрытие",
			"cost": "1 основное",
			"disabled": locked or cover_reason != &"",
			"tooltip": (
				"Выберите соседнего союзника с допустимой геометрией. Каждое "
				+ "прикрытое прямое попадание снижается на 30% по всем компонентам "
				+ "до брони. Нужна стойка; каждое срабатывание расходует 1 дополнительное действие.\n"
				+ (
					String(reason_text.call(cover_reason))
					if cover_reason != &""
					else "Клик — выбор союзника."
				)
			),
		})
	if (
		session is BattleCoreReactionsSession
		and session.selected_unit() != null
		and ControlRules.has_stunning_strike(session.selected_unit())
	):
		var stun_actor := session.selected_unit()
		var stun_reason := ControlRules.action_reason(stun_actor)
		if locked: stun_reason = &"battle/input_locked"
		elif not stun_actor.can_attack(): stun_reason = &"attack/insufficient_main"
		descriptors.append({
			"action_id": &"stunning_strike",
			"label": "Оглушающий удар",
			"cost": "Перк · 1 основное",
			"disabled": stun_reason != &"",
			"tooltip": (
				"Обычные урон, крит и толчок; оглушение накладывается после "
				+ "положительного физического урона HP. Без кровотечения. "
				+ "Иммунитет цели пропускает только оглушение.\n"
				+ (
					String(reason_text.call(stun_reason))
					if stun_reason != &""
					else "Клик — выбрать цель; плата происходит после проверки владения и допуска."
				)
			),
		})
	if (
		session is BattleCoreReactionsSession
		and MeleeThreat.has_counterattack(session.selected_unit())
	):
		var counter_reason := (session as BattleCoreReactionsSession).reaction_reason(
			CombatPerksState.Mode.COUNTERATTACK
		)
		if locked: counter_reason = &"battle/input_locked"
		descriptors.append({
			"action_id": &"counterattack_guard",
			"label": "Контратака",
			"cost": "Перк · 1 основное",
			"disabled": counter_reason != &"",
			"tooltip": (
				"Охранная стойка сохраняется. После прямого ближнего удара по вам "
				+ "последует один ответный удар без толчка; по замороженной цели — "
				+ "крит. Расходуется 1 дополнительное действие.\n"
				+ (
					String(reason_text.call(counter_reason))
					if counter_reason != &""
					else "Наведение показывает полный прогноз стойки. Клик включает режим за 1 основное действие."
				)
			),
		})
	if session is BattleCoreReactionsSession:
		var retreat_reason := (session as BattleCoreReactionsSession).retreat_reason()
		descriptors.append({
			"action_id": &"safe_retreat",
			"label": "Безопасный отход",
			"cost": "1 основное + движение",
			"disabled": locked or retreat_reason != &"",
			"tooltip": (
				"Один маршрут без перехвата Оппортунистом. Контроль и опасности "
				+ "сохраняются. Основное списывается с первым сегментом, движение — "
				+ "за пройденный путь.\n"
				+ (
					String(reason_text.call(retreat_reason))
					if retreat_reason != &""
					else "Выберите клетку; наведение покажет последствия."
				)
			),
		})
	# Новые действия дополняют список, сохраняя прежние клавиши и страницы.
	if session is BattleCoreReactionsSession and session.selected_unit() != null:
		var reaction_session := session as BattleCoreReactionsSession
		var burning_rule := (
			"Огонь 4 урона; крит ×2 по замороженной цели. Без толчка. "
			+ "Требуется положительный огненный урон HP."
		)
		if (
			session.selected_unit().combat_perks != null
			and session.selected_unit().combat_perks.definition.burning_bypass_hp_gate
		):
			burning_rule = (
				"Огонь 4 урона; крит ×2 по замороженной цели. Без толчка. "
				+ "Перк позволяет наложить горение без положительного огненного урона HP."
			)
		var abilities: Array = [
			[&"elemental_burning", &"burning", "Поджечь", burning_rule],
			[
				&"elemental_wet",
				&"wet",
				"Облить",
				"Мокрый на 3 своих хода; снимает горение и защищает от "
				+ "одного наложения горения. Без урона.",
			],
			[
				&"elemental_freeze",
				&"freeze",
				"Заморозить",
				"Мокрую цель замораживает только при броне ниже 50% максимума; "
				+ "сухую сначала делает мокрой. Замороженную можно продлить при том же "
				+ "пороге. Без урона.",
			],
		]
		for ability: Array in abilities:
			var reason := reaction_session.cast_reason(ability[1])
			descriptors.append({
				"action_id": ability[0],
				"label": ability[2],
				"cost": "1 основное",
				"disabled": locked or reason != &"",
				"tooltip": (
					"Дальность: 3 клетки. "
					+ String(ability[3])
					+ "\n"
					+ (
						String(reason_text.call(reason))
						if reason != &""
						else "Клик — выбрать цель; расход после проверки цели."
					)
				),
			})
	return descriptors

static func item(
	item_instance: ItemInstance,
	action_id: StringName,
	reason: StringName,
	reason_text: Callable
) -> Dictionary:
	if item_instance == null:
		return {
			"label": "—",
			"disabled": true,
		}
	var action := item_instance.get_use_action()
	if action == null:
		return {
			"action_id": action_id,
			"label": item_instance.get_definition().display_name,
			"disabled": true,
			"tooltip": String(reason_text.call(&"item/not_usable")),
		}
	var detail := ""
	var ready := ""
	match action.get_target_mode():
		ItemUseAction.TargetMode.SELF:
			detail = "Лечение себя до +%s HP; %s.\n" % [
				String.num(action.get_heal_amount()).trim_suffix(".0"),
				BattleInspectionText.item_cost_text(action),
			]
			ready = "Стойка сохраняется."
		ItemUseAction.TargetMode.ADJACENT_CELL:
			detail = (
				"Помощник: %s HP, действует со следующего хода команды. Один на владельца, "
				+ "до гибели или конца боя. %s.\n"
			) % [
				BattleInspectionText.summon_hp_text(item_instance),
				BattleInspectionText.item_cost_text(action),
			]
			ready = "Выберите соседнюю свободную безопасную клетку той же высоты."
	return {
		"action_id": action_id,
		"label": "%s %d/%d" % [
			item_instance.get_definition().display_name,
			item_instance.get_charges_left(),
			action.get_max_charges(),
		],
		"cost": "%d основное" % action.get_main_cost(),
		"disabled": reason != &"",
		"tooltip": detail + (
			String(reason_text.call(reason))
			if reason != &""
			else ready
		),
	}

static func cover_choice_reason(
	reaction_session: BattleCoreReactionsSession,
	targets: Array[int]
) -> StringName:
	var reason := reaction_session.reaction_reason(CombatPerksState.Mode.COVER)
	for target: int in targets:
		reason = reaction_session.reaction_reason(CombatPerksState.Mode.COVER, target)
		if reason == &"": return reason
	return reason
