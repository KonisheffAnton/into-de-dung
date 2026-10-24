extends Button
class_name HubDeckTypeCard

var type_id: String = ""

func render_card(card: MageCardDefinition, count: int, selected: bool) -> void:
	type_id = "" if card == null else card.id
	disabled = card == null
	var title := "" if card == null else ("▸ " if selected else "") + card.name
	var subtitle := "" if card == null else "%d маны · %d/2" % [card.mana_cost, count]
	for child: Node in find_children("*", "", true, false):
		match String(child.get_meta(&"hub_field", "")):
			"title":
				if child is Label: (child as Label).text = title
			"subtitle":
				if child is Label: (child as Label).text = subtitle
				if child is Control: (child as Control).tooltip_text = card.description if card != null else ""
	set_meta(&"hub_type_id", type_id)
	set_meta(&"hub_selected", selected)
