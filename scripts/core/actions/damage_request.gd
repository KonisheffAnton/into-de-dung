extends RefCounted
class_name DamageRequest

var target_unit_id: int
var amount: float
var damage_type: StringName
var armor_mode: StringName
var source: DamageSource

func _init(p_target_unit_id: int = 0, p_amount: float = 0.0, p_damage_type: StringName = &"", p_armor_mode: StringName = &"", p_source: DamageSource = null) -> void:
	target_unit_id = p_target_unit_id; amount = p_amount; damage_type = p_damage_type; armor_mode = p_armor_mode; source = p_source
func copy() -> DamageRequest: return DamageRequest.new(target_unit_id, amount, damage_type, armor_mode, source.copy() if source != null else null)
