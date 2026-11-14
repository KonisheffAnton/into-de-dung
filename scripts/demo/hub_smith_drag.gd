extends RefCounted
class_name HubSmithDrag

static func payload(page: HubSectionPage, item_id: int, source: String) -> Dictionary:
	if page == null or page._profile == null or not page._profile.items.has(item_id): return {}
	var profile := page._profile
	var hero: HeroProgression = profile.heroes.get(page._selected_hero_id) as HeroProgression
	if hero == null or hero.hp_current <= 0.0: return {}
	var item: Dictionary = profile.items[item_id]
	var slot := HeroGearCatalog.slot(String(item.get("definition", "")))
	if slot not in ["weapon", "armor"]: return {}
	var owner_id := int(item.get("hero_id", 0))
	if source == "slot" and owner_id != hero.id: return {}
	return {
		"kind": "hub_smith", "page_id": page.get_instance_id(),
		"hero_id": hero.id, "hero_expected": hero.to_dict(),
		"item_id": item_id, "item_expected": item.duplicate(true),
		"slot": slot, "source": source,
		"target_expected": profile.equipped(hero.id, slot).duplicate(true),
	}

static func reason(page: HubSectionPage, data: Variant, target: String) -> String:
	if page == null or page._profile == null or not page.is_visible_in_tree(): return "Кузнец закрыт"
	if not data is Dictionary or data.get("kind") != "hub_smith" or int(data.get("page_id", 0)) != page.get_instance_id(): return "Это не предмет кузнеца"
	var profile := page._profile
	if profile.phase != "hub": return "Экипировку можно менять только в хабе"
	var hero_id := int(data.get("hero_id", 0))
	var item_id := int(data.get("item_id", 0))
	if page._selected_hero_id != hero_id or not profile.heroes.has(hero_id): return "Выбранный герой изменился"
	var hero: HeroProgression = profile.heroes[hero_id] as HeroProgression
	if hero == null or hero.hp_current <= 0.0 or hero.to_dict() != data.get("hero_expected", {}): return "Данные героя устарели"
	if not profile.items.has(item_id) or profile.items[item_id] != data.get("item_expected", {}): return "Предмет или его владелец изменился"
	var item: Dictionary = profile.items[item_id]
	var source := String(data.get("source", ""))
	var slot := String(data.get("slot", ""))
	if slot not in ["weapon", "armor"] or HeroGearCatalog.slot(String(item.get("definition", ""))) != slot: return "Тип предмета изменился"
	if profile.equipped(hero_id, slot) != data.get("target_expected", {}): return "Слот героя изменился"
	var owner_id := int(item.get("hero_id", 0))
	if target == "inventory":
		if source != "slot" or owner_id != hero_id: return "Снимать можно только вещь выбранного героя"
		return ""
	if target != slot: return "Неверный слот для этого типа предмета"
	if owner_id == hero_id: return "Уже надето: изменение не требуется"
	if owner_id != 0: return "Сначала выберите владельца и снимите предмет"
	if not HeroGearCatalog.allowed(String(item.get("definition", "")), hero.class_id): return "Оружие доступно только герою своего класса"
	return ""

static func commit(page: HubSectionPage, data: Variant, target: String) -> void:
	var refusal := reason(page, data, target)
	if not refusal.is_empty():
		show_reason(page, refusal)
		return
	var item_id := int(data.get("item_id", 0))
	var hero_id := int(data.get("hero_id", 0))
	# Мутация остаётся у владельца профиля: он повторно проверит условия и сначала запишет копию.
	page.equipment_requested.emit(item_id, hero_id, target != "inventory")

static func show_reason(page: HubSectionPage, value: String) -> void:
	if page == null: return
	var hint := page._slot("smith_equipment_hint") as Label
	if hint != null: hint.text = value

static func inventory_target(node: Node) -> HubSmithInventoryDrop:
	var parent := node.get_parent()
	while parent != null:
		if parent is HubSmithInventoryDrop: return parent as HubSmithInventoryDrop
		parent = parent.get_parent()
	return null
