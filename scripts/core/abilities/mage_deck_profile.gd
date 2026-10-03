class_name MageDeckProfile
extends RefCounted

static func initial() -> Dictionary:
	return {"schema":1,"catalog_id":"mage-neutral-v1","catalog_version":1,
		"base_types":MageCardCatalog.default_base_types(),"crafted_types":[],"forge_discovered_types":[]}

static func valid(data: Variant) -> bool:
	if not ItemSimulationSnapshot._shape(data,{"schema":TYPE_INT,"catalog_id":TYPE_STRING,"catalog_version":TYPE_INT,"base_types":TYPE_ARRAY,"crafted_types":TYPE_ARRAY,"forge_discovered_types":TYPE_ARRAY}): return false
	if data.schema != 1 or data.catalog_id != "mage-neutral-v1" or data.catalog_version != 1 or not MageCardCatalog.valid_base(data.base_types): return false
	var sorted: Array = data.base_types.duplicate(); sorted.sort()
	if sorted != data.base_types: return false
	for key: String in ["crafted_types","forge_discovered_types"]:
		var previous := ""
		for value: Variant in data[key]:
			if typeof(value) != TYPE_STRING or value <= previous or MageCardCatalog.get_card(value) == null: return false
			previous = value
	return true
