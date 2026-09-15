extends RefCounted
class_name ItemSimulationState

var _board: BattleBoard
var _owners: Array[ItemOwnerState] = []
var _inventories: Array[InventoryState] = []
var _equipment: Array[EquipmentState] = []
var _summons: Array[Dictionary] = []

func _init(board: BattleBoard, owners: Array[ItemOwnerState], inventories: Array[InventoryState], equipment: Array[EquipmentState]) -> void:
	_board = board
	# Списки принадлежат оболочке, иначе внешний composition root мог бы менять её во время preflight.
	_owners = owners.duplicate()
	_inventories = inventories.duplicate()
	_equipment = equipment.duplicate()

func get_board() -> BattleBoard:
	return _board

func get_owners() -> Array[ItemOwnerState]:
	return _owners.duplicate()

func get_owner(unit_id: int) -> ItemOwnerState:
	for owner in _owners:
		if owner != null and owner.get_owner() != null and owner.get_owner().id == unit_id:
			return owner
	return null

func get_inventory(unit_id: int) -> InventoryState:
	for inventory in _inventories:
		if inventory != null and not inventory.is_closed() and inventory._state._inventory_registered and inventory._state.get_owner() != null and inventory._state.get_owner().id == unit_id:
			return inventory
	return null

func get_equipment(unit_id: int) -> EquipmentState:
	for equipment in _equipment:
		if equipment != null and not equipment.is_closed() and equipment._state._equipment_registered and equipment._state.get_owner() != null and equipment._state.get_owner().id == unit_id:
			return equipment
	return null

func get_inventories() -> Array[InventoryState]:
	return _inventories.duplicate()

func get_equipment_facades() -> Array[EquipmentState]:
	return _equipment.duplicate()

func get_summons() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: Variant in _summons:
		if record is Dictionary:
			# Возвращаем копию всей записи: capture должен отклонить лишние поля, а не скрыть их.
			result.append((record as Dictionary).duplicate(true))
	return result

func is_summon_pending(unit_id: int) -> bool:
	for record: Dictionary in _summons:
		if record["unit_id"] == unit_id: return record["pending"]
	return false

func summon_owner_id(unit_id: int) -> int:
	for record: Dictionary in _summons:
		if record["unit_id"] == unit_id: return record["owner_unit_id"]
	return 0

func active_summon(owner_id: int) -> UnitState:
	for record: Dictionary in _summons:
		if record["owner_unit_id"] != owner_id: continue
		var unit := _board.get_unit_by_id(record["unit_id"]) if _board != null else null
		if unit != null and unit.is_alive(): return unit
	return null

func register_summon_owner(unit: UnitState, owner_id: int) -> void:
	# Метаданные регистрируются до board.add_unit, чтобы admission видел pending атомарно.
	if unit == null or _board == null or unit.id <= 0 or unit.id == owner_id: return
	if active_summon(owner_id) != null: return
	for record: Dictionary in _summons:
		if record["unit_id"] == unit.id: return
	var owner := ItemOwnerState.new(unit)
	owner.register_inventory()
	owner.register_equipment()
	_summons.append({"unit_id": unit.id, "owner_unit_id": owner_id, "pending": true})
	_owners.append(owner)
	_inventories.append(InventoryState._restore_registered(owner))
	_equipment.append(EquipmentState._restore_registered(owner))
