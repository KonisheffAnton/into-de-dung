extends RefCounted
class_name ItemSimulationState

var _board: BattleBoard
var _owners: Array[ItemOwnerState] = []
var _inventories: Array[InventoryState] = []
var _equipment: Array[EquipmentState] = []

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
