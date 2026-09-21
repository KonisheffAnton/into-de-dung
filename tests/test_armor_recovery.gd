extends SceneTree

var passed: int = 0
var failed: int = 0

func _initialize() -> void: call_deferred("_run")
func check(value: bool, label: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		printerr("FAIL ARMOR RECOVERY: " + label)

func pieces(s: BattleArmorSession, unit: UnitState) -> Array[ItemInstance]:
	var result: Array[ItemInstance] = []
	for item: ItemInstance in s.state.get_owner(unit.id)._items.values():
		if item.get_definition().armor_max > 0: result.append(item)
	return result

func cast(s: BattleArmorSession, volume: int = 20) -> ActionReceipt:
	var unit := s.units[0]
	return s._queue.submit(RestoreArmorCommand.new(unit.id, volume, s.context.get_revision()), s.context)

func _run() -> void:
	var s := BattleArmorSession.new()
	var unit := s.units[0]
	var items := pieces(s, unit)
	items[0].armor_remaining = 30; items[1].armor_remaining = 30
	var before_rng := s.context.get_rng().to_dict()
	var initial := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	var admitted := s.context._move_rules
	for rules: MoveRules in [null, MoveRules.new([], 1, &"spatial_move_v1")]:
		s.context._move_rules = rules
		var refused := cast(s)
		check(refused.status == &"REJECTED" and refused.reason == &"armor/not_admitted", "restore needs active admission")
		check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == initial and s.context.get_rng().to_dict() == before_rng, "admission refusal has no cost or mutation")
	s.context._move_rules = admitted
	var receipt := cast(s, 3)
	check(receipt.status == &"APPLIED", "cast applied: " + String(receipt.reason))
	check(items[0].armor_remaining == 32 and items[1].armor_remaining == 31, "shortage 30/10 restores 2/1")
	check(unit.action_resources.get_main_left() == 0, "full cast cost")
	check(unit.armor.grants.is_empty() and s.context.get_rng().to_dict() == before_rng, "no extra or RNG for proportional restore")
	check(receipt.get_events().size() == 1 and receipt.get_events()[0]["items"].size() == 2, "actual item restore event")
	unit.try_refill_turn_resources()
	items[0].armor_remaining = 59; items[1].armor_remaining = 40
	receipt = cast(s)
	check(receipt.status == &"APPLIED" and items[0].armor_remaining == 60 and unit.armor.grants[0]["remaining"] == 19, "overflow restores one and grants19")
	unit.try_refill_turn_resources()
	unit.armor.perks.append({"id": "carry", "kind": "persistent_armor", "source": "item"})
	receipt = cast(s)
	check(receipt.status == &"APPLIED" and unit.armor.grants.size() == 2 and unit.armor.grants[1]["remaining"] == 20, "new cast adds separate grant")
	check(unit.armor.grants[0]["expires"] == "battle" and unit.armor.grants[1]["expires"] == "persistent", "new perk does not extend old grant")
	for enemy: UnitState in s.units:
		if enemy.faction != Faction.Type.ENEMY: continue
		s._queue.submit(DeathCommand.new(enemy.id, DamageSource.new(&"test",0,enemy.cell)), s.context)
	check(not unit.armor.in_battle and unit.armor.grants.size() == 1 and unit.armor.grants[0]["remaining"] == 20, "battle end expires only ordinary grants")
	check(ArmorEndBattleCommand.new(unit.id).validate(s.context) != &"", "expiry cannot repeat")
	check(unit.armor.grants.size() == 1, "expiry idempotent")
	var before := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	unit.try_refill_turn_resources()
	before = ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	receipt = cast(s)
	check(receipt.status == &"REJECTED" and receipt.reason == &"armor/full", "out of battle full rejects")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == before, "refusal unchanged")
	items[0].armor_remaining = 55
	receipt = cast(s)
	check(receipt.status == &"APPLIED" and items[0].armor_remaining == 60 and unit.armor.grants[0]["remaining"] == 20 and unit.action_resources.get_main_left() == 0, "outside partial restore pays full cost and preserves persistent")
	var view := ArmorRuntime.capture(s.state.get_owner(unit.id))
	view["items"][view["items"].size() - 2]["remaining"] = 30
	view["items"][view["items"].size() - 1]["remaining"] = 30
	var selection: Array[int] = [items[0].get_item_instance_id(), items[1].get_item_instance_id()]
	var repair := ArmorRecovery.repair(view, selection, 3, 50)
	check(repair["reason"] == &"" and repair["cost"] == 3 and repair["items"][0]["after"] == 32 and repair["items"][1]["after"] == 31, "repair30/10 budget3 pays3")
	view = ArmorRuntime.capture(s.state.get_owner(unit.id))
	for item: Dictionary in view["items"]:
		if item["item_id"] == selection[0]: item["remaining"] = 55
	repair = ArmorRecovery.repair(view, selection, 20, 100)
	check(repair["cost"] == 5, "repair pays actual shortage5")
	repair = ArmorRecovery.repair(view, selection, 20, 2)
	check(repair["cost"] == 2, "repair limited by squad materials")
	check(ArmorRecovery.repair(view, selection, 0, 100)["cost"] == 0, "zero repair no payment")
	s.close()

	s = BattleArmorSession.new()
	unit = s.units[0]
	items = pieces(s, unit)
	var unchanged := ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict()
	receipt = cast(s, 0)
	check(receipt.status == &"REJECTED" and unit.action_resources.get_main_left() == 1, "zero cast rejects without cost")
	check(ItemSimulationSnapshot.capture(s.state, []).snapshot.to_dict() == unchanged, "zero cast leaves all state")
	unit.armor.in_battle = false
	s.state.get_equipment(unit.id).unequip(EquipmentState.EquipSlot.ARMOR)
	s.state.get_equipment(unit.id).unequip(EquipmentState.EquipSlot.TRINKET)
	unit.armor.in_battle = true
	receipt = cast(s)
	check(receipt.status == &"APPLIED" and ArmorRuntime.totals(ArmorRuntime.capture(s.state.get_owner(unit.id)))["maximum"] == 0 and unit.armor.grants[0]["remaining"] == 20, "zero max gets temporary armor")
	check(not s.state.get_equipment(unit.id).equip(EquipmentState.EquipSlot.ARMOR, items[0]), "cannot change equipment during battle")
	s.close()
	print("ARMOR RECOVERY RESULTS: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
