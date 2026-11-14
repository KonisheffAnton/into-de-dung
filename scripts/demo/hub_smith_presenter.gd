extends RefCounted
class_name HubSmithPresenter

const ITEMS_PAGE_SIZE: int = 6

static func render(page: HubSectionPage, profile: HeroHubState) -> void:
	if page == null or profile == null: return
	_render_hero_selector(page, profile)
	_render_inventory(page, profile)
	_render_figure(page, profile)
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
	if action == "smith_equipment" or action == "smith_unequip":
		var button := page._action_button(action)
		if not page.is_visible_in_tree() or button == null or not button.is_visible_in_tree() or profile.phase != "hub": return true
		var item := _selected_item(profile, page._selected_item_id)
		var hero: HeroProgression = profile.heroes.get(page._selected_hero_id) as HeroProgression
		if item.is_empty() or hero == null or hero.hp_current <= 0.0: return true
		if HeroGearCatalog.definition(String(item.get("definition", ""))) == null: return true
		var owner_id := int(item.get("hero_id", 0))
		var equip_item := action == "smith_equipment"
		if equip_item:
			if owner_id != 0: return true
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

static func _render_figure(page: HubSectionPage, profile: HeroHubState) -> void:
	var hero: HeroProgression = profile.heroes.get(page._selected_hero_id) as HeroProgression
	page._portrait("smith_portrait", HubSkeletonCard.hero_texture(hero.class_id, StringName(page.character_skins.get(hero.class_id, &""))) if hero != null else null)
	for slot_name: String in ["weapon", "armor"]:
		var slot := page._slot("smith_%s_slot" % slot_name) as HubSmithSlot
		if slot == null: continue
		var item: Dictionary = profile.equipped(hero.id, slot_name) if hero != null else {}
		var definition := HeroGearCatalog.definition(String(item.get("definition", ""))) if not item.is_empty() else null
		slot.smith_page = page
		slot.item_id = int(item.get("id", 0))
		slot.text = "+" if definition == null else ("⚔" if slot_name == "weapon" else "◆")
		slot.tooltip_text = ("Оружие · пустой слот" if slot_name == "weapon" else "Доспех · пустой слот") if definition == null else definition.display_name + " · клик для осмотра"
		slot.disabled = hero == null

static func _render_inventory(page: HubSectionPage, profile: HeroHubState) -> void:
	var ids := page._item_ids()
	page._items_page = clampi(page._items_page, 0, maxi(0, (ids.size() - 1) / ITEMS_PAGE_SIZE))
	page._text("item_count", "Все вещи · %d" % ids.size())
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
			var empty_card := card as HubSmithItemCard
			if empty_card != null: empty_card.item_id = 0
			continue
		var item: Dictionary = profile.items[ids[item_index]]
		var definition := HeroGearCatalog.definition(String(item.get("definition", "")))
		if definition == null:
			card.render_card("", "—")
			card.tooltip_text = ""
			var invalid_card := card as HubSmithItemCard
			if invalid_card != null: invalid_card.item_id = 0
			continue
		var owner: HeroProgression = profile.heroes.get(int(item.get("hero_id", 0))) as HeroProgression
		var full_owner := "Склад" if owner == null else owner.name
		var subtitle := full_owner.left(11) + "…" if full_owner.length() > 12 else full_owner
		var symbol := "◆" if HeroGearCatalog.slot(String(item.definition)) == "armor" else "⚔"
		card.render_card("item:%d" % ids[item_index], definition.display_name, subtitle, symbol)
		card.tooltip_text = "%s · %s\n%s" % ["Доспех" if symbol == "◆" else "Оружие", full_owner, definition.description]
		var drag_card := card as HubSmithItemCard
		if drag_card != null:
			drag_card.smith_page = page
			drag_card.item_id = ids[item_index]
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
		page._text("smith_compare", "Надето / Выбрано / Разница: —")
		_set_equipment_action(page, false, false)
		return
	var item_definition := String(item.get("definition", ""))
	var definition := HeroGearCatalog.definition(item_definition)
	if definition == null:
		page._text("item_title", "Неизвестный предмет")
		page._text("item_symbol", "—")
		page._text("item_detail", "Определение предмета недоступно")
		_set_detail_tooltip(page, "")
		page._text("smith_equipment_hint", "Предмет нельзя экипировать")
		page._text("smith_compare", "Надето / Выбрано / Разница: —")
		_set_equipment_action(page, false, false)
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
	page._text("smith_compare", _comparison(profile, selected_hero, item))
	var hint := ""
	var can_equip := false
	var can_unequip := false
	if profile.phase != "hub": hint = "Экипировку можно менять только в хабе"
	elif selected_hero == null or selected_hero.hp_current <= 0.0: hint = "Нет живого выбранного героя"
	elif owner_id == selected_hero.id:
		can_unequip = true
		hint = "Снятие бесплатно; предмет останется на складе"
	elif owner_id != 0:
		hint = "Сначала выберите владельца и снимите предмет"
	elif not HeroGearCatalog.allowed(item_definition, selected_hero.class_id):
		hint = "Оружие доступно только герою своего класса"
	else:
		can_equip = true
		hint = "Бесплатно; заменённый предмет вернётся на склад"
	_set_equipment_action(page, can_equip, can_unequip)
	page._text("smith_equipment_hint", hint)

static func _set_equipment_action(page: HubSectionPage, can_equip: bool, can_unequip: bool) -> void:
	page._action_enabled("smith_equipment", can_equip)
	page._action_enabled("smith_unequip", can_unequip)

static func _comparison(profile: HeroHubState, hero: HeroProgression, selected: Dictionary) -> String:
	if hero == null or selected.is_empty(): return "Надето / Выбрано / Разница: —"
	var slot_name := HeroGearCatalog.slot(String(selected.get("definition", "")))
	var current: Dictionary = profile.equipped(hero.id, slot_name)
	var selected_stats := _comparison_stats(selected)
	var current_stats := _comparison_stats(current)
	var lines: Array[String] = ["Надето         Выбрано         Разница"]
	for key: String in selected_stats:
		var before := float(current_stats.get(key, 0.0))
		var after := float(selected_stats[key])
		lines.append("%s  %s → %s  (%+.1f)" % [key, String.num(before, 1), String.num(after, 1), after - before])
	return "\n".join(lines)

static func _comparison_stats(item: Dictionary) -> Dictionary:
	if item.is_empty(): return {}
	var key := String(item.get("definition", ""))
	var definition := HeroGearCatalog.definition(key)
	if definition == null: return {}
	if HeroGearCatalog.slot(key) == "armor":
		return {"Броня": float(item.get("remaining", 0.0)), "Макс.": float(definition.armor_max)}
	var values: Dictionary = {"Физ. база": 0.0, "Огонь": 0.0, "Пробивание": 0.0, "Доп. атаки": 0.0}
	for effect: ItemEffect in definition.effects:
		if effect is StatModifierEffect:
			var modifier := effect as StatModifierEffect
			if modifier.stat_type == StatTypes.StatType.WEAPON_DAMAGE: values["Физ. база"] += modifier.value
			elif modifier.stat_type == StatTypes.StatType.PHYSICAL_PIERCING_PERCENT: values["Пробивание"] += modifier.value
	if key == "weapon:mage":
		var mage := HeroCatalog.class_definition(&"mage")
		if mage != null: values["Огонь"] = float(mage.weapon_damage)
	for perk: StringName in definition.equipment_perks:
		if perk == &"extra_attack": values["Доп. атаки"] += 1.0
	return values

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
