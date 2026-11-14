extends Control
class_name ExpeditionDashboard

signal tab_requested(tab_id: StringName)
signal start_requested
signal manage_requested
signal hire_requested(candidate_id: int)
signal party_requested(hero_id: int, join_party: bool)
signal equipment_requested(item_id: int, hero_id: int, equip_item: bool)
signal allocation_requested(hero_id: int, expected: Dictionary, delta: Array[int])
signal skin_selection_requested(class_id: StringName, skin_id: StringName)
signal deck_action_requested(action: String, type_id: String)
signal party_move_requested(hero_id: int, target_index: int, expected_party: Array[int])
signal party_select_requested(slot_index: int, hero_id: int, expected_party: Array[int])
signal hero_route_requested(hero_id: int, destination: StringName)

const TAB_IDS: Array[StringName] = [&"expedition", &"mercenaries", &"smith", &"schools", &"deck"]
var _tabs: Array[Button] = []
@onready var _hero_cards: HubSquadList = $Layout/Content/LeftColumn/PartyPanel/PartyContent/HeroCards
@onready var _party_count: Label = $Layout/Content/LeftColumn/PartyPanel/PartyContent/PartyHeader/PartyCount
@onready var _gold: Label = $Layout/Resources/Gold
@onready var _essence: Label = $Layout/Resources/Essence
@onready var _items: Label = $Layout/Resources/Items
@onready var _reserve: Label = $Layout/Resources/Reserve
@onready var _preparation_title: Label = $Layout/Content/PreparationPanel/PreparationContent/PreparationTitle
@onready var _route: Label = $Layout/Content/PreparationPanel/PreparationContent/Route
@onready var _party_summary: Label = $Layout/Content/PreparationPanel/PreparationContent/PartySummary
@onready var _deck_summary: Label = $Layout/Content/PreparationPanel/PreparationContent/DeckSummary
@onready var _launch_hint: Label = $Layout/Content/PreparationPanel/PreparationContent/LaunchHint
@onready var _start_button: Button = $Layout/Content/PreparationPanel/PreparationContent/StartJourney
@onready var _manage_button: Button = $Layout/Content/LeftColumn/PartyPanel/PartyContent/ManageParty
@onready var _diorama: HubDiorama = $Layout/Content/CenterSpace/Diorama
@onready var _picker: HubPartyPicker = $PartyPicker
@onready var _warnings: VBoxContainer = $Layout/Content/PreparationPanel/PreparationContent/WarningsScroll/Warnings
@onready var _fix_button: Button = $Layout/Content/PreparationPanel/PreparationContent/FixSpace/FixIssue

var _active_tab: StringName = &"expedition"
var character_skins: Dictionary[StringName, StringName] = {}
var skin_notice: String = ""
var _section_pages: Dictionary[StringName, HubSectionPage] = {}
var _deck_page: HubDeckPage
var _profile: HeroHubState
var _picker_slot: int = -1
var _picker_expected: Array[int] = []
var _editing_deck: bool = false

func _ready() -> void:
	for tab_id: StringName in TAB_IDS:
		var tab_button: Button
		for node: Node in find_children("*", "Button", true, false):
			if StringName(node.get_meta(&"hub_tab", &"")) == tab_id:
				tab_button = node as Button
				break
		_tabs.append(tab_button)
	for index: int in _tabs.size():
		if is_instance_valid(_tabs[index]): _tabs[index].pressed.connect(_on_tab_pressed.bind(TAB_IDS[index]))
	_start_button.pressed.connect(_on_start_pressed)
	_manage_button.pressed.connect(_on_manage_pressed)
	_hero_cards.slot_selected.connect(_open_party_picker)
	_hero_cards.reorder_requested.connect(_on_party_reorder)
	_picker.hero_selected.connect(_on_picker_selected)
	_picker.cancelled.connect(_on_picker_cancelled)
	_fix_button.pressed.connect(_on_fix_issue)
	for node: Node in find_children("*", "HubDeckPage", true, false):
		_deck_page = node as HubDeckPage
		_deck_page.action_requested.connect(_on_deck_action_requested)
		break
	for child: Node in find_children("*", "HubSectionPage", true, false):
		if child is HubSectionPage:
			var page := child as HubSectionPage
			_section_pages[page.section_id] = page
			page.manage_requested.connect(_on_manage_pressed)
			if page.section_id == &"mercenaries":
				page.hire_requested.connect(_on_hire_requested)
				page.party_requested.connect(_on_party_requested)
				page.allocation_requested.connect(_on_allocation_requested)
				page.skin_selection_requested.connect(_on_skin_selection_requested)
				page.hero_route_requested.connect(_on_hero_route_requested)
			elif page.section_id == &"smith":
				page.equipment_requested.connect(_on_equipment_requested)

func render_profile(profile: HeroHubState, expedition: bool, tab: StringName, launch_enabled: bool, launch_hint: String, editing: bool = false, draft: Array = []) -> void:
	if profile == null:
		return
	_profile = profile
	_editing_deck = editing
	_active_tab = tab if TAB_IDS.has(tab) else &"expedition"
	if _active_tab != &"expedition": _picker.close()
	_render_tabs()
	($Layout/Content as Control).visible = _active_tab == &"expedition"
	if is_instance_valid(_deck_page) and is_ancestor_of(_deck_page):
		_deck_page.visible = _active_tab == &"deck"
		if _deck_page.visible: _deck_page.render_profile(profile, editing, draft)
	for key: StringName in _section_pages:
		if not is_instance_valid(_section_pages[key]): continue
		var page := _section_pages[key]
		if not is_ancestor_of(page): continue
		page.visible = key == _active_tab
		if page.visible:
			# Одинаковый выбор нужен карточкам отряда и карточкам списка наёмников.
			page.character_skins = character_skins.duplicate()
			page.skin_notice = skin_notice if key == &"mercenaries" else ""
			page.render_profile(profile)
	_render_party(profile)
	_gold.text = "Золото   %d" % profile.gold
	_essence.text = "Эссенция   %d" % profile.essence
	_items.text = "Экипировка · всего   %d" % profile.items.size()
	_reserve.text = "В резерве   %d" % _living_reserve_count(profile)
	if _active_tab != &"expedition": return
	var active_count: int = profile.party.size()
	_party_count.text = str(active_count)
	_party_summary.text = "Отряд: %d" % active_count
	_route.text = "7 комнат" if expedition else "1 бой"
	_deck_summary.text = _deck_summary_text(profile)
	if editing: _deck_summary.text += "\nЧерновик: %d/10" % draft.size()
	_launch_hint.text = launch_hint
	if editing: _launch_hint.text = "Завершите редактирование колоды"
	_start_button.disabled = not launch_enabled
	_fix_button.visible = not launch_enabled
	_fix_button.text = "К колоде" if editing else "Выбрать отряд"
	if not editing and not _has_living_heroes(profile): _fix_button.text = "Нанять героя"
	_render_warnings(profile)
	if _active_tab == &"expedition":
		_preparation_title.text = "Подготовка к походу" if expedition else "Подготовка к бою"
		_route.visible = true
		_party_summary.visible = true
		_deck_summary.visible = true
		_launch_hint.visible = true
		_start_button.visible = true
		_manage_button.visible = true

func _render_party(profile: HeroHubState) -> void:
	_hero_cards.render_profile(profile, character_skins)
	_diorama.render_profile(profile, character_skins)

func _open_party_picker(slot_index: int) -> void:
	if _active_tab != &"expedition" or not is_visible_in_tree() or _profile == null: return
	if not _has_living_heroes(_profile):
		tab_requested.emit(&"mercenaries")
		var page := _section_pages.get(&"mercenaries") as HubSectionPage
		if page != null: page.call_deferred("_on_action", "mercenaries_hire")
		return
	_picker_slot = slot_index
	_picker_expected = _profile.party.duplicate()
	_picker.open_for(_profile, slot_index, character_skins)

func _on_picker_selected(hero_id: int) -> void:
	if not _picker.is_visible_in_tree() or _active_tab != &"expedition": return
	var slot := _picker_slot
	var expected: Array[int] = _picker_expected.duplicate()
	_picker.close()
	party_select_requested.emit(slot, hero_id, expected)
	_hero_cards.call_deferred("focus_slot", slot)

func _on_picker_cancelled() -> void:
	_hero_cards.call_deferred("focus_slot", _picker_slot)

func _on_party_reorder(hero_id: int, target_index: int, expected: Array[int]) -> void:
	if _active_tab == &"expedition" and is_visible_in_tree() and not _picker.is_visible_in_tree():
		party_move_requested.emit(hero_id, target_index, expected)

func _on_fix_issue() -> void:
	if _active_tab != &"expedition" or not is_visible_in_tree() or not _fix_button.is_visible_in_tree(): return
	if _editing_deck: tab_requested.emit(&"deck")
	else: _open_party_picker(0)

func _has_living_heroes(profile: HeroHubState) -> bool:
	for hero: HeroProgression in profile.heroes.values():
		if hero != null and hero.hp_current > 0.0: return true
	return false

func _render_warnings(profile: HeroHubState) -> void:
	for child: Node in _warnings.get_children():
		_warnings.remove_child(child)
		child.queue_free()
	if profile.party.size() > 0 and profile.party.size() < HeroHubState.MAX_PARTY:
		_add_warning("В отряде есть свободные места", 0, &"party")
	for id: int in profile.party:
		var hero := profile.heroes.get(id) as HeroProgression
		if hero == null: continue
		if hero.available_points() > 0:
			_add_warning("%s: +%d очк. развития" % [hero.name, hero.available_points()], id, &"development")
		for item_id: int in profile.items:
			var item: Dictionary = profile.items[item_id]
			if int(item.hero_id) != id: continue
			var gear := HeroGearCatalog.definition(String(item.definition))
			if gear != null and gear.armor_max > 0.0 and float(item.remaining) < gear.armor_max:
				_add_warning("%s: броня %s/%d" % [hero.name, String.num(float(item.remaining), 1), gear.armor_max], id, &"smith")

func _add_warning(text: String, hero_id: int, destination: StringName) -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size.y = 44.0
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(_on_warning_pressed.bind(hero_id, destination))
	_warnings.add_child(button)

func _on_warning_pressed(hero_id: int, destination: StringName) -> void:
	if _active_tab != &"expedition" or not is_visible_in_tree(): return
	if destination == &"party": _open_party_picker(_profile.party.size())
	else: hero_route_requested.emit(hero_id, destination)

func select_hero_for(hero_id: int, destination: StringName) -> void:
	var target: StringName = &"mercenaries" if destination == &"development" else destination
	var page := _section_pages.get(target) as HubSectionPage
	if page == null: return
	page._selected_hero_id = hero_id
	page._selected_candidate = false
	page._mercenary_mode = &"owned"
	if destination == &"development": page.call_deferred("_on_action", "development_open")

func _living_reserve_count(profile: HeroHubState) -> int:
	var count: int = 0
	for hero_id: Variant in profile.heroes:
		if profile.party.has(int(hero_id)):
			continue
		var hero := profile.heroes[hero_id] as HeroProgression
		if hero != null and hero.hp_current > 0.0:
			count += 1
	return count

func _deck_summary_text(profile: HeroHubState) -> String:
	if profile.mage_deck.is_empty():
		return "Колода: Не используется"
	var base_types: Variant = profile.mage_deck.get("base_types", [])
	var count: int = base_types.size() if base_types is Array else 0
	return "Колода: %d карт" % count

func _render_tabs() -> void:
	for index: int in _tabs.size():
		if is_instance_valid(_tabs[index]): _tabs[index].set_pressed_no_signal(TAB_IDS[index] == _active_tab)

func _on_tab_pressed(tab_id: StringName) -> void:
	if _picker.is_visible_in_tree(): return
	var index := TAB_IDS.find(tab_id)
	if index < 0: return
	var button := _tabs[index]
	if not is_instance_valid(button) or not button.is_visible_in_tree(): return
	tab_requested.emit(tab_id)

func _on_start_pressed() -> void:
	if _start_button.disabled or _picker.is_visible_in_tree():
		return
	start_requested.emit()

func _on_manage_pressed() -> void:
	manage_requested.emit()

func _on_hire_requested(candidate_id: int) -> void:
	if _active_tab == &"mercenaries" and is_visible_in_tree(): hire_requested.emit(candidate_id)

func _on_party_requested(hero_id: int, join_party: bool) -> void:
	if _active_tab == &"mercenaries" and is_visible_in_tree(): party_requested.emit(hero_id, join_party)

func _on_equipment_requested(item_id: int, hero_id: int, equip_item: bool) -> void:
	if _active_tab == &"smith" and is_visible_in_tree(): equipment_requested.emit(item_id, hero_id, equip_item)

func _on_allocation_requested(hero_id: int, expected: Dictionary, delta: Array[int]) -> void:
	if _active_tab == &"mercenaries" and is_visible_in_tree(): allocation_requested.emit(hero_id, expected, delta)

func _on_skin_selection_requested(class_id: StringName, skin_id: StringName) -> void:
	if _active_tab == &"mercenaries" and is_visible_in_tree(): skin_selection_requested.emit(class_id, skin_id)

func _on_hero_route_requested(hero_id: int, destination: StringName) -> void:
	if _active_tab == &"mercenaries" and is_visible_in_tree(): hero_route_requested.emit(hero_id, destination)

func deck_page_visible() -> bool:
	return is_instance_valid(_deck_page) and is_ancestor_of(_deck_page) and _deck_page.is_visible_in_tree()

func _on_deck_action_requested(action: String, type_id: String) -> void:
	if _active_tab == &"deck" and deck_page_visible(): deck_action_requested.emit(action, type_id)
