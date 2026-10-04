class_name MageDeckPanel
extends RefCounted

static func base_editor(host: HeroHubScreen) -> void:
	var panel := host._content.get_node("BaseDeck") as Control
	var total_count: int = host.deck_draft.size() if host.deck_editing else host.run.mage_deck.base_types.size()
	HubUI.text(panel, ^"Title", "КОЛОДА МАГА · %d/10 · не более двух одного типа" % total_count)
	(panel.get_node("Summary") as Control).visible = not host.deck_editing
	(panel.get_node("deck_edit") as Control).visible = not host.deck_editing
	(panel.get_node("Editor") as Control).visible = host.deck_editing
	HubUI.bind(panel, ^"deck_edit", func() -> void:
		host.deck_editing = true
		host.deck_draft = host.run.mage_deck.base_types.duplicate()
		host._render())
	if not host.deck_editing:
		var names: PackedStringArray = []
		for card: MageCardDefinition in MageCardCatalog.all():
			var count: int = host.run.mage_deck.base_types.count(card.id)
			if count > 0: names.append("%s ×%d" % [card.name,count])
		HubUI.text(panel, ^"Summary", " · ".join(names))
		return
	HubUI.text(panel, ^"Editor/Count", "В составе: %d/10" % host.deck_draft.size())
	for card: MageCardDefinition in MageCardCatalog.all():
		var row := HubUI.instance("deck_card_entry", panel.get_node("Editor/Cards"))
		HubUI.text(row, ^"Row/Title", "%s · %d маны · %d/2" % [card.name,card.mana_cost,host.deck_draft.count(card.id)])
		HubUI.text(row, ^"Description", card.description)
		# Godot нормализует точку в имени Node; стабильный ключ нужен UI и тесту.
		var key := card.id.replace(".", "_")
		var minus := HubUI.bind(row, ^"Row/Less", _change_base.bind(host,card.id,-1))
		var plus := HubUI.bind(row, ^"Row/More", _change_base.bind(host,card.id,1))
		minus.name = "deck_less_" + key
		plus.name = "deck_more_" + key
		minus.disabled = host.deck_draft.count(card.id) == 0
		plus.disabled = host.deck_draft.count(card.id) == 2
	var save := HubUI.bind(panel, ^"Editor/deck_save", func() -> void:
		var values := host.deck_draft.duplicate()
		host.deck_editing = false
		host.deck_draft.clear()
		host._mutate(&"set_mage_base",[values]))
	save.disabled = not MageCardCatalog.valid_base(host.deck_draft)
	HubUI.bind(panel, ^"Editor/deck_cancel", func() -> void:
		host.deck_editing = false
		host.deck_draft.clear()
		host._render())

static func _change_base(host: HeroHubScreen, type_id: String, change: int) -> void:
	if not host.deck_editing or host._pending_save != null: return
	if change < 0: host.deck_draft.erase(type_id)
	elif host.deck_draft.count(type_id) < 2: host.deck_draft.append(type_id)
	host._render()

static func camp_editor(host: HeroHubScreen) -> void:
	var run := host.run.expedition
	var panel := host._content.get_node("CampDeck") as Control
	(panel.get_node("camp_deck_edit") as Control).visible = not host.deck_editing
	(panel.get_node("Editor") as Control).visible = host.deck_editing
	var edit := HubUI.bind(panel, ^"camp_deck_edit", func() -> void:
		# Черновик не должен менять опубликованный поход до записи candidate.
		host.deck_editing = true
		host.deck_draft = run.active_ids.duplicate()
		host._render())
	edit.text = "Изменить состав · %d активных / %d всего" % [run.active_ids.size(),run.cards.size()]
	if not host.deck_editing: return
	HubUI.text(panel, ^"Editor/Count", "Активно: %d · в хранении: %d" % [host.deck_draft.size(),run.cards.size()-host.deck_draft.size()])
	for record: Dictionary in run.cards:
		var card := MageCardCatalog.get_card(record.type_id)
		var id: int = record.id
		var row := HubUI.instance("card_choice", panel.get_node("Editor/Cards"))
		var button := HubUI.bind(row, ^"Choose", func() -> void:
			if host.deck_draft.has(id): host.deck_draft.erase(id)
			else: host.deck_draft.append(id)
			host._render())
		button.name = "camp_card_%d" % id
		button.text = "%s %s #%d · %s" % ["✓" if host.deck_draft.has(id) else "□",card.name,id,"база" if record.origin == "base" else "находка"]
		(row.get_node("Description") as Control).hide()
	var save := HubUI.bind(panel, ^"Editor/camp_deck_save", func() -> void:
		var values := host.deck_draft.duplicate()
		host.deck_editing = false
		host.deck_draft.clear()
		host._expedition_action("deck_compose",{"active_ids":values}))
	save.disabled = host.deck_draft.size() < 10
	HubUI.bind(panel, ^"Editor/camp_deck_cancel", func() -> void:
		host.deck_editing = false
		host.deck_draft.clear()
		host._render())

static func rewards(host: HeroHubScreen) -> void:
	var panel := HubUI.instance("deck_rewards_panel", host._content)
	(panel.get_node("FinalHint") as Control).visible = host.run.expedition.current_node().kind == "final"
	var types: Array = host.run.battle_report.offered_types
	for index: int in types.size():
		var card := MageCardCatalog.get_card(types[index])
		var row := HubUI.instance("card_choice", panel.get_node("Cards"))
		var button := HubUI.bind(row, ^"Choose", host._expedition_action.bind("reward",{"index":index}))
		button.name = "reward_%d" % index
		button.text = "%s · %d маны" % [card.name,card.mana_cost]
		HubUI.text(row, ^"Description", card.description)
	HubUI.bind(panel, ^"reward_skip", host._expedition_action.bind("reward",{"index":-1}))

static func report(host: HeroHubScreen) -> void:
	var report := host.run.battle_report
	var panel := HubUI.instance("deck_report_panel", host._content)
	var selection := panel.get_node("Selection") as Label
	selection.visible = report.reward_state in ["chosen", "skipped"]
	if report.reward_state == "chosen": selection.text = "Выбрана карта: " + MageCardCatalog.get_card(report.selected_type).name
	elif report.reward_state == "skipped": selection.text = "Награда пропущена."
	(panel.get_node("Return") as Control).visible = report.return_reason != "none"
	if report.return_reason == "none": return
	HubUI.text(panel, ^"Return/Title", "КАРТЫ ПОХОДА · переработано %d · эссенция +%d" % [report.recycled_count,report.essence_awarded])
	for record: Dictionary in report.returned_cards:
		if record.origin == "base": continue
		host._text_for_box(panel.get_node("Return/Cards"), "%s #%d · %s · %s" % [MageCardCatalog.get_card(record.type_id).name,record.id,"активная" if record.was_active else "хранение","потеряна" if record.disposition == "lost" else "переработана"],15)
	var names: PackedStringArray = []
	for type_id: String in report.new_forge_types: names.append(MageCardCatalog.get_card(type_id).name)
	HubUI.text(panel, ^"Return/Forge", "Новые открытия для кузни: " + ", ".join(names) + ". Это ещё не созданные артефакты.").visible = not names.is_empty()
