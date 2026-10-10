extends RefCounted
class_name ActionAttackPolicy

## Состояние политики живёт ровно один submit; порядок drain остаётся у очереди.
var defer_item_reactions: bool = false
var _stances: Array[Dictionary] = []
var _root: Command
var _counter_considered: bool = false

func _init(root: Command, context: ActionContext) -> void:
	_root = root
	if root is AttackCommand:
		var attacker := (root as AttackCommand).get_actor_unit_id()
		var definition := context.get_attack_rules().get_definition((root as AttackCommand).get_attack_definition_id())
		defer_item_reactions = definition != null and (definition.bleeding_policy != &"" or definition.entangle_on_physical_hp or definition.stun_on_physical_hp or definition.chain_push)
		if context.get_state().artifacts != null and context.get_state().artifacts.ordinary(attacker,(root as AttackCommand).get_attack_definition_id()): defer_item_reactions = true
		# Срок отмены — весь каскад атаки, включая legacy balance/push и item-heal.
		for unit in context.get_state().get_board().get_all_units():
			_stances.append({"unit": unit, "expected": false if unit.id == attacker else unit.guard_stance})

func stances_valid() -> bool:
	for stance: Dictionary in _stances:
		var unit: UnitState = stance["unit"]
		if unit.guard_stance != stance["expected"]: return false
	return true

func finish_deferred_phase() -> bool:
	if not defer_item_reactions: return false
	defer_item_reactions = false
	return true

func take_counterattack(context: ActionContext) -> AttackCommand:
	# Единственный ответ принадлежит корню после полного drain его последствий.
	if _counter_considered: return null
	_counter_considered = true
	var counter := _counterattack_after(_root, context)
	if counter != null:
		var response := context.get_attack_rules().get_definition(counter.get_attack_definition_id())
		defer_item_reactions = response.bleeding_policy != &""
	return counter

static func _counterattack_after(root: Command, context: ActionContext) -> AttackCommand:
	if root.get_script() != AttackCommand or (root as AttackCommand).is_reaction(): return null
	var attack := root as AttackCommand
	var rules := context.get_attack_rules()
	var definition := rules.get_definition(attack.get_attack_definition_id())
	var response := rules.get_definition(&"counter_strike")
	# Только прямой weapon pipeline с явно заданным обычным ответом.
	if definition == null or definition.profile != AttackRules.ARMOR_PROFILE or response == null or not response.reaction_strike: return null
	var board := context.get_state().get_board()
	var defender := board.get_unit_by_id(attack.get_target_unit_id())
	var attacker := board.get_unit_by_id(attack.get_actor_unit_id())
	if not MeleeThreat.reaction_ready(context, defender, CombatPerksState.Mode.COUNTERATTACK) or not MeleeThreat.threatens(context, defender, attacker): return null
	return AttackCommand.counterattack(defender, attacker, context.get_revision())
