extends RefCounted
class_name HubMercenaryPresenter

const CARD: PackedScene = preload("res://scenes/demo/hub/sections/roster_hero_card.tscn")
const FEATURE: PackedScene = preload("res://scenes/demo/hub/feature_icon.tscn")

static func render(page: HubSectionPage, profile: HeroHubState) -> void:
	# Успешный найм сохраняет осматриваемый ID и переводит его в список своих героев.
	if page._selected_candidate and profile.heroes.has(page._selected_hero_id):
		page._mercenary_mode = &"owned"
		page._selected_candidate = false
		page._last_candidate_id = 0
	var candidates := page._mercenary_mode == &"hire"
	var roster: Array[HeroProgression] = []
	if candidates:
		roster.assign(profile.candidates)
	else:
		for id: int in profile.party:
			var member := profile.heroes.get(id) as HeroProgression
			if member != null and member.hp_current > 0.0: roster.append(member)
		for id: int in profile.heroes:
			var member := profile.heroes[id] as HeroProgression
			if member != null and member.hp_current > 0.0 and not profile.party.has(id): roster.append(member)
	var hero: HeroProgression = null
	for item: HeroProgression in roster:
		if item.id == page._selected_hero_id: hero = item; break
	if hero == null and not roster.is_empty(): hero = roster[0]
	page._selected_hero_id = hero.id if hero != null else 0
	page._selected_candidate = candidates
	if candidates: page._last_candidate_id = page._selected_hero_id
	else: page._last_owned_id = page._selected_hero_id
	page._text("roster_title", "Кандидаты" if candidates else "Мои герои")
	page._text("roster_count", str(roster.size()))
	for action: String in ["mercenaries_owned", "mercenaries_hire"]:
		var tab := page._action_button(action)
		if tab != null: tab.set_pressed_no_signal((action == "mercenaries_hire") == candidates)
	_render_grid(page, profile, roster)
	page._text("hero_title", hero.name if hero != null else "Нет героев")
	page._portrait("hero_portrait", HubSkeletonCard.hero_texture(hero.class_id, StringName(page.character_skins.get(hero.class_id, &""))) if hero != null else null)
	page._render_skin_choice(hero)
	page._render_skin_notice()
	page._update_mercenary_action(hero)
	page._action_enabled("hero_smith", hero != null and not candidates)
	_render_features(page, hero)
	if hero == null:
		for key: String in ["hero_identity", "hero_detail", "hero_equipment", "hero_points"]: page._text(key, "")
		return
	var definition := HeroCatalog.class_definition(hero.class_id)
	var membership := "Кандидат" if candidates else "В отряде" if profile.party.has(hero.id) else "В резерве"
	page._text("hero_identity", "%s · ур. %d · %s" % [definition.display_name, hero.level(), membership])
	page._text("hero_points", "+%d очк." % hero.available_points() if hero.available_points() > 0 else "")
	var attrs := hero.attributes()
	var armor := profile.equipped(hero.id, "armor") if not candidates else {}
	var weapon := profile.equipped(hero.id, "weapon") if not candidates else {}
	var armor_key := String(armor.get("definition", "armor:" + String(hero.class_id) if candidates else ""))
	var weapon_key := String(weapon.get("definition", "weapon:" + String(hero.class_id) if candidates else ""))
	var armor_definition := HeroGearCatalog.definition(armor_key) if not armor_key.is_empty() else null
	var weapon_definition := HeroGearCatalog.definition(weapon_key) if not weapon_key.is_empty() else null
	var armor_text := "Нет брони"
	if armor_definition != null:
		armor_text = "%s/%d" % [String.num(float(armor.get("remaining", armor_definition.armor_max)), 1), armor_definition.armor_max]
	page._text("hero_detail", "Мощь                 %d\nЛовкость             %d\nИнтеллект            %d\nВыносливость      %d\nМастерство         %d\n\nМакс. здоровье   %.0f\nБроня   %s" % [attrs[0], attrs[1], attrs[3], attrs[2], attrs[4], hero.max_hp(), armor_text])
	page._text("hero_equipment", "%s\n%s" % [weapon_definition.display_name if weapon_definition != null else "Без оружия", armor_definition.display_name if armor_definition != null else "Без доспеха"])

static func _render_grid(page: HubSectionPage, profile: HeroHubState, roster: Array[HeroProgression]) -> void:
	var grid := page._slot("mercenary_grid") as GridContainer
	if grid == null: return
	var existing: Dictionary[String, HubSkeletonCard] = {}
	for child: Node in grid.get_children():
		if child is HubSkeletonCard and child.has_meta(&"hub_generated"):
			existing[(child as HubSkeletonCard).selection_key] = child as HubSkeletonCard
	for index: int in roster.size():
		var hero := roster[index]
		var key := ("candidate:" if page._selected_candidate else "hero:") + str(hero.id)
		var card := existing.get(key) as HubSkeletonCard
		if card == null:
			card = CARD.instantiate() as HubSkeletonCard
			card.set_meta(&"hub_generated", true)
			grid.add_child(card)
			card.selected.connect(page._on_selected)
		else: existing.erase(key)
		grid.move_child(card, index)
		var definition := HeroCatalog.class_definition(hero.class_id)
		var membership := "Кандидат" if page._selected_candidate else "В отряде" if profile.party.has(hero.id) else "В резерве"
		card.render_card(key, hero.name, "%s · %d" % [definition.display_name, hero.level()], membership, HubSkeletonCard.hero_texture(hero.class_id, StringName(page.character_skins.get(hero.class_id, &""))))
		card.set_pressed_no_signal(hero.id == page._selected_hero_id)
		card.tooltip_text = "%s · %s · уровень %d\n%s" % [hero.name, definition.display_name, hero.level(), membership]
	for card: HubSkeletonCard in existing.values():
		grid.remove_child(card)
		card.queue_free()

static func _render_features(page: HubSectionPage, hero: HeroProgression) -> void:
	var features: Array[Dictionary] = HubHeroFeatures.entries(hero)
	for passive: bool in [true, false]:
		var row := page._slot("passive_icons" if passive else "ability_icons") as Container
		if row == null: continue
		var entries: Array[Dictionary] = []
		for item: Dictionary in features:
			if bool(item.passive) == passive: entries.append(item)
		var group := page._slot("passive_group" if passive else "ability_group") as Control
		if group != null: group.visible = not entries.is_empty()
		while row.get_child_count() > entries.size():
			var removed := row.get_child(row.get_child_count() - 1)
			row.remove_child(removed)
			removed.queue_free()
		while row.get_child_count() < entries.size(): row.add_child(FEATURE.instantiate())
		for index: int in entries.size():
			var item := entries[index]
			(row.get_child(index) as HubFeatureIcon).set_feature(item.title, item.description, item.icon, passive)
