extends RefCounted
class_name BattleFrameText

class CardText:
	extends RefCounted
	var text: String = ""
	var tooltip: String = ""

static func roster(row: Dictionary) -> String:
	var status := BattleStatusPresentation.summary(BattleStatusPresentation.entries(row))
	var text: String = ""
	if row.alive:
		text = "%s · HP %.1f / %.1f" % [row.name, row.hp, row.hp_max]
	else:
		text = "%s · погиб" % row.name
	if not status.is_empty(): text += " · " + status
	return text

static func details(row: Dictionary) -> String:
	return "%s · основное %d · движение %.1f · броня %d + %d" % [
		row.name,
		row.main,
		row.move,
		int(row.armor.get("current", 0)) - int(row.armor.get("extra", 0)),
		int(row.armor.get("extra", 0))
	]

static func mage(abilities: Dictionary, deck: Dictionary) -> String:
	if not deck.is_empty():
		var serials: Array = abilities.get("serials", [])
		var replacement_available: bool = serials.size() > 0 \
			and int(deck.get("replaced_serial", 0)) != int(serials[0]) \
			and not deck.get("draw_ids", []).is_empty()
		var replacement: String = "доступна" if replacement_available else "использована или добор пуст"
		return "Мана %d/%d · добор %d · сыграно %d · замена: %s" % [
			int(abilities.get("mana", 0)),
			int(abilities.get("maximum", 0)),
			deck.get("draw_ids", []).size(),
			deck.get("spent_ids", []).size(),
			replacement
		]
	return "Маг · мана %d" % int(abilities.get("mana", 0)) if not abilities.is_empty() else ""

static func mage_ledger_suffix(entry: Dictionary) -> String:
	var label: String = "огонь" if entry.ability_id == "mage.fire" else "лечение"
	return " · %s %d" % [label, int(entry.remaining)]

static func deck_tooltip(deck: Dictionary) -> String:
	return "Рука %d/6 · кадр исполненного действия" % deck.get("hand_ids", []).size()

static func card(deck: Dictionary, id: int) -> CardText:
	var type_id: String = ""
	for definition_row: Dictionary in deck.get("cards", []):
		if int(definition_row.id) == id:
			type_id = String(definition_row.type_id)
			break
	var definition := MageCardCatalog.get_card(type_id)
	var result := CardText.new()
	if definition != null:
		result.text = "%s\n%d маны" % [definition.name, definition.mana_cost]
		result.tooltip = "%s · копия #%d" % [definition.description, id]
	else:
		result.text = "Карта #%d" % id
		result.tooltip = "Копия #%d" % id
	return result
