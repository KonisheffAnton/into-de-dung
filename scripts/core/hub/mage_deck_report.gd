class_name MageDeckReport
extends RefCounted

const FIELDS: Dictionary = {"ruleset_id":TYPE_STRING,"reward_state":TYPE_STRING,"offered_types":TYPE_ARRAY,"selected_type":TYPE_STRING,"selected_card_id":TYPE_INT,"recycled_count":TYPE_INT,"new_forge_types":TYPE_ARRAY,"return_reason":TYPE_STRING,"returned_cards":TYPE_ARRAY}

static func upgrade(report: Dictionary, offered: Array) -> Dictionary:
	var data := report.duplicate(true)
	data.erase("artifact_selected")
	data.merge({"schema":2,"ruleset_id":ExpeditionRulesRegistry.DECK,"reward_state":"pending" if not offered.is_empty() else "none","offered_types":offered.duplicate(),"selected_type":"","selected_card_id":0,"recycled_count":0,"new_forge_types":[],"return_reason":"none","returned_cards":[]},true)
	return data

static func finish_run(hub: HeroHubState, defeat: bool, completed: bool) -> String:
	var run := hub.expedition
	var early: bool = not defeat and not completed
	if early:
		hub.battle_report = upgrade(PostBattleRules.begin(hub,"expedition",run.current_node().id,run.battle_serial,"Досрочное возвращение",true,false),[])
	var report := hub.battle_report
	report.return_reason = "defeat" if defeat else ("completed" if completed else "early")
	report.completed = completed; report.gold_scope = "hub"
	var new_types: Array[String] = []
	for card: Dictionary in run.cards:
		var disposition := "expired" if card.origin == "base" else ("lost" if defeat else "recycled")
		report.returned_cards.append({"id":card.id,"type_id":card.type_id,"origin":card.origin,"was_active":run.active_ids.has(card.id),"disposition":disposition})
		if disposition == "recycled":
			report.recycled_count += 1
			if not hub.mage_deck.forge_discovered_types.has(card.type_id) and not new_types.has(card.type_id): new_types.append(card.type_id)
	var essence: int = report.recycled_count * 10
	var gold: int = 0 if defeat else run.gold + (ExpeditionCatalog.FINAL_GOLD if completed else 0)
	if hub.gold > ExpeditionRunState.MAX_VALUE - gold or hub.essence > ExpeditionRunState.MAX_VALUE - essence: return "expedition/overflow"
	if defeat:
		for id: int in run.ordinary_item_ids: hub.items.erase(id)
	hub.gold += gold; hub.essence += essence
	new_types.sort(); report.new_forge_types = new_types
	hub.mage_deck.forge_discovered_types.append_array(new_types); hub.mage_deck.forge_discovered_types.sort()
	report.essence_awarded = essence; report.gold_lost = run.gold if defeat else 0
	if completed: report.gold_awarded += ExpeditionCatalog.FINAL_GOLD
	if early: report.gold_awarded = gold
	hub.last_result = "%s. Золото +%d, эссенция +%d. Найденные карты: %s." % ["Поражение" if defeat else ("Поход завершён" if completed else "Досрочное возвращение"),gold,essence,"потеряны" if defeat else "переработаны"]
	hub.expedition = null; hub.phase = "hub"; hub._refresh_candidates()
	return ""

static func valid(data: Dictionary, hub: HeroHubState) -> bool:
	if hub.mage_deck.is_empty() or typeof(data.get("schema")) != TYPE_INT or data.schema != 2: return false
	for key: String in FIELDS:
		if not data.has(key) or typeof(data[key]) != FIELDS[key]: return false
	# Общая форма проверяется до чтения полей и строк героев из внешнего save.
	var legacy := data.duplicate(true)
	for key: String in FIELDS: legacy.erase(key)
	legacy.schema = 1; legacy["artifact_selected"] = ""
	if not PostBattleRules._valid_legacy_report(legacy,hub,data.return_reason == "early"): return false
	if data.has("artifact_selected") or data.ruleset_id != ExpeditionRulesRegistry.DECK or data.source != "expedition": return false
	if data.reward_state not in ["pending","chosen","skipped","none"] or data.return_reason not in ["none","early","completed","defeat"]: return false
	var offered: Dictionary = {}
	for value: Variant in data.offered_types:
		if typeof(value) != TYPE_STRING or MageCardCatalog.get_card(value) == null or offered.has(value): return false
		offered[value] = true
	if data.offered_types.size() != (0 if data.reward_state == "none" else 3): return false
	if data.reward_state == "chosen":
		if not offered.has(data.selected_type) or data.selected_card_id < 11: return false
	elif data.selected_type != "" or data.selected_card_id != 0: return false
	var previous: int = 0; var recycled: int = 0; var found: Dictionary = {}; var chosen_present := false
	var base: Array[String] = []; var active_count: int = 0
	for card: Variant in data.returned_cards:
		if not ItemSimulationSnapshot._shape(card,{"id":TYPE_INT,"type_id":TYPE_STRING,"origin":TYPE_STRING,"was_active":TYPE_BOOL,"disposition":TYPE_STRING}): return false
		if card.id != previous + 1 or card.id >= ActionContext.MAX_ID or MageCardCatalog.get_card(card.type_id) == null or card.origin != ("base" if card.id <= 10 else "found"): return false
		previous = card.id
		if card.origin == "base": base.append(card.type_id)
		if card.was_active: active_count += 1
		if card.disposition != ("expired" if card.origin == "base" else ("lost" if data.return_reason == "defeat" else "recycled")): return false
		if card.disposition == "recycled": recycled += 1; found[card.type_id] = true
		if card.id == data.selected_card_id: chosen_present = card.type_id == data.selected_type and card.origin == "found"
	if data.recycled_count != recycled or data.essence_awarded != recycled * 10: return false
	var previous_type := ""
	for value: Variant in data.new_forge_types:
		if typeof(value) != TYPE_STRING or value <= previous_type or not found.has(value) or not hub.mage_deck.forge_discovered_types.has(value): return false
		previous_type = value
	if data.return_reason == "none":
		if not data.returned_cards.is_empty() or data.completed or not data.new_forge_types.is_empty(): return false
		if data.open:
			if hub.expedition == null or not hub.expedition.is_deck() or data.offered_types != hub.expedition.current_node().reward: return false
			if data.reward_state == "pending" and hub.expedition.phase != "reward": return false
			if data.reward_state in ["chosen","skipped"] and hub.expedition.phase != "route": return false
			if data.reward_state == "none": return false
			if data.reward_state == "chosen":
				var selected: Dictionary = {}
				for copy: Dictionary in hub.expedition.cards:
					if copy.id == data.selected_card_id: selected = copy
				if selected.get("type_id") != data.selected_type or selected.get("origin") != "found": return false
	else:
		if not MageCardCatalog.valid_base(base) or active_count < 10: return false
		if data.returned_cards.size() < 10 or (data.open and hub.phase != "hub") or data.completed != (data.return_reason == "completed"): return false
		if data.reward_state == "pending" or (data.reward_state == "chosen" and not chosen_present): return false
		if data.return_reason in ["early","defeat"] and data.reward_state != "none": return false
		if data.return_reason == "completed" and data.reward_state not in ["chosen","skipped"]: return false
		if data.return_reason == "early":
			if data.node_id != 8 or not data.victory or not data.repairs.is_empty() or not data.achievements.is_empty() or data.points_awarded != 0: return false
			for row: Dictionary in data.heroes:
				if row.xp_before != row.xp_after or row.hp_restored != 0.0: return false
	return true
