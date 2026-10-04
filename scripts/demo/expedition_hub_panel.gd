extends RefCounted
class_name ExpeditionHubPanel

static func render(host: HeroHubScreen) -> void:
	var run := host.run.expedition
	var page := host._page("ExpeditionPage")
	HubUI.text(page, ^"Title", "ПОХОД · пройдено %d/7 · добыча %d золота" % [run.resolved.size(),run.gold])
	HubUI.text(page, ^"Message", host._message).visible = not host._message.is_empty()
	for id: int in host.run.party:
		var hero: HeroProgression = host.run.heroes[id]
		var armor := host.run.equipped(id,"armor")
		var armor_text := "%d/%d" % [armor.remaining,HeroGearCatalog.definition(armor.definition).armor_max] if not armor.is_empty() else "0/0"
		host._text_for_box(page.get_node("Party"), "%s · HP %.1f/%d · броня %s · свободные очки %d" % [hero.name,hero.hp_current,hero.max_hp(),armor_text,hero.available_points()],16)
	(page.get_node("LegacyRewards") as Control).visible = run.phase == "reward"
	(page.get_node("Service") as Control).visible = run.phase == "service"
	(page.get_node("Camp") as Control).visible = run.phase == "camp_departure"
	match run.phase:
		"reward":
			host._content = page.get_node("LegacyRewards/Choices") as VBoxContainer
			var rewards: Array = run.current_node().reward
			for index: int in rewards.size():
				var definition := ExpeditionCatalog.artifact(rewards[index])
				_action(host,host._content,definition.title,"reward_%d" % index,"reward",{"index":index})
				host._text(definition.description,15)
		"service":
			var node := run.current_node()
			HubUI.text(page, ^"Service/Title", ExpeditionCatalog.room_name(node.kind) + " · " + ExpeditionMapView.modifier_name(node.modifier))
			var heal := HubUI.bind(page, ^"Service/service_heal", host._expedition_action.bind("service",{"kind":"heal"}))
			heal.text = "Восстановить %d%% максимального HP всему отряду" % (50 if node.modifier == "healing" else 25)
			var repair := HubUI.bind(page, ^"Service/service_repair", host._expedition_action.bind("service",{"kind":"repair"}))
			repair.text = "Починить %d%% максимальной брони всему отряду" % (50 if node.modifier == "repair" else 25)
		"camp_departure":
			host._content = page.get_node("Camp/Deck") as VBoxContainer
			host._content.visible = run.is_deck()
			if run.is_deck(): MageDeckPanel.camp_editor(host)
			HubUI.bind(page, ^"Camp/camp_continue", host._expedition_action.bind("continue",{}))
			var leave := HubUI.bind(page, ^"Camp/camp_leave", host._expedition_action.bind("leave",{}))
			leave.text = "Вернуться в хаб · сохранить добычу и переработать " + ("найденные карты" if run.is_deck() else "артефакты")
	var map := preload("res://scenes/demo/hub/expedition_map.tscn").instantiate() as ExpeditionMapView
	map.run = run
	map.set_meta(&"hub_dynamic", true)
	map.room_chosen.connect(func(id: int) -> void: host._expedition_action("choose",{"node":id}))
	page.get_node("Map").add_child(map)
	(page.get_node("Preparation") as Control).visible = run.phase == "route"
	if run.phase != "route": return
	var selectors := page.get_node("Preparation/Selectors")
	for id: int in host.run.party:
		host._button_for(selectors,("• " if id == host.selected_hero_id else "") + (host.run.heroes[id] as HeroProgression).name,"select_%d" % id,host._select_hero.bind(id))
	HubUI.text(page, ^"Preparation/Hero", host._hero_detail(host.run.heroes[host.selected_hero_id]))
	host._content = page.get_node("Preparation/Allocation") as VBoxContainer
	host._allocation_controls()
	(page.get_node("Preparation/Deck") as Control).visible = run.is_deck()
	(page.get_node("Preparation/Artifacts") as Control).visible = not run.is_deck()
	if run.is_deck():
		HubUI.text(page, ^"Preparation/Deck", "Колода: %d активных, %d в хранении. Пересборка доступна у костра." % [run.active_ids.size(),run.cards.size()-run.active_ids.size()])
	else:
		host._content = page.get_node("Preparation/Artifacts/Entries") as VBoxContainer
		if run.artifacts.is_empty(): host._text("Пока пусто. Артефакт выбирается после каждой победы до финала.")
		for item: Dictionary in run.artifacts:
			var owner := "рюкзак" if item.hero_id == 0 else "%s · слот %d" % [(host.run.heroes[item.hero_id] as HeroProgression).name,item.slot]
			var entry := HubUI.instance("expedition_item", host._content)
			HubUI.text(entry, ^"Title", "%s #%d · %d/%d · %s" % [ExpeditionCatalog.artifact_name(item.definition),item.id,item.stacks,ExpeditionCatalog.artifact(item.definition).max_stacks,owner])
			HubUI.text(entry, ^"Description", ExpeditionCatalog.artifact(item.definition).description)
			var row := entry.get_node("Actions")
			if item.hero_id != 0: _action(host,row,"Снять в рюкзак","artifact_off_%d" % item.id,"artifact_unequip",{"item":item.id,"hero":0,"slot":0})
			for slot: int in range(1,4):
				_action(host,row,"Выбранному · слот %d" % slot,"artifact_%d_slot_%d" % [item.id,slot],"artifact_equip",{"item":item.id,"hero":host.selected_hero_id,"slot":slot})
			if item.definition == "spark":
				for other: Dictionary in run.artifacts:
					if other.id > item.id and other.definition == "spark":
						var merge := _action(host,row,"Объединить с #%d" % other.id,"merge_%d_%d" % [item.id,other.id],"artifact_merge",{"item":other.id,"target":item.id})
						merge.disabled = int(item.stacks) + int(other.stacks) > 3
	for id: int in run.ordinary_item_ids:
		var item: Dictionary = host.run.items[id]
		var definition := HeroGearCatalog.definition(item.definition)
		var owner := "рюкзак" if item.hero_id == 0 else (host.run.heroes[item.hero_id] as HeroProgression).name
		var entry := HubUI.instance("expedition_item", page.get_node("Preparation/Equipment"))
		HubUI.text(entry, ^"Title", "%s #%d · %s%s" % [definition.display_name,id,owner," · броня %d/%d" % [item.remaining,definition.armor_max] if definition.armor_max > 0 else ""])
		(entry.get_node("Description") as Control).hide()
		var row := entry.get_node("Actions")
		if item.hero_id != 0: _action(host,row,"Снять","gear_off_%d" % id,"unequip",{"item":id,"hero":0})
		var equip := _action(host,row,"Надеть выбранному","gear_on_%d" % id,"equip",{"item":id,"hero":host.selected_hero_id})
		equip.disabled = not HeroGearCatalog.allowed(item.definition,(host.run.heroes[host.selected_hero_id] as HeroProgression).class_id)

static func _action(host: HeroHubScreen, parent: Node, label: String, key: String, action: String, args: Dictionary = {}) -> Button:
	return host._button_for(parent,label,key,host._expedition_action.bind(action,args))
