extends Resource
class_name ExpeditionEncounterDefinition

@export var kind: String = "battle"
@export var variant: int = 0
@export var enemy_hp: int = 24
@export var enemy_strength: int = 3
@export var enemy_weapon_damage: int = 3
@export var enemy_impact: int = 4
@export var enemy_balance: int = 12
@export var enemy_move: int = 4
@export var enemy_range: int = 1
@export var enemy_cells: Array[Vector2i] = []
@export var hazard_cells: Array[Vector2i] = [Vector2i(3,2),Vector2i(4,4),Vector2i(3,6)]

func valid() -> bool:
	if kind not in ["battle","elite","final"] or variant < 0 or variant > (2 if kind == "battle" else 1): return false
	if enemy_hp < 1 or enemy_hp > 1000 or enemy_strength < 0 or enemy_strength > 100 or enemy_cells.size() != (3 if kind == "battle" else 4): return false
	if enemy_weapon_damage < 0 or enemy_weapon_damage > 100 or enemy_impact < 0 or enemy_impact > 100 or enemy_balance < 1 or enemy_balance > 100 or enemy_move < 1 or enemy_move > 8 or enemy_range < 1 or enemy_range > 8: return false
	var cells: Dictionary = {}
	for cell: Vector2i in enemy_cells:
		if cell.x < 5 or cell.x > 7 or cell.y < 0 or cell.y > 7 or cells.has(cell): return false
		cells[cell] = true
	for cell: Vector2i in hazard_cells:
		if cell.x < 2 or cell.x > 7 or cell.y < 0 or cell.y > 7 or cells.has(cell): return false
		cells[cell] = true
	return true

func to_values() -> Dictionary:
	var enemies: Array[Array] = []
	var hazards: Array[Array] = []
	for cell: Vector2i in enemy_cells: enemies.append([cell.x,cell.y])
	for cell: Vector2i in hazard_cells: hazards.append([cell.x,cell.y])
	return {"kind":kind,"variant":variant,"version":1,"enemy_hp":enemy_hp,"enemy_strength":enemy_strength,
		"enemy_weapon_damage":enemy_weapon_damage,"enemy_impact":enemy_impact,"enemy_balance":enemy_balance,
		"enemy_move":enemy_move,"enemy_range":enemy_range,"enemy_cells":enemies,"hazard_cells":hazards}
