extends Control
class_name HeroHubScreen

@export var save_path: String = "user://hero-hub-v1.save"

var run: HeroHubState
var selected_hero_id: int = 0
var pending_delta: Array[int] = [0, 0, 0, 0]
var battle_view: HeroHubBattleView
var _battle_bundle: Dictionary = {}
var _pending_save: HeroHubState
var _storage_error: String = ""
var _message: String = ""
var _root_panel: Control
var _content: VBoxContainer

func _ready() -> void:
	var save_existed := FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")
	var loaded := HeroHubStore.read_run(save_path)
	run = loaded.get("run") as HeroHubState
	_storage_error = String(loaded.get("error", ""))
	if run != null and not save_existed and _storage_error.is_empty():
		# Первый профиль сразу фиксируется, чтобы кандидаты и стартовый отряд не менялись после перезапуска.
		selected_hero_id = run.party[0] if not run.party.is_empty() else 0
		_commit(run)
		return
	if run != null and not run.heroes.is_empty():
		selected_hero_id = int(run.heroes.keys()[0])
		if not run.party.is_empty(): selected_hero_id = run.party[0]
	_render()

func _process(_delta: float) -> void:
	if battle_view == null or battle_view.is_execution_pending() or _pending_save != null:
		return
	var outcome := HeroHubBattleFactory.outcome(_battle_bundle)
	if outcome.is_empty():
		return
	var candidate := _copy_run()
	if candidate == null or not candidate.finish_battle(int(outcome.get("serial", -1)), bool(outcome.get("victory", false)), outcome.get("hp", {}), outcome.get("gear", {})):
		_storage_error = "Результат боя не прошёл проверку. Исход сохранён в текущей контрольной точке."
		_clear_battle()
		_render()
		return
	_commit(candidate)

func _exit_tree() -> void:
	_clear_battle()

func _copy_run() -> HeroHubState:
	return HeroHubState.from_dict(run.to_dict()) if run != null else null

func _commit(candidate: HeroHubState) -> void:
	var error := HeroHubStore.write_run(save_path, candidate)
	if not error.is_empty():
		_pending_save = candidate
		_storage_error = error
		if battle_view != null:
			battle_view.set_process(false)
			battle_view.hide()
		_render()
		return
	run = candidate
	_pending_save = null
	_storage_error = ""
	_message = "Профиль сохранён."
	_clear_battle()
	_render()

func _retry_save() -> void:
	if _pending_save != null:
		_commit(_pending_save)

func _mutate(method: StringName, args: Array = []) -> void:
	if run == null or _pending_save != null or not _storage_error.is_empty() or battle_view != null:
		return
	var candidate := _copy_run()
	if candidate == null:
		_message = "Не удалось скопировать профиль."
		_render()
		return
	var result: Variant = candidate.callv(method, args)
	if not (result is bool and result):
		_message = "Действие недоступно: проверьте отряд, очки и золото."
		_render()
		return
	if method == &"start_battle":
		_commit(candidate)
		return
	_message = "Изменения сохранены."
	_commit(candidate)

func _start_battle() -> void:
	if run == null or run.party.is_empty() or _pending_save != null or not _storage_error.is_empty():
		return
	var candidate := _copy_run()
	if candidate == null or not candidate.start_battle():
		_message = "Нужен хотя бы один герой в отряде."
		_render()
		return
	_commit(candidate)

func _begin_battle() -> void:
	if run == null or run.phase != "battle":
		_render()
		return
	_battle_bundle = HeroHubBattleFactory.create(run)
	if _battle_bundle.is_empty() or not _battle_bundle.has("session"):
		_storage_error = "Не удалось собрать бой из сохранённого отряда и экипировки."
		_render()
		return
	battle_view = HeroHubBattleView.new()
	battle_view.supplied_session = _battle_bundle["session"]
	battle_view.return_requested.connect(_on_battle_return)
	battle_view.restart_requested.connect(_restart_checkpoint)
	battle_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(battle_view)

func _on_battle_return() -> void:
	# Результат берётся только из терминального состояния сессии, никакого ручного исхода UI нет.
	if battle_view != null and not battle_view.is_execution_pending():
		_process(0.0)

func _restart_checkpoint() -> void:
	if battle_view == null or battle_view.is_execution_pending() or _pending_save != null:
		return
	if battle_view._battle.phase != BattleTacticalSession.Phase.FAULTED:
		return
	# Только явное действие игрока повторяет начало; prefix ошибочного боя не даёт наград.
	_clear_battle()
	_render()

func _clear_battle() -> void:
	if battle_view != null:
		battle_view._join_execution()
		remove_child(battle_view)
		battle_view.queue_free()
		battle_view = null
	if not _battle_bundle.is_empty():
		var session: Variant = _battle_bundle.get("session")
		if session != null:
			session.call("close")
	_battle_bundle.clear()

func _render() -> void:
	var previous_scroll := find_child("HeroHubScroll", true, false) as ScrollContainer
	var scroll_offset: int = previous_scroll.scroll_vertical if previous_scroll != null else 0
	if battle_view != null:
		_clear_battle()
	if run != null:
		var selected: HeroProgression = run.heroes.get(selected_hero_id)
		if selected == null or selected.hp_current <= 0.0:
			selected_hero_id = 0
			for id: int in run.heroes:
				var candidate: HeroProgression = run.heroes[id]
				if candidate.hp_current > 0.0:
					selected_hero_id = id
					break
	if _root_panel != null:
		remove_child(_root_panel)
		_root_panel.queue_free()
	_root_panel = PanelContainer.new()
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111a27")
	for side: String in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 20.0)
	_root_panel.add_theme_stylebox_override("panel", style)
	add_child(_root_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_root_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("intoDeDung · Хаб героев", 27)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if run != null:
		var gold_label := _label("Золото: %d" % run.gold, 21)
		gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		gold_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		header.add_child(gold_label)
	var scroll := ScrollContainer.new()
	scroll.name = "HeroHubScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	scroll.set_deferred("scroll_vertical", scroll_offset)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)
	if not _storage_error.is_empty():
		_text("Сохранение недоступно: " + _storage_error)
		if _pending_save != null: _button_for(_content, "Повторить запись", "retry_save", _retry_save)
		return
	if run == null:
		_text("Профиль не загружен. Сохранение не изменено.")
		return
	_text(run.last_result, 18)
	if run.phase == "battle":
		_begin_battle()
		return
	if not _message.is_empty(): _text(_message)
	_hub_content()

func _hub_content() -> void:
	_text("ОТРЯД · выберите до трёх героев. Перед боем их HP восстанавливается.", 20)
	var party_row := HFlowContainer.new()
	_content.add_child(party_row)
	for id: int in run.heroes:
		var hero: HeroProgression = run.heroes[id]
		var button := Button.new()
		button.text = ("✓ " if run.party.has(id) else "□ ") + hero.name
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_toggle_party.bind(id))
		party_row.add_child(button)
	_text("СОСТАВ · %d/%d · выбранный герой: %s" % [run.party.size(), HeroHubState.MAX_PARTY, _selected_name()], 17)
	_text("ГЕРОИ", 20)
	for id: int in run.heroes:
		var hero: HeroProgression = run.heroes[id]
		var box := VBoxContainer.new()
		_content.add_child(box)
		var select_row := HBoxContainer.new()
		box.add_child(select_row)
		var selected := " · выбран" if selected_hero_id == id else ""
		var choose := Button.new()
		choose.text = "%s · %s · уровень %d · XP %d.%d · очки %d%s" % [hero.name, HeroCatalog.class_definition(hero.class_id).display_name, hero.level(), hero.xp_tenths / 10, hero.xp_tenths % 10, hero.available_points(), selected]
		choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choose.pressed.connect(_select_hero.bind(id))
		select_row.add_child(choose)
		_text_for_box(box, _hero_detail(hero), 14)
	_text("ПРЕДВАРИТЕЛЬНЫЕ ОЧКИ · %s" % _selected_name(), 19)
	_allocation_controls()
	_text("КАНДИДАТЫ · состав %d/%d · бесплатный найм, свойства показаны до найма" % [run.heroes.size(), HeroHubState.MAX_ROSTER], 20)
	if run.items.size() + 2 > HeroHubState.MAX_ITEMS:
		_text("Для комплекта новичка нужно два места: освободите склад, выбросив ненужные ненадетые предметы.")
	for index: int in run.candidates.size():
		var candidate: HeroProgression = run.candidates[index]
		var candidate_box := VBoxContainer.new()
		_content.add_child(candidate_box)
		_text_for_box(candidate_box, _hero_detail(candidate), 15)
		var hire: Button = _button_for(candidate_box, "Нанять без переброса свойств", "hire_%d" % index, _hire.bind(index))
		hire.disabled = run.heroes.size() >= HeroHubState.MAX_ROSTER or run.items.size() + 2 > HeroHubState.MAX_ITEMS
	_text("СКЛАД ЭКИПИРОВКИ · всего вещей %d/%d" % [run.items.size(), HeroHubState.MAX_ITEMS], 20)
	_equipment_controls()
	var footer := HBoxContainer.new()
	_content.add_child(footer)
	var send := Button.new()
	send.text = "Отправиться в настоящий бой"
	send.custom_minimum_size = Vector2(320, 44)
	send.pressed.connect(_start_battle)
	send.disabled = run.party.is_empty() or _pending_save != null
	footer.add_child(send)
	footer.add_child(_label("Выбранных героев и их экипировку можно менять в хабе.", 14))

func _hero_detail(hero: HeroProgression) -> String:
	var definition := HeroCatalog.class_definition(hero.class_id)
	var stats := hero.attributes()
	var is_candidate := not run.heroes.has(hero.id)
	var equipped_weapon := run.equipped(hero.id, "weapon") if not is_candidate else {}
	var weapon_damage := float(definition.weapon_damage) if is_candidate else (0.0 if equipped_weapon.is_empty() else _weapon_damage(String(equipped_weapon.definition), definition.weapon_damage))
	var equipped_armor := run.equipped(hero.id, "armor") if not is_candidate else {}
	var armor_text := "%d/%d" % [definition.armor_max, definition.armor_max] if is_candidate else ("%d/%d" % [equipped_armor.remaining, HeroGearCatalog.definition(String(equipped_armor.definition)).armor_max] if not equipped_armor.is_empty() else "0/0")
	var base_stats := "Мощь %d · Ловкость %d · Выносливость %d · Интеллект %d" % [stats[0], stats[1], stats[2], stats[3]]
	var xp_text := "%d.%d опыта всего" % [hero.xp_tenths / 10, hero.xp_tenths % 10]
	var perk := HeroCatalog.perk_text(hero.perk)
	var weapon_name: String = {"warrior":"меч", "archer":"лук", "rogue":"кинжал", "mage":"посох"}.get(String(hero.class_id), "оружие класса")
	var abilities := definition.abilities_text
	if hero.class_id == &"mage": abilities += " Броня +20."
	abilities += " Общие действия: походный флакон (4 + Мощь), общий отход и стойка."
	var allowed := "Оружие: только %s своего класса · доспехи: любое обычное имеющееся" % weapon_name
	return "%s\n%s\nУровень %d · %s · свободно очков: %d\nПерк: %s\nБазовые атрибуты: Мощь %d / Ловкость %d / Выносливость %d / Интеллект %d\nHP %.1f/%d · равновесие %d · движение %.0f · сопротивление огню %d%%\nБроня надетого доспеха: %s · базовый урон оружия: %s\nСпособности: %s\nДопуски: %s" % [hero.name, base_stats, hero.level(), xp_text, hero.available_points(), perk, hero.base_attributes[0], hero.base_attributes[1], hero.base_attributes[2], hero.base_attributes[3], hero.hp_current, hero.max_hp(), hero.balance_max(), hero.move_max(), hero.fire_resistance(), armor_text, String.num(weapon_damage).trim_suffix(".0"), abilities, allowed]

func _weapon_damage(key: String, fallback: int) -> float:
	var definition := HeroGearCatalog.definition(key)
	if definition == null: return float(fallback)
	if String(definition.id) == "weapon:mage": return float(fallback)
	for effect: ItemEffect in definition.effects:
		if effect is StatModifierEffect and (effect as StatModifierEffect).stat_type == StatTypes.StatType.WEAPON_DAMAGE:
			return (effect as StatModifierEffect).value
	return 0.0

func _allocation_controls() -> void:
	var hero: HeroProgression = run.heroes.get(selected_hero_id)
	if hero == null:
		_text("Выберите героя для изменения характеристик.")
		return
	var attributes := ["Мощь", "Ловкость", "Выносливость", "Интеллект"]
	var preview := HeroProgression.from_dict(hero.to_dict())
	var preview_ok := preview != null and _delta_sum() > 0 and preview.apply_allocation(pending_delta)
	var row := HBoxContainer.new()
	_content.add_child(row)
	for index: int in 4:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size.x = 200
		row.add_child(cell)
		_text_for_box(cell, attributes[index], 15)
		var controls := HBoxContainer.new()
		cell.add_child(controls)
		_button_for(controls, "−", "alloc_minus_%d" % index, _change_delta.bind(index, -1))
		_text_for_box(controls, "%d" % pending_delta[index], 16)
		var plus := _button_for(controls, "+", "alloc_plus_%d" % index, _change_delta.bind(index, 1))
		plus.disabled = hero.available_points() <= _delta_sum()
	var summary := _label("Сейчас %s" % _stat_preview(hero), 15)
	_content.add_child(summary)
	if preview_ok:
		_text("После применения: %s" % _allocation_delta_text(hero, preview), 15)
	else:
		_text("Предпросмотр: выберите очки в пределах уровня и лимита атрибута 40.")
	var actions := HBoxContainer.new()
	_content.add_child(actions)
	var apply := _button_for(actions, "Применить распределение", "apply_allocation", _apply_allocation)
	apply.disabled = not preview_ok
	_button_for(actions, "Отменить предварительное", "cancel_allocation", _cancel_allocation)
	var reset := _button_for(actions, "Перераспределить · %d золота" % HeroHubState.RESPEC_PRICE, "respec", _respec)
	reset.disabled = hero.available_points() == hero.level() - 1 or run.gold < HeroHubState.RESPEC_PRICE

func _stat_preview(hero: HeroProgression) -> String:
	var attrs := hero.attributes()
	return "Мощь %d · Ловкость %d · Выносливость %d · Интеллект %d · HP %.1f/%d · HP макс. %d · равновесие %d · движение %.0f · огонь %d%% · %s · флакон %d HP" % [attrs[0], attrs[1], attrs[2], attrs[3], hero.hp_current, hero.max_hp(), hero.max_hp(), hero.balance_max(), hero.move_max(), hero.fire_resistance(), _attack_base_text(hero), 4 + attrs[0]]

func _allocation_delta_text(before: HeroProgression, after: HeroProgression) -> String:
	var old_stats := before.attributes()
	var new_stats := after.attributes()
	var labels: Array[String] = ["Мощь", "Ловкость", "Выносливость", "Интеллект"]
	var parts: PackedStringArray = []
	for index: int in 4:
		parts.append("%s %d→%d (%+d)" % [labels[index], old_stats[index], new_stats[index], new_stats[index] - old_stats[index]])
	parts.append("HP %.1f→%.1f (%+.1f)" % [before.hp_current, after.hp_current, after.hp_current - before.hp_current])
	parts.append("макс. HP %d→%d (%+d)" % [before.max_hp(), after.max_hp(), after.max_hp() - before.max_hp()])
	parts.append("равновесие %d→%d (%+d)" % [before.balance_max(), after.balance_max(), after.balance_max() - before.balance_max()])
	parts.append("движение %.0f→%.0f (%+.0f)" % [before.move_max(), after.move_max(), after.move_max() - before.move_max()])
	parts.append("сопротивление огню %d→%d (%+d%%)" % [before.fire_resistance(), after.fire_resistance(), after.fire_resistance() - before.fire_resistance()])
	parts.append("%s→%s" % [_attack_base_text(before), _attack_base_text(after)])
	parts.append("флакон %d→%d HP" % [4 + before.attributes()[0], 4 + after.attributes()[0]])
	return " · ".join(parts)

func _attack_base_text(hero: HeroProgression) -> String:
	var class_definition := HeroCatalog.class_definition(hero.class_id)
	var weapon: Dictionary = run.equipped(hero.id, "weapon") if run != null and run.heroes.has(hero.id) else {}
	var weapon_value := 0.0 if weapon.is_empty() else _weapon_damage(String(weapon.definition), class_definition.weapon_damage)
	if hero.class_id == &"mage":
		return "огненная база %d (не урон по цели)" % (hero.attributes()[0] + int(weapon_value))
	return "база основной атаки %d (не урон по цели)" % (hero.attributes()[0] + int(weapon_value))

func _equipment_controls() -> void:
	var selector := HFlowContainer.new()
	_content.add_child(selector)
	for id: int in run.heroes:
		var hero: HeroProgression = run.heroes[id]
		var button := Button.new()
		button.text = ("• " if selected_hero_id == id else "") + hero.name
		button.pressed.connect(_select_hero.bind(id))
		selector.add_child(button)
	_text("Экипировка героя: " + _selected_name(), 16)
	for item_id: int in run.items:
		var item: Dictionary = run.items[item_id]
		var definition := HeroGearCatalog.definition(String(item.definition))
		if definition == null: continue
		var owner := "на складе" if int(item.hero_id) == 0 else "надето на " + String((run.heroes[item.hero_id] as HeroProgression).name)
		var detail := " · броня %d/%d" % [item.remaining, definition.armor_max] if definition.armor_max > 0 else ""
		var row := HBoxContainer.new()
		_content.add_child(row)
		_text_for_box(row, "%s #%d · %s%s" % [definition.display_name, item_id, owner, detail], 15)
		if selected_hero_id != 0 and int(item.hero_id) == selected_hero_id:
			_button_for(row, "Снять на склад", "unequip_%d" % item_id, _unequip.bind(item_id))
		elif selected_hero_id != 0 and int(item.hero_id) == 0:
			var equip := _button_for(row, "Надеть выбранному", "equip_%d" % item_id, _equip.bind(item_id, selected_hero_id))
			equip.disabled = not HeroGearCatalog.allowed(String(item.definition), (run.heroes[selected_hero_id] as HeroProgression).class_id)
		if int(item.hero_id) == 0:
			_button_for(row, "Выбросить навсегда", "discard_%d" % item_id, _discard.bind(item_id))

func _toggle_party(id: int) -> void:
	_mutate(&"toggle_party", [id])

func _hire(index: int) -> void:
	_mutate(&"hire", [index])

func _apply_allocation() -> void:
	if _delta_sum() <= 0: return
	var delta: Array[int] = pending_delta.duplicate()
	pending_delta = [0, 0, 0, 0]
	_mutate(&"allocate", [selected_hero_id, delta])

func _respec() -> void:
	pending_delta = [0, 0, 0, 0]
	_mutate(&"respec", [selected_hero_id])

func _equip(item_id: int, hero_id: int) -> void:
	_mutate(&"equip", [item_id, hero_id])

func _unequip(item_id: int) -> void:
	_mutate(&"unequip", [item_id])

func _discard(item_id: int) -> void:
	_mutate(&"discard_item", [item_id])

func _change_delta(index: int, amount: int) -> void:
	var hero: HeroProgression = run.heroes.get(selected_hero_id)
	if hero == null: return
	var next := pending_delta[index] + amount
	if next < 0 or _delta_sum() + amount > hero.available_points(): return
	var projected := HeroProgression.from_dict(hero.to_dict())
	if amount > 0:
		var trial := pending_delta.duplicate()
		trial[index] += 1
		var projected_alloc: Array[int] = [trial[0], trial[1], trial[2], trial[3]]
		if projected.available_points() < _delta_sum() + 1 or projected.attributes()[index] + projected_alloc[index] > 40: return
	pending_delta[index] = next
	_render()

func _cancel_allocation() -> void:
	pending_delta = [0, 0, 0, 0]
	_render()

func _delta_sum() -> int:
	var result := 0
	for value: int in pending_delta: result += value
	return result

func _select_hero(id: int) -> void:
	selected_hero_id = id
	pending_delta = [0, 0, 0, 0]
	_render()

func _selected_name() -> String:
	var hero: HeroProgression = run.heroes.get(selected_hero_id)
	return hero.name if hero != null else "не выбран"

func _label(value: String, size: int = 16) -> Label:
	var result := Label.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", Color("dce7f2"))
	return result

func _text(value: String, size: int = 16) -> void:
	_content.add_child(_label(value, size))

func _text_for_box(parent: Node, value: String, size: int = 16) -> void:
	parent.add_child(_label(value, size))

func _button_for(parent: Node, value: String, key: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = key
	button.text = value
	button.custom_minimum_size.y = 34
	button.pressed.connect(action)
	parent.add_child(button)
	return button
