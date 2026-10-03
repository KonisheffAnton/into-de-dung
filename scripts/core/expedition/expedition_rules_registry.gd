class_name ExpeditionRulesRegistry
extends RefCounted

const LEGACY: String = "u14-legacy-v1"
const DECK: String = "u14-deck-v1"

static func content_values() -> Dictionary:
	var data := ExpeditionCatalog.content_values()
	data.catalog_id = "u14-deck-content-v1"
	var cards: Array = []
	for card: MageCardDefinition in MageCardCatalog.all():
		var mechanical := card.to_dict()
		for key: String in ["name","description","image_key"]: mechanical.erase(key)
		cards.append(mechanical)
	return {"catalog_id":"u14-deck-content-v1","version":1,"rooms":data.rooms,"encounters":data.encounters,"cards":cards}

static func matches_content(data: Variant, deck: bool) -> bool:
	return ExpeditionCatalog._same_values(data, content_values()) if deck else ExpeditionCatalog.matches_content(data)

static func reward_seed(seed_value: int) -> int:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(("mage-reward-v1|%d" % seed_value).to_utf8_buffer())
	var bytes := hashing.finish()
	var result: int = 0
	for i: int in 8: result |= (int(bytes[i]) & (127 if i == 7 else 255)) << (8 * i)
	return result

static func generate(seed_value: int) -> Dictionary:
	# Геометрия, услуги и семена боёв остаются в своих прежних потоках.
	var plan := ExpeditionGenerator.generate(seed_value)
	plan.schema = 2; plan["ruleset_id"] = DECK; plan.content = content_values()
	var rng := CombatRng.new(reward_seed(seed_value))
	for node: Dictionary in plan.nodes:
		if node.kind not in ["battle","elite","final"]: continue
		var types: Array[String] = []
		for card: MageCardDefinition in MageCardCatalog.all(): types.append(String(card.id))
		types.sort()
		for i: int in 3:
			var value := rng.next_int(&"combat",12-i)
			if value < 0: return {}
			var other := i + value
			var saved: String = types[i]; types[i] = types[other]; types[other] = saved
		node.reward = types.slice(0,3)
	return plan
