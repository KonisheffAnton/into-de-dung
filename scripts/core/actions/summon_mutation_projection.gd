extends RefCounted
class_name SummonMutationProjection

## Ожидаемый снимок атомарного создания помощника. Это checkpoint для проверки
## callbacks, а не preview: прогноз по-прежнему исполняет настоящую команду.
## Меняются только DTO; live-позицию и occupancy записывает BattleBoard.add_unit.
static func expected(before: ItemSimulationSnapshot, helper: UnitState, actor_id: int, height: int, main_cost: int, item_id: int = 0, charge_cost: int = 0, corpse_id: int = 0, ability_after: Dictionary = {}) -> ItemSnapshotResult:
	if before == null or helper == null or main_cost < 0 or (main_cost == 0 and ability_after.is_empty()):
		return ItemSimulationSnapshot._failure("summon/projection")
	var data := before.to_dict()
	if not ability_after.is_empty():
		if not data.has("abilities") or not BattleAbilityState.valid(ability_after): return ItemSimulationSnapshot._failure("summon/projection")
		data["abilities"] = ability_after.duplicate(true)
	if data.get("schema_version") not in [3, 4, 5, 6, 7, 8]: return ItemSimulationSnapshot._failure("summon/projection")
	var unit := helper.to_snapshot_dict()
	if unit.is_empty(): return ItemSimulationSnapshot._failure("summon/projection")
	unit["height"] = height
	var board: Dictionary = data["board_snapshot"]["board"]
	var actor_found := false
	for existing: Dictionary in board["units"]:
		if existing["id"] != actor_id: continue
		if not existing.has("action_resources"): return ItemSimulationSnapshot._failure("summon/projection")
		existing["action_resources"]["main_left"] -= main_cost
		actor_found = true
	if not actor_found: return ItemSimulationSnapshot._failure("summon/projection")
	if item_id != 0:
		var item_found := false
		for owner: Dictionary in data["owners"]:
			if owner["owner_unit_id"] != actor_id: continue
			for item: Dictionary in owner["items"]:
				if item["item_instance_id"] == item_id:
					item["charges_left"] -= charge_cost
					item_found = true
		if not item_found: return ItemSimulationSnapshot._failure("summon/projection")
	if corpse_id != 0:
		if not data.has("environment"): return ItemSimulationSnapshot._failure("summon/projection")
		var environment := CombatEnvironmentState.from_dict(data["environment"])
		if environment == null or environment.consume_corpse(corpse_id).is_empty(): return ItemSimulationSnapshot._failure("summon/projection")
		data["environment"] = environment.to_dict()
	board["board_version"] += 1
	board["units"].append(unit)
	board["occupancy"].append({"x": helper.cell.x, "y": helper.cell.y, "unit_id": helper.id})
	data["owners"].append({"schema_version": 1, "owner_unit_id": helper.id, "next_item_id": 1, "next_effect_id": 1, "closed": false, "inventory_lifecycle": 1, "equipment_lifecycle": 1, "inventory_order": [], "definitions": [], "items": []})
	data["summons"].append({"unit_id": helper.id, "owner_unit_id": actor_id, "pending": true})
	# Полная проверка итогового графа остаётся: лимиты, owner/item связи, pending,
	# геометрия и схемы не зависят от корректности построителя этой проекции.
	return ItemSimulationSnapshot.from_dict(data)
