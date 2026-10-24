extends Control
class_name HubDeckPage

signal action_requested(action: String, type_id: String)

const PAGE_SIZE: int = 6

var selected_type_id: String = ""
var catalog_page: int = 0
var _profile: HeroHubState
var _editing: bool = false
var _draft_view: Array[String] = []
var _catalog: Array[MageCardDefinition] = []

func _ready() -> void:
	_catalog = MageCardCatalog.all()
	_connect_controls()

func render_profile(profile: HeroHubState, editing: bool, draft: Array) -> void:
	_connect_controls()
	_profile = profile
	_editing = editing
	_draft_view.clear()
	for value: Variant in draft:
		if typeof(value) == TYPE_STRING: _draft_view.append(String(value))
	if _catalog.is_empty(): _catalog = MageCardCatalog.all()
	if _catalog.is_empty():
		selected_type_id = ""
		catalog_page = 0
		_render_empty()
		return
	if MageCardCatalog.get_card(selected_type_id) == null:
		selected_type_id = _catalog[0].id
	catalog_page = clampi(catalog_page, 0, maxi(ceili(float(_catalog.size()) / float(PAGE_SIZE)) - 1, 0))
	_render_catalog()
	_render_selection()
	_render_deck()
	_render_actions()

func _connect_controls() -> void:
	for node: Node in find_children("*", "", true, false):
		if not node is BaseButton: continue
		var button := node as BaseButton
		var callback := _on_button_pressed.bind(button)
		if not button.pressed.is_connected(callback):
			button.pressed.connect(callback)

func _on_button_pressed(button: BaseButton) -> void:
	if button == null or not is_ancestor_of(button) or button.disabled or not is_visible_in_tree() or not button.is_visible_in_tree(): return
	var action := String(button.get_meta(&"hub_action", ""))
	if action.is_empty(): return
	if action == "deck_select_card":
		var type_id := String(button.get_meta(&"hub_type_id", ""))
		if MageCardCatalog.get_card(type_id) == null: return
		selected_type_id = type_id
		var index := MageCardCatalog.IDS.find(type_id)
		if index >= 0: catalog_page = floori(float(index) / float(PAGE_SIZE))
		_render_catalog()
		_render_selection()
		_render_actions()
		return
	if action == "deck_page_prev" or action == "deck_page_next":
		var last_page := maxi(ceili(float(_catalog.size()) / float(PAGE_SIZE)) - 1, 0)
		catalog_page = clampi(catalog_page + (-1 if action == "deck_page_prev" else 1), 0, last_page)
		_render_catalog()
		_render_pagination()
		return
	if _profile == null: return
	var legacy := _profile.mage_deck.is_empty()
	if action == "close":
		action_requested.emit("close", "")
		return
	if legacy or _profile.phase != "hub": return
	match action:
		"edit":
			if not _editing: action_requested.emit("edit", "")
		"plus":
			if _editing and _selected_count() < 2: action_requested.emit("plus", selected_type_id)
		"minus":
			if _editing and _selected_count() > 0: action_requested.emit("minus", selected_type_id)
		"save":
			if _editing and MageCardCatalog.valid_base(_draft_view): action_requested.emit("save", "")
		"cancel":
			if _editing: action_requested.emit("cancel", "")

func _render_empty() -> void:
	_text("deck_legacy_hint", "Колода недоступна")
	_text("deck_selected_title", "")
	_text("deck_selected_mana", "")
	_text("deck_selected_description", "")
	_text("deck_summary", "")
	_text("deck_count", "")
	for index: int in PAGE_SIZE:
		var card := _slot("deck_card_%d" % index) as HubDeckTypeCard
		if card != null: card.render_card(null, 0, false)

func _render_catalog() -> void:
	var start := catalog_page * PAGE_SIZE
	var current_types := _current_types()
	for index: int in PAGE_SIZE:
		var card := _slot("deck_card_%d" % index) as HubDeckTypeCard
		if card == null: continue
		var catalog_index := start + index
		if catalog_index >= _catalog.size():
			card.render_card(null, 0, false)
			continue
		var definition := _catalog[catalog_index]
		card.render_card(definition, current_types.count(definition.id), definition.id == selected_type_id)
	_render_pagination()

func _render_selection() -> void:
	var definition := MageCardCatalog.get_card(selected_type_id)
	_text("deck_selected_title", "" if definition == null else definition.name)
	_text("deck_selected_mana", "" if definition == null else "%d маны · %d/2 копии" % [definition.mana_cost, _selected_count()])
	_text("deck_selected_description", "" if definition == null else definition.description)
	var desc := _slot("deck_selected_description") as Control
	if desc != null: desc.tooltip_text = definition.description if definition != null else ""
	_render_catalog()

func _render_deck() -> void:
	if _profile == null:
		_text("deck_summary", "")
		_text("deck_count", "")
		return
	var types := _draft_view if _editing else _profile_types()
	var lines: PackedStringArray = []
	for definition: MageCardDefinition in _catalog:
		var count := types.count(definition.id)
		if count > 0: lines.append("%s ×%d" % [definition.name, count])
	_text("deck_summary", " · ".join(lines) if not lines.is_empty() else "В составе пока нет карт")
	_text("deck_count", "Карт в составе: %d/10" % types.size())

func _render_actions() -> void:
	if _profile == null: return
	var legacy := _profile.mage_deck.is_empty()
	var editable := _editing and not legacy and _profile.phase == "hub"
	var edit_button := _action_button("edit")
	if edit_button != null:
		edit_button.disabled = legacy or _profile.phase != "hub" or _editing
		edit_button.text = "Изменить"
	var plus_button := _action_button("plus")
	if plus_button != null: plus_button.disabled = not editable or _selected_count() >= 2
	var minus_button := _action_button("minus")
	if minus_button != null: minus_button.disabled = not editable or _selected_count() <= 0
	var save_button := _action_button("save")
	if save_button != null: save_button.disabled = not editable or not MageCardCatalog.valid_base(_draft_view)
	var cancel_button := _action_button("cancel")
	if cancel_button != null: cancel_button.disabled = not editable
	var legacy_label := _slot("deck_legacy_hint") as Control
	if legacy_label is Label:
		(legacy_label as Label).text = "Колода не используется в этом профиле" if legacy else "Ровно 10 карт · не более 2 копий одного типа"
	var selection_label := _action_button("plus")
	if selection_label != null: selection_label.tooltip_text = "Выберите профиль с включённой колодой" if legacy else "Добавить выбранный тип, максимум две копии"
	if save_button != null: save_button.tooltip_text = "Сохранить текущий состав колоды"
	if save_button != null: save_button.text = "Сохранить"
	_render_pagination()

func _render_pagination() -> void:
	var page_label := _slot("deck_page_number") as Label
	var pages := maxi(ceili(float(_catalog.size()) / float(PAGE_SIZE)), 1)
	if page_label != null: page_label.text = "Каталог %d/%d" % [catalog_page + 1, pages]
	var previous := _action_button("deck_page_prev")
	if previous != null: previous.disabled = catalog_page <= 0
	var next := _action_button("deck_page_next")
	if next != null: next.disabled = catalog_page >= pages - 1

func _profile_types() -> Array[String]:
	var result: Array[String] = []
	if _profile == null: return result
	var values: Variant = _profile.mage_deck.get("base_types", [])
	if typeof(values) != TYPE_ARRAY: return result
	for value: Variant in values:
		if typeof(value) == TYPE_STRING: result.append(String(value))
	return result

func _current_types() -> Array[String]:
	return _draft_view.duplicate() if _editing else _profile_types()

func _selected_count() -> int:
	return _current_types().count(selected_type_id)

func _slot(key: String) -> Node:
	for node: Node in find_children("*", "", true, false):
		if String(node.get_meta(&"hub_slot", "")) == key: return node
	return null

func _action_button(key: String) -> Button:
	for node: Node in find_children("*", "", true, false):
		if String(node.get_meta(&"hub_action", "")) == key and node is Button: return node as Button
	return null

func _text(key: String, value: String) -> void:
	var node := _slot(key)
	if node is Label: (node as Label).text = value
