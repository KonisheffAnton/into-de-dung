class_name MageDeckPanel
extends RefCounted

const CARD_ICON: Texture2D = preload("res://assets/placeholder_battle/mage_card.svg")

static func base_editor(host: HeroHubScreen) -> void:
	var total_count: int = host.deck_draft.size() if host.deck_editing else host.run.mage_deck.base_types.size()
	host._text("КОЛОДА МАГА · %d/10 · не более двух одного типа" % total_count,20)
	if not host.deck_editing:
		var names: PackedStringArray = []
		for card: MageCardDefinition in MageCardCatalog.all():
			var count: int = host.run.mage_deck.base_types.count(card.id)
			if count > 0: names.append("%s ×%d" % [card.name,count])
		host._text(" · ".join(names),15)
		host._button_for(host._content,"Пересобрать базу","deck_edit",func() -> void:
			host.deck_editing = true; host.deck_draft = host.run.mage_deck.base_types.duplicate(); host._render())
		return
	host._text("В составе: %d/10" % host.deck_draft.size(),18)
	for card: MageCardDefinition in MageCardCatalog.all():
		var row := HBoxContainer.new(); host._content.add_child(row)
		var icon := TextureRect.new()
		icon.texture = CARD_ICON
		icon.custom_minimum_size = Vector2(18,18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		host._text_for_box(row,"%s · %d маны · %d/2" % [card.name,card.mana_cost,host.deck_draft.count(card.id)],16)
		# Godot нормализует точку в имени Node; стабильный ключ нужен UI и тесту.
		var key := card.id.replace(".", "_")
		var minus := host._button_for(row,"−","deck_less_" + key,_change_base.bind(host,card.id,-1))
		var plus := host._button_for(row,"+","deck_more_" + key,_change_base.bind(host,card.id,1))
		minus.disabled = host.deck_draft.count(card.id) == 0; plus.disabled = host.deck_draft.count(card.id) == 2
		host._text(card.description,14)
	var save := host._button_for(host._content,"Сохранить колоду","deck_save",func() -> void:
		var values := host.deck_draft.duplicate(); host.deck_editing = false; host.deck_draft.clear(); host._mutate(&"set_mage_base",[values]))
	save.disabled = not MageCardCatalog.valid_base(host.deck_draft)
	host._button_for(host._content,"Отмена","deck_cancel",func() -> void: host.deck_editing = false; host.deck_draft.clear(); host._render())

static func _change_base(host: HeroHubScreen, type_id: String, change: int) -> void:
	if not host.deck_editing or host._pending_save != null: return
	if change < 0: host.deck_draft.erase(type_id)
	elif host.deck_draft.count(type_id) < 2: host.deck_draft.append(type_id)
	host._render()

static func camp_editor(host: HeroHubScreen) -> void:
	var run := host.run.expedition
	host._text("КОЛОДА У КОСТРА · минимум 10 активных карт",20)
	if not host.deck_editing:
		host._button_for(host._content,"Изменить состав · %d активных / %d всего" % [run.active_ids.size(),run.cards.size()],"camp_deck_edit",func() -> void:
			# Черновик не должен менять опубликованный поход до записи candidate.
			host.deck_editing = true; host.deck_draft = run.active_ids.duplicate(); host._render())
		return
	host._text("Активно: %d · в хранении: %d" % [host.deck_draft.size(),run.cards.size()-host.deck_draft.size()],16)
	for record: Dictionary in run.cards:
		var card := MageCardCatalog.get_card(record.type_id)
		var id: int = record.id
		var button := host._button_for(host._content,"%s %s #%d · %s" % ["✓" if host.deck_draft.has(id) else "□",card.name,id,"база" if record.origin == "base" else "находка"],"camp_card_%d" % id,func() -> void:
			if host.deck_draft.has(id): host.deck_draft.erase(id)
			else: host.deck_draft.append(id)
			host._render())
		_card_button_icon(button)
	var save := host._button_for(host._content,"Применить состав","camp_deck_save",func() -> void:
		var values := host.deck_draft.duplicate(); host.deck_editing = false; host.deck_draft.clear(); host._expedition_action("deck_compose",{"active_ids":values}))
	save.disabled = host.deck_draft.size() < 10
	host._button_for(host._content,"Отмена","camp_deck_cancel",func() -> void: host.deck_editing = false; host.deck_draft.clear(); host._render())

static func rewards(host: HeroHubScreen) -> void:
	host._text("НАГРАДА · выберите одну карту или откажитесь",20)
	if host.run.expedition.current_node().kind == "final": host._text("Выбранная карта сразу будет переработана: +10 эссенции и открытие её типа для будущей кузни.",15)
	var types: Array = host.run.battle_report.offered_types
	for index: int in types.size():
		var card := MageCardCatalog.get_card(types[index])
		var button := host._button_for(host._content,"%s · %d маны" % [card.name,card.mana_cost],"reward_%d" % index,host._expedition_action.bind("reward",{"index":index}))
		_card_button_icon(button)
		host._text(card.description,15)
	host._button_for(host._content,"Отказаться от награды","reward_skip",host._expedition_action.bind("reward",{"index":-1}))

static func _card_button_icon(button: Button) -> void:
	button.icon = CARD_ICON
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width",18)

static func report(host: HeroHubScreen) -> void:
	var report := host.run.battle_report
	if report.reward_state == "chosen": host._text("Выбрана карта: " + MageCardCatalog.get_card(report.selected_type).name,17)
	elif report.reward_state == "skipped": host._text("Награда пропущена.",16)
	if report.return_reason == "none": return
	host._text("КАРТЫ ПОХОДА · переработано %d · эссенция +%d" % [report.recycled_count,report.essence_awarded],20)
	for record: Dictionary in report.returned_cards:
		if record.origin == "base": continue
		host._text("%s #%d · %s · %s" % [MageCardCatalog.get_card(record.type_id).name,record.id,"активная" if record.was_active else "хранение","потеряна" if record.disposition == "lost" else "переработана"],15)
	var names: PackedStringArray = []
	for type_id: String in report.new_forge_types: names.append(MageCardCatalog.get_card(type_id).name)
	if not names.is_empty(): host._text("Новые открытия для кузни: " + ", ".join(names) + ". Это ещё не созданные артефакты.",15)
