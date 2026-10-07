extends RefCounted
class_name ArmorState

## Capability включается явно; пустой запас не выключает свойства экипировки.
signal changed(kind: StringName, key: int, before: int, after: int)

var natural: Dictionary = {"physical": 0, "fire": 0}
var perks: Array[Dictionary] = []
var grants: Array[Dictionary] = []
var next_grant_id: int = 1
var battle_id: int = 1
var in_battle: bool = true
var shield: Dictionary = {}
var raised_shield: Dictionary = {}

func to_dict() -> Dictionary:
	var result := {"schema_version": 1, "natural": natural.duplicate(true), "perks": perks.duplicate(true), "grants": grants.duplicate(true), "next_grant_id": next_grant_id, "battle_id": battle_id, "in_battle": in_battle}
	RaisedShield.write_state(result, raised_shield)
	SpellShield.write_state(result, shield)
	return result

static func from_dict(data: Dictionary) -> ArmorState:
	if not valid(data): return null
	var result := ArmorState.new()
	result.natural = data["natural"].duplicate(true)
	result.perks.assign(data["perks"].duplicate(true))
	result.grants.assign(data["grants"].duplicate(true))
	result.next_grant_id = data["next_grant_id"]
	result.battle_id = data["battle_id"]
	result.in_battle = data["in_battle"]
	result.shield = data.get("shield", {}).duplicate(true)
	result.raised_shield = data.get("raised_shield", {}).duplicate(true)
	return result

static func valid(data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.get("schema_version") == 3:
		if not data.has("raised_shield") or not RaisedShield.valid(data["raised_shield"]) or data["raised_shield"].is_empty(): return false
		var prior: Dictionary = data.duplicate(true)
		prior.erase("raised_shield")
		prior["schema_version"] = 2 if prior.has("shield") else 1
		return valid(prior)
	if typeof(data) == TYPE_DICTIONARY and data.get("schema_version") == 2:
		if data.has("raised_shield"): return false
		if not data.get("in_battle", false) or not SpellShield.valid(data.get("shield")): return false
		var prior: Dictionary = data.duplicate(true)
		SpellShield.write_state(prior, {})
		return valid(prior)
	if not ItemSimulationSnapshot._shape(data, {"schema_version": TYPE_INT, "natural": TYPE_DICTIONARY, "perks": TYPE_ARRAY, "grants": TYPE_ARRAY, "next_grant_id": TYPE_INT, "battle_id": TYPE_INT, "in_battle": TYPE_BOOL}): return false
	if data["schema_version"] != 1 or data["next_grant_id"] < 1 or data["next_grant_id"] >= ActionContext.MAX_ID or data["battle_id"] < 1: return false
	if not valid_resistances(data["natural"]) or data["perks"].size() > 4096 or data["grants"].size() > 4096: return false
	var ids: Dictionary = {}
	for perk: Variant in data["perks"]:
		if ItemSimulationSnapshot._shape(perk, {"id": TYPE_STRING, "kind": TYPE_STRING, "source": TYPE_STRING}):
			if perk["id"].is_empty() or perk["kind"] != "persistent_armor" or perk["source"].is_empty(): return false
			if ids.has(perk["id"]) and ids[perk["id"]] != perk: return false
			ids[perk["id"]] = perk
			continue
		if not ItemSimulationSnapshot._shape(perk, {"id": TYPE_STRING, "type": TYPE_STRING, "branch": TYPE_STRING, "bonus": TYPE_INT}): return false
		if perk["id"].is_empty() or perk["type"] not in ["physical", "fire"] or perk["branch"] not in ["both", "armor", "natural"] or perk["bonus"] < 0: return false
		if ids.has(perk["id"]) and ids[perk["id"]] != perk: return false
		ids[perk["id"]] = perk
	ids.clear()
	for grant: Variant in data["grants"]:
		if not ItemSimulationSnapshot._shape(grant, {"grant_id": TYPE_INT, "source": TYPE_STRING, "remaining": TYPE_INT, "expires": TYPE_STRING, "battle_id": TYPE_INT}): return false
		if grant["grant_id"] < 1 or grant["grant_id"] >= data["next_grant_id"] or ids.has(grant["grant_id"]) or grant["source"].is_empty() or grant["remaining"] < 0 or grant["expires"] not in ["battle", "persistent"] or grant["battle_id"] < 1: return false
		if grant["expires"] == "battle" and (not data["in_battle"] or grant["battle_id"] != data["battle_id"]): return false
		ids[grant["grant_id"]] = true
	return true

static func valid_resistances(data: Variant) -> bool:
	return ItemSimulationSnapshot._shape(data, {"physical": TYPE_INT, "fire": TYPE_INT})
