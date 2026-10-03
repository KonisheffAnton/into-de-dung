extends RefCounted
class_name ExpeditionHubPanel

static func render(host: HeroHubScreen) -> void:
	var run := host.run.expedition
	host._text("ПОХОД · пройдено %d/7 · добыча %d золота" % [run.resolved.size(),run.gold],23)
	host._text("Связи ведут вперёд. Условия раскрыты только у ближайших доступных комнат. Добыча сохраняется при возвращении.",15)
	if not host._message.is_empty(): host._text(host._message,14)
	for id: int in host.run.party:
		var hero: HeroProgression = host.run.heroes[id]
		var armor := host.run.equipped(id,"armor")
		var armor_text := "%d/%d" % [armor.remaining,HeroGearCatalog.definition(armor.definition).armor_max] if not armor.is_empty() else "0/0"
		host._text("%s · HP %.1f/%d · броня %s · свободные очки %d" % [hero.name,hero.hp_current,hero.max_hp(),armor_text,hero.available_points()],16)
	match run.phase:
		"reward":
			host._text("ПОБЕДА · выберите один артефакт, затем распределите экипировку",20)
			var rewards: Array = run.current_node().reward
			for index: int in rewards.size():
				var definition := ExpeditionCatalog.artifact(rewards[index])
				_action(host,host._content,definition.title,"reward_%d" % index,"reward",{"index":index})
				host._text(definition.description,15)
		"service":
			var node := run.current_node()
			host._text(ExpeditionCatalog.room_name(node.kind) + " · " + ExpeditionMapView.modifier_name(node.modifier),20)
			_action(host,host._content,"Восстановить %d%% максимального HP всему отряду" % (50 if node.modifier == "healing" else 25),"service_heal","service",{"kind":"heal"})
			_action(host,host._content,"Починить %d%% максимальной брони всему отряду" % (50 if node.modifier == "repair" else 25),"service_repair","service",{"kind":"repair"})
		"camp_departure":
			host._text("Безопасная точка · услуга получена",20)
			if run.is_deck(): MageDeckPanel.camp_editor(host)
			_action(host,host._content,"Продолжить поход","camp_continue","continue")
			_action(host,host._content,"Вернуться в хаб · сохранить добычу и переработать " + ("найденные карты" if run.is_deck() else "артефакты"),"camp_leave","leave")
	var map := ExpeditionMapView.new()
	map.run = run; map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.room_chosen.connect(func(id: int) -> void: host._expedition_action("choose",{"node":id}))
	host._content.add_child(map)
	if run.phase != "route": return
	host._text("ПОДГОТОВКА · выберите героя",20)
	var selectors := HFlowContainer.new(); host._content.add_child(selectors)
	for id: int in host.run.party:
		host._button_for(selectors,("• " if id == host.selected_hero_id else "") + (host.run.heroes[id] as HeroProgression).name,"select_%d" % id,host._select_hero.bind(id))
	host._text(host._hero_detail(host.run.heroes[host.selected_hero_id]),14)
	host._allocation_controls()
	if run.is_deck():
		host._text("Колода: %d активных, %d в хранении. Пересборка доступна у костра." % [run.active_ids.size(),run.cards.size()-run.active_ids.size()],16)
	else:
		host._text("АРТЕФАКТЫ · 3 слота · объединённые стаки неделимы",20)
		if run.artifacts.is_empty(): host._text("Пока пусто. Артефакт выбирается после каждой победы до финала.")
		for item: Dictionary in run.artifacts:
			var owner := "рюкзак" if item.hero_id == 0 else "%s · слот %d" % [(host.run.heroes[item.hero_id] as HeroProgression).name,item.slot]
			host._text("%s #%d · %d/%d · %s" % [ExpeditionCatalog.artifact_name(item.definition),item.id,item.stacks,ExpeditionCatalog.artifact(item.definition).max_stacks,owner],17)
			host._text(ExpeditionCatalog.artifact(item.definition).description,14)
			var row := HFlowContainer.new(); host._content.add_child(row)
			if item.hero_id != 0: _action(host,row,"Снять в рюкзак","artifact_off_%d" % item.id,"artifact_unequip",{"item":item.id,"hero":0,"slot":0})
			for slot: int in range(1,4):
				_action(host,row,"Выбранному · слот %d" % slot,"artifact_%d_slot_%d" % [item.id,slot],"artifact_equip",{"item":item.id,"hero":host.selected_hero_id,"slot":slot})
			if item.definition == "spark":
				for other: Dictionary in run.artifacts:
					if other.id > item.id and other.definition == "spark":
						var merge := _action(host,row,"Объединить с #%d" % other.id,"merge_%d_%d" % [item.id,other.id],"artifact_merge",{"item":other.id,"target":item.id})
						merge.disabled = int(item.stacks) + int(other.stacks) > 3
	host._text("ПОХОДНАЯ ЭКИПИРОВКА",20)
	for id: int in run.ordinary_item_ids:
		var item: Dictionary = host.run.items[id]
		var definition := HeroGearCatalog.definition(item.definition)
		var owner := "рюкзак" if item.hero_id == 0 else (host.run.heroes[item.hero_id] as HeroProgression).name
		var row := HFlowContainer.new(); host._content.add_child(row)
		host._text_for_box(row,"%s #%d · %s%s" % [definition.display_name,id,owner," · броня %d/%d" % [item.remaining,definition.armor_max] if definition.armor_max > 0 else ""],15)
		if item.hero_id != 0: _action(host,row,"Снять","gear_off_%d" % id,"unequip",{"item":id,"hero":0})
		var equip := _action(host,row,"Надеть выбранному","gear_on_%d" % id,"equip",{"item":id,"hero":host.selected_hero_id})
		equip.disabled = not HeroGearCatalog.allowed(item.definition,(host.run.heroes[host.selected_hero_id] as HeroProgression).class_id)

static func _action(host: HeroHubScreen, parent: Node, label: String, key: String, action: String, args: Dictionary = {}) -> Button:
	return host._button_for(parent,label,key,host._expedition_action.bind(action,args))
