extends RefCounted
class_name ExpeditionRunState

const MAX_VALUE: int = 1000000000
var run_id: int = 0
var plan: Dictionary = {}
var phase: String = "route"
var route: Array[int] = []
var resolved: Array[int] = []
var ordinary_item_ids: Array[int] = []
var battle_serial: int = 0
var checkpoint: Dictionary = {}
var gold: int = 0
var repair_spent: int = 0
var artifacts: Array[Dictionary] = []
var next_artifact_id: int = 1
var fallen: Array[String] = []
var ruleset_id: String = ExpeditionRulesRegistry.LEGACY
var cards: Array[Dictionary] = []
var active_ids: Array[int] = []
var next_card_id: int = 1
var reward_decisions: Array[Dictionary] = []

func is_deck() -> bool:
	return ruleset_id == ExpeditionRulesRegistry.DECK

func active_cards() -> Array:
	var result: Array = []
	for card: Dictionary in cards:
		if active_ids.has(card.id): result.append(card.duplicate(true))
	return result

func current_node() -> Dictionary:
	return {} if route.is_empty() else plan.nodes[route.back() - 1].duplicate(true)

func available_nodes() -> Array[int]:
	var result: Array[int] = []
	if phase != "route": return result
	var ids: Array = plan.start if route.is_empty() else current_node().next
	for id: int in ids: result.append(id)
	return result

func artifact(id: int) -> Dictionary:
	for item: Dictionary in artifacts:
		if item.id == id: return item
	return {}

func to_dict() -> Dictionary:
	var data := {"schema":4,"ruleset_id":ruleset_id,"run_id":run_id,"plan":plan.duplicate(true),"phase":phase,
		"route":route.duplicate(),"resolved":resolved.duplicate(),"ordinary_item_ids":ordinary_item_ids.duplicate(),
		"battle_serial":battle_serial,"checkpoint":checkpoint.duplicate(true),"gold":gold,"repair_spent":repair_spent,
		"artifacts":artifacts.duplicate(true),"next_artifact_id":next_artifact_id,"fallen":fallen.duplicate()}
	if is_deck():
		data.erase("artifacts"); data.erase("next_artifact_id")
		data.merge({"catalog_id":"mage-neutral-v1","catalog_version":1,"cards":cards.duplicate(true),"active_ids":active_ids.duplicate(),"next_card_id":next_card_id,"reward_decisions":reward_decisions.duplicate(true)},true)
	return data

static func from_dict(data: Variant) -> ExpeditionRunState:
	if not data is Dictionary or typeof(data.get("schema")) != TYPE_INT or data.schema != 4: return null
	if typeof(data.get("ruleset_id")) != TYPE_STRING or data.ruleset_id not in [ExpeditionRulesRegistry.LEGACY, ExpeditionRulesRegistry.DECK]: return null
	var deck: bool = data.ruleset_id == ExpeditionRulesRegistry.DECK
	var shape := {"schema":TYPE_INT,"ruleset_id":TYPE_STRING,"run_id":TYPE_INT,"plan":TYPE_DICTIONARY,"phase":TYPE_STRING,"route":TYPE_ARRAY,"resolved":TYPE_ARRAY,"ordinary_item_ids":TYPE_ARRAY,"battle_serial":TYPE_INT,"checkpoint":TYPE_DICTIONARY,"gold":TYPE_INT,"repair_spent":TYPE_INT,"fallen":TYPE_ARRAY}
	if not deck: shape.merge({"artifacts":TYPE_ARRAY,"next_artifact_id":TYPE_INT})
	if deck:
		shape.merge({"catalog_id":TYPE_STRING,"catalog_version":TYPE_INT,"cards":TYPE_ARRAY,"active_ids":TYPE_ARRAY,"next_card_id":TYPE_INT,"reward_decisions":TYPE_ARRAY})
	if not ItemSimulationSnapshot._shape(data,shape): return null
	if deck and (data.ruleset_id != ExpeditionRulesRegistry.DECK or data.catalog_id != "mage-neutral-v1" or data.catalog_version != 1): return null
	if data.run_id < 1 or data.run_id > MAX_VALUE or not ExpeditionGenerator.valid(data.plan): return null
	if data.plan.ruleset_id != data.ruleset_id: return null
	if data.phase not in ["route","battle","reward","service","camp_departure"] or data.gold < 0 or data.gold > MAX_VALUE: return null
	if data.battle_serial < 0 or data.battle_serial > 6: return null
	if not deck and (data.next_artifact_id < 1 or data.next_artifact_id > 6 or data.artifacts.size() > 5): return null
	if data.route.size() > 7 or data.ordinary_item_ids.size() > HeroHubState.MAX_PARTY * 2 or data.fallen.size() > HeroHubState.MAX_PARTY: return null
	var result := ExpeditionRunState.new()
	result.ruleset_id = data.ruleset_id
	result.run_id = data.run_id; result.plan = data.plan.duplicate(true); result.phase = data.phase
	var previous: int = 0
	for id: Variant in data.route:
		if typeof(id) != TYPE_INT or id < 1 or id > data.plan.nodes.size(): return null
		var allowed: Array = data.plan.start if previous == 0 else data.plan.nodes[previous - 1].next
		if not allowed.has(id): return null
		result.route.append(id); previous = id
	for id: Variant in data.resolved:
		if typeof(id) != TYPE_INT or not result.route.has(id) or result.resolved.has(id): return null
		result.resolved.append(id)
	var required_resolved: Array[int] = result.route.duplicate()
	if result.phase != "route":
		if required_resolved.is_empty(): return null
		required_resolved.pop_back()
	if result.resolved != required_resolved: return null
	if result.phase == "route" and not result.route.is_empty() and result.current_node().kind == "final": return null
	if result.phase != "route":
		var kind: String = result.current_node().kind
		if result.phase == "battle" and kind not in ["battle","elite","final"]: return null
		if result.phase == "reward" and kind not in (["battle","elite","final"] if deck else ["battle","elite"]): return null
		if result.phase == "service" and kind not in ["rest","camp"]: return null
		if result.phase == "camp_departure" and kind != "camp": return null
	var combat_count: int = 0
	for id: int in result.route:
		if data.plan.nodes[id - 1].kind in ["battle","elite","final"]: combat_count += 1
	if combat_count != data.battle_serial: return null
	var expected_gold: int = 0
	for id: int in result.route:
		var node: Dictionary = data.plan.nodes[id - 1]
		if result.resolved.has(id) or (id == result.route.back() and result.phase == "reward"):
			if node.kind == "cache": expected_gold += ExpeditionCatalog.RICH_CACHE_GOLD if node.modifier == "rich" else ExpeditionCatalog.CACHE_GOLD
			else: expected_gold += ExpeditionCatalog.room(node.kind).gold
	var spent: int = data.repair_spent
	if spent < 0 or spent > expected_gold or data.gold != expected_gold - spent: return null
	result.repair_spent = spent
	for id: Variant in data.ordinary_item_ids:
		if typeof(id) != TYPE_INT or id < 1 or id >= MAX_VALUE or result.ordinary_item_ids.has(id): return null
		result.ordinary_item_ids.append(id)
	var ids: Dictionary = {}; var slots: Dictionary = {}; var types: Dictionary = {}
	var copies: int = 0
	for item: Variant in data.get("artifacts",[]):
		if not ItemSimulationSnapshot._shape(item, {"id":TYPE_INT,"definition":TYPE_STRING,"stacks":TYPE_INT,"hero_id":TYPE_INT,"slot":TYPE_INT}): return null
		var definition := ExpeditionCatalog.artifact(item.definition)
		if definition == null or item.id < 1 or item.id >= data.next_artifact_id or ids.has(item.id) or item.stacks < 1 or item.stacks > definition.max_stacks: return null
		if item.hero_id < 0 or item.hero_id >= MAX_VALUE or item.slot < 0 or item.slot > 3 or (item.hero_id == 0) != (item.slot == 0): return null
		if item.hero_id != 0:
			var slot_key := "%d:%d" % [item.hero_id,item.slot]
			var type_key := "%d:%s" % [item.hero_id,item.definition]
			if slots.has(slot_key) or types.has(type_key): return null
			slots[slot_key] = true; types[type_key] = true
		ids[item.id] = true; copies += item.stacks
		result.artifacts.append(item.duplicate(true))
	# Каждая награда создаёт одну копию; слияние не уничтожает ценность переработки.
	if not deck and (copies != data.next_artifact_id - 1 or copies != result._completed_reward_count()): return null
	if deck and not result._read_cards(data): return null
	for name_value: Variant in data.fallen:
		if typeof(name_value) != TYPE_STRING or name_value.length() > 128: return null
		result.fallen.append(name_value)
	result.battle_serial = data.battle_serial; result.gold = data.gold
	if not deck: result.next_artifact_id = data.next_artifact_id
	result.checkpoint = data.checkpoint.duplicate(true)
	if result.phase == "battle":
		if deck:
			if not result._valid_deck_checkpoint(): return null
		else:
			if not ItemSimulationSnapshot._shape(result.checkpoint, {"heroes":TYPE_ARRAY,"items":TYPE_ARRAY,"artifacts":TYPE_ARRAY,"seed":TYPE_INT}): return null
			if result.checkpoint.seed != result.current_node().battle_seed: return null
	else:
		if not result.checkpoint.is_empty(): return null
	return result

func _completed_reward_count() -> int:
	var count: int = 0
	for id: int in resolved:
		if plan.nodes[id - 1].kind in ["battle","elite"]: count += 1
	return count

func valid_profile(hub: HeroHubState) -> bool:
	if is_deck() and hub.mage_deck.is_empty(): return false
	if hub.phase != "expedition" or hub.run_serial != run_id or hub.party.is_empty(): return false
	for id: int in hub.party:
		if not hub.heroes.has(id) or (hub.heroes[id] as HeroProgression).hp_current <= 0.0: return false
	for id: int in ordinary_item_ids:
		if not hub.items.has(id): return false
		var owner: int = hub.items[id].hero_id
		if owner != 0 and not hub.party.has(owner): return false
	for item: Dictionary in hub.items.values():
		if hub.party.has(item.hero_id) and not ordinary_item_ids.has(item.id): return false
	for item: Dictionary in artifacts:
		if item.hero_id != 0 and not hub.party.has(item.hero_id): return false
	if phase == "battle":
		if checkpoint != make_checkpoint(hub, int(current_node().battle_seed)): return false
	return true

static func make_checkpoint(hub: HeroHubState, seed_value: int) -> Dictionary:
	var heroes: Array[Dictionary] = []; var items: Array[Dictionary] = []
	for id: int in hub.party: heroes.append((hub.heroes[id] as HeroProgression).to_dict())
	var ids: Array = hub.items.keys(); ids.sort()
	for id: int in ids:
		if hub.party.has(hub.items[id].hero_id): items.append(hub.items[id].duplicate(true))
	var run := hub.expedition
	if run.is_deck():
		return {"schema":1,"ruleset_id":ExpeditionRulesRegistry.DECK,"run_id":run.run_id,"node_id":run.current_node().id,"battle_serial":run.battle_serial,
			"legacy_inputs":{"heroes":heroes,"items":items,"seed":seed_value},"cards":run.cards.duplicate(true),"active_ids":run.active_ids.duplicate(),"catalog_id":"mage-neutral-v1","catalog_version":1,
			"draw_seed":BattleDeckState.draw_seed(run.run_id,run.current_node().id,run.battle_serial,seed_value)}
	return {"heroes":heroes,"items":items,"artifacts":run.artifacts.duplicate(true),"seed":seed_value}

func _read_cards(data: Dictionary) -> bool:
	if data.next_card_id < 11 or data.next_card_id >= ActionContext.MAX_ID or data.cards.size() != data.next_card_id - 1: return false
	var base_types: Array = []
	for i: int in data.cards.size():
		var card: Variant = data.cards[i]
		if not ItemSimulationSnapshot._shape(card,{"id":TYPE_INT,"type_id":TYPE_STRING,"origin":TYPE_STRING}): return false
		if card.id != i + 1 or MageCardCatalog.get_card(card.type_id) == null or card.origin != ("base" if i < 10 else "found"): return false
		if i < 10: base_types.append(card.type_id)
		cards.append(card.duplicate(true))
	if not MageCardCatalog.valid_base(base_types): return false
	var sorted: Array = base_types.duplicate(); sorted.sort()
	if sorted != base_types: return false
	var previous: int = 0
	for id: Variant in data.active_ids:
		if typeof(id) != TYPE_INT or id <= previous or id >= data.next_card_id: return false
		active_ids.append(id); previous = id
	if active_ids.size() < 10: return false
	var expected_nodes: Array[int] = []
	for id: int in resolved:
		if plan.nodes[id-1].kind in ["battle","elite","final"]: expected_nodes.append(id)
	if data.reward_decisions.size() != expected_nodes.size(): return false
	var next_found: int = 10
	for i: int in expected_nodes.size():
		var decision: Variant = data.reward_decisions[i]
		if not ItemSimulationSnapshot._shape(decision,{"node_id":TYPE_INT,"choice_index":TYPE_INT}) or decision.node_id != expected_nodes[i] or decision.choice_index < -1 or decision.choice_index > 2: return false
		if decision.choice_index >= 0:
			if next_found >= cards.size() or cards[next_found].type_id != plan.nodes[decision.node_id-1].reward[decision.choice_index]: return false
			next_found += 1
		reward_decisions.append(decision.duplicate(true))
	if next_found != cards.size(): return false
	next_card_id = data.next_card_id
	return true

func _valid_deck_checkpoint() -> bool:
	if not ItemSimulationSnapshot._shape(checkpoint,{"schema":TYPE_INT,"ruleset_id":TYPE_STRING,"run_id":TYPE_INT,"node_id":TYPE_INT,"battle_serial":TYPE_INT,"legacy_inputs":TYPE_DICTIONARY,"cards":TYPE_ARRAY,"active_ids":TYPE_ARRAY,"catalog_id":TYPE_STRING,"catalog_version":TYPE_INT,"draw_seed":TYPE_INT}): return false
	if checkpoint.schema != 1 or checkpoint.ruleset_id != ruleset_id or checkpoint.run_id != run_id or checkpoint.node_id != current_node().id or checkpoint.battle_serial != battle_serial: return false
	if checkpoint.catalog_id != "mage-neutral-v1" or checkpoint.catalog_version != 1 or checkpoint.cards != cards or checkpoint.active_ids != active_ids: return false
	if not ItemSimulationSnapshot._shape(checkpoint.legacy_inputs,{"heroes":TYPE_ARRAY,"items":TYPE_ARRAY,"seed":TYPE_INT}) or checkpoint.legacy_inputs.seed != current_node().battle_seed: return false
	return checkpoint.draw_seed == BattleDeckState.draw_seed(run_id,current_node().id,battle_serial,current_node().battle_seed)
