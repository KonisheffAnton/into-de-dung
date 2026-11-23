extends Control
class_name HubDeckPage

signal action_requested(action: String, type_id: String)

const PAGE_SIZE: int = 8
const DECK_ROW: PackedScene = preload("res://scenes/demo/hub/sections/deck_list_entry.tscn")

var selected_type_id: String = ""
var catalog_page: int = 0
var _profile: HeroHubState
var _editing: bool = false
var _draft_view: Array[String] = []
var _catalog: Array[MageCardDefinition] = []
var _view_generation: int = 0
var _rendered_deck: Dictionary = {}

func _ready() -> void:
	_catalog = MageCardCatalog.all()
	_connect_controls()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey: return
	if not event.pressed or event.echo or event.keycode != KEY_ESCAPE: return
	var viewport := get_viewport()
	if not viewport.gui_is_dragging(): return
	var payload: Variant = viewport.gui_get_drag_data()
	if payload is Dictionary and payload.get("page_id") == get_instance_id():
		viewport.gui_cancel_drag()
		viewport.set_input_as_handled()

func render_profile(profile: HeroHubState, editing: bool, draft: Array) -> void:
	_view_generation += 1
	_connect_controls()
	_profile = profile
	_rendered_deck = {} if profile == null else profile.mage_deck.duplicate(true)
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
		if button is HubDeckTypeCard:
			var inspect := _inspect_card.bind(button)
			if not button.mouse_entered.is_connected(inspect): button.mouse_entered.connect(inspect)
			if not button.focus_entered.is_connected(inspect): button.focus_entered.connect(inspect)
	_connect_drop_controls()

func _inspect_card(button: BaseButton) -> void:
	if button == null or not is_ancestor_of(button) or button.disabled or not is_visible_in_tree() or not button.is_visible_in_tree(): return
	var type_id := String(button.get_meta(&"hub_type_id", ""))
	if MageCardCatalog.get_card(type_id) == null: return
	selected_type_id = type_id
	_render_selection()
	_render_actions()

func _on_button_pressed(button: BaseButton) -> void:
	if button == null or not is_ancestor_of(button) or button.disabled or not is_visible_in_tree() or not button.is_visible_in_tree(): return
	var action := String(button.get_meta(&"hub_action", ""))
	if action.is_empty(): return
	if action == "deck_select_card":
		if button is HubDeckTypeCard and (button as HubDeckTypeCard).drag_started: return
		var type_id := String(button.get_meta(&"hub_type_id", ""))
		if MageCardCatalog.get_card(type_id) == null: return
		_inspect_card(button)
		_request_type_action("add", type_id)
		return
	if action == "deck_remove_card":
		_request_type_action("remove", String(button.get_meta(&"hub_type_id", "")))
		return
	if action == "deck_page_prev" or action == "deck_page_next":
		var last_page := maxi(ceili(float(_catalog.size()) / float(PAGE_SIZE)) - 1, 0)
		catalog_page = clampi(catalog_page + (-1 if action == "deck_page_prev" else 1), 0, last_page)
		_view_generation += 1
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
		card.configure_drag(get_instance_id(), _view_generation, _can_add(definition.id))
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
	var list := _slot("deck_rows") as VBoxContainer
	if list == null: return
	# Только строки состава принадлежат данным; постоянная разметка книги не пересоздаётся.
	HubUI.clear_dynamic(list)
	var ordered: Array[MageCardDefinition] = _catalog.duplicate()
	ordered.sort_custom(func(a: MageCardDefinition, b: MageCardDefinition) -> bool:
		return a.mana_cost < b.mana_cost if a.mana_cost != b.mana_cost else a.id < b.id)
	for definition: MageCardDefinition in ordered:
		var count := types.count(definition.id)
		if count <= 0: continue
		var row := DECK_ROW.instantiate() as Button
		row.set_meta(&"hub_dynamic", true)
		row.set_meta(&"hub_type_id", definition.id)
		row.tooltip_text = "%s\n%d маны · %d копии\nНажмите, чтобы убрать одну копию" % [definition.description, definition.mana_cost, count]
		row.disabled = not _can_edit()
		list.add_child(row)
		for field: Node in row.find_children("*", "Label", true, false):
			match String(field.get_meta(&"hub_field", "")):
				"title": (field as Label).text = definition.name
				"mana": (field as Label).text = str(definition.mana_cost)
				"count": (field as Label).text = "×%d" % count
	_connect_controls()

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
		(legacy_label as Label).text = "Колода не используется в этом профиле" if legacy else "10 карт · до 2 копий одного типа"
	var hint := "Нажмите на карту или перетащите её в колоду"
	if legacy: hint = "В этом профиле колода не используется"
	elif _current_types().size() >= 10: hint = "Колода заполнена. Нажмите на строку, чтобы убрать карту"
	_text("deck_interaction_hint", hint)
	var selection_label := _action_button("plus")
	if selection_label != null: selection_label.tooltip_text = "Выберите профиль с включённой колодой" if legacy else "Добавить выбранный тип, максимум две копии"
	if save_button != null: save_button.tooltip_text = "Сохранить текущий состав колоды"
	if save_button != null: save_button.text = "Сохранить"
	_render_pagination()

func _render_pagination() -> void:
	var page_label := _slot("deck_page_number") as Label
	var pages := maxi(ceili(float(_catalog.size()) / float(PAGE_SIZE)), 1)
	if page_label != null: page_label.text = "Страница %d / %d" % [catalog_page + 1, pages]
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

func _can_edit() -> bool:
	return _profile != null and _profile.phase == "hub" and not _profile.mage_deck.is_empty() and _profile.mage_deck == _rendered_deck

func _can_add(type_id: String) -> bool:
	return _can_edit() and MageCardCatalog.get_card(type_id) != null and _current_types().size() < 10 and _current_types().count(type_id) < 2

func _request_type_action(action: String, type_id: String) -> void:
	if not is_visible_in_tree() or not _can_edit() or MageCardCatalog.get_card(type_id) == null: return
	if action == "add" and not _can_add(type_id): return
	if action == "remove" and not _current_types().has(type_id): return
	action_requested.emit(action, type_id)

func _connect_drop_controls() -> void:
	var target := _slot("deck_drop_target") as Control
	if target == null: return
	var controls: Array[Control] = [target]
	for node: Node in target.find_children("*", "Control", true, false): controls.append(node as Control)
	for control: Control in controls:
		control.set_drag_forwarding(Callable(), _can_drop_card.bind(control), _drop_card.bind(control))

func _can_drop_card(at_position: Vector2, data: Variant, receiver: Control) -> bool:
	var target := _slot("deck_drop_target") as Control
	if target == null or not is_instance_valid(receiver) or not target.is_visible_in_tree() or not receiver.is_visible_in_tree(): return false
	if receiver != target and not target.is_ancestor_of(receiver): return false
	if not target.get_global_rect().has_point(receiver.get_global_transform() * at_position): return false
	if not data is Dictionary: return false
	var payload: Dictionary = data
	if payload.get("kind") != "hub_spellbook_card": return false
	if typeof(payload.get("page_id")) != TYPE_INT or payload.page_id != get_instance_id(): return false
	if typeof(payload.get("generation")) != TYPE_INT or payload.generation != _view_generation: return false
	if typeof(payload.get("source_id")) != TYPE_INT or typeof(payload.get("type_id")) != TYPE_STRING: return false
	var source := instance_from_id(payload.source_id) as HubDeckTypeCard
	if source == null or not is_ancestor_of(source) or not source.is_visible_in_tree() or source.disabled: return false
	if source.type_id != payload.type_id or not source.drag_started: return false
	return is_visible_in_tree() and _can_add(payload.type_id)

func _drop_card(at_position: Vector2, data: Variant, receiver: Control) -> void:
	# Допуск пересчитывается при отпускании: смена страницы/профиля или повтор payload не добавляют карту.
	if _can_drop_card(at_position, data, receiver): _request_type_action("add", String(data.type_id))

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
