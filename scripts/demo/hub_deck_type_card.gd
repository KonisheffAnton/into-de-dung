extends Button
class_name HubDeckTypeCard

var type_id: String = ""
var drag_started: bool = false
var _drag_enabled: bool = false
var _page_id: int = -1
var _generation: int = -1

func configure_drag(page_id: int, generation: int, enabled: bool) -> void:
	_page_id = page_id
	_generation = generation
	_drag_enabled = enabled

func render_card(card: MageCardDefinition, count: int, selected: bool) -> void:
	type_id = "" if card == null else card.id
	disabled = card == null
	tooltip_text = "" if card == null else "%s\nСтоимость: %d маны\nВ колоде: %d/2 копии" % [card.description, card.mana_cost, count]
	var title := "" if card == null else ("▸ " if selected else "") + card.name
	for child: Node in find_children("*", "", true, false):
		match String(child.get_meta(&"hub_field", "")):
			"title":
				if child is Label: (child as Label).text = title
			"subtitle":
				if child is Label: (child as Label).text = "" if card == null else "Общая"
			"description":
				if child is Label: (child as Label).text = "" if card == null else _short_description(card.description)
			"mana":
				if child is Label: (child as Label).text = "" if card == null else str(card.mana_cost)
			"count":
				if child is Label: (child as Label).text = "" if card == null else "×%d" % count
			"sigil":
				if child is Label: (child as Label).text = "" if card == null else _sigil_for(card.id)
	set_meta(&"hub_type_id", type_id)
	set_meta(&"hub_selected", selected)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if not _drag_enabled or type_id.is_empty() or not is_visible_in_tree() or disabled:
		return null
	if MageCardCatalog.get_card(type_id) == null:
		return null
	var preview := duplicate(0) as Control
	if preview != null:
		preview.set_script(null)
		preview.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		preview.custom_minimum_size = Vector2(108, 130)
		preview.size = Vector2(108, 130)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_drag_preview(preview)
	drag_started = true
	return {
		"kind": "hub_spellbook_card",
		"type_id": type_id,
		"source_id": int(get_instance_id()),
		"page_id": _page_id,
		"generation": _generation,
	}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		set_deferred("drag_started", false)

func _short_description(value: String) -> String:
	return value if value.length() <= 54 else value.substr(0, 53) + "…"

func _sigil_for(card_id: String) -> String:
	match card_id:
		"card.binding_thread": return "⌁"
		"card.fire", "card.burning", "card.fire_imbue": return "✦"
		"card.shield", "card.heal": return "◇"
		"card.summon", "card.raise": return "✹"
		_: return "✧"
