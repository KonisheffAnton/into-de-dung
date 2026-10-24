extends RefCounted
class_name HubSmithPresenter

const ITEMS_PAGE_SIZE: int = 6

static func render(page: HubSectionPage, profile: HeroHubState) -> void:
	if page == null or profile == null: return
	_render_hero_selector(page, profile)
	_render_inventory(page, profile)
	_render_item_detail(page, profile)

static func handle_action(page: HubSectionPage, profile: HeroHubState, action: String) -> bool:
	if page == null or profile == null or page.section_id != &"smith": return false
	if action == "smith_hero_prev" or action == "smith_hero_next":
		var button := page._action_button(action)
		if not page.is_visible_in_tree() or button == null or not button.is_visible_in_tree(): return true
		var hero_ids := _living_hero_ids(profile)
		var index := hero_ids.find(page._selected_hero_id)
		if index < 0: return true
		if action == "smith_hero_prev" and index > 0: page._selected_hero_id = hero_ids[index - 1]
		elif action == "smith_hero_next" and index + 1 < hero_ids.size(): page._selected_hero_id = hero_ids[index + 1]
		return true
	if action == "smith_equipment":
		var button := page._action_button(action)
		if not page.is_visible_in_tree() or button == null or not button.is_visible_in_tree() or profile.phase != "hub": return true
		var item := _selected_item(profile, page._selected_item_id)
		var hero: HeroProgression = profile.heroes.get(page._selected_hero_id) as HeroProgression
		if item.is_empty() or hero == null or hero.hp_current <= 0.0: return true
		if HeroGearCatalog.definition(String(item.get("definition", ""))) == null: return true
		var owner_id := int(item.get("hero_id", 0))
		var equip_item := owner_id == 0
		if equip_item:
			if not HeroGearCatalog.allowed(String(item.get("definition", "")), hero.class_id): return true
		elif owner_id != hero.id:
			return true
		# Владелец публикует экипировку только после успешной записи копии профиля.
		page.equipment_requested.emit(page._selected_item_id, hero.id, equip_item)
		return true
	return false

static func _render_hero_selector(page: HubSectionPage, profile: HeroHubState) -> void:
	var hero_ids := _living_hero_ids(profile)
	var index := hero_ids.find(page._selected_hero_id)
	if index < 0:
		# Мёртвый или удалённый герой больше не выбирается для работы с экипировкой.
		var fallback_id := 0
		if not profile.party.is_empty() and hero_ids.has(profile.party[0]): fallback_id = profile.party[0]
		elif not hero_ids.is_empty(): fallback_id = hero_ids[0]
		page._selected_hero_id = fallback_id
		index = hero_ids.find(fallback_id)
	var hero: HeroProgression = profile.heroes.get(page._selected_hero_id) as HeroProgression
	page._text("smith_hero", "%s · ур. %d" % [hero.name, hero.level()] if hero != null else "Нет живых героев")
	page._action_enabled("smith_hero_prev", index > 0)
	page._action_enabled("smith_hero_next", index >= 0 and index + 1 < hero_ids.size())

static func _render_inventory(page: HubSectionPage, profile: HeroHubState) -> void:
	var ids := page._item_ids()
	page._items_page = clampi(page._items_page, 0, maxi(0, (ids.size() - 1) / ITEMS_PAGE_SIZE))
	page._text("item_count", "Экипировка · %d" % ids.size())
	page._text("item_page", "%d / %d" % [page._items_page + 1, maxi(1, ceili(float(ids.size()) / ITEMS_PAGE_SIZE))])
	page._action_enabled("items_prev", page._items_page > 0)
	page._action_enabled("items_next", (page._items_page + 1) * ITEMS_PAGE_SIZE < ids.size())
	for slot: int in ITEMS_PAGE_SIZE:
		var card := page._slot("item_%d" % slot) as HubSkeletonCard
		if card == null: continue
		var item_index := page._items_page * ITEMS_PAGE_SIZE + slot
		if item_index >= ids.size():
			card.render_card("", "—")
			card.tooltip_text = ""
			continue
		var item: Dictionary = profile.items[ids[item_index]]
		var definition := HeroGearCatalog.definition(String(item.get("definition", "")))
		if definition == null:
			card.render_card("", "—")
			card.tooltip_text = ""
			continue
		var owner: HeroProgression = profile.heroes.get(int(item.get("hero_id", 0))) as HeroProgression
		var subtitle := "Склад" if owner == null else "Надето"
		var symbol := "◆" if HeroGearCatalog.slot(String(item.definition)) == "armor" else "⚔"
		card.render_card("item:%d" % ids[item_index], definition.display_name, subtitle, symbol)
		card.tooltip_text = definition.description
	if not ids.has(page._selected_item_id):
		var first_visible_index := page._items_page * ITEMS_PAGE_SIZE
		page._selected_item_id = ids[first_visible_index] if first_visible_index < ids.size() else (ids[0] if not ids.is_empty() else 0)

static func _render_item_detail(page: HubSectionPage, profile: HeroHubState) -> void:
	var item := _selected_item(profile, page._selected_item_id)
	var selected_hero: HeroProgression = profile.heroes.get(page._selected_hero_id) as HeroProgression
	if item.is_empty():
		page._text("item_title", "Выберите предмет")
		page._text("item_symbol", "—")
		page._text("item_detail", "Склад пуст")
		_set_detail_tooltip(page, "")
		page._text("smith_equipment_hint", "Нет выбранного предмета")
		page._text("smith_required", "Улучшение: —")
		_set_equipment_action(page, "", false)
		return
	var item_definition := String(item.get("definition", ""))
	var definition := HeroGearCatalog.definition(item_definition)
	if definition == null:
		page._text("item_title", "Неизвестный предмет")
		page._text("item_symbol", "—")
		page._text("item_detail", "Определение предмета недоступно")
		_set_detail_tooltip(page, "")
		page._text("smith_equipment_hint", "Предмет нельзя экипировать")
		page._text("smith_required", "Улучшение: —")
		_set_equipment_action(page, "", false)
		return
	var armor := HeroGearCatalog.slot(item_definition) == "armor"
	var owner_id := int(item.get("hero_id", 0))
	var owner: HeroProgression = profile.heroes.get(owner_id) as HeroProgression
	var owner_text := "На складе" if owner == null else "Надето: " + owner.name
	var details := owner_text
	var full_details := owner_text
	if armor:
		details += "\nОстаток брони: %.1f/%d" % [float(item.get("remaining", 0.0)), definition.armor_max]
		full_details += "\nТекущий остаток прочности брони: %.1f из %d" % [float(item.get("remaining", 0.0)), definition.armor_max]
	else:
		var class_definition := HeroCatalog.class_definition(StringName(item_definition.get_slice(":", 1)))
		var physical_damage := 0.0
		var piercing := 0.0
		for effect: ItemEffect in definition.effects:
			if effect is StatModifierEffect:
				var modifier := effect as StatModifierEffect
				if modifier.stat_type == StatTypes.StatType.WEAPON_DAMAGE: physical_damage += modifier.value
				elif modifier.stat_type == StatTypes.StatType.PHYSICAL_PIERCING_PERCENT: piercing += modifier.value
		if item_definition == "weapon:mage" and class_definition != null:
			details += "\nОгненная база: +%d" % class_definition.weapon_damage
			full_details += "\nПосох прибавляет %d к базе огненной атаки; это не итоговый урон по цели." % class_definition.weapon_damage
		elif physical_damage != 0.0:
			details += "\nФиз. база оружия: +%.0f" % physical_damage
			full_details += "\nОружие прибавляет %.0f к физической базе; это не итоговый урон по цели." % physical_damage
		if piercing != 0.0:
			details += "\nПробивание: +%.0f%%" % piercing
			full_details += "\nДоля физической базы, обходящая броню: %.0f%%." % piercing
		var extra_attacks := 0
		for perk: StringName in definition.equipment_perks:
			if perk == &"extra_attack": extra_attacks += 1
		if extra_attacks > 0:
			details += "\nДоп. атака: +%d" % extra_attacks
			full_details += "\nЭффект даёт %d последовательную атаку по той же цели." % extra_attacks
	page._text("item_title", definition.display_name)
	page._text("item_symbol", "◆" if armor else "⚔")
	page._text("item_detail", details)
	if not definition.description.is_empty(): full_details += "\n" + definition.description
	_set_detail_tooltip(page, full_details)
	page._text("smith_required", "Улучшение: —")
	var hint := ""
	var action_text := "Надеть"
	var can_act := false
	if profile.phase != "hub": hint = "Экипировку можно менять только в хабе"
	elif selected_hero == null or selected_hero.hp_current <= 0.0: hint = "Нет живого выбранного героя"
	elif owner_id == selected_hero.id:
		action_text = "Снять"
		can_act = true
		hint = "Снятие бесплатно; предмет останется на складе"
	elif owner_id != 0:
		hint = "Сначала выберите владельца и снимите предмет"
	elif not HeroGearCatalog.allowed(item_definition, selected_hero.class_id):
		hint = "Оружие доступно только герою своего класса"
	else:
		can_act = true
		hint = "Бесплатно; заменённый предмет вернётся на склад"
	_set_equipment_action(page, action_text, can_act)
	page._text("smith_equipment_hint", hint)

static func _set_equipment_action(page: HubSectionPage, label: String, enabled: bool) -> void:
	var button := page._action_button("smith_equipment")
	if button != null:
		button.text = label
		button.disabled = not enabled
	var upgrade := page._slot("smith_upgrade") as Button
	if upgrade != null: upgrade.disabled = true

static func _selected_item(profile: HeroHubState, item_id: int) -> Dictionary:
	if item_id == 0 or not profile.items.has(item_id): return {}
	var item: Dictionary = profile.items[item_id]
	return item

static func _set_detail_tooltip(page: HubSectionPage, value: String) -> void:
	var detail_label := page._slot("item_detail") as Label
	if detail_label != null: detail_label.tooltip_text = value

static func _living_hero_ids(profile: HeroHubState) -> Array[int]:
	var ids: Array[int] = []
	for id: int in profile.heroes:
		var hero: HeroProgression = profile.heroes[id] as HeroProgression
		if hero != null and hero.hp_current > 0.0: ids.append(id)
	ids.sort()
	return ids
