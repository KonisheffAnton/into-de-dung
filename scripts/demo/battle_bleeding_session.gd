extends BattleArmorSession
class_name BattleBleedingSession

var rune_selected: bool = false
var turn_events: Array[Dictionary] = []

func reset() -> void:
	super.reset()
	rune_selected = false
	turn_events.clear()
	for unit: UnitState in units: unit.bleeding = BleedingState.new()
	units[3].bleeding.immune = true
	var rules := context.get_attack_rules()
	var ordinary := rules.get_definition(&"demo_strike")
	ordinary.bleeding_policy = &"physical_hp"
	var rune := rules.get_definition(&"demo_strike")
	rune.id = &"blood_rune"
	rune.bleeding_policy = &"bypass_hp_gate"
	context._attack_rules = AttackRules.new(rules._actors, rules._pairs, [ordinary, rune])
	flow_log = ["Кровотечение: каждое успешное наложение добавляет 2 тика по 4 в начале хода цели; естественная защита уменьшает урон.", "Персонажи игрока имеют перк «Кровавая руна»: клавиша 5 выбирает атаку, накладывающую кровотечение даже без физического урона HP. Иммунитет сохраняется."]

func _command_for(id: int) -> AttackCommand:
	var actor := selected_unit()
	var target := board.get_unit_by_id(id)
	if not can_player_act() or actor == null or target == null or not target.is_alive() or not actor.is_hostile_to(target): return null
	return AttackCommand.new(actor.id, target.id, actor.cell, target.cell, &"blood_rune" if rune_selected else &"demo_strike", context.get_revision())

func attack_unit(id: int) -> ActionReceipt:
	var command := _command_for(id)
	if command == null: return _reject(&"attack/invalid_target")
	return _submit(command)

func preview_attack(id: int) -> AttackForecast:
	var command := _command_for(id)
	if command == null: return AttackForecast.rejected(&"attack/invalid_target")
	return AttackForecast.build(context, _queue, command)

func prepare_attack_forecast(id: int) -> ForecastSimulation.Prepared:
	var command := _command_for(id)
	if command == null: return ForecastSimulation.Prepared.rejected(&"attack/invalid_target")
	return ForecastSimulation.prepare(context, _queue, command)

func _refill(faction: Faction.Type) -> bool:
	_transitioning = true
	var receipt := _submit(BleedingTurnCommand.new(faction, context.get_revision()))
	turn_events.append_array(receipt.get_events())
	_transitioning = false
	if receipt.status != ActionReceipt.APPLIED:
		_set_terminal(Phase.FAULTED, "Не удалось исполнить кровотечение. Начните бой заново.")
		return false
	# Tick может завершить бой: исход не перезаписывается очередной фазой/refill.
	if phase not in [Phase.PLAYER_TURN, Phase.ENEMY_TURN]: return false
	return super._refill(faction)
