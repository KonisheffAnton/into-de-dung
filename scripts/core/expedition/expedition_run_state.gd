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
var artifacts: Array[Dictionary] = []
var next_artifact_id: int = 1
var fallen: Array[String] = []

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
	return {"schema":1,"run_id":run_id,"plan":plan.duplicate(true),"phase":phase,
		"route":route.duplicate(),"resolved":resolved.duplicate(),"ordinary_item_ids":ordinary_item_ids.duplicate(),
		"battle_serial":battle_serial,"checkpoint":checkpoint.duplicate(true),"gold":gold,
		"artifacts":artifacts.duplicate(true),"next_artifact_id":next_artifact_id,"fallen":fallen.duplicate()}

static func from_dict(data: Variant) -> ExpeditionRunState:
	if not ItemSimulationSnapshot._shape(data, {"schema":TYPE_INT,"run_id":TYPE_INT,"plan":TYPE_DICTIONARY,"phase":TYPE_STRING,"route":TYPE_ARRAY,"resolved":TYPE_ARRAY,"ordinary_item_ids":TYPE_ARRAY,"battle_serial":TYPE_INT,"checkpoint":TYPE_DICTIONARY,"gold":TYPE_INT,"artifacts":TYPE_ARRAY,"next_artifact_id":TYPE_INT,"fallen":TYPE_ARRAY}): return null
	if data.schema != 1 or data.run_id < 1 or data.run_id > MAX_VALUE or not ExpeditionGenerator.valid(data.plan): return null
	if data.phase not in ["route","battle","reward","service","camp_departure"] or data.gold < 0 or data.gold > MAX_VALUE: return null
	if data.battle_serial < 0 or data.battle_serial > 6 or data.next_artifact_id < 1 or data.next_artifact_id > 6: return null
	if data.route.size() > 7 or data.ordinary_item_ids.size() > HeroHubState.MAX_PARTY * 2 or data.artifacts.size() > 5 or data.fallen.size() > HeroHubState.MAX_PARTY: return null
	var result := ExpeditionRunState.new()
	result.run_id = data.run_id; result.plan = data.plan.duplicate(true); result.phase = data.phase
	var previous: int = 0
	for id: Variant in data.route:
		if typeof(id) != TYPE_INT or id < 1 or id > 14: return null
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
		if result.phase == "reward" and kind not in ["battle","elite"]: return null
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
	if data.gold != expected_gold: return null
	for id: Variant in data.ordinary_item_ids:
		if typeof(id) != TYPE_INT or id < 1 or id >= MAX_VALUE or result.ordinary_item_ids.has(id): return null
		result.ordinary_item_ids.append(id)
	var ids: Dictionary = {}; var slots: Dictionary = {}; var types: Dictionary = {}
	var copies: int = 0
	for item: Variant in data.artifacts:
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
	if copies != data.next_artifact_id - 1 or copies != result._completed_reward_count(): return null
	for name_value: Variant in data.fallen:
		if typeof(name_value) != TYPE_STRING or name_value.length() > 128: return null
		result.fallen.append(name_value)
	result.battle_serial = data.battle_serial; result.gold = data.gold
	result.next_artifact_id = data.next_artifact_id
	result.checkpoint = data.checkpoint.duplicate(true)
	if result.phase == "battle":
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
	return {"heroes":heroes,"items":items,"artifacts":hub.expedition.artifacts.duplicate(true),"seed":seed_value}
