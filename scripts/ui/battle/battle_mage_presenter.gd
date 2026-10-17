extends RefCounted
class_name BattleMagePresenter

# Вызывается синхронно под guard Demo: runtime и callbacks здесь не удерживаются.
static func refresh_spells(
	mage_session: BattleCoreReactionsSession,
	row: Control,
	label: Label,
	buttons: Dictionary,
	effect_label: Callable,
	spell_help: Callable,
	reason_text: Callable
) -> void:
	var ability := mage_session.state.abilities
	label.text = "Маг · мана %d/%d" % [ability.mana, ability.maximum]
	label.tooltip_text = (
		"Откаты: длительность: огонь %d, лечение %d · осталось: огонь %d, лечение %d"
		% [
			ability.definition(&"mage.fire").cooldown_turns,
			ability.definition(&"mage.heal").cooldown_turns,
			ability.remaining(&"mage.fire"),
			ability.remaining(&"mage.heal")
		]
	)
	var available_buttons: Array[Button] = []
	for id: StringName in buttons:
		var button: Button = buttons[id]
		var definition := ability.definition(id)
		# В панели видимостью управляет pager только при смене фильтра или страницы,
		# иначе сброс между кадрами отменит удерживаемое нажатие.
		if not (row is BattleMageBar): button.visible = definition != null
		var reason := mage_session.mage_reason(id)
		button.disabled = reason != &""
		if definition == null: continue
		available_buttons.append(button)
		button.tooltip_text = (
			"%s · %d маны · откат %d, осталось %d\n%s"
			% [
				effect_label.call(id),
				definition.mana_cost,
				definition.cooldown_turns,
				ability.remaining(id),
				spell_help.call(id)
			]
		)
		if id == &"mage.test_poison":
			button.tooltip_text += "\nЖивой враг на доске, кроме ожидающего вступления помощника. Без затрат действий героя."
		elif AbilityDefinition.TEST_EFFECTS.has(id):
			button.tooltip_text += "\nТестовое заклинание: любая живая цель на доске, включая союзников. Без затрат действий героя."
		if reason != &"": button.tooltip_text += "\n" + reason_text.call(reason)
	if row is BattleMageBar:
		var bar := row as BattleMageBar
		bar.configure(available_buttons)
		bar.set_paging_enabled(true)

static func refresh_deck(
	mage_session: BattleCoreReactionsSession,
	row: Control,
	label: Label,
	buttons: Array[Button],
	confirm_button: Button,
	replace_button: Button,
	mulligan_ids: Array[int],
	selected_id: int,
	reason_text: Callable
) -> void:
	var deck := mage_session.state.deck
	var ability := mage_session.state.abilities
	if deck == null or ability == null: return
	var setup: bool = mage_session.is_deploying()
	var replacement: String = (
		"доступна"
		if deck.replaced_serial != ability.serials[0] and not deck.draw_ids.is_empty()
		else "использована или добор пуст"
	)
	if setup: replacement = "до двух стартовых карт" if not deck.mulligan_done else "стартовая подтверждена"
	label.text = (
		"Мана %d/%d · добор %d · сыграно %d · замена: %s"
		% [ability.mana, ability.maximum, deck.draw_ids.size(), deck.spent_ids.size(), replacement]
	)
	label.tooltip_text = "Рука %d/6" % deck.hand_ids.size()
	var shown: Array[Button] = []
	var ids: Array[int] = deck.hand_ids.duplicate()
	var reasons: Dictionary[int, StringName] = {}
	if not setup: reasons = mage_session.mage_card_reasons(ids)
	for slot: int in buttons.size():
		var button: Button = buttons[slot]
		if slot >= deck.hand_ids.size(): continue
		var id: int = deck.hand_ids[slot]
		var card := deck.card(id)
		var definition := MageCardCatalog.get_card(String(card.get("type_id", "")))
		if definition == null: continue
		shown.append(button)
		button.toggle_mode = setup and mage_session.mage_deployment_confirmed and not deck.mulligan_done
		button.set_pressed_no_signal(mulligan_ids.has(id) if button.toggle_mode else selected_id == id)
		button.text = "%s\n%d маны" % [definition.name, definition.mana_cost]
		button.tooltip_text = "%s\n%s\nКопия #%d" % [definition.name, definition.description, id]
		var reason: StringName = reasons.get(id, &"") if not setup else &""
		button.disabled = (
			not mage_session.mage_deployment_confirmed
			if setup
			else reason not in [&"", &"mage_card/insufficient_mana"]
		)
		if not setup and button.disabled: button.tooltip_text += "\n" + reason_text.call(reason)
		elif reason == &"mage_card/insufficient_mana": button.tooltip_text += "\nМаны для розыгрыша нет; заменить карту можно бесплатно."
	if setup:
		if mage_session.mage_deployment_confirmed and not deck.mulligan_done:
			confirm_button.text = (
				"Заменить %d/2 · начать" % mulligan_ids.size()
				if not mulligan_ids.is_empty()
				else "Пропустить · начать"
			)
			confirm_button.disabled = false
			shown.append(confirm_button)
	else:
		replace_button.text = "Заменить карту"
		replace_button.disabled = (
			selected_id == 0
			or deck.draw_ids.is_empty()
			or deck.replaced_serial == ability.serials[0]
			or not mage_session.can_player_act()
		)
		shown.append(replace_button)
	if row is BattleMageBar:
		var bar := row as BattleMageBar
		bar.configure(shown)
		bar.set_paging_enabled(true)
