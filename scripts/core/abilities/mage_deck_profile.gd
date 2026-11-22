class_name MageDeckProfile
extends RefCounted

static func initial() -> Dictionary:
	return {"schema":2,"catalog_id":"mage-neutral-v1","catalog_version":1,
		"base_types":MageCardCatalog.default_base_types(),"crafted_types":[],"forge_discovered_types":[],
		"host_hero_id":0,"host_glow":{"color":"amber","form":"flame","flicker":"soft"}}

static func valid(data: Variant) -> bool:
	if not ItemSimulationSnapshot._shape(data,{"schema":TYPE_INT,"catalog_id":TYPE_STRING,"catalog_version":TYPE_INT,"base_types":TYPE_ARRAY,"crafted_types":TYPE_ARRAY,"forge_discovered_types":TYPE_ARRAY,"host_hero_id":TYPE_INT,"host_glow":TYPE_DICTIONARY}): return false
	if data.schema != 2 or data.catalog_id != "mage-neutral-v1" or data.catalog_version != 1 or not MageCardCatalog.valid_base(data.base_types): return false
	if data.host_hero_id < 0 or data.host_hero_id >= 1000000000: return false
	if not ItemSimulationSnapshot._shape(data.host_glow,{"color":TYPE_STRING,"form":TYPE_STRING,"flicker":TYPE_STRING}): return false
	if data.host_glow.color not in ["amber","blue","violet","white"] or data.host_glow.form not in ["glow","flame"] or data.host_glow.flicker not in ["still","soft"]: return false
	var sorted: Array = data.base_types.duplicate(); sorted.sort()
	if sorted != data.base_types: return false
	for key: String in ["crafted_types","forge_discovered_types"]:
		var previous := ""
		for value: Variant in data[key]:
			if typeof(value) != TYPE_STRING or value <= previous or MageCardCatalog.get_card(value) == null: return false
			previous = value
	return true
