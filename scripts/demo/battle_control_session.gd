extends BattleArmorSession
class_name BattleControlSession

## Сценарий C1 начинает с двух контролируемых целей; наложение — отдельный срез.
func reset() -> void:
	super.reset()
	var positions: Array[Vector2i] = [Vector2i(2, 2), Vector2i(3, 2), Vector2i(5, 4), Vector2i(4, 4), Vector2i(0, 5), Vector2i(5, 0)]
	for i in units.size():
		var unit: UnitState = units[i]
		unit.control = ControlState.new()
		if not board.move_unit(unit, positions[i]):
			push_error("C1 placement failed for unit %d" % unit.id)
	units[1].control.stunned_turns = 1
	units[3].control.entangled_turns = 1
	var definition := AttackDefinition.new()
	definition.id = &"demo_strike"
	definition.profile = AttackRules.ARMOR_PROFILE
	definition.damage_components = [{"type": "fire", "policy": "standard", "numerator": 10, "denominator": 1, "source": "flame_rune", "factor_num": 1, "factor_den": 1}]
	definition.backstab_bonus_percent = 50
	definition.critical_on_control = true
	var pairs: Array[Dictionary] = []
	for actor: UnitState in units:
		for target: UnitState in units:
			if actor != target: pairs.append({"actor_unit_id": actor.id, "target_unit_id": target.id})
	context._attack_rules = AttackRules.new(_unit_ids(), pairs, [definition])
	flow_log = ["Оглушённый Страж впереди: крит ×2. Опутанный Щит слева от Бора: удар в спину +50% и крит. Путы снимаются после настоящего толчка; оба состояния истекают в конце хода своей команды."]

func _refill(faction: Faction.Type) -> bool:
	var outgoing := Faction.Type.PLAYER if faction == Faction.Type.ENEMY else Faction.Type.ENEMY
	_transitioning = true
	var expiry := super._submit(ControlTurnEndCommand.new(outgoing, context.get_revision()))
	_transitioning = false
	if expiry.status != ActionReceipt.APPLIED:
		_set_terminal(Phase.FAULTED, "Не удалось завершить состояния хода. Начните бой заново.")
		return false
	for event: Dictionary in expiry.get_events():
		if event.get("kind") == &"control_changed" and event.get("reason") == &"turn_end":
			var unit := board.get_unit_by_id(int(event["target_unit_id"]))
			flow_log.append("%s: срок состояния контроля истёк." % unit.debug_name)
	return super._refill(faction)
