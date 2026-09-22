extends BattleDemo
class_name D4BattleView

var supplied_session: D4BattleSession

func _create_session() -> void:
	session = supplied_session
	_battle = supplied_session
	tactical_mode = true
	armor_mode = true
	bleeding_mode = true

func _build_ui() -> void:
	super._build_ui()
	# Переключение полигонов и сброс боя не должны обходить состояние забега.
	for child: Node in _mode_button.get_parent().get_children():
		if child is Button: (child as Button).hide()

func _refresh() -> void:
	super._refresh()
	_heading.text = "intoDeDung / Забег"
	_instructions.text = "M — движение · A — атака · 2 — стойка · 4 — броня · 5 — руна · Enter — конец хода"
	if _battle.phase in [BattleTacticalSession.Phase.VICTORY, BattleTacticalSession.Phase.DEFEAT, BattleTacticalSession.Phase.MUTUAL_DESTRUCTION]:
		_stats.text = "Бой завершён. Результат забега сохраняется."
		_status.text = _battle.phase_text()

func reset_demo() -> void:
	_status.text = "Забег сохраняет начало текущего боя; R не сбрасывает его."

func toggle_scenario() -> void:
	pass

func _open_armor_scenario(_with_bleeding: bool = false) -> void:
	pass
