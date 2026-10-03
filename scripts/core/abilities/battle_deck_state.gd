extends RefCounted
class_name BattleDeckState

const MAX_ID: int = ActionContext.MAX_ID
const HAND_LIMIT: int = 6
var catalog_id: String = MageCardCatalog.CATALOG_ID
var catalog_version: int = MageCardCatalog.VERSION
var cards: Array[Dictionary] = []
var draw_ids: Array[int] = []
var hand_ids: Array[int] = []
var spent_ids: Array[int] = []
var draw_rng: CombatRng
var mulligan_done: bool = false
var replaced_serial: int = 0

func to_dict() -> Dictionary:
	return {"schema":1,"catalog_id":catalog_id,"catalog_version":catalog_version,
		"cards":cards.duplicate(true),"draw_ids":draw_ids.duplicate(),"hand_ids":hand_ids.duplicate(),
		"spent_ids":spent_ids.duplicate(),"draw_rng":{} if draw_rng == null else draw_rng.to_dict(),
		"mulligan_done":mulligan_done,"replaced_serial":replaced_serial}

func duplicate() -> BattleDeckState:
	return from_dict(to_dict())

func apply_values(value: Dictionary) -> bool:
	var checked := BattleDeckState.from_dict(value)
	if checked == null: return false
	if draw_rng == null: draw_rng=CombatRng.new()
	if not draw_rng.from_dict(value.draw_rng): return false
	catalog_id=checked.catalog_id; catalog_version=checked.catalog_version
	cards.assign(checked.cards); draw_ids.assign(checked.draw_ids); hand_ids.assign(checked.hand_ids); spent_ids.assign(checked.spent_ids)
	mulligan_done=checked.mulligan_done; replaced_serial=checked.replaced_serial
	return true

func valid() -> bool:
	if catalog_id != MageCardCatalog.CATALOG_ID or catalog_version != MageCardCatalog.VERSION or draw_rng == null or draw_rng.get_script() != CombatRng: return false
	if cards.size() >= MAX_ID or replaced_serial < 0 or replaced_serial >= MAX_ID: return false
	var by_id: Dictionary = {}; var previous: int = 0
	for item: Dictionary in cards:
		if not ItemSimulationSnapshot._shape(item,{"id":TYPE_INT,"type_id":TYPE_STRING,"origin":TYPE_STRING}): return false
		if item.id <= previous or item.id >= MAX_ID or MageCardCatalog.get_card(item.type_id) == null or item.origin not in ["base","found"]: return false
		by_id[item.id]=item; previous=item.id
	var seen: Dictionary = {}
	for zone: Array in [draw_ids,hand_ids,spent_ids]:
		for id: int in zone:
			if id <= 0 or id >= MAX_ID or seen.has(id) or not by_id.has(id): return false
			seen[id]=true
	if cards.size() < 10 or seen.size() != cards.size() or hand_ids.size() > HAND_LIMIT: return false
	previous = 0
	for id: int in spent_ids:
		if id <= previous: return false
		previous=id
	return mulligan_done or (spent_ids.is_empty() and hand_ids.size() == 5 and replaced_serial == 0)

static func from_dict(value: Variant) -> BattleDeckState:
	if typeof(value) != TYPE_DICTIONARY: return null
	var fields: Dictionary = {"schema":TYPE_INT,"catalog_id":TYPE_STRING,"catalog_version":TYPE_INT,"cards":TYPE_ARRAY,
		"draw_ids":TYPE_ARRAY,"hand_ids":TYPE_ARRAY,"spent_ids":TYPE_ARRAY,"draw_rng":TYPE_DICTIONARY,
		"mulligan_done":TYPE_BOOL,"replaced_serial":TYPE_INT}
	if not ItemSimulationSnapshot._shape(value,fields) or value.schema != 1: return null
	var result := BattleDeckState.new()
	result.catalog_id=value.catalog_id; result.catalog_version=value.catalog_version
	for item: Variant in value.cards:
		if typeof(item) != TYPE_DICTIONARY: return null
		result.cards.append(item.duplicate(true))
	for id: Variant in value.draw_ids:
		if typeof(id) != TYPE_INT: return null
		result.draw_ids.append(id)
	for id: Variant in value.hand_ids:
		if typeof(id) != TYPE_INT: return null
		result.hand_ids.append(id)
	for id: Variant in value.spent_ids:
		if typeof(id) != TYPE_INT: return null
		result.spent_ids.append(id)
	result.draw_rng=CombatRng.new()
	if not result.draw_rng.from_dict(value.draw_rng): return null
	result.mulligan_done=value.mulligan_done; result.replaced_serial=value.replaced_serial
	return result if result.valid() else null

static func create(card_values: Array, seed: int) -> BattleDeckState:
	var result := BattleDeckState.new(); result.draw_rng=CombatRng.new(seed)
	for value: Variant in card_values:
		if typeof(value) != TYPE_DICTIONARY or not ItemSimulationSnapshot._shape(value,{"id":TYPE_INT,"type_id":TYPE_STRING,"origin":TYPE_STRING}): return null
		result.cards.append(value.duplicate(true))
	result.cards.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id < b.id)
	for item: Dictionary in result.cards: result.draw_ids.append(item.id)
	for i: int in range(result.draw_ids.size() - 1, 0, -1):
		var j: int = result.draw_rng.next_int(&"combat",i + 1)
		if j < 0: return null
		var tmp: int = result.draw_ids[i]; result.draw_ids[i]=result.draw_ids[j]; result.draw_ids[j]=tmp
	for _i: int in range(min(5,result.draw_ids.size())): result.hand_ids.append(result.draw_ids.pop_front())
	return result if result.valid() else null

static func draw_seed(run_id: int, node_id: int, battle_serial: int, battle_seed: int) -> int:
	if run_id <= 0 or run_id >= MAX_ID or node_id <= 0 or node_id >= MAX_ID or battle_serial <= 0 or battle_serial >= MAX_ID: return -1
	var source: String = "mage-deck-v1|%d|%d|%d|%d" % [run_id,node_id,battle_serial,battle_seed]
	var hasher := HashingContext.new()
	if hasher.start(HashingContext.HASH_SHA256) != OK or hasher.update(source.to_utf8_buffer()) != OK: return -1
	var digest: PackedByteArray = hasher.finish()
	var result: int = 0
	for index: int in range(8): result |= int(digest[index]) << (8 * index)
	return result & MAX_ID

func mulligan(ids: Array[int]) -> Dictionary:
	if not valid() or mulligan_done or not spent_ids.is_empty() or ids.size() > 2: return {}
	var chosen: Dictionary = {}
	for id: int in ids:
		if chosen.has(id) or not hand_ids.has(id): return {}
		chosen[id]=true
	var after := duplicate()
	if after == null: return {}
	if ids.is_empty(): after.mulligan_done=true; return {"after":after.to_dict()}
	var selected_slots: Array[int] = []
	for idx: int in range(after.hand_ids.size()):
		if chosen.has(after.hand_ids[idx]): selected_slots.append(idx)
	var old_ids: Array[int] = []
	for slot: int in selected_slots: old_ids.append(after.hand_ids[slot])
	var picked: Array[int] = []
	var slot_index: int = 0
	for old_id: int in old_ids:
		var old_type: String = after.card(old_id).type_id
		var candidates := _replacement_candidates(after.draw_ids, after.cards, old_type)
		if candidates.is_empty(): candidates = after.draw_ids.duplicate()
		if candidates.is_empty(): return {}
		var index: int = after.draw_rng.next_int(&"combat", candidates.size())
		if index < 0: return {}
		var new_id: int = candidates[index]
		after.draw_ids.erase(new_id); picked.append(new_id); after.hand_ids[selected_slots[slot_index]]=new_id
		slot_index += 1
	# Копии возвращаются только после всех выборов: одна карта не станет кандидатом для другой.
	for old_id: int in old_ids: after.draw_ids.append(old_id)
	for i: int in range(after.draw_ids.size() - 1, 0, -1):
		var j: int = after.draw_rng.next_int(&"combat", i + 1)
		if j < 0: return {}
		var tmp: int = after.draw_ids[i]; after.draw_ids[i]=after.draw_ids[j]; after.draw_ids[j]=tmp
	after.mulligan_done=true
	return {"after":after.to_dict()}

func replace(id: int, serial: int) -> Dictionary:
	if not valid() or not mulligan_done or serial <= 0 or serial >= MAX_ID or replaced_serial == serial or not hand_ids.has(id) or draw_ids.is_empty(): return {}
	var after := duplicate(); var old_type: String = after.card(id).type_id
	var candidates := _replacement_candidates(after.draw_ids, after.cards, old_type)
	if candidates.is_empty(): candidates=after.draw_ids.duplicate()
	var index: int = after.draw_rng.next_int(&"combat", candidates.size())
	if index < 0: return {}
	var new_id: int = candidates[index]; after.draw_ids.erase(new_id)
	after.hand_ids[after.hand_ids.find(id)]=new_id; after.draw_ids.append(id)
	for i: int in range(after.draw_ids.size() - 1,0,-1):
		var j: int=after.draw_rng.next_int(&"combat",i+1)
		if j < 0: return {}
		var tmp: int=after.draw_ids[i]; after.draw_ids[i]=after.draw_ids[j]; after.draw_ids[j]=tmp
	after.replaced_serial=serial
	return {"after":after.to_dict()}

func draw() -> Dictionary:
	if not valid() or not mulligan_done: return {}
	var after := duplicate()
	if after.hand_ids.size() < HAND_LIMIT and not after.draw_ids.is_empty(): after.hand_ids.append(after.draw_ids.pop_front())
	return {"after":after.to_dict()}

func play(id: int) -> Dictionary:
	if not valid() or not hand_ids.has(id): return {}
	var after := duplicate(); after.hand_ids.erase(id); after.spent_ids.append(id); after.spent_ids.sort()
	return {"after":after.to_dict()}

func card(id: int) -> Dictionary:
	for item: Dictionary in cards:
		if item.id == id: return item.duplicate(true)
	return {}

static func _replacement_candidates(source: Array[int], all_cards: Array[Dictionary], excluded_type: String) -> Array[int]:
	var result: Array[int] = []
	for id: int in source:
		for item: Dictionary in all_cards:
			if item.id == id and item.type_id != excluded_type: result.append(id)
	return result
