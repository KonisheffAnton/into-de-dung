extends RefCounted
class_name DamageSource

const KINDS: Array[StringName] = [&"attack", &"collision", &"fall", &"cell", &"status", &"item", &"test", &"mage"]
var kind: StringName
var source_instance_id: int
var origin_cell: Vector2i
var instigator_unit_id: int
var credit_unit_id: int

func _init(p_kind: StringName = &"", p_source_instance_id: int = 0, p_origin_cell: Vector2i = Vector2i.ZERO, p_instigator_unit_id: int = 0, p_credit_unit_id: int = 0) -> void:
	kind = p_kind; source_instance_id = p_source_instance_id; origin_cell = p_origin_cell; instigator_unit_id = p_instigator_unit_id; credit_unit_id = p_credit_unit_id
func copy() -> DamageSource: return DamageSource.new(kind, source_instance_id, origin_cell, instigator_unit_id, credit_unit_id)
func to_dict() -> Dictionary:
	return {"kind": kind, "source_instance_id": source_instance_id, "origin_cell": origin_cell, "instigator_unit_id": instigator_unit_id, "credit_unit_id": credit_unit_id}
func validate(context: ActionContext) -> StringName:
	if not KINDS.has(kind): return &"source/kind"
	if source_instance_id < 0 or source_instance_id >= ActionContext.MAX_ID: return &"source/source_instance_id"
	if instigator_unit_id < 0 or credit_unit_id < 0 or instigator_unit_id >= ActionContext.MAX_ID or credit_unit_id >= ActionContext.MAX_ID: return &"source/unit_id"
	if context == null or context.get_state() == null or context.get_state().get_board() == null: return &"source/context"
	if kind == &"mage" and not valid_mage(to_dict()): return &"source/mage"
	if kind != &"mage" and origin_cell == Vector2i(-1, -1): return &"source/origin"
	var board := context.get_state().get_board()
	if instigator_unit_id != 0 and board.get_unit_by_id(instigator_unit_id) == null: return &"source/instigator_unit_id"
	if credit_unit_id != 0 and board.get_unit_by_id(credit_unit_id) == null: return &"source/credit_unit_id"
	return &""

static func valid_mage(value: Dictionary) -> bool:
	return value.get("kind") == &"mage" and value.get("source_instance_id") in [1, 2] and value.get("origin_cell") == Vector2i(-1, -1) and value.get("instigator_unit_id") == 0 and value.get("credit_unit_id") == 0
