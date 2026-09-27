extends RefCounted
class_name PlayerTurnFixture

## Создаёт обычную сессию реакций и переводит её в состояние выбора игрока для теста действия.
static func create() -> BattleCoreReactionsSession:
	var session := BattleCoreReactionsSession.new()
	session.state.abilities = null
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	session.selected_id = session.units[0].id
	return session

## UI runner ставит уже созданную сцену в состояние проверки ввода до первого кадра.
static func enter_player_turn(demo: BattleDemo) -> void:
	var session := demo.session as BattleCoreReactionsSession
	session.state.abilities = null
	session.phase = BattleTacticalSession.Phase.PLAYER_TURN
	session.selected_id = session.units[0].id
	demo._refresh()
