extends BattleDemo
class_name HeroHubBattleView

signal return_requested
signal restart_requested

var supplied_session: BattleCoreReactionsSession
var _return_button: Button

func _allows_execution_worker() -> bool:
	# Экран хаба также прекращает чтение сессии до возвращения владения из worker.
	return true

func _create_session() -> void:
	session = supplied_session
	_battle = supplied_session as BattleTacticalSession
	tactical_mode = true
	armor_mode = true
	bleeding_mode = true
	environment_mode = true
	control_mode = true
	core_combination_mode = true
	core_reactions_mode = true
	deployment_enabled = false
	_ai_delay = 0.0
	_flow_cursor = 0

func _build_ui() -> void:
	super._build_ui()
	board_view.environment_mode = true
	# Сценарные переходы и сброс обходили бы сохранённую контрольную точку отряда.
	_mode_button.hide()
	_hide_named_buttons(self, ["Забег", "Сбросить бой  ·  R", "Сравнить ходы", "Сочетания ядра"])
	_return_button = Button.new()
	_return_button.name = "ReturnToHeroHubButton"
	_return_button.text = "Вернуться в хаб"
	_return_button.custom_minimum_size = Vector2(190, 38)
	_return_button.pressed.connect(_request_return)
	_heading.get_parent().add_child(_return_button)

func _refresh() -> void:
	super._refresh()
	if _heading == null or session == null:
		return
	_heading.text = "intoDeDung · Отряд в бою"
	_subtitle.visible = true
	if _battle == null:
		_subtitle.text = "Сессия боя недоступна."
		_instructions.text = "Вернитесь в хаб после проверки результата."
		return
	var terminal := _battle.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION]
	var faulted := _battle.phase == BattleTacticalSession.Phase.FAULTED
	_return_button.text = "Повторить бой с начала" if faulted else "Вернуться в хаб"
	_return_button.disabled = not (terminal or faulted) or is_execution_pending()
	if terminal or faulted:
		_stats.text = _battle.phase_text()
		_status.text = "Бой остановлен. Можно повторить сохранённое начало." if faulted else "Результат передаётся в хаб."
	if faulted:
		_subtitle.text = "Ошибка исполнения. Награды не начислены; контрольная точка сохранена."
		_instructions.text = "Повторить бой с начала — восстановить сохранённый отряд и экипировку."
	elif _battle.phase == BattleTacticalSession.Phase.VICTORY:
		_subtitle.text = "Победа. Результат автоматически записывается после завершения действия."
		_instructions.text = "Бой завершён. Хаб сохранит опыт, золото, HP и состояние экипировки."
	elif _battle.phase in [BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION]:
		_subtitle.text = "Поражение. Исход автоматически записывается после завершения действия."
		_instructions.text = "Бой завершён. Хаб сохранит состояние отряда и потери."
	else:
		_subtitle.text = "Настоящий тактический бой · ход: %s" % ("отряда" if _battle.can_player_act() else "противника")
		_instructions.text = "Используйте действия и прогнозы боевого интерфейса. После терминального исхода результат сохранится в профиле."

func reset_demo() -> void:
	# Сброс создал бы новый бой вне сохранённого run_serial.
	return

func toggle_scenario() -> void:
	return

func _open_core_combination_scenario() -> void:
	return

func _request_return() -> void:
	if is_execution_pending() or _battle == null:
		return
	if _battle.phase == BattleTacticalSession.Phase.FAULTED:
		restart_requested.emit()
		return
	if _battle.phase not in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION]:
		return
	return_requested.emit()

func _hide_named_buttons(parent: Node, labels: Array[String]) -> void:
	for child: Node in parent.get_children():
		if child is Button and (child as Button).text in labels:
			(child as Button).hide()
		_hide_named_buttons(child, labels)
