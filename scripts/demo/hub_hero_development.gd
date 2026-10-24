extends RefCounted
class_name HubHeroDevelopment

const ATTRIBUTE_NAMES: Array[String] = ["Мощь", "Ловкость", "Выносливость", "Интеллект", "Мастерство"]

var target_hero_id: int = 0
var expected: Dictionary = {}
var delta: Array[int] = [0, 0, 0, 0, 0]

func render(page: HubSectionPage, profile: HeroHubState) -> void:
	if page == null or profile == null: return
	_render_open_button(page, profile)
	var hero := _target_hero(profile)
	if target_hero_id != 0 and hero == null:
		# В опубликованном профиле погибший или удалённый герой больше не может быть целью.
		_clear_draft()
	if hero != null and hero.to_dict() != expected:
		# Только новая опубликованная запись меняет базу черновика; отказ записи оставляет её прежней.
		expected = hero.to_dict()
		delta = [0, 0, 0, 0, 0]
	var panel := page._slot("development_panel") as Control
	if panel == null: return
	if hero == null:
		_clear_panel(page)
		return
	_render_draft(page, profile, hero)

func handle_action(page: HubSectionPage, profile: HeroHubState, action: String) -> bool:
	if page == null or profile == null or page.section_id != &"mercenaries": return false
	if action == "development_open":
		var button := page._action_button(action)
		var panel := page._slot("development_panel") as Control
		if not page.is_visible_in_tree() or button == null or not button.is_visible_in_tree() or panel == null: return true
		if profile.phase != "hub" or page._selected_candidate: return true
		var hero := _target_candidate(page, profile)
		if hero == null or hero.hp_current <= 0.0: return true
		target_hero_id = hero.id
		expected = hero.to_dict()
		delta = [0, 0, 0, 0, 0]
		panel.show()
		return true
	if action == "development_close":
		if not _internal_action_ready(page, action): return true
		close(page)
		return true
	if action == "development_cancel":
		if not _internal_action_ready(page, action): return true
		delta = [0, 0, 0, 0, 0]
		return true
	if action == "development_apply":
		if not _internal_action_ready(page, action) or profile.phase != "hub": return true
		var hero := _target_hero(profile)
		var preview := _preview(hero)
		if hero == null or preview == null or _delta_sum() <= 0: return true
		# Хозяин проверяет ожидаемую версию и сохраняет копию, поэтому отказ не теряет черновик.
		page.allocation_requested.emit(target_hero_id, expected.duplicate(true), delta.duplicate())
		return true
	if action.begins_with("development_minus_") or action.begins_with("development_plus_"):
		if not _internal_action_ready(page, action) or profile.phase != "hub": return true
		var hero := _target_hero(profile)
		if hero == null: return true
		var index_text := action.trim_prefix("development_minus_") if action.begins_with("development_minus_") else action.trim_prefix("development_plus_")
		if not index_text.is_valid_int(): return true
		var index := int(index_text)
		if index < 0 or index >= ATTRIBUTE_NAMES.size(): return true
		if action.begins_with("development_minus_"):
			if delta[index] > 0: delta[index] -= 1
		else:
			if _delta_sum() < hero.available_points(): delta[index] += 1
		return true
	return false

func close(page: HubSectionPage) -> void:
	var panel: Control = null
	if page != null: panel = page._slot("development_panel") as Control
	if panel != null: panel.hide()
	_clear_draft()

func _render_open_button(page: HubSectionPage, profile: HeroHubState) -> void:
	var button := page._action_button("development_open")
	var hero := _target_candidate(page, profile)
	var enabled := profile.phase == "hub" and not page._selected_candidate and hero != null and hero.hp_current > 0.0 and page._slot("development_panel") != null
	if button == null: return
	button.text = "Развитие · %d" % hero.available_points() if hero != null and not page._selected_candidate else "Развитие"
	button.disabled = not enabled
	if page._selected_candidate:
		button.tooltip_text = "Сначала наймите кандидата"
	elif hero != null:
		button.tooltip_text = "Уровень %d · XP %d.%d · свободных очков %d" % [hero.level(), floori(float(hero.xp_tenths) / 10.0), hero.xp_tenths % 10, hero.available_points()]
	else:
		button.tooltip_text = "Доступно для нанятого живого героя в хабе"

func _render_draft(page: HubSectionPage, profile: HeroHubState, hero: HeroProgression) -> void:
	page._text("development_title", hero.name)
	page._text("development_progress", "Уровень %d · XP %d.%d всего" % [hero.level(), floori(float(hero.xp_tenths) / 10.0), hero.xp_tenths % 10])
	page._text("development_points", "Свободно: %d · в черновике: %d" % [hero.available_points(), _delta_sum()])
	var preview := _preview(hero)
	var current_attributes := hero.attributes()
	var preview_attributes := current_attributes if preview == null else preview.attributes()
	for index: int in ATTRIBUTE_NAMES.size():
		page._text("development_value_%d" % index, "%s  %d → %d  (%+d)" % [ATTRIBUTE_NAMES[index], current_attributes[index], preview_attributes[index], delta[index]])
		var minus := page._action_button("development_minus_%d" % index)
		if minus != null: minus.disabled = profile.phase != "hub" or preview == null or delta[index] <= 0
		var plus := page._action_button("development_plus_%d" % index)
		if plus != null: plus.disabled = profile.phase != "hub" or preview == null or _delta_sum() >= hero.available_points()
	page._text("development_preview", "—" if preview == null else _preview_text(profile, hero, preview))
	var preview_label := page._slot("development_preview") as Label
	if preview_label != null: preview_label.tooltip_text = "Пары показывают текущие значения и черновой предпросмотр. База атаки не является уроном по цели."
	var apply_button := page._action_button("development_apply")
	if apply_button != null: apply_button.disabled = profile.phase != "hub" or preview == null or _delta_sum() <= 0
	var cancel_button := page._action_button("development_cancel")
	if cancel_button != null: cancel_button.disabled = profile.phase != "hub" or _delta_sum() <= 0
	var close_button := page._action_button("development_close")
	if close_button != null: close_button.disabled = false

func _clear_panel(page: HubSectionPage) -> void:
	page._text("development_title", "Герой недоступен")
	page._text("development_progress", "")
	page._text("development_points", "")
	page._text("development_preview", "")
	var preview_label := page._slot("development_preview") as Label
	if preview_label != null: preview_label.tooltip_text = ""
	for index: int in ATTRIBUTE_NAMES.size():
		page._text("development_value_%d" % index, "")
		var minus := page._action_button("development_minus_%d" % index)
		if minus != null: minus.disabled = true
		var plus := page._action_button("development_plus_%d" % index)
		if plus != null: plus.disabled = true
	var apply_button := page._action_button("development_apply")
	if apply_button != null: apply_button.disabled = true
	var cancel_button := page._action_button("development_cancel")
	if cancel_button != null: cancel_button.disabled = true
	var close_button := page._action_button("development_close")
	if close_button != null: close_button.disabled = false

func _preview_text(profile: HeroHubState, current: HeroProgression, preview: HeroProgression) -> String:
	var current_attrs := current.attributes()
	var preview_attrs := preview.attributes()
	var lines: PackedStringArray = []
	lines.append("HP тек.: %.1f → %.1f" % [current.hp_current, preview.hp_current])
	lines.append("HP макс.: %.1f → %.1f" % [current.max_hp(), preview.max_hp()])
	lines.append("Равновесие: %d → %d" % [current.balance_max(), preview.balance_max()])
	lines.append("Движение: %.0f → %.0f" % [current.move_max(), preview.move_max()])
	lines.append("Сопр. физ.: %.1f%% → %.1f%%" % [current.physical_resistance(), preview.physical_resistance()])
	lines.append("Сопр. огонь: %.1f%% → %.1f%%" % [current.fire_resistance(), preview.fire_resistance()])
	lines.append("Прямой урон: ×%.2f → ×%.2f" % [CharacterAttributeRules.power_multiplier(float(current_attrs[0])), CharacterAttributeRules.power_multiplier(float(preview_attrs[0]))])
	lines.append("Урон состояний: ×%.2f → ×%.2f" % [CharacterAttributeRules.status_multiplier(float(current_attrs[3])), CharacterAttributeRules.status_multiplier(float(preview_attrs[3]))])
	lines.append("Бонус позиции: ×%.2f → ×%.2f" % [CharacterAttributeRules.position_bonus_multiplier(float(current_attrs[4])), CharacterAttributeRules.position_bonus_multiplier(float(preview_attrs[4]))])
	lines.append("Крит: ×%.2f → ×%.2f" % [CharacterAttributeRules.critical_multiplier(float(current_attrs[4])), CharacterAttributeRules.critical_multiplier(float(preview_attrs[4]))])
	lines.append("%s: %.1f → %.1f (не урон по цели)" % [_attack_base_label(current), _attack_base(profile, current), _attack_base(profile, preview)])
	lines.append("Флакон: %d → %d HP" % [4 + current_attrs[0], 4 + preview_attrs[0]])
	return "\n".join(lines)

func _attack_base_label(hero: HeroProgression) -> String:
	return "Огненная база" if hero.class_id == &"mage" else "База осн. атаки"

func _attack_base(profile: HeroHubState, hero: HeroProgression) -> float:
	var class_definition := HeroCatalog.class_definition(hero.class_id)
	var weapon: Dictionary = profile.equipped(hero.id, "weapon")
	var weapon_value := 0.0 if weapon.is_empty() else _weapon_damage(String(weapon.get("definition", "")), class_definition.weapon_damage)
	return (3.0 + weapon_value) * CharacterAttributeRules.power_multiplier(float(hero.attributes()[0]))

func _weapon_damage(key: String, fallback: int) -> float:
	var definition := HeroGearCatalog.definition(key)
	if definition == null: return float(fallback)
	if String(definition.id) == "weapon:mage": return float(fallback)
	for effect: ItemEffect in definition.effects:
		if effect is StatModifierEffect and (effect as StatModifierEffect).stat_type == StatTypes.StatType.WEAPON_DAMAGE:
			return (effect as StatModifierEffect).value
	return 0.0

func _internal_action_ready(page: HubSectionPage, action: String) -> bool:
	if not page.is_visible_in_tree(): return false
	var panel := page._slot("development_panel") as Control
	var button := page._action_button(action)
	return panel != null and panel.is_visible_in_tree() and button != null and button.is_visible_in_tree()

func _target_hero(profile: HeroHubState) -> HeroProgression:
	if target_hero_id <= 0 or not profile.heroes.has(target_hero_id): return null
	var hero: HeroProgression = profile.heroes[target_hero_id] as HeroProgression
	return hero if hero != null and hero.hp_current > 0.0 else null

func _target_candidate(page: HubSectionPage, profile: HeroHubState) -> HeroProgression:
	if page._selected_candidate: return null
	return profile.heroes.get(page._selected_hero_id) as HeroProgression

func _preview(hero: HeroProgression) -> HeroProgression:
	if hero == null: return null
	var result := HeroProgression.from_dict(hero.to_dict())
	if result == null: return null
	if _delta_sum() > 0 and not result.apply_allocation(delta): return null
	return result

func _delta_sum() -> int:
	var total := 0
	for value: int in delta: total += value
	return total

func _clear_draft() -> void:
	target_hero_id = 0
	expected = {}
	delta = [0, 0, 0, 0, 0]
