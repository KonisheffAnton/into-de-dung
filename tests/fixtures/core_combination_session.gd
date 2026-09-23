extends D4BattleSession

## Композиция только для K1: production-команды, без нового игрового сценария.
var boundary_receipts: Array[ActionReceipt] = []

func build() -> bool:
	var run := D4RunState.new()
	if not run.equip(13, 1) or not run.start_run() or not configure(run): return false
	for y: int in board.height:
		for x: int in board.width:
			board.set_height_steps(Vector2i(x, y), 0)
			board.set_terrain(Vector2i(x, y), TerrainType.Type.FLOOR)
	for unit: UnitState in units:
		unit.control = ControlState.new()
	state.environment = CombatEnvironmentState.new()
	state.environment.ignite(Vector2i(2, 3))
	if not board.move_unit(units[0], Vector2i(4, 3)): return false
	if not board.move_unit(units[3], Vector2i(3, 3)): return false
	units[3].control.entangled_turns = 1
	units[3].bleeding.immune = false
	var rules := context.get_attack_rules()
	var definition := rules.get_definition(&"demo_strike")
	definition.backstab_bonus_percent = 50
	definition.critical_on_control = true
	context._attack_rules = AttackRules.new(rules._actors, rules._pairs, [definition])
	return context.get_attack_rules().validate() == &"" and select_unit(units[0].id)

func _refill(faction: Faction.Type) -> bool:
	# Демо C1 и D3 имеют отдельные адаптеры: здесь явно соединён их прежний порядок.
	var outgoing := Faction.Type.PLAYER if faction == Faction.Type.ENEMY else Faction.Type.ENEMY
	_transitioning = true
	var receipt := _submit(ControlTurnEndCommand.new(outgoing, context.get_revision()))
	_transitioning = false
	if receipt.status != ActionReceipt.APPLIED:
		_set_terminal(Phase.FAULTED, "K1: control expiry failed")
		return false
	return super._refill(faction)

func _submit(command: Command) -> ActionReceipt:
	var receipt := super._submit(command)
	if command.get_kind() in [&"control_turn_end", &"bleeding_turn"]:
		boundary_receipts.append(receipt)
	return receipt
