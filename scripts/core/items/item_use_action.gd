extends Resource
class_name ItemUseAction

enum Kind { HEAL_SELF, SUMMON_ADJACENT }
enum TargetMode { SELF, ADJACENT_CELL }

const MAIN_COST: int = 1
const CHARGE_COST: int = 1

var _kind: Kind
var _target_mode: TargetMode
var _heal_amount: float = 0.0
var _summon_definition: SummonDefinition = null
var _max_charges: int

static func from_definition(definition: ItemDef) -> ItemUseAction:
	if definition == null: return null
	var script: Script = definition.get_script()
	if script != ItemDef and script != Item: return null
	if definition.max_charges < 1 or definition.max_charges > 4096 or not definition.summon_definition_valid(): return null
	var action := ItemUseAction.new()
	action._max_charges = definition.max_charges
	if definition.use_summon:
		if definition.use_heal_amount != 0.0: return null
		var summon := definition.get_summon_definition()
		if not SummonDefinition.valid_definition(summon): return null
		action._kind = Kind.SUMMON_ADJACENT
		action._target_mode = TargetMode.ADJACENT_CELL
		action._summon_definition = summon
	else:
		if not is_finite(definition.use_heal_amount) or definition.use_heal_amount <= 0.0 or definition.summon_definition != null: return null
		action._kind = Kind.HEAL_SELF
		action._target_mode = TargetMode.SELF
		action._heal_amount = definition.use_heal_amount
	return action

func get_kind() -> Kind: return _kind
func get_target_mode() -> TargetMode: return _target_mode
func get_heal_amount() -> float: return _heal_amount
func get_summon_definition() -> SummonDefinition:
	return _summon_definition.duplicate(true) as SummonDefinition if _summon_definition != null else null
func get_max_charges() -> int: return _max_charges
func get_main_cost() -> int: return MAIN_COST
func get_charge_cost() -> int: return CHARGE_COST

func create_command(actor_id: int, item_id: int, expected_revision: int, cell: Vector2i = Vector2i(-1, -1)) -> Command:
	if get_script() != ItemUseAction: return null
	match _kind:
		Kind.HEAL_SELF:
			if _target_mode != TargetMode.SELF or not is_finite(_heal_amount) or _heal_amount <= 0.0 or _max_charges < 1 or _max_charges > 4096: return null
			return UseHealingItemCommand.new(actor_id, item_id, expected_revision)
		Kind.SUMMON_ADJACENT:
			if _target_mode != TargetMode.ADJACENT_CELL or _summon_definition == null or not SummonDefinition.valid_definition(_summon_definition) or _max_charges < 1 or _max_charges > 4096: return null
			return UseSummoningItemCommand.new(actor_id, item_id, cell, expected_revision)
	return null

func availability_reason(context: ActionContext, actor_id: int, item_id: int, cell: Vector2i = Vector2i(-1, -1)) -> StringName:
	if context == null: return &"item/invalid_runtime"
	var command := create_command(actor_id, item_id, context.get_revision(), cell)
	if command == null: return &"item/not_usable"
	return command.validate(context)

## Подсказка нужна для планирования; validate и очередь всё равно заново проверяют runtime целиком.
func hint_reason(context: ActionContext, actor_id: int, item_id: int, cell: Vector2i = Vector2i(-1, -1)) -> StringName:
	if context == null: return &"item/invalid_runtime"
	var command := create_command(actor_id, item_id, context.get_revision(), cell)
	if command is UseHealingItemCommand: return (command as UseHealingItemCommand).hint_reason(context)
	if command is UseSummoningItemCommand: return (command as UseSummoningItemCommand).hint_reason(context)
	return &"item/not_usable"

func target_cells(board: BattleBoard, origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _kind != Kind.SUMMON_ADJACENT or board == null: return result
	for offset: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		var cell := origin + offset
		if UseSummoningItemCommand.valid_cell(board, origin, cell): result.append(cell)
	return result
