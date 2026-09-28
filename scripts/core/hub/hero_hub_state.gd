extends RefCounted
class_name HeroHubState

const MAX_ROSTER: int = 12
const MAX_PARTY: int = 3
const RESPEC_PRICE: int = 50
const VICTORY_XP: int = 100
const VICTORY_GOLD: int = 40
const MAX_ITEMS: int = 2048
var heroes: Dictionary = {}
var party: Array[int] = []
var candidates: Array[HeroProgression] = []
var items: Dictionary = {}
var phase: String = "hub"
var gold: int = 100
var next_id: int = 1
var next_item_id: int = 1
var run_serial: int = 0
var rng_state: int = 0
var last_result: String = "Выберите отряд. Новички нанимаются бесплатно."

static func create(seed_value: int = 73191) -> HeroHubState:
	var result := HeroHubState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for class_id: StringName in HeroCatalog.class_ids():
		var hero := HeroCatalog.make_hero(result.next_id, class_id, rng)
		result.next_id += 1
		result.heroes[hero.id] = hero
		result._starter_gear(hero)
		if result.party.size() < MAX_PARTY: result.party.append(hero.id)
	result.rng_state = rng.state
	result._refresh_candidates()
	return result

func _refresh_candidates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.state = rng_state
	candidates.clear()
	for class_id: StringName in HeroCatalog.class_ids():
		candidates.append(HeroCatalog.make_hero(next_id, class_id, rng))
		next_id += 1
	rng_state = rng.state

func _starter_gear(hero: HeroProgression) -> void:
	for slot_name: String in ["weapon", "armor"]:
		var key := slot_name + ":" + String(hero.class_id)
		items[next_item_id] = {"id":next_item_id, "definition":key, "hero_id":hero.id, "remaining":HeroGearCatalog.definition(key).armor_max}
		next_item_id += 1

func hire(index: int) -> bool:
	if phase != "hub" or heroes.size() >= MAX_ROSTER or index < 0 or index >= candidates.size() or items.size() + 2 > MAX_ITEMS or next_id >= 1000000000: return false
	var hero := candidates[index]
	heroes[hero.id] = hero
	_starter_gear(hero)
	# Бесплатный новичок всегда доступен; новый ID не перебрасывает показанные свойства.
	var replacement := HeroProgression.from_dict(hero.to_dict())
	replacement.id = next_id
	replacement.name = "%s %d" % [HeroCatalog.class_definition(hero.class_id).display_name, next_id]
	next_id += 1
	candidates[index] = replacement
	return true

func toggle_party(id: int) -> bool:
	if phase != "hub" or not heroes.has(id): return false
	if party.has(id): party.erase(id)
	elif party.size() < MAX_PARTY: party.append(id)
	else: return false
	return true

func allocate(id: int, delta: Array[int]) -> bool:
	if phase != "hub" or not heroes.has(id): return false
	return (heroes[id] as HeroProgression).apply_allocation(delta)

func respec(id: int) -> bool:
	if phase != "hub" or gold < RESPEC_PRICE or not heroes.has(id): return false
	if not (heroes[id] as HeroProgression).reset_allocations(): return false
	gold -= RESPEC_PRICE
	return true

func equipped(id: int, slot_name: String) -> Dictionary:
	for item: Dictionary in items.values():
		if item.hero_id == id and HeroGearCatalog.slot(item.definition) == slot_name: return item
	return {}

func equip(item_id: int, hero_id: int) -> bool:
	if phase != "hub" or not items.has(item_id) or not heroes.has(hero_id): return false
	var item: Dictionary = items[item_id]
	var hero: HeroProgression = heroes[hero_id]
	if not HeroGearCatalog.allowed(item.definition, hero.class_id): return false
	var old := equipped(hero_id, HeroGearCatalog.slot(item.definition))
	if not old.is_empty(): old.hero_id = 0
	item.hero_id = hero_id
	return true

func unequip(item_id: int) -> bool:
	if phase != "hub" or not items.has(item_id): return false
	items[item_id].hero_id = 0
	return true

func discard_item(item_id: int) -> bool:
	if phase != "hub" or not items.has(item_id) or int(items[item_id].hero_id) != 0:
		return false
	# Освобождение склада явно выбирает игрок; автоматической потери добычи нет.
	items.erase(item_id)
	return true

func start_battle() -> bool:
	if phase != "hub" or party.is_empty() or party.size() > MAX_PARTY or run_serial >= 1000000000: return false
	for id: int in party:
		if not heroes.has(id): return false
	for id: int in party:
		var hero: HeroProgression = heroes[id]
		hero.hp_current = hero.max_hp()
	run_serial += 1
	phase = "battle"
	return true

func battle_items() -> Array[int]:
	var result: Array[int] = []
	for id: int in items:
		if party.has(items[id].hero_id): result.append(id)
	result.sort()
	return result

func finish_battle(serial: int, victory: bool, hp: Dictionary, gear: Dictionary) -> bool:
	if phase != "battle" or serial != run_serial or hp.size() != party.size() or gear.size() != battle_items().size(): return false
	var living: int = 0
	for id: Variant in hp:
		if typeof(id) != TYPE_INT or not party.has(id) or typeof(hp[id]) not in [TYPE_INT, TYPE_FLOAT]: return false
		var value := float(hp[id])
		if not is_finite(value) or value < 0 or value > (heroes[id] as HeroProgression).max_hp(): return false
		if value > 0: living += 1
	if victory != (living > 0): return false
	for id: Variant in gear:
		if typeof(id) != TYPE_INT or not battle_items().has(id) or typeof(gear[id]) != TYPE_INT: return false
		if gear[id] < 0 or gear[id] > HeroGearCatalog.definition(items[id].definition).armor_max: return false
	if victory:
		for id: int in heroes:
			if (heroes[id] as HeroProgression).xp_tenths > HeroProgression.MAX_XP_TENTHS - VICTORY_XP * 10: return false
		if gold > 1000000000 - VICTORY_GOLD: return false
	var lost: Array[int] = []
	for id: int in party:
		if float(hp[id]) <= 0: lost.append(id)
		else: (heroes[id] as HeroProgression).hp_current = float(hp[id])
	for id: int in gear:
		if not victory: items.erase(id)
		else:
			items[id].remaining = gear[id]
			if lost.has(items[id].hero_id): items[id].hero_id = 0
	for id: int in lost:
		heroes.erase(id)
		party.erase(id)
	if victory:
		gold += VICTORY_GOLD
		for id: int in heroes:
			# Десятые опыта сохраняют ровно 10%, включая награды меньше десяти.
			(heroes[id] as HeroProgression).award_experience_tenths(VICTORY_XP * (10 if party.has(id) else 1))
	phase = "hub"
	last_result = ("Победа: бойцам +%d опыта, резерву +%d; +%d золота." % [VICTORY_XP, VICTORY_XP / 10, VICTORY_GOLD]) if victory else "Поражение. Опыт не начислен. Бесплатные новички доступны в найме."
	last_result += " Погибло: %d." % lost.size()
	_refresh_candidates()
	return true

func to_dict() -> Dictionary:
	var hero_rows: Array[Dictionary] = []
	var candidate_rows: Array[Dictionary] = []
	var item_rows: Array[Dictionary] = []
	var ids := heroes.keys(); ids.sort()
	for id: int in ids: hero_rows.append((heroes[id] as HeroProgression).to_dict())
	for hero: HeroProgression in candidates: candidate_rows.append(hero.to_dict())
	ids = items.keys(); ids.sort()
	for id: int in ids: item_rows.append(items[id].duplicate(true))
	return {"schema":1, "heroes":hero_rows, "party":party.duplicate(), "candidates":candidate_rows, "items":item_rows, "phase":phase, "gold":gold, "next_id":next_id, "next_item_id":next_item_id, "run_serial":run_serial, "rng_state":rng_state, "last_result":last_result}

static func from_dict(data: Variant) -> HeroHubState:
	if not ItemSimulationSnapshot._shape(data, {"schema":TYPE_INT,"heroes":TYPE_ARRAY,"party":TYPE_ARRAY,"candidates":TYPE_ARRAY,"items":TYPE_ARRAY,"phase":TYPE_STRING,"gold":TYPE_INT,"next_id":TYPE_INT,"next_item_id":TYPE_INT,"run_serial":TYPE_INT,"rng_state":TYPE_INT,"last_result":TYPE_STRING}): return null
	if data.schema != 1 or data.phase not in ["hub", "battle"] or data.gold < 0 or data.gold > 1000000000 or data.run_serial < 0 or data.run_serial > 1000000000: return null
	if data.next_id < 1 or data.next_id > 1000000000 or data.next_item_id < 1 or data.next_item_id > 1000000000 or data.last_result.length() > 1024: return null
	if data.heroes.size() > MAX_ROSTER or data.party.size() > MAX_PARTY or data.candidates.size() != 4 or data.items.size() > MAX_ITEMS: return null
	var result := HeroHubState.new()
	var ids: Dictionary = {}
	for row: Variant in data.heroes:
		var hero := HeroProgression.from_dict(row)
		if hero == null or ids.has(hero.id) or hero.id >= data.next_id: return null
		ids[hero.id] = true
		result.heroes[hero.id] = hero
	var classes: Dictionary = {}
	for row: Variant in data.candidates:
		var hero := HeroProgression.from_dict(row)
		if hero == null or ids.has(hero.id) or hero.id >= data.next_id or hero.xp_tenths != 0 or hero.hp_current != hero.max_hp() or classes.has(hero.class_id): return null
		ids[hero.id] = true; classes[hero.class_id] = true
		result.candidates.append(hero)
	for id: Variant in data.party:
		if typeof(id) != TYPE_INT or not result.heroes.has(id) or result.party.has(id): return null
		result.party.append(id)
	if data.phase == "battle" and (result.party.is_empty() or data.run_serial == 0): return null
	var slots: Dictionary = {}
	for row: Variant in data.items:
		if not ItemSimulationSnapshot._shape(row, {"id":TYPE_INT,"definition":TYPE_STRING,"hero_id":TYPE_INT,"remaining":TYPE_INT}): return null
		var definition := HeroGearCatalog.definition(row.definition)
		if definition == null or row.id < 1 or row.id >= data.next_item_id or result.items.has(row.id) or row.remaining < 0 or row.remaining > definition.armor_max: return null
		if row.hero_id != 0:
			if not result.heroes.has(row.hero_id) or not HeroGearCatalog.allowed(row.definition, (result.heroes[row.hero_id] as HeroProgression).class_id): return null
			var key := "%d:%s" % [row.hero_id, HeroGearCatalog.slot(row.definition)]
			if slots.has(key): return null
			slots[key] = true
		result.items[row.id] = row.duplicate(true)
	result.phase = data.phase; result.gold = data.gold
	result.next_id = data.next_id; result.next_item_id = data.next_item_id
	result.run_serial = data.run_serial; result.rng_state = data.rng_state; result.last_result = data.last_result
	return result
