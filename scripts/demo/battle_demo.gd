extends Control
class_name BattleDemo

@export var tactical_mode: bool = false
@export var armor_mode: bool = false
@export var bleeding_mode: bool = false
@export var environment_mode: bool = false
@export var control_mode: bool = false
@export var core_combination_mode: bool = false
@export var core_reactions_mode: bool = false
@export var deployment_enabled: bool = true
var session: BattleDemoSession
var board_view: BattleDemoBoard
var attack_mode: bool = false
var summoning_mode: bool = false
var raising_mode: bool = false
var retreat_mode: bool = false
var inspected_id: int = UnitId.NONE
var _roster: VBoxContainer
var _roster_presenter: BattleRosterPresenter = BattleRosterPresenter.new()
var _hud_bound: bool = false
var _stats: Label
var _hint: Label
var _log: RichTextLabel
var _move_button: Button
var _attack_button: Button
var _action_bar: BattleActionBar
var _status: Label
var _journal: Array[String] = []
var _battle: BattleTacticalSession
var _phase_label: Label
var _phase_row: HBoxContainer
var _end_turn_button: Button
var _mode_button: Button
var _heading: Label
var _subtitle: Label
var _instructions: Label
var _ai_delay: float = 0.0
var _flow_cursor: int = 0
var _forecast_panel: RichTextLabel
var _forecast: AttackForecast
var _attack_forecast_pending: bool = false
var _attack_forecast_actor: int = UnitId.NONE
var _attack_forecast_variant: StringName = &""
var _attack_forecast_generation: int = 0
var _attack_forecast_job_generation: int = -1
var _attack_forecast_worker := preload("res://scripts/demo/attack_forecast_worker.gd").new()
var _move_forecast: MoveForecast
var _move_forecast_cell := Vector2i(-1, -1)
var _move_forecast_actor: int = UnitId.NONE
var _move_forecast_revision: int = -1
var _move_forecast_retreat: bool = false
const MOVE_HOVER_SETTLE_MS: int = 60
var _move_forecast_pending: bool = false
var _move_forecast_due: int = 0
var _move_forecast_generation: int = 0
var _move_forecast_job_generation: int = -1
var _move_forecast_worker := MoveForecastWorker.new()
var _action_forecast_pending: bool = false
var _action_forecast_freshness: BattleForecastFreshness
var _mage_display_freshness: BattleForecastFreshness
var _action_freshness_expected: bool = false
var _action_forecast_kind: StringName = &""
var _action_forecast_actor: int = UnitId.NONE
var _action_forecast_revision: int = -1
var _action_forecast_cell := Vector2i(-1, -1)
var _action_forecast_generation: int = 0
var _action_forecast_job_generation: int = -1
var _action_forecast_corpse_id: int = 0
var _action_forecast_session_id: int = 0
var _action_forecast_target_id: int = UnitId.NONE
var _action_forecast_effect: StringName = &""
var _action_forecast_cache: Dictionary = {}
var _action_forecast_worker := preload("res://scripts/demo/action_forecast_worker.gd").new()
var _item_forecast: ItemUseForecast
var _item_forecast_kind: StringName = &""
var _item_forecast_cell := Vector2i(-1, -1)
var _item_forecast_revision: int = -1
var _raise_forecast: RaiseCorpseForecast
var _raise_forecast_cell := Vector2i(-1, -1)
var _raise_forecast_actor: int = UnitId.NONE
var _raise_forecast_revision: int = -1
var _armor_forecast: ForecastSimulation
var _mage_row: HBoxContainer
var _mage_label: Label
var _mage_fire: Button
var _mage_buttons: Dictionary = {}
var _mage_heal: Button
var _card_buttons: Array[Button] = []
var _card_replace_button: Button
var _card_confirm_button: Button
var _card_selected_id: int = 0
var _mulligan_ids: Array[int] = []
var _action_forecast_card_id: int = 0
var _elemental_forecast: ForecastSimulation
var _armor_forecast_actor: int = UnitId.NONE
var _armor_forecast_revision: int = -1
var _guard_forecast: GuardForecast
var _guard_forecast_actor: int = UnitId.NONE
var _guard_forecast_revision: int = -1
var _guard_forecast_mode: int = 0
var _guard_forecast_target: int = 0
var _cover_guard_mode: bool = false
var _descriptors_session_id: int = 0
var _descriptors_actor: int = UnitId.NONE
var _forecast_cell := Vector2i(-1, -1)
var _forecast_target_id: int = UnitId.NONE
var _forecast_revision: int = -1
var _log_heading: Label
var _forecast_heading: Label
var _pointer_position := Vector2(-1, -1)
var _shown_inspection_id: int = UnitId.NONE
var _hovered_bar_action: StringName = &""
var _execution_worker := BattleExecutionWorker.new()
var _forecast_preparation_worker := BattleForecastPreparationWorker.new()
var _forecast_preparation_kind: StringName = &""
var _forecast_preparation_generation: int = -1
var _forecast_preparation_discard: bool = false
var _forecast_preparation_recovering: bool = false
var _forecast_replaying_intent: bool = false
var _forecast_hover_pending: bool = false
var _forecast_pointer_pending: bool = false
var _forecast_latest_hover := Vector2i(-1, -1)
var _forecast_input_intents: Array[Dictionary] = []
const MAX_FORECAST_INPUT_INTENTS: int = 32
@export var presentation_enabled: bool = true
var _presentation_player: BattlePresentationPlayer
var _presentation_before: Dictionary = {}
var _presentation_after: Dictionary = {}
var _presentation_roots: Array[Dictionary] = []
var _presentation_events: Array[Dictionary] = []
var _presentation_seen: Dictionary = {}
var _presentation_method: StringName
var _presentation_result: Variant
var _presentation_target: bool = false
var _receipt_already_presented: bool = false
var _skip_presentation_button: Button
var _speed_presentation_button: Button
var _diagnostics: PanelContainer
var _diagnostics_button: Button
var _compact_inspection: RichTextLabel
var _character_card: BattleCharacterCard
var _character_card_id: int = UnitId.NONE
var _character_card_session: int = 0
var _character_card_identity: Dictionary = {}
var _display_inspection_id: int = UnitId.NONE
var _turn_forecast: TurnForecast
var _turn_forecast_pending: bool = false
var _turn_forecast_generation: int = 0
var _turn_forecast_job_generation: int = -1
var _turn_forecast_session_id: int = 0
var _turn_forecast_actor: int = UnitId.NONE
var _turn_forecast_revision: int = -1
var _turn_forecast_worker := TurnForecastWorker.new()
var _environment_button: Button
var _cloth_palette: OptionButton
var _environment_forecast: ForecastSimulation
var _stage_next_refresh: bool = false
var _refresh_followup: Dictionary = {}
var _refresh_stage: int = 0
var _interactive_refresh_pending: bool = false
var _skip_refresh: bool = false
var _environment_forecast_pending: bool = false
var _environment_forecast_generation: int = 0
var _environment_forecast_job: int = -1
var _environment_forecast_session: int = 0
var _environment_forecast_revision: int = -1
var _environment_forecast_actor: int = 0
var _environment_forecast_worker := preload("res://scripts/demo/action_forecast_worker.gd").new()

func is_execution_pending() -> bool:
	return _execution_worker.is_started() or _forecast_preparation_worker.is_started() \
		or (_forecast_preparation_recovering and not _forecast_replaying_intent) or is_presentation_pending()

func _defer_forecast_intent(method: StringName, args: Array = []) -> bool:
	if _forecast_replaying_intent or not (_forecast_preparation_worker.is_started() or _forecast_preparation_recovering or _interactive_refresh_pending): return false
	# Храним смысл действия (ID/клетку), а не экранные координаты: камера может двигаться.
	var intent := {"method": method, "args": args.duplicate(true)}
	if _forecast_input_intents.size() < MAX_FORECAST_INPUT_INTENTS:
		_forecast_input_intents.append(intent)
	else:
		# Ограниченный UI-буфер не становится очередью боевых команд.
		_forecast_input_intents[-1] = intent
	_forecast_preparation_discard = true
	return true

func _start_forecast_preparation(kind: StringName, method: StringName, args: Array, generation: int) -> bool:
	if not _allows_execution_worker() or session == null or session.get_script() != BattleCoreReactionsSession: return false
	var owned := session as BattleCoreReactionsSession
	if not _forecast_preparation_worker.start(owned, method, args, kind == &"action" and _action_freshness_expected): return false
	_forecast_preparation_kind = kind
	_forecast_preparation_generation = generation
	_forecast_preparation_discard = false
	_forecast_hover_pending = false
	_forecast_pointer_pending = false
	board_view.execution_pending = true
	board_view.forecast_preparation_pending = true
	board_view.session = null
	session = null
	_battle = null
	return true

func _forecast_preparation_is_current(kind: StringName, generation: int) -> bool:
	match kind:
		&"move": return generation == _move_forecast_generation and _move_forecast_pending and _move_forecast_request_current()
		&"attack": return generation == _attack_forecast_generation and _attack_forecast_pending and _attack_forecast_request_current()
		&"action": return generation == _action_forecast_generation and _action_forecast_pending and _action_forecast_request_current()
		&"environment": return generation == _environment_forecast_generation and _environment_forecast_pending and _environment_request_current()
		&"turn": return generation == _turn_forecast_generation and _turn_forecast_pending and _turn_forecast_request_current()
	return false

func _discard_forecast_preparation(prepared: Variant) -> void:
	if prepared is ForecastSimulation.Prepared: ForecastSimulation.discard_prepared(prepared)
	# TurnForecast.Prepared содержит только отделённые значения/оболочки, без live state.

func _restore_forecast_owner(completed: Dictionary) -> void:
	session = completed.session
	_battle = session as BattleTacticalSession
	board_view.session = session
	board_view.execution_pending = false
	board_view.forecast_preparation_pending = false

func _poll_forecast_preparation() -> void:
	var completed := _forecast_preparation_worker.take_finished()
	if completed.is_empty(): return
	_restore_forecast_owner(completed)
	var kind := _forecast_preparation_kind
	_forecast_preparation_kind = &""
	if kind == &"action" and _action_freshness_expected and _forecast_preparation_generation == _action_forecast_generation \
			and not _forecast_preparation_discard and _forecast_input_intents.is_empty():
		_action_forecast_freshness = completed.get("freshness") as BattleForecastFreshness
		if _action_forecast_freshness == null:
			# Неполный свидетель не означает совпадение: сохраняем прежний полный путь.
			_action_freshness_expected = false
			_action_forecast_cache = _current_magic_snapshot_cache()
	# mouse_exited не отменяет цель сам по себе: курсор может читать её на панели.
	var current := not _forecast_preparation_discard \
		and _forecast_input_intents.is_empty() and _forecast_preparation_is_current(kind, _forecast_preparation_generation)
	var prepared: Variant = completed.prepared
	if current and bool(completed.sync_fallback):
		# Непереносимый пользовательский граф сохраняет прежний синхронный путь.
		prepared = TurnForecast.prepare(session as BattleCoreReactionsSession) if completed.method == &"turn" \
			else session.callv(BattleForecastPreparationWorker._prepare_method(completed.method), completed.args)
	if current and prepared != null:
		match kind:
			&"move": _move_forecast_worker.start(prepared as ForecastSimulation.Prepared)
			&"attack": _attack_forecast_worker.start(prepared as ForecastSimulation.Prepared)
			&"action":
				var action_prepared := prepared as ForecastSimulation.Prepared
				_action_forecast_corpse_id = (action_prepared.command as RaiseCorpseCommand)._corpse_id if action_prepared.command is RaiseCorpseCommand else 0
				_action_forecast_worker.start(action_prepared)
			&"environment": _environment_forecast_worker.start(prepared as ForecastSimulation.Prepared)
			&"turn": _turn_forecast_worker.start(prepared as TurnForecast.Prepared)
	else:
		_discard_forecast_preparation(prepared)
		_clear_forecast()
	_forecast_preparation_discard = false
	if _forecast_hover_pending or _forecast_pointer_pending or not _forecast_input_intents.is_empty():
		_forecast_preparation_recovering = true
		board_view.execution_pending = true
		board_view.forecast_preparation_pending = true

func _recover_forecast_input() -> void:
	# Одна UI-операция за кадр; после первой live-команды действует обычная блокировка.
	_forecast_replaying_intent = true
	board_view.execution_pending = false
	board_view.forecast_preparation_pending = false
	if not _forecast_input_intents.is_empty():
		var intent: Dictionary = _forecast_input_intents.pop_front()
		callv(intent.method, intent.args)
		if _interactive_refresh_pending:
			# Выбор следующего режима ещё не команда: сохраняем последующий клик.
			_forecast_preparation_recovering = false
		elif _execution_worker.is_started() or is_presentation_pending():
			_forecast_input_intents.clear()
			_forecast_hover_pending = false
			_forecast_pointer_pending = false
			_forecast_preparation_recovering = false
	else:
		if _forecast_hover_pending:
			_forecast_hover_pending = false
			_hover(_forecast_latest_hover)
		_forecast_pointer_pending = false
		_update_action_bar_hover()
		_update_turn_forecast_hover()
		_update_environment_forecast_hover()
	if _forecast_input_intents.is_empty() and not _forecast_hover_pending and not _forecast_pointer_pending: _forecast_preparation_recovering = false
	_forecast_replaying_intent = false
	if _forecast_preparation_recovering:
		board_view.execution_pending = true
		board_view.forecast_preparation_pending = true

func _join_forecast_preparation() -> void:
	var completed := _forecast_preparation_worker.take_finished(true)
	if not completed.is_empty():
		_restore_forecast_owner(completed)
		_discard_forecast_preparation(completed.prepared)
	_forecast_preparation_kind = &""
	_forecast_preparation_recovering = false
	_forecast_replaying_intent = false
	_forecast_preparation_discard = false
	_forecast_hover_pending = false
	_forecast_pointer_pending = false
	_forecast_input_intents.clear()
	if board_view != null: board_view.forecast_preparation_pending = false

func is_presentation_pending() -> bool:
	return not _refresh_followup.is_empty() or (_presentation_player != null and _presentation_player.active)

func _allows_execution_worker() -> bool:
	return get_script() == BattleDemo

func _execute_live(method: StringName, args: Array = [], target_attempt: bool = false) -> void:
	if _defer_forecast_intent(&"_execute_live", [method, args, target_attempt]): return
	if is_execution_pending(): return
	if _mage_row is BattleMageBar: (_mage_row as BattleMageBar).set_paging_enabled(false)
	_clear_forecast()
	if _allows_execution_worker() and session != null and session.get_script() == BattleCoreReactionsSession:
		var owned := session as BattleCoreReactionsSession
		# Отрисовка уже держит значения последнего refresh. Убираем доступ UI к runtime.
		board_view.execution_pending = true
		board_view.session = null
		session = null
		_battle = null
		# Main проверяет владение порциями; before/after собираются в потоке после допуска.
		# take_presentation_before нужен только при отказе запуска для sync fallback.
		var started := _execution_worker.start(owned, method, args, target_attempt, presentation_enabled, true, true)
		_presentation_before = _execution_worker.take_presentation_before()
		if started:
			_status.text = "Выполняется действие…"
			return
		session = owned
		_battle = owned
		board_view.session = owned
		board_view.execution_pending = false
	elif presentation_enabled and session != null and session.get_script() == BattleCoreReactionsSession and BattleExecutionWorker.can_transfer(session):
		# Sync-only оболочки сохраняют тот же аудит перед включением показа.
		_presentation_before = ActionPresentationState.capture(session.state)
		session.begin_presentation_capture()
	_complete_live(method, session.callv(method, args), target_attempt)

func _poll_execution() -> void:
	if not _refresh_followup.is_empty():
		if _refresh_stage == -3:
			# Кадр выбора уже содержит обработку мыши/карты; обновление начнётся в следующем.
			_refresh_stage = -2
			return
		elif _refresh_stage == -2:
			var followup := _refresh_followup
			_refresh_followup = {}
			_refresh_mage()
			_refresh_followup = followup
			_refresh_stage = -1
			return
		elif _refresh_stage == -1:
			var receipt_message: String = _refresh_followup.get("receipt_message", "")
			_refresh_followup = {}
			_begin_refresh(true)
			if not receipt_message.is_empty(): _refresh_followup.receipt_message = receipt_message
			return
		elif _refresh_stage == 0:
			if _interactive_refresh_pending: board_view.execution_pending = false
			board_view.prepare_refresh()
			if _interactive_refresh_pending: board_view.execution_pending = true
		elif _refresh_stage == 1:
			if _interactive_refresh_pending: board_view.execution_pending = false
			board_view.publish_refresh()
			if _interactive_refresh_pending: board_view.execution_pending = true
		else:
			var followup := _refresh_followup
			_refresh_followup = {}
			_finish_refresh(followup)
			if _interactive_refresh_pending:
				_interactive_refresh_pending = false
				_forecast_preparation_recovering = true
		_refresh_stage += 1
		return
	var completed := _execution_worker.take_finished()
	if completed.is_empty(): return
	_restore_execution_owner(completed)
	_presentation_before = completed.get("presentation_before", {})
	_presentation_after = completed.get("presentation_after", {})
	_complete_live(completed.method, completed.result, completed.target_attempt)

func _restore_execution_owner(completed: Dictionary) -> void:
	session = completed.session
	_battle = session as BattleTacticalSession
	board_view.session = session
	board_view.execution_pending = false
	if completed.get("sync_fallback", false):
		completed.result = session.callv(completed.method, completed.args)

func _join_execution() -> void:
	_join_forecast_preparation()
	if _interactive_refresh_pending and board_view != null: board_view.execution_pending = false
	_interactive_refresh_pending = false
	_refresh_followup.clear()
	_stage_next_refresh = false
	if _presentation_player != null: _presentation_player.cancel()
	# Reset/выход ждут завершения prefix, но не публикуют устаревший receipt в новый бой.
	var completed := _execution_worker.take_finished(true)
	if not completed.is_empty(): _restore_execution_owner(completed)
	if not _presentation_before.is_empty() and session != null: session.take_presentation_capture()
	_presentation_before.clear()
	_presentation_after.clear()
	_presentation_roots.clear()
	_presentation_events.clear()
	_presentation_result = null
	if board_view != null: board_view.execution_pending = false
	if board_view != null: board_view.set_acting_unit(UnitId.NONE)
	if _skip_presentation_button != null:
		_skip_presentation_button.visible = core_reactions_mode
		_skip_presentation_button.disabled = true
	if _speed_presentation_button != null: _speed_presentation_button.visible = core_reactions_mode

func _complete_live(method: StringName, result: Variant, target_attempt: bool) -> void:
	if not _presentation_before.is_empty():
		_presentation_roots = session.take_presentation_capture()
		var frames: Array[Dictionary] = []
		for root: Dictionary in _presentation_roots:
			frames.append_array(root.frames)
			# Сессия уже отделила эти кадры от receipt на worker. Для финального
			# журнала нужны только события: не удерживаем второй набор всех after.
			var event_frames: Array[Dictionary] = []
			for frame: Dictionary in root.frames: event_frames.append({"events": frame.events, "step": frame.step})
			root.frames = event_frames
		if not frames.is_empty():
			_presentation_method = method
			_presentation_result = result
			_presentation_target = target_attempt
			_presentation_seen.clear()
			board_view.execution_pending = true
			_skip_presentation_button.show()
			_skip_presentation_button.disabled = false
			_speed_presentation_button.show()
			# Слоты остаются на месте; до завершения показа запрещено только исполнение.
			_disable_action_buttons(_action_bar)
			_disable_action_buttons(_mage_row)
			_move_button.disabled = true
			_attack_button.disabled = true
			_end_turn_button.disabled = true
			_environment_button.disabled = true
			_phase_label.text = "Показ действия"
			_render_presentation_hud(_presentation_before)
			var final_state := _presentation_after if not _presentation_after.is_empty() else ActionPresentationState.capture(session.state)
			_presentation_player.play_owned_frames(board_view, _presentation_before, frames, final_state)
			return
		# Отвергнутый/пустой capture всё равно завершает worker-переход; его HUD
		# и поле нужно опубликовать теми же порциями, пока ввод остаётся закрыт.
		_stage_next_refresh = not _skip_refresh
		_presentation_before.clear()
		_presentation_after.clear()
	if method == &"end_player_turn":
		if result:
			_clear_action_mode()
			_ai_delay = 0.5
		_refresh()
	elif result is ActionReceipt:
		_show_receipt(result, target_attempt)
	else:
		_refresh()

func _presentation_frame_started(frame: Dictionary) -> void:
	_presentation_events.assign(frame.events)
	var caption := "Изменение состояния хода"
	for event: Dictionary in frame.events:
		var value := BattleDemoBoard._presentation_caption(event)
		if event.get("kind") == &"moved": value = "Движение"
		if not value.is_empty():
			caption = value
			break
	_status.text = caption + " · Пробел: пропустить · ×1 / ×3"

func _presentation_frame_finished(state: Dictionary) -> void:
	for event: Dictionary in _presentation_events: _note_presentation_event(event)
	# Пустой marker цепи публикует тот же снимок: HUD уже содержит эти значения.
	# Сигнал, журнал и осмотр сохраняются, без второго форматирования всего roster.
	if _presentation_player == null or not _presentation_player.is_repeated_chain_publication():
		_render_presentation_hud(state)
	_log.text = "\n".join(_journal)
	_displayed_unit_hovered(_display_inspection_id)

func _disable_action_buttons(parent: Node) -> void:
	if parent is BattleMageBar: (parent as BattleMageBar).set_paging_enabled(false)
	for child: Node in parent.get_children():
		if child is Button: (child as Button).disabled = true
		_disable_action_buttons(child)

func set_diagnostics_visible(value: bool) -> void:
	if _diagnostics == null: return
	_diagnostics.visible = value
	_diagnostics_button.set_pressed_no_signal(value)

func _displayed_unit_hovered(unit_id: int) -> void:
	_display_inspection_id = unit_id
	board_view.set_hovered_unit(unit_id)
	if _compact_inspection == null: return
	_compact_inspection.text = board_view.displayed_unit_summary(unit_id, true)
	_compact_inspection.tooltip_text = board_view.displayed_unit_details(unit_id)
	if not is_execution_pending(): _compact_inspection.tooltip_text += _card_imbue_text(unit_id)
	board_view.tooltip_text = _compact_inspection.tooltip_text if unit_id != UnitId.NONE else ""
	if unit_id == UnitId.NONE: _displayed_cell_hovered(board_view.hover_cell)

func _displayed_cell_hovered(cell: Vector2i) -> void:
	if _compact_inspection == null or _display_inspection_id != UnitId.NONE: return
	# Во время исполнения указатель клетки не публикуется: старую клетку не выдаём за новую.
	if is_execution_pending():
		_compact_inspection.text = "Наведите на фигуру для осмотра."
		_compact_inspection.tooltip_text = ""
		board_view.tooltip_text = ""
		return
	_compact_inspection.text = board_view.displayed_cell_summary(cell, true)
	_compact_inspection.tooltip_text = board_view.displayed_cell_summary(cell)
	board_view.tooltip_text = _compact_inspection.tooltip_text if cell.x >= 0 else ""

func _card_imbue_text(unit_id: int) -> String:
	if unit_id <= 0 or session == null or session.state == null or session.state.card_effects == null or session.state.abilities == null: return ""
	var unit := session.board.get_unit_by_id(unit_id)
	if unit == null or unit.faction not in [Faction.Type.PLAYER, Faction.Type.ENEMY]: return ""
	for effect: Dictionary in session.state.card_effects.fire_imbues:
		if effect.unit_id != unit_id: continue
		var serial: int = session.state.abilities.serials[unit.faction]
		return "\nОгненное усиление +2: этот ход и %d следующих (карта #%d)." % [maxi(0, effect.expires_after_serial - serial), effect.source_card_id]
	return ""

func _note_presentation_event(event: Dictionary) -> void:
	var seq := int(event.get("event_seq", 0))
	if _presentation_seen.has(seq): return
	_presentation_seen[seq] = true
	_note(_event_text(event))

func _render_presentation_hud(state: Dictionary) -> void:
	# Кадр может прийти при временно снятой сессии, поэтому здесь важны только ID снимка.
	if _character_card != null and _character_card_id != UnitId.NONE:
		_character_card.show_data(BattleCharacterCardData.frame(state.get("units", {}).get(_character_card_id, {}), _character_card_identity))
	_roster_presenter.ensure_mode(core_reactions_mode)
	var roster_ids: Array[int] = []
	var details: PackedStringArray = []
	for row: Dictionary in state.get("units", {}).values():
		var unit_id: int = int(row.get("id", UnitId.NONE))
		if unit_id <= UnitId.NONE: continue
		roster_ids.append(unit_id)
		var text: String = BattleFrameText.roster(row)
		var button := _roster_presenter.get_or_create_button(unit_id)
		button.text = text
		button.disabled = true
		button.set_pressed_no_signal(false)
		if not core_reactions_mode:
			button.clip_text = true
			button.custom_minimum_size = Vector2(480, 30)
		button.tooltip_text = text
		if row.alive:
			details.append(BattleFrameText.details(row))
	_roster_presenter.retain_ordered(roster_ids)
	_stats.text = "\n".join(details)
	var abilities: Dictionary = state.get("abilities", {})
	var frame_deck: Dictionary = state.get("deck", {})
	_mage_label.text = BattleFrameText.mage(abilities, frame_deck)
	if not frame_deck.is_empty():
		_mage_label.tooltip_text = BattleFrameText.deck_tooltip(frame_deck)
		var frame_buttons: Array[Button] = []
		for slot: int in mini(_card_buttons.size(), frame_deck.get("hand_ids", []).size()):
			var id: int = int(frame_deck["hand_ids"][slot])
			var card_text: BattleFrameText.CardText = BattleFrameText.card(frame_deck, id)
			var button: Button = _card_buttons[slot]
			button.text = card_text.text
			button.tooltip_text = card_text.tooltip
			button.disabled = true
			frame_buttons.append(button)
		if _mage_row is BattleMageBar: (_mage_row as BattleMageBar).configure(frame_buttons)
	for entry: Dictionary in abilities.get("ledger", []):
		if String(entry.get("ability_id", "")).begins_with("mage."):
			_mage_label.text += BattleFrameText.mage_ledger_suffix(entry)

func skip_presentation() -> void:
	_skip_refresh = true
	if _presentation_player != null: _presentation_player.skip()
	# Явный skip по прежнему контракту сразу возвращает готовое управление.
	while not _refresh_followup.is_empty(): _poll_execution()
	_skip_refresh = false

func _toggle_presentation_speed() -> void:
	_presentation_player.set_speed(3.0 if _presentation_player.speed < 2.0 else 1.0)
	_speed_presentation_button.text = "Скорость ×%d" % int(_presentation_player.speed)

func _finish_presentation() -> void:
	for root: Dictionary in _presentation_roots:
		for frame: Dictionary in root.frames:
			for event: Dictionary in frame.events: _note_presentation_event(event)
	# turn_events дублирует уже собранные roots; журнал границы не должен повторяться.
	if session is BattleBleedingSession: (session as BattleBleedingSession).turn_events.clear()
	_presentation_before.clear()
	_presentation_after.clear()
	_presentation_roots.clear()
	_presentation_events.clear()
	board_view.execution_pending = false
	_skip_presentation_button.visible = core_reactions_mode
	board_view.set_acting_unit(UnitId.NONE)
	_skip_presentation_button.disabled = true
	_speed_presentation_button.visible = core_reactions_mode
	_receipt_already_presented = true
	# Завершение не должно складывать HUD, чтение runtime и публикацию поля
	# в один кадр. Ввод остаётся закрыт до последней части refresh.
	_stage_next_refresh = not _skip_refresh
	_complete_live(_presentation_method, _presentation_result, _presentation_target)
	_receipt_already_presented = false
	_presentation_result = null

func _ready() -> void:
	_create_session()
	_build_ui()
	_presentation_player = BattlePresentationPlayer.new()
	add_child(_presentation_player)
	_presentation_player.frame_started.connect(_presentation_frame_started)
	_presentation_player.frame_finished.connect(_presentation_frame_finished)
	_presentation_player.finished.connect(_finish_presentation)
	_note("Победите противников. Берегите своих персонажей у края." if tactical_mode else "Полигон готов. Все шесть персонажей управляются вручную.")
	_refresh()

func _create_session() -> void:
	_roster_presenter.reset()
	# Составной сценарий проверяется первым, чтобы его флаги отображения не подменили сессию.
	if core_combination_mode:
		session = BattleCoreReactionsSession.new() if core_reactions_mode else BattleCoreCombinationSession.new()
		if deployment_enabled: (session as BattleCoreCombinationSession).begin_deployment()
	elif control_mode:
		session = BattleControlSession.new()
	else:
		session = BattleEnvironmentSession.new() if environment_mode else (BattleBleedingSession.new() if bleeding_mode else (BattleArmorSession.new() if armor_mode else (BattleTacticalSession.new() if tactical_mode else BattleDemoSession.new())))
	_battle = session as BattleTacticalSession
	_ai_delay = 0.0
	_flow_cursor = 0

func _process(delta: float) -> void:
	if _forecast_preparation_worker.is_started():
		_poll_forecast_preparation()
		return
	if _forecast_preparation_recovering:
		_recover_forecast_input()
		return
	if _execution_worker.is_started() or not _refresh_followup.is_empty():
		_poll_execution()
		return
	if is_presentation_pending(): return
	# Готовый прогноз и панель уже показаны для этого точного мира. Один сырой
	# обход проверяет оба; повторный admission всех карт здесь ничего не обновит.
	if _elemental_forecast != null and _action_forecast_freshness != null \
			and _mage_display_freshness == _action_forecast_freshness \
			and _action_forecast_request_current():
		return
	_refresh_mage()
	_process_move_forecast()
	_process_attack_forecast()
	_process_action_forecast()
	# Панель обновлена выше, а action только что проверил свежесть готовых чисел.
	if _elemental_forecast != null and not _action_forecast_pending:
		_mage_display_freshness = _action_forecast_freshness
	_process_turn_forecast()
	_process_environment_forecast()
	if _battle == null or _battle.phase != BattleTacticalSession.Phase.ENEMY_TURN: return
	_ai_delay -= delta
	if _ai_delay > 0.0: return
	# Один шаг за кадр; reset/смена режима не оставляют отложенных команд старого боя.
	_ai_delay = 0.7
	_execute_live(&"step_enemy")

func _input(event: InputEvent) -> void:
	if (_forecast_preparation_worker.is_started() or _forecast_preparation_recovering or _interactive_refresh_pending) and event is InputEventMouseMotion:
		_pointer_position = (event as InputEventMouseMotion).position
		_forecast_pointer_pending = true
	# Горячая клавиша показа должна опережать Space у кнопки, сохранившей фокус.
	if is_presentation_pending() and not _interactive_refresh_pending and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		skip_presentation()
		get_viewport().set_input_as_handled()
		return
	if is_execution_pending(): return
	if event is InputEventMouseMotion:
		# Координата самого viewport-события одинакова для мыши и replay/test input.
		_pointer_position = (event as InputEventMouseMotion).position
		_update_action_bar_hover()
		_update_turn_forecast_hover()
		_update_environment_forecast_hover()
		if (_forecast != null or _attack_forecast_pending or _move_forecast != null or _move_forecast_pending or _raise_forecast != null or (_item_forecast != null and _item_forecast_kind == &"summon")) and board_view.hover_cell.x < 0 and not _forecast_reading_region().has_point(_pointer_position) and not board_view.get_global_rect().has_point(_pointer_position):
			_clear_forecast()
			_refresh_inspection()

func _exit_tree() -> void:
	_join_execution()
	_action_forecast_freshness = null
	_move_forecast_worker.close()
	_attack_forecast_worker.close()
	_action_forecast_worker.close()
	_turn_forecast_worker.close()
	_environment_forecast_worker.close()
	_turn_forecast = null
	_turn_forecast_pending = false
	_attack_forecast_pending = false
	_move_forecast_pending = false
	_forecast = null
	_move_forecast = null
	_item_forecast = null
	_item_forecast_kind = &""
	_raise_forecast = null
	_armor_forecast = null
	_armor_forecast_actor = UnitId.NONE
	_armor_forecast_revision = -1
	_guard_forecast = null
	if board_view != null:
		board_view.forecast = null
		board_view.move_forecast = null
		board_view.move_forecast_pending = false
		board_view.pending_move_path.clear()
		board_view.sneak_threat_ids.clear()
		board_view.compact_forecast.publish({}, Vector2i(-1, -1), board_view)
		board_view.session = null
	if session != null: session.close()
	session = null

func _build_ui() -> void:
	if core_reactions_mode:
		_build_authored_hud()
		return
	_build_legacy_ui()

func _build_authored_hud() -> void:
	if _hud_bound: return
	var hud := get_node_or_null("BattleHUD") as Control
	if hud == null:
		# Прямые .new() из тестов получают ту же сцену, что и редакторский вход.
		hud = (load("res://scenes/demo/battle/battle_hud.tscn") as PackedScene).instantiate() as Control
		add_child(hud)
	var deck_layout: bool = session != null and session.state != null and session.state.deck != null
	var handlers: Dictionary[StringName, Callable] = {
		&"toggle_scenario": toggle_scenario,
		&"open_expedition": func() -> void: get_tree().change_scene_to_file("res://scenes/demo/expedition_d4.tscn"),
		&"reset_demo": reset_demo,
		&"skip_presentation": skip_presentation,
		&"toggle_presentation_speed": _toggle_presentation_speed,
		&"request_environment_forecast": _request_environment_forecast,
		&"cloth_palette_selected": _on_cloth_palette_selected,
		&"mage_page_changed": _mage_page_changed,
		&"choose_elemental": _choose_elemental,
		&"choose_card_slot": _choose_card_slot,
		&"replace_selected_card": _replace_selected_card,
		&"confirm_selected_mulligan": _confirm_selected_mulligan,
		&"set_move_mode": set_attack_mode.bind(false),
		&"set_attack_mode": set_attack_mode.bind(true),
		&"end_turn": end_turn,
		&"open_core_combination": _open_core_combination_scenario,
		&"forecast_wheel": _board_forecast_wheel_input,
		&"handle_cell": handle_cell,
		&"hover": _hover,
		&"displayed_unit_hovered": _displayed_unit_hovered,
		&"action_bar_requested": _action_bar_requested,
		&"action_bar_hovered": _action_bar_hovered,
		&"action_bar_hover_left": _action_bar_hover_left,
		&"set_diagnostics_visible": set_diagnostics_visible,
		&"leave_forecast_panel": _leave_forecast_panel,
	}
	var binding := BattleHudBinding.bind(hud, handlers, deck_layout)
	_heading = binding.heading
	_mode_button = binding.mode_button
	_subtitle = binding.subtitle
	_phase_row = binding.phase_row
	_phase_label = binding.phase_label
	_skip_presentation_button = binding.skip_presentation_button
	_speed_presentation_button = binding.speed_presentation_button
	_environment_button = binding.environment_button
	_cloth_palette = binding.cloth_palette
	_mage_label = binding.mage_label
	_mage_row = binding.mage_row
	_mage_buttons = binding.mage_buttons
	_mage_fire = binding.mage_fire
	_mage_heal = binding.mage_heal
	_card_buttons = binding.card_buttons
	_card_replace_button = binding.card_replace_button
	_card_confirm_button = binding.card_confirm_button
	_move_button = binding.move_button
	_attack_button = binding.attack_button
	_end_turn_button = binding.end_turn_button
	board_view = binding.board_view
	board_view.session = session
	_cloth_palette.select(DefenderClothPalette.valid_index(board_view.defender_cloth_palette))
	_action_bar = binding.action_bar
	_hint = binding.hint
	_compact_inspection = binding.compact_inspection
	_compact_inspection.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_character_card = hud.get_node("CharacterCard") as BattleCharacterCard
	_character_card.close_requested.connect(_close_character_card)
	board_view.character_card_input_enabled = true
	board_view.character_card_requested.connect(_open_character_card)
	for control: Control in [hud, board_view, _mage_row, binding.status]:
		control.resized.connect(_queue_character_card_layout)
	_mage_row.visibility_changed.connect(_queue_character_card_layout)
	_diagnostics_button = binding.diagnostics_button
	_diagnostics = binding.diagnostics
	_roster = binding.roster
	_roster_presenter.bind(_roster, _on_roster_entry_pressed, _button)
	_stats = binding.stats
	_log_heading = binding.log_heading
	_log = binding.log
	_forecast_heading = binding.forecast_heading
	_forecast_panel = binding.forecast_panel
	_status = binding.status
	_instructions = binding.instructions
	_hud_bound = true

func _build_legacy_ui() -> void:
	var handlers: Dictionary[StringName, Callable] = {
		&"toggle_scenario": toggle_scenario,
		&"open_expedition": func() -> void: get_tree().change_scene_to_file("res://scenes/demo/expedition_d4.tscn"),
		&"reset_demo": reset_demo,
		&"skip_presentation": skip_presentation,
		&"toggle_presentation_speed": _toggle_presentation_speed,
		&"request_environment_forecast": _request_environment_forecast,
		&"choose_elemental": _choose_elemental,
		&"set_move_mode": set_attack_mode.bind(false),
		&"set_attack_mode": set_attack_mode.bind(true),
		&"end_turn": end_turn,
		&"open_core_combination": _open_core_combination_scenario,
		&"forecast_wheel": _board_forecast_wheel_input,
		&"handle_cell": handle_cell,
		&"hover": _hover,
		&"displayed_unit_hovered": _displayed_unit_hovered,
		&"action_bar_requested": _action_bar_requested,
		&"action_bar_hovered": _action_bar_hovered,
		&"action_bar_hover_left": _action_bar_hover_left,
		&"leave_forecast_panel": _leave_forecast_panel,
	}
	board_view = BattleDemoBoard.new()
	board_view.session = session
	var hud := BattleLegacyHud.build(self, board_view, handlers, tactical_mode)
	_heading = hud.heading
	_mode_button = hud.mode_button
	_subtitle = hud.subtitle
	_phase_row = hud.phase_row
	_phase_label = hud.phase_label
	_skip_presentation_button = hud.skip_presentation_button
	_speed_presentation_button = hud.speed_presentation_button
	_environment_button = hud.environment_button
	_mage_label = hud.mage_label
	_mage_row = hud.mage_row
	_mage_buttons = hud.mage_buttons
	_mage_fire = hud.mage_fire
	_mage_heal = hud.mage_heal
	_move_button = hud.move_button
	_attack_button = hud.attack_button
	_end_turn_button = hud.end_turn_button
	board_view = hud.board_view
	_action_bar = hud.action_bar
	_hint = hud.hint
	_roster = hud.roster
	_roster_presenter.bind(_roster, _on_roster_entry_pressed, _button)
	_stats = hud.stats
	_log_heading = hud.log_heading
	_log = hud.log
	_forecast_heading = hud.forecast_heading
	_forecast_panel = hud.forecast_panel
	_status = hud.status
	_instructions = hud.instructions

func _label(value: String, font_size: int, color: Color) -> Label:
	return BattleLegacyHud.make_label(value, font_size, color)

func _on_roster_entry_pressed(unit_id: int) -> void:
	if _defer_forecast_intent(&"_on_roster_entry_pressed", [unit_id]): return
	# Сигнал хранит ID, а выбранное действие определяется только по текущей сессии.
	if is_execution_pending() or session == null or session.board == null: return
	var unit := session.board.get_unit_by_id(unit_id)
	if unit == null or not unit.is_alive(): return
	if _battle != null and unit.faction == Faction.Type.ENEMY: inspect_enemy(unit_id)
	else: select_character(unit_id)

func _button(value: String) -> Button:
	return BattleLegacyHud.make_button(value)

func set_attack_mode(enabled: bool) -> void:
	if _defer_forecast_intent(&"set_attack_mode", [enabled]): return
	if is_execution_pending(): return
	if _battle != null and not _battle.can_player_act(): return
	var leaving_magic: bool = _card_selected_id > 0 or (session is BattleCoreReactionsSession and session.elemental_selected != &"")
	_clear_action_mode()
	attack_mode = enabled
	if leaving_magic: _refresh_magic_mode()
	else: _refresh()

func _clear_action_mode() -> void:
	if is_execution_pending(): return
	_card_selected_id = 0
	# Только состояние ввода: остатки действий и результат команды принадлежат сессии.
	if session is BattleBleedingSession: (session as BattleBleedingSession).rune_selected = false
	if session is BattleCoreCombinationSession: (session as BattleCoreCombinationSession).entangle_selected = false
	if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).stun_selected = false
	if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).warrior_selected = &""
	if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).elemental_selected = &""
	summoning_mode = false
	raising_mode = false
	retreat_mode = false
	attack_mode = false
	_cover_guard_mode = false
	_clear_forecast()
	# Режим действия закрывает осмотр, чтобы подсветка не смешивалась с целью атаки.
	inspected_id = UnitId.NONE

func _choose_elemental(effect: StringName) -> void:
	if _defer_forecast_intent(&"_choose_elemental", [effect]): return
	if is_execution_pending() or not session is BattleCoreReactionsSession: return
	var reaction_session := session as BattleCoreReactionsSession
	var reason := reaction_session.cast_reason(effect)
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	reaction_session.elemental_selected = effect
	_refresh_magic_mode()

func _action_bar_requested(action_id: StringName) -> void:
	if _defer_forecast_intent(&"_action_bar_requested", [action_id]): return
	if is_execution_pending(): return
	if not tactical_mode or (_battle != null and not _battle.can_player_act()): return
	match action_id:
		&"entangling_strike":
			set_attack_mode(true)
			if session is BattleCoreCombinationSession:
				(session as BattleCoreCombinationSession).entangle_selected = true
				_refresh()
		WarriorKit.CLEAVE, WarriorKit.KICK:
			set_attack_mode(true)
			if session is BattleCoreReactionsSession:
				(session as BattleCoreReactionsSession).warrior_selected = action_id
				_refresh()
		&"stunning_strike":
			set_attack_mode(true)
			if session is BattleCoreReactionsSession:
				(session as BattleCoreReactionsSession).stun_selected = true
				_refresh()
		&"elemental_burning": _choose_elemental(&"burning")
		&"elemental_wet": _choose_elemental(&"wet")
		&"elemental_freeze": _choose_elemental(&"freeze")
		&"blood_rune":
			set_attack_mode(true)
			if session is BattleBleedingSession:
				(session as BattleBleedingSession).rune_selected = true
				_refresh()
		&"attack": set_attack_mode(true)
		&"raise_shields":
			_clear_action_mode()
			_execute_live(&"raise_shields")
		&"guard": _use_guard()
		&"opportunity_guard": _choose_reaction_guard(CombatPerksState.Mode.OPPORTUNIST)
		&"cover_guard": _choose_reaction_guard(CombatPerksState.Mode.COVER)
		&"counterattack_guard": _choose_reaction_guard(CombatPerksState.Mode.COUNTERATTACK)
		&"healing_item": _use_healing_item()
		&"summoning_item": _choose_summoning()
		&"raise_corpse": _choose_raise()
		&"safe_retreat": _choose_retreat()
		&"restore_armor":
			if session is BattleArmorSession:
				_clear_action_mode()
				_execute_live(&"restore_selected_armor")

func _use_healing_item() -> void:
	if _defer_forecast_intent(&"_use_healing_item", []): return
	if is_execution_pending(): return
	if _battle == null: return
	_clear_action_mode()
	_execute_live(&"use_healing_item")

func _use_guard() -> void:
	if _defer_forecast_intent(&"_use_guard", []): return
	if is_execution_pending(): return
	if _battle == null: return
	_clear_action_mode()
	_execute_live(&"guard_selected")

func _choose_reaction_guard(mode: int) -> void:
	if _defer_forecast_intent(&"_choose_reaction_guard", [mode]): return
	if is_execution_pending(): return
	if not session is BattleCoreReactionsSession or _battle == null: return
	var reaction_session := session as BattleCoreReactionsSession
	if mode == CombatPerksState.Mode.COVER:
		var eligible := reaction_session.cover_targets()
		var reason := _cover_choice_reason(reaction_session, eligible)
		if reason != &"":
			_status.text = _reason_text(reason)
			return
		_clear_action_mode()
		_cover_guard_mode = true
		_refresh()
		return
	if mode not in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COUNTERATTACK]: return
	_clear_action_mode()
	_execute_live(&"set_reaction_guard", [mode])

func _cover_choice_reason(reaction_session: BattleCoreReactionsSession, targets: Array[int]) -> StringName:
	return BattleActionDescriptors.cover_choice_reason(reaction_session, targets)

func select_character(id: int) -> void:
	if _defer_forecast_intent(&"select_character", [id]): return
	if is_execution_pending(): return
	if session.select_unit(id):
		inspected_id = UnitId.NONE
		_clear_action_mode()
		_refresh()

func _is_deploying() -> bool:
	return session is BattleCoreCombinationSession and (session as BattleCoreCombinationSession).is_deploying()

func inspect_enemy(id: int) -> void:
	if _defer_forecast_intent(&"inspect_enemy", [id]): return
	if is_execution_pending(): return
	if _battle == null or (not _is_deploying() and not _battle.can_player_act()): return
	var unit := session.board.get_unit_by_id(id)
	if unit == null or not unit.is_alive() or unit.faction != Faction.Type.ENEMY: return
	summoning_mode = false
	raising_mode = false
	retreat_mode = false
	attack_mode = false
	if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).stun_selected = false
	if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).warrior_selected = &""
	_clear_forecast()
	inspected_id = UnitId.NONE if inspected_id == id else id
	_cover_guard_mode = false
	_refresh()

func handle_cell(cell: Vector2i) -> void:
	if _defer_forecast_intent(&"handle_cell", [cell]): return
	if is_execution_pending(): return
	if _is_deploying():
		if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).mage_deployment_confirmed:
			_status.text = "Расстановка подтверждена. Выберите до двух карт и подтвердите или пропустите замену."
			return
		var unit := session.board.occupant_at(cell)
		if unit != null:
			if unit.faction == Faction.Type.PLAYER: select_character(unit.id)
			else: inspect_enemy(unit.id)
		else:
			inspected_id = UnitId.NONE
			var placed := (session as BattleCoreCombinationSession).place_selected(cell)
			_refresh()
			if not placed: _status.text = "Нужна свободная безопасная клетка в подсвеченной зоне A3–F6."
		return
	if _battle != null and not _battle.can_player_act(): return
	var occupant := session.board.occupant_at(cell)
	if _card_selected_id > 0 and session is BattleCoreReactionsSession and session.state.deck != null:
		var card := session.state.deck.card(_card_selected_id)
		var definition := MageCardCatalog.get_card(String(card.get("type_id", "")))
		var cell_card: bool = definition != null and definition.target_policy in ["valid_cell", "corpse_cell"]
		if not cell_card and occupant == null:
			var rejected := ActionReceipt.new()
			rejected.reason = &"mage/invalid_target"
			_show_receipt(rejected, true)
			return
		_execute_live(&"play_mage_card", [_card_selected_id, 0 if cell_card else occupant.id, cell], true)
		return
	if _cover_guard_mode and session is BattleCoreReactionsSession:
		var reaction_session := session as BattleCoreReactionsSession
		if occupant != null and reaction_session.cover_targets().has(occupant.id):
			_clear_forecast()
			_cover_guard_mode = false
			_execute_live(&"set_reaction_guard", [CombatPerksState.Mode.COVER, occupant.id])
		else:
			_status.text = "Выберите подсвеченного союзника для Прикрытия или нажмите Esc."
		return
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &"":
		var spell := (session as BattleCoreReactionsSession).elemental_selected
		if AbilityDefinition.is_cell_spell(spell):
			_execute_live(&"cast_mage_cell", [spell, cell], true)
			return
		if occupant == null:
			_status.text = "Выберите допустимую живую цель."
			return
		if AbilityDefinition.mage_source_id(spell) > 0: _execute_live(&"cast_mage_spell", [spell, occupant.id], true)
		else: _execute_live(&"cast_unit", [occupant.id], true)
	elif summoning_mode:
		_execute_live(&"use_summoning_item", [cell], true)
	elif raising_mode and session is BattleEnvironmentSession:
		_execute_live(&"raise_corpse", [cell], true)
	elif attack_mode:
		if occupant == null:
			var rejected := ActionReceipt.new()
			rejected.reason = &"attack/invalid_target"
			_show_receipt(rejected, true)
			return
		# В командном бою союзник под курсором означает выбор, а не дружественный удар.
		if _battle != null and occupant.is_alive() and occupant.faction == Faction.Type.PLAYER:
			select_character(occupant.id)
			return
		_execute_live(&"attack_unit", [occupant.id], true)
	elif occupant != null:
		if _battle != null and occupant.faction == Faction.Type.ENEMY:
			if retreat_mode:
				inspect_enemy(occupant.id)
			else:
				inspected_id = UnitId.NONE
				_execute_live(&"click_attack", [occupant.id], true)
		else:
			select_character(occupant.id)
	elif inspected_id != UnitId.NONE:
		# Первый клик по пустой клетке завершает осмотр; движение требует второго клика.
		inspected_id = UnitId.NONE
		_refresh()
	else:
		_execute_live(&"retreat_to" if retreat_mode else &"move_to", [cell], retreat_mode)

func reset_demo() -> void:
	_join_execution()
	_clear_forecast()
	session.reset()
	_card_selected_id = 0
	_mulligan_ids.clear()
	_cover_guard_mode = false
	_descriptors_session_id = 0
	_descriptors_actor = UnitId.NONE
	summoning_mode = false
	raising_mode = false
	retreat_mode = false
	attack_mode = false
	inspected_id = UnitId.NONE
	_journal.clear()
	_flow_cursor = 0
	_ai_delay = 0.0
	_note("Бой сброшен: здоровье, действия и предметы восстановлены.")
	_refresh()

func _on_cloth_palette_selected(index: int) -> void:
	if board_view == null: return
	board_view.set_defender_cloth_palette(index)

func toggle_scenario() -> void:
	_join_execution()
	control_mode = false
	core_combination_mode = false
	_cover_guard_mode = false
	_clear_forecast()
	session.close()
	armor_mode = false
	bleeding_mode = false
	environment_mode = false
	tactical_mode = not tactical_mode
	_create_session()
	board_view.session = session
	summoning_mode = false
	raising_mode = false
	retreat_mode = false
	attack_mode = false
	inspected_id = UnitId.NONE
	_journal.clear()
	_note("Начат бой против компьютера." if tactical_mode else "Полигон: все персонажи управляются вручную.")
	_refresh()

func _open_core_combination_scenario() -> void:
	_join_execution()
	_clear_forecast()
	retreat_mode = false
	_cover_guard_mode = false
	if session != null: session.close()
	core_combination_mode = true
	# Эти флаги включают уже существующие подсказки и действия окружения/контроля.
	control_mode = true
	armor_mode = true
	bleeding_mode = true
	environment_mode = true
	tactical_mode = true
	_create_session()
	board_view.session = session
	board_view.environment_mode = true
	summoning_mode = false
	raising_mode = false
	attack_mode = false
	inspected_id = UnitId.NONE
	_journal.clear()
	_note("Реакции и скрытая атака: полный общий бой." if session is BattleCoreReactionsSession else "Сочетания ядра: пробивающий клинок Бора, контроль, тыл и крит, кровотечение, шипы и поднятие тела.")
	_refresh()

func end_turn() -> void:
	if _defer_forecast_intent(&"end_turn", []): return
	if is_execution_pending(): return
	if _battle == null: return
	if _is_deploying():
		if session is BattleCoreReactionsSession and session.state.deck != null:
			var mage_session := session as BattleCoreReactionsSession
			if not mage_session.mage_deployment_confirmed:
				if mage_session.confirm_mage_deployment():
					_clear_action_mode()
					_status.text = "Расстановка подтверждена. Выберите до двух карт для замены и подтвердите или пропустите."
				else: _status.text = "Сначала разместите всех союзников на безопасных клетках."
				_refresh()
				return
			if not session.state.deck.mulligan_done:
				_confirm_selected_mulligan()
				return
		if (session as BattleCoreCombinationSession).start_battle(): _clear_action_mode()
		_refresh()
		return
	_execute_live(&"end_player_turn")

func _refresh_mage() -> void:
	# Явный refresh может увидеть временную raw-мутацию с последующим откатом.
	_mage_display_freshness = null
	if not is_execution_pending() and _mage_row != null:
		var mage_session := session as BattleCoreReactionsSession
		_mage_row.visible = mage_session != null and mage_session.state.abilities != null
		_mage_label.visible = _mage_row.visible and not (core_reactions_mode and mage_session != null and mage_session.state.deck != null)
		if board_view != null and not board_view.authored_layout:
			board_view.custom_minimum_size.y = 350.0 if _compact_inspection != null else (476.0 if _mage_row.visible else 520.0)
		if _mage_row.visible:
			if mage_session.state.deck != null:
				_refresh_deck_bar(mage_session)
				return
			BattleMagePresenter.refresh_spells(
				mage_session, _mage_row, _mage_label, _mage_buttons,
				_elemental_effect_label, _mage_spell_help, _reason_text
			)

func _refresh_deck_bar(mage_session: BattleCoreReactionsSession) -> void:
	BattleMagePresenter.refresh_deck(
		mage_session, _mage_row, _mage_label, _card_buttons,
		_card_confirm_button, _card_replace_button, _mulligan_ids,
		_card_selected_id, _reason_text
	)

func _choose_card_slot(slot: int) -> void:
	if _defer_forecast_intent(&"_choose_card_slot", [slot]): return
	if is_execution_pending() or not session is BattleCoreReactionsSession or session.state.deck == null: return
	var mage_session := session as BattleCoreReactionsSession
	if slot < 0 or slot >= mage_session.state.deck.hand_ids.size(): return
	var id: int = mage_session.state.deck.hand_ids[slot]
	if mage_session.is_deploying():
		if not mage_session.mage_deployment_confirmed or mage_session.state.deck.mulligan_done: return
		if _mulligan_ids.has(id): _mulligan_ids.erase(id)
		elif _mulligan_ids.size() < 2: _mulligan_ids.append(id)
		else: _status.text = "Можно заменить не более двух карт."
		_refresh()
		return
	var reason := mage_session.mage_card_reason(id)
	if reason != &"" and reason != &"mage_card/insufficient_mana": _status.text = _reason_text(reason); return
	_clear_action_mode()
	_card_selected_id = id
	_refresh_magic_mode()

func _replace_selected_card() -> void:
	if _defer_forecast_intent(&"_replace_selected_card", []): return
	if is_execution_pending() or _card_selected_id == 0 or not session is BattleCoreReactionsSession: return
	_execute_live(&"replace_mage_card", [_card_selected_id], true)

func _confirm_selected_mulligan() -> void:
	if _defer_forecast_intent(&"_confirm_selected_mulligan", []): return
	if is_execution_pending() or not session is BattleCoreReactionsSession: return
	var mage_session := session as BattleCoreReactionsSession
	if not mage_session.is_deploying() or not mage_session.mage_deployment_confirmed or mage_session.state.deck == null or mage_session.state.deck.mulligan_done: return
	var receipt := mage_session.confirm_mage_mulligan(_mulligan_ids)
	if receipt.status != ActionReceipt.APPLIED:
		_show_receipt(receipt)
		return
	_mulligan_ids.clear()
	if mage_session.start_battle(): _clear_action_mode()
	_refresh()

func _mage_page_changed(_page: int) -> void:
	if _defer_forecast_intent(&"_mage_page_changed", [_page]): return
	if is_execution_pending(): return
	_clear_action_mode()
	_refresh_magic_mode()

func _refresh_magic_mode() -> void:
	if not is_node_ready() or not is_processing() or not can_process() or not _allows_execution_worker() or session == null \
			or session.get_script() != BattleCoreReactionsSession:
		_refresh()
		return
	# Полный свежий refresh сохраняется, но его части больше не задерживают кадр выбора.
	_interactive_refresh_pending = true
	_forecast_preparation_recovering = false
	board_view.execution_pending = true
	board_view.forecast_preparation_pending = true
	_refresh_followup = {"begin": true}
	_refresh_stage = -3

func _mage_spell_help(id: StringName) -> String:
	match id:
		&"mage.fire": return "4 огненного урона врагу, без поджога. Вся доска."
		&"mage.heal": return "Восстановить союзнику 4 HP. Вся доска."
		&"mage.test_burning": return "Тест: +1 стак горения; повторное наложение обновляет срок до 2 тиков. Вода гасит, лёд тает. Снимает кровотечение."
		&"mage.test_poison": return "Тест: 4 прямого физического урона врагу; при положительном уроне HP накладывает +1 урон и +1 тик яда. Тики наносят урон только HP, броню не меняют."
		&"mage.test_wet": return "Тест: вода на 3 хода цели, гасит горение."
		&"mage.test_freeze": return "Тест: сухую цель сначала мочит; мокрую замораживает на 2 хода при броне ниже половины. Иммунитет сохраняется."
		&"mage.test_stun": return "Тест: оглушение до конца хода цели, без удара. Иммунитет сохраняется."
		&"mage.test_roots": return "Тест: корни до конца хода цели, без удара. Иммунитет сохраняется."
		&"mage.test_bleeding": return "Тест: +1 стак, срок 3 тика. Горение и иммунитет блокируют наложение."
		&"mage.test_heal": return "Тест: восстановить раненому союзнику 4 HP, без затрат действий и предметов героя."
		&"mage.test_summon": return "Помощник рядом с любым союзником, включая помощников. Без владельца и лимита; готов со следующего своего хода. 1 мана."
		&"mage.shield": return "Щит: 6 HP, один удар любого урона. Остаток проходит защиты и броню; новый щит заменяет прежний. 1 мана, откат 0."
		&"mage.test_raise": return "Новое создание из тела рядом с любым союзником. Без владельца и лимита; готов со следующего своего хода. 1 мана."
	return ""

func _refresh() -> void:
	if _defer_forecast_intent(&"_refresh", []): return
	if _stage_next_refresh:
		_stage_next_refresh = false
		_refresh_followup = {"begin": true}
		_refresh_stage = -1
		return
	_begin_refresh()

func _begin_refresh(staged: bool = false) -> void:
	# Интерактивная смена режима уже обновила панель мага отдельной стадией.
	if not _interactive_refresh_pending: _refresh_mage()
	if is_execution_pending(): return
	_roster_presenter.ensure_scope(session.get_instance_id(), core_reactions_mode)
	# Любой refresh перечитывает состояние, включая изменения вне command revision.
	var refresh_turn := (_turn_forecast != null or _turn_forecast_pending) and (_over_end_turn_button() or _forecast_reading_region().has_point(_pointer_position))
	var refresh_environment := (_environment_forecast != null or _environment_forecast_pending) and (_over_environment_button() or _forecast_reading_region().has_point(_pointer_position))
	var refresh_armor := (_armor_forecast != null or (_action_forecast_pending and _action_forecast_kind == &"armor")) and _hovered_bar_action == &"restore_armor"
	var refresh_guard_action := _hovered_bar_action if _guard_forecast != null or (_action_forecast_pending and _action_forecast_kind in [&"guard", &"opportunity", &"counterattack", &"raise_shields"]) else &""
	var refresh_healing := (_item_forecast != null or (_action_forecast_pending and _action_forecast_kind == &"healing")) and _hovered_bar_action == &"healing_item"
	var refresh_guard := refresh_guard_action in [&"guard", &"opportunity_guard", &"counterattack_guard", &"raise_shields"]
	var reset_dynamic_page := _descriptors_session_id != session.get_instance_id() or _descriptors_actor != session.selected_id
	_clear_forecast()
	if inspected_id != UnitId.NONE:
		var inspected := session.board.get_unit_by_id(inspected_id) if session != null and session.board != null else null
		if _battle == null or (not _battle.can_player_act() and not _is_deploying()) or inspected == null or not inspected.is_alive() or inspected.faction != Faction.Type.ENEMY:
			inspected_id = UnitId.NONE
	_heading.text = "intoDeDung   /   Бой у обрыва" if tactical_mode else "intoDeDung   /   Полигон"
	if armor_mode: _heading.text = "intoDeDung   /   Броня и огонь"
	if bleeding_mode: _heading.text = "intoDeDung   /   Кровотечение"
	if environment_mode: _heading.text = "intoDeDung   /   Среда и трупы"
	if control_mode: _heading.text = "intoDeDung   /   Крит и спина"
	if core_combination_mode: _heading.text = "intoDeDung   /   Сочетания ядра"
	if session is BattleCoreReactionsSession: _heading.text = "intoDeDung   /   Реакции и скрытая атака"
	_subtitle.text = "Трое против троих. Победите всех врагов; потеря команды означает поражение." if tactical_mode else "Поднимитесь по ступеням. Ударьте сверху. Столкните стража с уступа."
	_subtitle.visible = not tactical_mode
	if not core_reactions_mode: _status.custom_minimum_size.y = 26 if tactical_mode else 46
	_mode_button.text = "Полигон" if tactical_mode else "Бой против ИИ"
	_phase_label.visible = tactical_mode
	_phase_row.visible = tactical_mode
	_end_turn_button.visible = tactical_mode
	_environment_button.visible = session is BattleCoreReactionsSession and not _is_deploying()
	_environment_button.disabled = not _can_forecast_environment()
	# В тактическом режиме атака должна иметь единственную точку входа в action bar;
	# старая кнопка остаётся частью sandbox-полигона для совместимости.
	_attack_button.visible = not tactical_mode
	_instructions.text = "1 / A: атака · 2: защита · 3: лечение · 4: призыв · M: движение · ЛКМ по врагу: атака · Осмотр: список · Enter: конец хода · R: заново" if tactical_mode else "Ступени: Астра → D3 → A → Страж. Стена: Бор → A → Щит. Пропасть: Рей → A → Мишень на G7."
	if armor_mode: _instructions.text = _instructions.text.replace("4: призыв", "4: броня +20")
	if environment_mode: _instructions.text = "1 / A: атака · 2: защита · 3: лечение · 6: поднять тело · M: движение · Enter: конец хода · R: заново"
	if session is BattleBleedingSession and (session as BattleBleedingSession).rune_selected:
		_instructions.text = "Кровавая руна (перк): выберите цель · 1 основное · Обходит требование HP-урона; иммунитет сохраняется · A: обычная атака"
	if session is BattleCoreCombinationSession:
		_instructions.text += " · 7: опутывающий удар"
		if (session as BattleCoreCombinationSession).entangle_selected:
			_instructions.text = "Опутывающий удар: выберите цель · 1 основное · Путы после физического HP-урона · A: обычная атака"
	if session is BattleCoreReactionsSession and WarriorKit.is_skill((session as BattleCoreReactionsSession).warrior_selected):
		_instructions.text = ("Пинок ногой: соседняя цель · 1 дополнительное · без отката" if (session as BattleCoreReactionsSession).warrior_selected == WarriorKit.KICK else "Рассекающий удар: соседняя цель · 1 основное · откат 1") + " · A: обычная атака"
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).stun_selected:
		_instructions.text = "Оглушающий удар: выберите цель · 1 основное · Оглушение после физического HP-урона · A: обычная атака"
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &"":
		_instructions.text = "%s: выберите живую цель в пределах трёх клеток · 1 основное · Esc — отмена" % _elemental_effect_label((session as BattleCoreReactionsSession).elemental_selected)
		if AbilityDefinition.mage_source_id((session as BattleCoreReactionsSession).elemental_selected) > 0: _instructions.text = "Маг: выберите цель на доске · отдельная мана · Esc — отмена"
		if AbilityDefinition.is_cell_spell((session as BattleCoreReactionsSession).elemental_selected): _instructions.text = "Маг: свободная клетка рядом с любым союзником%s · 1 мана · Esc — отмена" % (" с телом" if (session as BattleCoreReactionsSession).elemental_selected == &"mage.test_raise" else "")
	var locked := _battle != null and not _battle.can_player_act()
	_move_button.disabled = locked
	if session.selected_unit() != null and ControlRules.action_reason(session.selected_unit(), true) != &"": _move_button.disabled = true
	_attack_button.disabled = locked
	_end_turn_button.disabled = locked
	_end_turn_button.text = "Начать бой · Enter" if _is_deploying() else "Завершить ход · Enter"
	if _is_deploying() and session is BattleCoreReactionsSession and session.state.deck != null:
		_end_turn_button.text = "Подтвердить расстановку · Enter" if not (session as BattleCoreReactionsSession).mage_deployment_confirmed else "Подтвердить карты · Enter"
	if _is_deploying(): _end_turn_button.disabled = false
	_action_bar.visible = tactical_mode
	if tactical_mode and _action_bar != null:
		var descriptors := BattleActionDescriptors.build(session, _battle, locked, environment_mode, _reason_text)
		if _action_bar.compact_vertical and session is BattleCoreReactionsSession:
			descriptors = (session as BattleCoreReactionsSession).visible_action_descriptors(descriptors)
		_action_bar.set_dynamic_descriptors(descriptors, reset_dynamic_page)
		_descriptors_session_id = session.get_instance_id()
		_descriptors_actor = session.selected_id
		var control_reason := ControlRules.action_reason(session.selected_unit())
		_action_bar.set_slot_enabled(&"attack", not locked and control_reason == &"", "Сейчас нельзя действовать." if locked else (_reason_text(control_reason) if control_reason != &"" else "1 основное действие"))
		var guard_reason := _battle.guard_reason() if _battle != null else &"battle/input_locked"
		var guard_enabled := not locked and guard_reason == &""
		_action_bar.set_slot_enabled(&"guard", guard_enabled, "1 основное действие" if guard_enabled else _reason_text(guard_reason))
	if _battle != null:
		_phase_label.text = _battle.phase_text()
		if session is BattleBleedingSession:
			for event: Dictionary in (session as BattleBleedingSession).turn_events: _note(_event_text(event))
			(session as BattleBleedingSession).turn_events.clear()
		while _flow_cursor < _battle.flow_log.size():
			_note(_battle.flow_log[_flow_cursor])
			_flow_cursor += 1
	_move_button.set_pressed_no_signal(not attack_mode)
	_attack_button.set_pressed_no_signal(attack_mode)
	_log.visible = not attack_mode
	_log_heading.visible = not attack_mode
	_forecast_panel.visible = attack_mode or _item_forecast != null or _move_forecast != null or _guard_forecast != null or _armor_forecast != null or _raise_forecast != null
	_forecast_heading.visible = attack_mode or _item_forecast != null or _move_forecast != null or _guard_forecast != null or _armor_forecast != null or _raise_forecast != null
	var elemental_mode: bool = session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &""
	_forecast_panel.visible = _forecast_panel.visible or elemental_mode or _elemental_forecast != null
	_forecast_heading.visible = _forecast_panel.visible
	if locked:
		summoning_mode = false
		raising_mode = false
		retreat_mode = false
		_cover_guard_mode = false
		if session is BattleCoreReactionsSession: (session as BattleCoreReactionsSession).elemental_selected = &""
	board_view.summoning_mode = summoning_mode
	board_view.raising_mode = raising_mode
	board_view.retreat_mode = retreat_mode
	board_view.environment_mode = environment_mode
	board_view.attack_mode = attack_mode
	board_view.elemental_mode = elemental_mode
	board_view.inspected_id = inspected_id
	board_view.reaction_zone_cells.clear()
	_update_area_preview()
	board_view.cover_target_ids.clear()
	board_view.sneak_threat_ids.clear()
	if session is BattleCoreReactionsSession and MeleeThreat.has_reactions(session.selected_unit()):
		if _cover_guard_mode: board_view.cover_target_ids.assign((session as BattleCoreReactionsSession).cover_targets())
	if _forecast != null:
		for event: Dictionary in _forecast.events:
			if event.get("kind") != &"attacked": continue
			var modifiers: Dictionary = event.get("modifiers", {})
			for threat_id: Variant in modifiers.get("threat_ids", []):
				if typeof(threat_id) == TYPE_INT and not board_view.sneak_threat_ids.has(threat_id): board_view.sneak_threat_ids.append(threat_id)
	var followup := {"refresh_turn": refresh_turn, "refresh_environment": refresh_environment, "refresh_armor": refresh_armor, "refresh_guard_action": refresh_guard_action, "refresh_healing": refresh_healing, "refresh_guard": refresh_guard, "locked": locked}
	if staged:
		# Заголовки оболочки должны попасть в тот же layout-проход: временный
		# текст base-сцены иначе дважды меняет размер поля между стадиями.
		_before_staged_refresh()
		_refresh_followup = followup
		_refresh_stage = 0
		return
	board_view.refresh()
	_finish_refresh(followup)

func _finish_refresh(followup: Dictionary) -> void:
	var locked: bool = followup.locked
	var refresh_turn: bool = followup.refresh_turn
	var refresh_environment: bool = followup.refresh_environment
	var refresh_armor: bool = followup.refresh_armor
	var refresh_guard_action: StringName = followup.refresh_guard_action
	var refresh_healing: bool = followup.refresh_healing
	var refresh_guard: bool = followup.refresh_guard
	var roster_ids: Array[int] = []
	for unit in session.units:
		roster_ids.append(unit.id)
		var alive := unit.is_alive()
		var waiting := " · ЖДЁТ ХОДА" if session.state.is_summon_pending(unit.id) and alive else ""
		var stance := " · ОХРАНА" if unit.guard_stance and alive else ""
		if alive and unit.control != null:
			if unit.control.stunned_turns > 0: stance += " · ОГЛУШЁН"
			if unit.control.entangled_turns > 0: stance += " · ОПУТАН"
		var perk_status := _perk_status_text(unit)
		var text := "%s%s%s  ·  %s" % [unit.debug_name, stance + waiting, perk_status, "HP %.1f / %.1f" % [unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX)] if alive else "погиб"]
		var button := _roster_presenter.get_or_create_button(unit.id)
		button.text = text
		button.tooltip_text = ""
		if session is BattleCoreReactionsSession:
			# Сочетания перков/контроля не должны расширять окно за пределы viewport.
			if not core_reactions_mode:
				button.clip_text = true
				button.custom_minimum_size.x = 480
			button.tooltip_text = text
			# HP идёт перед длинными перками, чтобы оставаться видимым при обрезке.
			button.text = "%s · %s%s%s" % [unit.debug_name, "HP %.1f / %.1f" % [unit.vitals.get_hp(), unit.get_stat(StatTypes.StatType.HP_MAX)] if alive else "погиб", stance + waiting, perk_status]
		if not core_reactions_mode:
			button.custom_minimum_size.y = 30
			button.toggle_mode = true
		button.set_pressed_no_signal(unit.id == session.selected_id and alive)
		if _battle != null and unit.faction == Faction.Type.ENEMY:
			button.set_pressed_no_signal(unit.id == inspected_id and alive)
			button.disabled = not alive or (locked and not _is_deploying())
		else:
			button.disabled = not alive or (locked and not _is_deploying())
	_roster_presenter.retain_ordered(roster_ids)
	var selected := session.selected_unit()
	if selected == null:
		_stats.text = "Выберите живого персонажа в списке."
		if locked:
			_stats.text = "Дождитесь завершения хода противника." if _battle.phase == BattleTacticalSession.Phase.ENEMY_TURN else "Бой окончен. Нажмите R, чтобы сыграть снова."
	else:
		_stats.text = _inspection_text(selected)
	if inspected_id != UnitId.NONE:
		var enemy := session.board.get_unit_by_id(inspected_id)
		if enemy != null:
			_stats.text = _inspection_text(enemy)
	_status.text = "Атака: щёлкните по цели. Расход — 1 основное действие." if attack_mode else ("ЛКМ: пустая клетка — движение; враг — подход и обычная атака; свой герой — выбор." if _battle != null else "Движение: щёлкните по свободной клетке. Персонаж на поле или в списке — выбор.")
	if _character_card != null and not attack_mode:
		# Постоянная инструкция убрана; слот остаётся для отказов/результатов без сдвига поля.
		_status.text = ""
	if attack_mode and session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).warrior_selected == WarriorKit.KICK:
		_status.text = "Пинок ногой: щёлкните по соседнему врагу. Расход — 1 дополнительное действие."
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &"":
		_status.text = "%s: наведите курсор на цель для прогноза, щёлкните для применения." % _elemental_effect_label((session as BattleCoreReactionsSession).elemental_selected)
	if inspected_id != UnitId.NONE:
		var enemy := session.board.get_unit_by_id(inspected_id)
		_status.text = "Осмотр: %s · движение на следующий ход: %.1f ОД\nТекущая расстановка; зона движения. Esc или клик по пустой клетке — закрыть." % [enemy.debug_name, enemy.get_stat(StatTypes.StatType.MOVE_RANGE)]
		if ControlRules.action_reason(enemy, true) != &"": _status.text = "Осмотр: %s · движение в ближайший ход недоступно из-за состояния.\nEsc или клик по пустой клетке — закрыть." % enemy.debug_name
	if summoning_mode: _status.text = "Призыв: выберите подсвеченную соседнюю клетку. 1 основное + 1 заряд. Esc — отмена."
	if raising_mode: _status.text = "Поднять тело: выберите подсвеченную соседнюю свободную клетку без шипов. 1 основное. Esc — отмена."
	if retreat_mode: _status.text = "Безопасный отход: выберите клетку. 1 основное + пройденное движение. Оппортунист не срабатывает; опасности сохраняются. Esc — отмена."
	if session.context.is_faulted(): _status.text = "Исполнение остановлено из-за ошибки. Выполненные последствия сохранены; сбросьте бой."
	if locked: _status.text = _battle.phase_text() + (" · Можно начать заново: R." if _battle.phase != BattleTacticalSession.Phase.ENEMY_TURN else " · Противник выполняет действия.")
	if _is_deploying():
		_instructions.text = "Выберите союзника → свободную клетку в зоне A3–F6. Перестановки бесплатны. Enter: начать бой · R: исходная расстановка"
		_status.text = "Расставьте отряд или начните с готовой позиции. Противников можно осмотреть; действия и эффекты пока не исполняются."
	elif session is BattleCoreCombinationSession:
		_instructions.text += " · 8: печать призыва"
	if session is BattleCoreReactionsSession and not _is_deploying():
		_instructions.text = "1–4: способности слева · маг: снизу · зелёная зона: союзник, красная: враг · контур: область выбранного действия"
	if _cover_guard_mode: _status.text = "Прикрытие: выберите подсвеченного союзника. 1 основное действие, дополнительное действие тратится при срабатывании. Esc — отмена."
	_hover(board_view.hover_cell)
	_log.text = "\n".join(_journal)
	if refresh_armor and _battle != null and _battle.can_player_act(): _action_bar_hovered(&"restore_armor")
	if refresh_guard and _battle != null and _battle.can_player_act(): _action_bar_hovered(refresh_guard_action)
	if refresh_healing and _battle != null and _battle.can_player_act(): _action_bar_hovered(&"healing_item")
	if refresh_turn and _can_forecast_turn(): _request_turn_forecast()
	if refresh_environment and _can_forecast_environment(): _request_environment_forecast()
	_render_forecast_panel()
	_displayed_unit_hovered(_display_inspection_id)
	_after_refresh()
	_refresh_character_card()
	if followup.has("receipt_message"): _status.text = followup.receipt_message

func _after_refresh() -> void:
	pass

func _before_staged_refresh() -> void:
	pass

func _perk_status_text(unit: UnitState) -> String:
	if not session is BattleCoreReactionsSession or unit.combat_perks == null: return ""
	var parts: PackedStringArray = []
	if unit.combat_perks.definition.sneak_attack: parts.append("Скрытая атака")
	if WarriorKit.enabled(unit): parts.append("Выносливость: +20% к получаемому исцелению и броне")
	if unit.combat_perks.definition.stunning_strike: parts.append("Оглушающий удар")
	if unit.combat_perks.definition.counterattack: parts.append("перк Контратака")
	if unit.combat_perks.definition.stun_immune: parts.append("иммунитет к оглушению")
	if unit.combat_perks.definition.entangle_immune: parts.append("иммунитет к путам")
	if MeleeThreat.has_reactions(unit):
		var mode_text := "Оппортунист (пассивный)" if MeleeThreat.has_passive_opportunist(unit) else "без режима"
		if unit.combat_perks.mode == CombatPerksState.Mode.OPPORTUNIST: mode_text = "Оппортунист"
		elif unit.combat_perks.mode == CombatPerksState.Mode.COVER: mode_text = "Прикрытие → " + _name_for(unit.combat_perks.cover_target_id)
		elif unit.combat_perks.mode == CombatPerksState.Mode.COUNTERATTACK: mode_text = "Контратака"
		parts.append("%s · %s %d" % [mode_text, "доп." if unit.combat_perks.uses_bonus_actions else "реакция", MeleeThreat.reaction_points(unit)])
	if unit.combat_perks.movement_stopped: parts.append("движение остановлено")
	return " · " + " · ".join(parts) if not parts.is_empty() else ""

func _inspection_text(unit: UnitState) -> String:
	return BattleInspectionText.build_live(unit, session.state, _inspection_options(unit))

func _inspection_options(unit: UnitState) -> BattleInspectionText.Options:
	var options := BattleInspectionText.Options.new()
	options.height_steps = session.board.get_height_steps(unit.cell)
	options.core_reactions = session is BattleCoreReactionsSession
	options.control_mode = control_mode
	options.bleeding_session = session is BattleBleedingSession
	options.summoning_supported = _battle == null or _battle.supports_summoning()
	if options.core_reactions and unit.combat_perks != null:
		if MeleeThreat.has_reactions(unit) \
		and unit.combat_perks.mode == CombatPerksState.Mode.COVER:
			options.cover_target_name = _name_for(unit.combat_perks.cover_target_id)
	if session.state.is_summon(unit.id) and not session.state.is_mage_summon(unit.id):
		options.summon_owner_name = _name_for(session.state.summon_owner_id(unit.id))
	return options

func _open_character_card(unit_id: int) -> void:
	if _character_card == null or is_execution_pending() or session == null: return
	_character_card_id = unit_id
	_character_card_session = session.get_instance_id()
	_refresh_character_card()

func _close_character_card() -> void:
	# Закрытие — только UI: выбранный союзник и остатки действий не меняются.
	_character_card_id = UnitId.NONE
	_character_card_identity.clear()
	if _character_card != null: _character_card.hide()
	_queue_character_card_layout()

func _refresh_character_card() -> void:
	if _character_card == null or _character_card_id == UnitId.NONE or is_execution_pending(): return
	if session == null or session.get_instance_id() != _character_card_session:
		_close_character_card()
		return
	var unit := session.board.get_unit_by_id(_character_card_id)
	if unit == null:
		_close_character_card()
		return
	var loadout: Dictionary = session.actor_loadouts.get(unit.id, {}) if session is BattleCoreReactionsSession else {}
	var data := BattleCharacterCardData.live(unit, session.state, loadout, _inspection_options(unit))
	data.details_text += _card_imbue_text(unit.id)
	_character_card_identity = {"class_label": data.class_label, "portrait": data.portrait}
	_character_card.show_data(data)
	_queue_character_card_layout()

func _queue_character_card_layout() -> void:
	call_deferred("_layout_character_card")

func _layout_character_card() -> void:
	if _character_card == null or _status == null: return
	var hud := _character_card.get_parent() as Control
	# Сообщения лежат поверх нижнего края поля: пустая строка не отнимает место у боя.
	var feedback_height := maxf(44.0, _status.get_combined_minimum_size().y)
	var width := minf(300.0, hud.size.x - 48.0)
	var feedback_width := hud.size.x - 48.0 - (width + 12.0 if _character_card.visible else 0.0)
	_status.position = Vector2(24.0, _hint.global_position.y - hud.global_position.y - feedback_height - 4.0)
	_status.size = Vector2(maxf(0.0, feedback_width), feedback_height)
	if not _character_card.visible: return
	var top := board_view.get_global_rect().position.y + 44.0
	var bottom := minf(hud.get_global_rect().end.y - 12.0, _hint.get_global_rect().position.y - 8.0)
	if _mage_row.is_visible_in_tree(): bottom = minf(bottom, _mage_row.get_global_rect().position.y - 12.0)
	# Карточка — независимый overlay. Меняем только её прямоугольник, не Board/камеру.
	_character_card.position = Vector2(hud.size.x - width - 24.0, top - hud.global_position.y)
	_character_card.size = Vector2(width, maxf(0.0, minf(570.0, bottom - top)))

func _stat_name(type: StatTypes.StatType) -> String:
	return BattleInspectionText.stat_name(type)

func _refresh_inspection() -> void:
	if is_execution_pending(): return
	var id := _forecast_target_id if _forecast != null or _attack_forecast_pending else inspected_id
	var unit := session.board.get_unit_by_id(id) if id != UnitId.NONE else session.selected_unit()
	if unit != null:
		if _shown_inspection_id != unit.id:
			(_stats.get_parent() as ScrollContainer).scroll_vertical = 0
		_shown_inspection_id = unit.id
		_stats.text = _inspection_text(unit) + _card_imbue_text(unit.id)

func _hover(cell: Vector2i) -> void:
	_displayed_cell_hovered(cell)
	if not _forecast_replaying_intent and (_forecast_preparation_worker.is_started() or _forecast_preparation_recovering or _interactive_refresh_pending):
		_forecast_latest_hover = cell
		_forecast_hover_pending = true
		return
	if is_execution_pending(): return
	if session == null or session.board == null: return
	if _is_deploying(): return
	if _environment_forecast != null or _environment_forecast_pending:
		if cell.x < 0:
			_resolve_hover_exit.call_deferred()
			return
		_clear_forecast()
	if _turn_forecast != null or _turn_forecast_pending:
		if cell.x < 0:
			_resolve_hover_exit.call_deferred()
			return
		_clear_forecast()
	if (_guard_forecast != null and _guard_forecast_mode != CombatPerksState.Mode.COVER or _armor_forecast != null) and cell.x >= 0: _clear_forecast()
	# Позволяем перейти к прокрутке длинной цепи, сохранив текущий прогноз.
	if (_forecast != null or _attack_forecast_pending or _action_forecast_pending or _item_forecast != null or _move_forecast != null or _move_forecast_pending or _raise_forecast != null or _guard_forecast != null or _armor_forecast != null or _elemental_forecast != null) and cell.x < 0:
		# mouse_exited может прийти раньше _input того же движения мыши.
		_resolve_hover_exit.call_deferred()
		return
	if raising_mode and session is BattleEnvironmentSession and _battle.can_player_act() and session.board.is_in_bounds(cell):
		var revision := session.context.get_revision()
		if (_raise_forecast == null and not _action_forecast_pending) or _raise_forecast_cell != cell or _raise_forecast_actor != session.selected_id or _raise_forecast_revision != revision:
			_clear_forecast()
			_raise_forecast_cell = cell
			_raise_forecast_actor = session.selected_id
			_raise_forecast_revision = revision
			_forecast_panel.get_v_scroll_bar().value = 0.0
			_request_action_forecast(&"raise", cell)
	elif summoning_mode and _battle != null and _battle.can_player_act() and session.board.is_in_bounds(cell):
		var revision := session.context.get_revision()
		if _item_forecast_kind != &"summon" or _item_forecast_cell != cell or _item_forecast_revision != revision:
			_clear_forecast()
			_item_forecast_kind = &"summon"
			_item_forecast_cell = cell
			_item_forecast_revision = revision
			_forecast_panel.get_v_scroll_bar().value = 0.0
			_request_action_forecast(&"summon", cell)
	elif _cover_guard_mode and session is BattleCoreReactionsSession:
		var target := session.board.occupant_at(cell) if session.board.is_in_bounds(cell) else null
		var reaction_session := session as BattleCoreReactionsSession
		if target != null and reaction_session.cover_targets().has(target.id):
			var revision := session.context.get_revision()
			if (_guard_forecast == null and not _action_forecast_pending) or _guard_forecast_actor != session.selected_id or _guard_forecast_revision != revision or _guard_forecast_mode != CombatPerksState.Mode.COVER or _guard_forecast_target != target.id:
				_clear_forecast()
				_guard_forecast_actor = session.selected_id
				_guard_forecast_revision = revision
				_guard_forecast_mode = CombatPerksState.Mode.COVER
				_guard_forecast_target = target.id
				_request_action_forecast(&"cover", cell)
		else:
			_clear_forecast()
	elif _card_selected_id > 0 and session is BattleCoreReactionsSession:
		var target := session.board.occupant_at(cell) if session.board.is_in_bounds(cell) else null
		var card := session.state.deck.card(_card_selected_id)
		var definition := MageCardCatalog.get_card(String(card.get("type_id", "")))
		var cell_card: bool = definition != null and definition.target_policy in ["valid_cell", "corpse_cell"]
		if _battle == null or not _battle.can_player_act() or (target == null and not cell_card):
			_clear_forecast()
		else:
			if _action_forecast_kind != &"mage_card" or _action_forecast_cell != cell or _action_forecast_card_id != _card_selected_id or _action_forecast_target_id != (target.id if target != null else UnitId.NONE) or _action_forecast_effect != StringName(String(card.get("type_id", ""))) or not _magic_forecast_state_current():
				_clear_forecast()
				_forecast_panel.get_v_scroll_bar().value = 0.0
				_request_action_forecast(&"mage_card", cell)
	elif session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).elemental_selected != &"":
		var reaction_session := session as BattleCoreReactionsSession
		var target := session.board.occupant_at(cell) if session.board.is_in_bounds(cell) else null
		var cell_spell := AbilityDefinition.is_cell_spell(reaction_session.elemental_selected)
		if _battle == null or not _battle.can_player_act() or (target == null and not cell_spell):
			_clear_forecast()
		else:
			if _action_forecast_kind != &"elemental" or _action_forecast_effect != reaction_session.elemental_selected or _action_forecast_cell != cell or _action_forecast_target_id != (target.id if target != null else UnitId.NONE) or _action_forecast_revision != session.context.get_revision() or not _magic_forecast_state_current():
				_clear_forecast()
				_forecast_panel.get_v_scroll_bar().value = 0.0
				_request_action_forecast(&"elemental", cell)
	elif not attack_mode and not summoning_mode and not raising_mode and inspected_id == UnitId.NONE and (_battle == null or _battle.can_player_act()) and session.board.is_in_bounds(cell) and session.board.occupant_at(cell) == null:
		var revision := session.context.get_revision()
		if (_move_forecast == null and not _move_forecast_pending) or _move_forecast_cell != cell or _move_forecast_actor != session.selected_id or _move_forecast_revision != revision or _move_forecast_retreat != retreat_mode:
			_clear_forecast()
			_move_forecast_pending = true
			_move_forecast_due = Time.get_ticks_msec() + MOVE_HOVER_SETTLE_MS
			_move_forecast_cell = cell
			_move_forecast_actor = session.selected_id
			_move_forecast_revision = revision
			_move_forecast_retreat = retreat_mode
			_forecast_panel.get_v_scroll_bar().value = 0.0
			board_view.move_forecast_pending = true
			# Быстрая геометрия не ждёт полного исполнения прогноза в рабочем потоке.
			if board_view.reachable_cells().has(cell): board_view.pending_move_path = session.path_to(cell)
			board_view.refresh_forecast()
	elif not attack_mode or (_battle != null and not _battle.can_player_act()) or not session.board.is_in_bounds(cell):
		_clear_forecast()
	else:
		var target := session.board.occupant_at(cell)
		if target == null:
			_clear_forecast()
		else:
			var revision := session.context.get_revision()
			if _forecast_cell != cell or _forecast_target_id != target.id or _forecast_revision != revision or _attack_forecast_actor != session.selected_id or _attack_forecast_variant != _attack_variant():
				_clear_forecast()
				_attack_forecast_pending = true
				_attack_forecast_actor = session.selected_id
				_attack_forecast_variant = _attack_variant()
				# Новый прогноз всегда читается с начала, даже после прокрутки предыдущей цели.
				_forecast_panel.get_v_scroll_bar().value = 0.0
				_forecast_cell = cell
				_forecast_target_id = target.id
				_forecast_revision = revision
	_refresh_inspection()

	if environment_mode and session is BattleEnvironmentSession and session.board.is_in_bounds(cell):
		var environment := (session as BattleEnvironmentSession).state.environment
		var details: Array[String] = []
		for corpse: Dictionary in environment.corpses_at(cell):
			var faction: String = {Faction.Type.PLAYER: "союзник", Faction.Type.ENEMY: "противник", Faction.Type.NEUTRAL: "нейтральный"}[corpse["faction"]]
			var kind := "гуманоид" if corpse["creature_kind"] == "humanoid" else String(corpse["creature_kind"])
			details.append("%s · %s" % [faction, kind])
		var fire_record: Dictionary = environment.fire_at(cell)
		var fire := "Опасностей нет."
		if not fire_record.is_empty():
			fire = _hazard_summary(fire_record)
		fire = _append_cell_hazards(fire, environment.hazards, cell)
		_hint.text = fire + ("\nТела ×%d: %s" % [details.size(), ", ".join(details)] if not details.is_empty() else "\nТрупов нет.")
		if environment.collapse.get("marked", []).has(cell):
			_hint.text = "%s · ОБВАЛ после вашего хода. Клетка станет пропастью; оставшийся здесь погибнет.\n" % _cell_name(cell) + _hint.text
		if raising_mode: _hint.text += "\nПоднятие: выберите соседнюю клетку той же высоты."
		var area_text := board_view.area_details(cell)
		if not area_text.is_empty(): _hint.text = area_text + "\n" + _hint.text
		_hint.tooltip_text = _hint.text
		_render_forecast_panel()
		return

	if summoning_mode:
		var item := _battle.summoning_item()
		_hint.text = "Бирюзовые точки — клетки призыва. Клик — %s.\nПомощник с %s HP действует со следующего хода своей команды. Esc — отмена." % [_item_cost_text(item.get_use_action() if item != null else null), _summon_hp_text(item)]
		return
	if not session.board.is_in_bounds(cell):
		var movement_cancel_hint := "Клик ПКМ — отмена; перетаскивание ПКМ — камера; Esc/M — отмена." if board_view.camera_controls_enabled else "ПКМ или Esc — движение."
		_hint.text = "Золотые клетки — движение врага на следующий ход; зона атаки не показана.\nВыбранный союзник сохранён. Осмотр не расходует действия." if inspected_id != UnitId.NONE else "Числа на клетках — высота. Бирюзовые точки — доступное движение.\nПолоски: здоровье / запас равновесия. %s" % movement_cancel_hint
		if control_mode and not session is BattleCoreReactionsSession and inspected_id == UnitId.NONE: _hint.text = "Розовая стрелка у ног — тыл: атака с соседней клетки даёт +50% базы.\nОглушение или путы на цели дают крит ×2; два состояния не складывают крит."
		return
	var reachable: Dictionary = board_view.reachable_cells()
	var cost := " · путь: %.1f ОД" % float(reachable[cell]) if reachable.has(cell) else ""
	_hint.text = "%s · высота %+.1f%s\n%s" % [_cell_name(cell), float(session.board.get_height_steps(cell)) / 2.0, cost, "Осмотр: зона движения на следующий ход, не атаки." if inspected_id != UnitId.NONE else "Прогноз показывает итог движения. Клик — выполнить; кольцо — конечная клетка."]
	if attack_mode: _hint.text = "Наведите на цель: прогноз одной атаки. Клик — выполнить.\nКрасный сегмент HP — потеря, зелёный — лечение; белая метка — итог."
	var environment_state: CombatEnvironmentState = session.state.environment if session.state != null else null
	if environment_state != null:
		var hazard: Dictionary = environment_state.fire_at(cell)
		if not hazard.is_empty():
			_hint.text += "\n" + _hazard_summary(hazard)
		var cell_hazards := _cell_hazard_text(environment_state.hazards, cell)
		if not cell_hazards.is_empty(): _hint.text += "\n" + cell_hazards
	_render_forecast_panel()

func _hazard_summary(hazard: Dictionary) -> String:
	if String(hazard.get("effect", "")) == "burning": return "Огонь: поджог при входе и в начале своего хода, независимо от брони."
	if hazard.has("effect"): return "Шипы: 8 физического урона при входе; кровотечение независимо от брони."
	return "Шипы: 8 урона при входе."

func _cell_hazard_text(hazards: Dictionary, cell: Vector2i) -> String:
	var lines: PackedStringArray = []
	if cell in hazards.get("acid", []): lines.append("Кислота: вход добавляет 1 ход; в начале своего командного хода снимает 10 брони, HP не затрагивает. Стоя в луже, вы добавляете ещё 1 ход.")
	for trap: Dictionary in hazards.get("traps", []):
		if trap.get("cell", Vector2i(-1, -1)) != cell: continue
		if String(trap.get("kind", "")) == "wall":
			lines.append("Настенная ловушка-шипы: срабатывает при толчке в соседнюю стену.")
		else:
			lines.append("Напольные шипы: добровольный вход взводит ловушку; она срабатывает в начале следующего хода этой команды. Толчок или падение минимум на 1 клетку срабатывает сразу.")
	return "\n".join(lines)

func _append_cell_hazards(base: String, hazards: Dictionary, cell: Vector2i) -> String:
	var details := _cell_hazard_text(hazards, cell)
	return base + ("\n" + details if not details.is_empty() else "")

func _attack_variant() -> StringName:
	if session is BattleCoreReactionsSession and WarriorKit.is_skill((session as BattleCoreReactionsSession).warrior_selected): return (session as BattleCoreReactionsSession).warrior_selected
	if session is BattleCoreReactionsSession and (session as BattleCoreReactionsSession).stun_selected: return &"stun"
	if session is BattleCoreCombinationSession and (session as BattleCoreCombinationSession).entangle_selected: return &"entangle"
	if session is BattleBleedingSession and (session as BattleBleedingSession).rune_selected: return &"rune"
	return &"ordinary"

func _attack_forecast_request_current() -> bool:
	if session == null or session.context == null or board_view == null: return false
	if not attack_mode or summoning_mode or raising_mode or _cover_guard_mode or (_battle != null and not _battle.can_player_act()): return false
	if session.selected_id != _attack_forecast_actor or session.context.get_revision() != _forecast_revision or _attack_variant() != _attack_forecast_variant: return false
	var target := session.board.get_unit_by_id(_forecast_target_id)
	if target == null or target.cell != _forecast_cell: return false
	# Переход к панели сохраняет ожидаемый результат так же, как уже готовый прогноз.
	return board_view.hover_cell == _forecast_cell or (board_view.hover_cell.x < 0 and _forecast_reading_region().has_point(_pointer_position))

func _request_action_forecast(kind: StringName, cell: Vector2i = Vector2i(-1, -1)) -> void:
	if is_execution_pending(): return
	_action_forecast_pending = true
	_action_forecast_kind = kind
	_action_forecast_actor = session.selected_id
	_action_forecast_revision = session.context.get_revision()
	_action_forecast_cell = cell
	_action_forecast_session_id = session.get_instance_id()
	_action_forecast_target_id = UnitId.NONE
	_action_forecast_effect = &""
	_action_forecast_card_id = 0
	_action_forecast_cache = {}
	_action_forecast_freshness = null
	_mage_display_freshness = null
	_action_freshness_expected = kind in [&"elemental", &"mage_card"] and _allows_execution_worker() and session.get_script() == BattleCoreReactionsSession
	if kind == &"elemental" and session is BattleCoreReactionsSession:
		var reaction_session := session as BattleCoreReactionsSession
		var target := session.board.occupant_at(cell) if session.board.is_in_bounds(cell) else null
		_action_forecast_target_id = target.id if target != null else UnitId.NONE
		_action_forecast_effect = reaction_session.elemental_selected
		if not _action_freshness_expected: _action_forecast_cache = _elemental_cast_cache(reaction_session.selected_unit(), target, _action_forecast_effect, cell if AbilityDefinition.is_cell_spell(_action_forecast_effect) else Vector2i(-1, -1))
	elif kind == &"mage_card" and session is BattleCoreReactionsSession:
		var target := session.board.occupant_at(cell) if session.board.is_in_bounds(cell) else null
		_action_forecast_card_id = _card_selected_id
		_action_forecast_target_id = target.id if target != null else UnitId.NONE
		_action_forecast_effect = StringName(String(session.state.deck.card(_card_selected_id).get("type_id", "")))
		if not _action_freshness_expected: _action_forecast_cache = _mage_card_cache(target, cell)
	_render_forecast_panel()

func _current_magic_snapshot_cache() -> Dictionary:
	var target := session.board.get_unit_by_id(_action_forecast_target_id)
	if _action_forecast_kind == &"mage_card": return _mage_card_cache(target, _action_forecast_cell)
	return _elemental_cast_cache(session.selected_unit(), target, _action_forecast_effect,
		_action_forecast_cell if AbilityDefinition.is_cell_spell(_action_forecast_effect) else Vector2i(-1, -1))

func _magic_forecast_state_current() -> bool:
	if _action_forecast_freshness != null: return _action_forecast_freshness.matches(session as BattleCoreReactionsSession)
	# До prepare чисел ещё нет; текущий мир будет строго снят владельцем в worker.
	if _action_freshness_expected: return _action_forecast_pending
	return _current_magic_snapshot_cache() == _action_forecast_cache

func _mage_card_cache(target: UnitState, cell: Vector2i) -> Dictionary:
	if not session is BattleCoreReactionsSession or session.state.deck == null or _card_selected_id <= 0: return {}
	var captured := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	return {"session_id": session.get_instance_id(), "card_instance_id": _card_selected_id,
		"target_id": target.id if target != null else UnitId.NONE, "cell": cell,
		"world": captured.snapshot.to_dict() if captured.snapshot != null else {}, "capture_reason": captured.reason,
		"rng": session.context.get_rng().to_dict().duplicate(true), "counters": session.context.simulation_counters(),
		"admission": SummonAdmission.values(session.context),
		"limits": [session._queue._max_commands, session._queue._max_events, session._queue._max_depth]}

func _elemental_cast_cache(actor: UnitState, target: UnitState, effect: StringName, cell: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if (target == null and not AbilityDefinition.is_cell_spell(effect)) or (actor == null and AbilityDefinition.mage_source_id(effect) == 0): return {}
	# Равные totals/revision не означают равные вещи, перки, RNG и последствия.
	var captured := ItemSimulationSnapshot.capture(session.state, session.context.get_unsupported_runtime_ids())
	return {
		"session_id": session.get_instance_id(), "actor_id": actor.id if actor != null else 0, "effect": effect,
		"target_id": target.id if target != null else UnitId.NONE, "cell": cell, "world": captured.snapshot.to_dict() if captured.snapshot != null else {},
		"capture_reason": captured.reason, "rng": session.context.get_rng().to_dict().duplicate(true),
		"counters": session.context.simulation_counters(), "admission": SummonAdmission.values(session.context),
		"limits": [session._queue._max_commands, session._queue._max_events, session._queue._max_depth],
	}

func _action_forecast_request_current() -> bool:
	if _battle == null or not _battle.can_player_act() or board_view == null: return false
	if session == null or session.get_instance_id() != _action_forecast_session_id or session.selected_id != _action_forecast_actor or session.context.get_revision() != _action_forecast_revision: return false
	var over_panel := board_view.hover_cell.x < 0 and _forecast_reading_region().has_point(_pointer_position)
	match _action_forecast_kind:
		&"healing": return _hovered_bar_action == &"healing_item" or over_panel
		&"armor": return _hovered_bar_action == &"restore_armor" or over_panel
		&"raise_shields": return _hovered_bar_action == &"raise_shields" or over_panel
		&"guard": return _hovered_bar_action == &"guard" or over_panel
		&"opportunity": return _hovered_bar_action == &"opportunity_guard" or over_panel
		&"counterattack": return _hovered_bar_action == &"counterattack_guard" or over_panel
		&"raise": return raising_mode and (board_view.hover_cell == _action_forecast_cell or over_panel)
		&"summon": return summoning_mode and (board_view.hover_cell == _action_forecast_cell or over_panel)
		&"cover":
			var target := session.board.get_unit_by_id(_guard_forecast_target)
			return _cover_guard_mode and target != null and target.cell == _action_forecast_cell and (board_view.hover_cell == _action_forecast_cell or over_panel)
		&"elemental":
			if not session is BattleCoreReactionsSession: return false
			var reaction_session := session as BattleCoreReactionsSession
			var target := session.board.get_unit_by_id(_action_forecast_target_id)
			var cell_spell := AbilityDefinition.is_cell_spell(_action_forecast_effect)
			if (not cell_spell and (target == null or target.cell != _action_forecast_cell)) or reaction_session.elemental_selected != _action_forecast_effect: return false
			if not _magic_forecast_state_current(): return false
			if _action_forecast_freshness == null and reaction_session.cast_reason(_action_forecast_effect) != &"": return false
			return board_view.hover_cell == _action_forecast_cell or over_panel
		&"mage_card":
			if not session is BattleCoreReactionsSession or _card_selected_id != _action_forecast_card_id: return false
			if session.state.deck == null or StringName(String(session.state.deck.card(_card_selected_id).get("type_id", ""))) != _action_forecast_effect: return false
			var target := session.board.get_unit_by_id(_action_forecast_target_id)
			if _action_forecast_target_id > 0 and (target == null or target.cell != _action_forecast_cell): return false
			if session.board.occupant_at(_action_forecast_cell) != target: return false
			if not _magic_forecast_state_current(): return false
			if _action_forecast_freshness == null and (session as BattleCoreReactionsSession).mage_card_reason(_card_selected_id) != &"": return false
			return board_view.hover_cell == _action_forecast_cell or over_panel
	return false

func _process_action_forecast() -> void:
	if is_execution_pending(): return
	# Готовый прогноз тоже устаревает при изменении мира без движения мыши.
	if _elemental_forecast != null and not _action_forecast_request_current():
		_clear_forecast()
		_hover(board_view.hover_cell)
	var result: ForecastSimulation = _action_forecast_worker.take_finished()
	if result != null and _action_forecast_pending and _action_forecast_job_generation == _action_forecast_generation:
		if not _action_forecast_request_current():
			_clear_forecast()
			return
		_action_forecast_pending = false
		match _action_forecast_kind:
			&"healing", &"summon": _item_forecast = ItemUseForecast.from_simulation(result)
			&"guard", &"opportunity", &"cover", &"counterattack", &"raise_shields": _guard_forecast = GuardForecast.from_simulation(result, _action_forecast_actor)
			&"raise": _raise_forecast = RaiseCorpseForecast.from_simulation(result, _action_forecast_actor, _action_forecast_corpse_id)
			&"armor": _armor_forecast = result
			&"elemental", &"mage_card": _elemental_forecast = result
		_render_forecast_panel()
		_refresh_inspection()
	if not _action_forecast_pending or _action_forecast_worker.is_started(): return
	if not _action_forecast_request_current():
		_clear_forecast()
		return
	var preparation_method: StringName = &""
	var preparation_args: Array = []
	match _action_forecast_kind:
		&"healing":
			preparation_method = &"item"; preparation_args = [ItemUseAction.Kind.HEAL_SELF]
		&"summon":
			preparation_method = &"item"; preparation_args = [ItemUseAction.Kind.SUMMON_ADJACENT, _action_forecast_cell]
		&"guard", &"opportunity", &"cover", &"counterattack":
			preparation_method = &"guard"; preparation_args = [_guard_forecast_mode, _guard_forecast_target]
		&"raise":
			preparation_method = &"raise_corpse"; preparation_args = [_action_forecast_cell]
		&"raise_shields": preparation_method = &"raise_shields"
		&"armor": preparation_method = &"restore_armor"
		&"elemental":
			if AbilityDefinition.is_cell_spell(_action_forecast_effect):
				preparation_method = &"mage_cell"; preparation_args = [_action_forecast_effect, _action_forecast_cell]
			else:
				preparation_method = &"cast"; preparation_args = [_action_forecast_target_id]
		&"mage_card":
			preparation_method = &"mage_card"; preparation_args = [_action_forecast_card_id, maxi(0, _action_forecast_target_id), _action_forecast_cell]
	_action_forecast_job_generation = _action_forecast_generation
	if _start_forecast_preparation(&"action", preparation_method, preparation_args, _action_forecast_generation): return
	var prepared: ForecastSimulation.Prepared
	match _action_forecast_kind:
		&"healing": prepared = _battle.prepare_item_forecast(ItemUseAction.Kind.HEAL_SELF)
		&"summon": prepared = _battle.prepare_item_forecast(ItemUseAction.Kind.SUMMON_ADJACENT, _action_forecast_cell)
		&"guard", &"opportunity", &"cover", &"counterattack": prepared = _battle.prepare_guard_forecast(_guard_forecast_mode, _guard_forecast_target)
		&"raise": prepared = (session as BattleEnvironmentSession).prepare_raise_corpse_forecast(_action_forecast_cell)
		&"raise_shields": prepared = _battle.prepare_raise_shields_forecast()
		&"armor": prepared = (session as BattleArmorSession).prepare_restore_armor_forecast()
		&"elemental":
			var reaction_session := session as BattleCoreReactionsSession
			prepared = reaction_session.prepare_mage_cell_forecast(_action_forecast_effect, _action_forecast_cell) if AbilityDefinition.is_cell_spell(_action_forecast_effect) else reaction_session.prepare_cast_forecast(_action_forecast_target_id)
		&"mage_card": prepared = (session as BattleCoreReactionsSession).prepare_mage_card_forecast(_action_forecast_card_id, _action_forecast_target_id if _action_forecast_target_id > 0 else 0, _action_forecast_cell)
	_action_forecast_corpse_id = (prepared.command as RaiseCorpseCommand)._corpse_id if prepared != null and prepared.command is RaiseCorpseCommand else 0
	_action_forecast_job_generation = _action_forecast_generation
	_action_forecast_worker.start(prepared)

func _process_attack_forecast() -> void:
	if is_execution_pending(): return
	var result := _attack_forecast_worker.take_finished()
	if result != null and _attack_forecast_pending and _attack_forecast_job_generation == _attack_forecast_generation:
		if not _attack_forecast_request_current():
			_clear_forecast()
			return
		_forecast = result
		_attack_forecast_pending = false
		board_view.forecast = result
		_sync_sneak_threat_highlight()
		board_view.refresh_forecast()
		_render_forecast_panel()
		_refresh_inspection()
	if not _attack_forecast_pending or _attack_forecast_worker.is_started(): return
	if not _attack_forecast_request_current():
		_clear_forecast()
		return
	_attack_forecast_job_generation = _attack_forecast_generation
	if _start_forecast_preparation(&"attack", &"attack", [_forecast_target_id], _attack_forecast_generation): return
	# Синхронная совместимость оболочек, не передающих session рабочему потоку.
	_attack_forecast_worker.start(session.prepare_attack_forecast(_forecast_target_id))

func _process_move_forecast() -> void:
	if is_execution_pending(): return
	var result := _move_forecast_worker.take_finished()
	if result != null and _move_forecast_pending and _move_forecast_job_generation == _move_forecast_generation:
		if not _move_forecast_request_current():
			_clear_forecast()
			return
		_move_forecast = result
		_move_forecast_pending = false
		board_view.move_forecast_pending = false
		board_view.pending_move_path.clear()
		board_view.move_forecast = result
		board_view.refresh_forecast()
		_render_forecast_panel()
	if not _move_forecast_pending or _move_forecast_worker.is_started() or Time.get_ticks_msec() < _move_forecast_due: return
	if not _move_forecast_request_current():
		_clear_forecast()
		return
	_move_forecast_job_generation = _move_forecast_generation
	if _start_forecast_preparation(&"move", &"retreat" if _move_forecast_retreat else &"move", [_move_forecast_cell], _move_forecast_generation): return
	# Синхронный fallback сохраняет подготовку на владельце для прочих session.
	var prepared := (session as BattleCoreReactionsSession).prepare_retreat_forecast(_move_forecast_cell) if _move_forecast_retreat and session is BattleCoreReactionsSession else session.prepare_move_forecast(_move_forecast_cell)
	_move_forecast_worker.start(prepared)

func _move_forecast_request_current() -> bool:
	if board_view == null: return false
	var over_panel := board_view.hover_cell.x < 0 and _forecast_reading_region().has_point(_pointer_position)
	return session != null and session.context != null and (board_view.hover_cell == _move_forecast_cell or over_panel) and session.selected_id == _move_forecast_actor and session.context.get_revision() == _move_forecast_revision and retreat_mode == _move_forecast_retreat and not attack_mode and not summoning_mode and not raising_mode and inspected_id == UnitId.NONE and (_battle == null or _battle.can_player_act())

func _board_forecast_wheel_input(event: InputEvent) -> bool:
	if is_execution_pending(): return false
	if not event is InputEventMouseButton: return false
	var wheel := event as InputEventMouseButton
	if not wheel.pressed or (wheel.button_index != MOUSE_BUTTON_WHEEL_UP and wheel.button_index != MOUSE_BUTTON_WHEEL_DOWN): return false
	if not _forecast_panel.is_visible_in_tree() or (_battle != null and not _battle.can_player_act()): return false
	var target_cell := _forecast_cell if _forecast != null and attack_mode else _move_forecast_cell
	if _raise_forecast != null and raising_mode: target_cell = _raise_forecast_cell
	if (_forecast == null or not attack_mode) and _move_forecast == null and _raise_forecast == null: return false
	if board_view.cell_at(wheel.position) != target_cell: return false
	var amount := 48.0 * (wheel.factor if wheel.factor > 0.0 else 1.0)
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP: amount = -amount
	var scroll_bar := _forecast_panel.get_v_scroll_bar()
	var last_value := maxf(scroll_bar.min_value, scroll_bar.max_value - scroll_bar.page)
	scroll_bar.value = clampf(scroll_bar.value + amount, scroll_bar.min_value, last_value)
	accept_event()
	return true

func _leave_forecast_panel() -> void:
	if is_execution_pending(): return
	_resolve_hover_exit.call_deferred()

func _resolve_hover_exit() -> void:
	if is_execution_pending(): return
	if _environment_forecast != null or _environment_forecast_pending:
		if _over_environment_button() or _forecast_reading_region().has_point(_pointer_position): return
		_clear_forecast()
		_refresh_inspection()
		return
	if _turn_forecast != null or _turn_forecast_pending:
		if _over_end_turn_button() or _forecast_reading_region().has_point(_pointer_position): return
		_clear_forecast()
		_refresh_inspection()
		return
	if session == null or board_view.hover_cell.x >= 0 or (_forecast == null and not _attack_forecast_pending and not _action_forecast_pending and _item_forecast == null and _move_forecast == null and _raise_forecast == null and _guard_forecast == null and _armor_forecast == null and _elemental_forecast == null): return
	if _item_forecast_kind == &"healing" and _hovered_bar_action == &"healing_item": return
	if (_armor_forecast != null or (_action_forecast_pending and _action_forecast_kind == &"armor")) and _hovered_bar_action == &"restore_armor": return
	if (_guard_forecast != null or (_action_forecast_pending and _action_forecast_kind in [&"guard", &"opportunity", &"counterattack", &"raise_shields"])) and _hovered_bar_action in [&"guard", &"opportunity_guard", &"counterattack_guard", &"raise_shields"]: return
	if _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_refresh_inspection()

func _forecast_reading_region() -> Rect2:
	if not _forecast_panel.is_visible_in_tree(): return Rect2()
	var panel := _forecast_panel.get_global_rect()
	# Узкий зазор между полем и панелью не должен прерывать переход курсора.
	var left := minf(board_view.get_global_rect().end.x, panel.position.x)
	return Rect2(Vector2(left, panel.position.y), Vector2(panel.end.x - left, panel.size.y))

func _clear_forecast() -> void:
	if _forecast_preparation_worker.is_started():
		_forecast_preparation_discard = true
		return
	if is_execution_pending(): return
	_environment_forecast_generation += 1
	_environment_forecast_pending = false
	_environment_forecast = null
	_turn_forecast_generation += 1
	_turn_forecast_pending = false
	_turn_forecast = null
	_turn_forecast_session_id = 0
	_turn_forecast_actor = UnitId.NONE
	_turn_forecast_revision = -1
	_action_forecast_generation += 1
	_action_forecast_pending = false
	_action_forecast_kind = &""
	_action_forecast_session_id = 0
	_action_forecast_target_id = UnitId.NONE
	_action_forecast_effect = &""
	_action_forecast_card_id = 0
	_action_forecast_cache.clear()
	_action_forecast_freshness = null
	_mage_display_freshness = null
	_action_freshness_expected = false
	var had_forecast := _forecast != null or _attack_forecast_pending or _move_forecast != null or _move_forecast_pending
	_attack_forecast_generation += 1
	_attack_forecast_pending = false
	_attack_forecast_actor = UnitId.NONE
	_attack_forecast_variant = &""
	_move_forecast_generation += 1
	_move_forecast_pending = false
	_forecast = null
	_move_forecast = null
	_move_forecast_cell = Vector2i(-1, -1)
	_move_forecast_actor = UnitId.NONE
	_move_forecast_revision = -1
	_item_forecast = null
	_item_forecast_kind = &""
	_item_forecast_cell = Vector2i(-1, -1)
	_item_forecast_revision = -1
	_raise_forecast = null
	_raise_forecast_cell = Vector2i(-1, -1)
	_raise_forecast_actor = UnitId.NONE
	_raise_forecast_revision = -1
	_armor_forecast = null
	_elemental_forecast = null
	_armor_forecast_actor = UnitId.NONE
	_armor_forecast_revision = -1
	_guard_forecast = null
	_guard_forecast_actor = UnitId.NONE
	_guard_forecast_revision = -1
	_guard_forecast_mode = 0
	_guard_forecast_target = 0
	_forecast_cell = Vector2i(-1, -1)
	_forecast_target_id = UnitId.NONE
	_forecast_revision = -1
	if board_view != null:
		board_view.compact_forecast.publish({}, Vector2i(-1, -1), board_view)
		board_view.forecast = null
		board_view.move_forecast = null
		board_view.move_forecast_pending = false
		board_view.pending_move_path.clear()
		board_view.sneak_threat_ids.clear()
		if had_forecast and board_view.session != null: board_view.refresh_forecast()
	if _forecast_panel != null:
		_forecast_panel.text = "Наведите курсор на врага в режиме A."
		_forecast_panel.visible = attack_mode
		_forecast_heading.visible = attack_mode
		_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ"
	if _log != null: _log.visible = not attack_mode
	if _log_heading != null: _log_heading.visible = not attack_mode

func _render_forecast_panel() -> void:
	BattleCompactForecastPresenter.publish(self)
	if is_execution_pending(): return
	if _forecast_panel == null: return
	if _environment_forecast_pending or _environment_forecast != null:
		_render_environment_forecast()
		return
	if _turn_forecast_pending or _turn_forecast != null:
		_render_turn_forecast()
		return
	if _action_forecast_pending:
		_forecast_panel.visible = true
		_forecast_heading.visible = true
		_forecast_heading.text = "ПРОГНОЗ ДЕЙСТВИЯ"
		_log.visible = false
		_log_heading.visible = false
		_forecast_panel.text = "Рассчитываем последствия для %s…" % _name_for(_action_forecast_target_id) if _action_forecast_kind == &"elemental" else "Рассчитываем последствия действия…"
		return
	if _armor_forecast != null:
		_render_armor_forecast_panel()
		return
	if _elemental_forecast != null:
		_render_elemental_forecast_panel()
		return
	if _guard_forecast != null:
		if _guard_forecast_mode in [CombatPerksState.Mode.OPPORTUNIST, CombatPerksState.Mode.COVER, CombatPerksState.Mode.COUNTERATTACK]: _render_reaction_guard_forecast()
		else: _render_guard_forecast_panel()
		return
	if _raise_forecast != null:
		_render_raise_forecast_panel()
		return
	if _move_forecast != null or _move_forecast_pending:
		_render_move_forecast_panel()
		return
	if _item_forecast != null:
		_render_item_forecast_panel()
		return
	if _attack_forecast_pending:
		_forecast_panel.text = "[font_size=16][color=#f7c97d]%s → %s[/color][/font_size]\nРассчитываем последствия удара…" % [_name_for(_attack_forecast_actor), _name_for(_forecast_target_id)]
		return
	if _forecast == null:
		_forecast_panel.text = "Наведите курсор на врага в режиме A."
		return
	var actor_name := _name_for(_attack_forecast_actor)
	var target_name := _name_for(_forecast_target_id)
	var event_lines: PackedStringArray = []
	var names: Dictionary[int, String] = {}
	if _forecast.status == ActionReceipt.APPLIED:
		for id_variant in _forecast.units:
			var id := int(id_variant)
			names[id] = _name_for(id)
		for event: Dictionary in _forecast.events:
			if event.get("kind") == &"chain_link":
				var id := int(event.target_unit_id)
				names[id] = _name_for(id)
			if event.get("kind") == &"hit_resolved":
				var id := int(event.target_unit_id)
				names[id] = _name_for(id)
			if event.get("kind") == &"attacked":
				var modifiers: Dictionary = event.get("modifiers", {})
				for ally_id: int in modifiers.get("surround_ally_ids", []): names[ally_id] = _name_for(ally_id)
				if modifiers.has("sneak_percent") and modifiers["sneak_percent"] == 50:
					for threat_id: int in modifiers.get("threat_ids", []): names[threat_id] = _name_for(threat_id)
			event_lines.append(_event_text(event))
	_forecast_panel.text = BattleForecastText.attack(
		_forecast, actor_name, target_name,
		_forecast_target_id, names, event_lines, session is BattleCoreReactionsSession,
		tactical_mode
	)

func _sync_sneak_threat_highlight() -> void:
	if is_execution_pending(): return
	if board_view == null: return
	board_view.sneak_threat_ids.clear()
	if _forecast == null: return
	for event: Dictionary in _forecast.events:
		if event.get("kind") != &"attacked": continue
		var modifiers: Dictionary = event.get("modifiers", {})
		for raw_id: Variant in modifiers.get("threat_ids", []):
			if typeof(raw_id) == TYPE_INT and not board_view.sneak_threat_ids.has(raw_id): board_view.sneak_threat_ids.append(raw_id)

func _control_skip_text(reason: StringName) -> String:
	return BattleForecastText.control_skip_text(reason)

func _render_move_forecast_panel() -> void:
	BattleCompactForecastPresenter.publish(self)
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	var event_lines: PackedStringArray = []
	var names: Dictionary[int, String] = {}
	if not _move_forecast_pending and _move_forecast.status in [ActionReceipt.APPLIED, ActionReceipt.INTERRUPTED]:
		for id: int in _move_forecast.units:
			var row: Dictionary = _move_forecast.units[id]
			if id == _move_forecast.actor_id or row["before"] != row["after"]: names[id] = _name_for(id)
		for event: Dictionary in _move_forecast.events: event_lines.append(_event_text(event))
	var has_pending_path := not board_view.pending_move_path.is_empty() if _move_forecast_pending else false
	_forecast_panel.text = BattleForecastText.move(
		_move_forecast, _move_forecast_cell, _move_forecast_retreat,
		_move_forecast_pending, has_pending_path, names, event_lines, tactical_mode
	)

func _action_bar_hovered(action_id: StringName) -> void:
	if is_execution_pending(): return
	var previous := _hovered_bar_action
	_hovered_bar_action = action_id
	_update_area_preview()
	if previous == &"healing_item" and action_id != &"healing_item": _resolve_item_hover_exit.call_deferred()
	if previous == &"guard" and action_id != &"guard": _resolve_guard_hover_exit.call_deferred()
	if previous in [&"opportunity_guard", &"counterattack_guard", &"raise_shields"] and action_id != previous: _resolve_guard_hover_exit.call_deferred()
	if previous == &"restore_armor" and action_id != &"restore_armor": _resolve_armor_hover_exit.call_deferred()
	if action_id == &"raise_shields":
		if _battle == null or not _battle.can_player_act(): return
		var revision := session.context.get_revision()
		if (_guard_forecast != null or _action_forecast_pending) and _action_forecast_kind == &"raise_shields" and _guard_forecast_actor == session.selected_id and _guard_forecast_revision == revision: return
		_clear_forecast()
		_guard_forecast_actor = session.selected_id
		_guard_forecast_revision = revision
		_request_action_forecast(&"raise_shields")
		return
	if action_id == &"opportunity_guard":
		if not session is BattleCoreReactionsSession or not _battle.can_player_act(): return
		var revision := session.context.get_revision()
		if (_guard_forecast != null or _action_forecast_pending) and _guard_forecast_actor == session.selected_id and _guard_forecast_revision == revision and _guard_forecast_mode == CombatPerksState.Mode.OPPORTUNIST: return
		_clear_forecast()
		_guard_forecast_actor = session.selected_id
		_guard_forecast_revision = revision
		_guard_forecast_mode = CombatPerksState.Mode.OPPORTUNIST
		_guard_forecast_target = 0
		_request_action_forecast(&"opportunity")
		return
	if action_id == &"counterattack_guard":
		if not session is BattleCoreReactionsSession or not _battle.can_player_act(): return
		var counter_revision := session.context.get_revision()
		if (_guard_forecast != null or _action_forecast_pending) and _guard_forecast_actor == session.selected_id and _guard_forecast_revision == counter_revision and _guard_forecast_mode == CombatPerksState.Mode.COUNTERATTACK: return
		_clear_forecast()
		_guard_forecast_actor = session.selected_id
		_guard_forecast_revision = counter_revision
		_guard_forecast_mode = CombatPerksState.Mode.COUNTERATTACK
		_guard_forecast_target = 0
		_request_action_forecast(&"counterattack")
		return
	if action_id == &"restore_armor":
		if not session is BattleArmorSession or not _battle.can_player_act(): return
		var current_revision := session.context.get_revision()
		if (_armor_forecast != null or _action_forecast_pending) and _armor_forecast_actor == session.selected_id and _armor_forecast_revision == current_revision: return
		_clear_forecast()
		_armor_forecast_actor = session.selected_id
		_armor_forecast_revision = current_revision
		_forecast_panel.get_v_scroll_bar().value = 0.0
		_request_action_forecast(&"armor")
		return
	if action_id == &"guard":
		if _battle == null or not _battle.can_player_act(): return
		var revision := session.context.get_revision()
		if (_guard_forecast != null or _action_forecast_pending) and _guard_forecast_actor == session.selected_id and _guard_forecast_revision == revision and _guard_forecast_mode == CombatPerksState.Mode.NONE and _action_forecast_kind == &"guard": return
		_clear_forecast()
		_guard_forecast_actor = session.selected_id
		_guard_forecast_revision = revision
		_forecast_panel.get_v_scroll_bar().value = 0.0
		_request_action_forecast(&"guard")
		_refresh_inspection()
		return
	if action_id != &"healing_item" or _battle == null: return
	var revision := session.context.get_revision()
	if _item_forecast_kind == &"healing" and _item_forecast_revision == revision: return
	_clear_forecast()
	_item_forecast_kind = &"healing"
	_item_forecast_revision = revision
	_forecast_panel.get_v_scroll_bar().value = 0.0
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_request_action_forecast(&"healing")

func _action_bar_hover_left(action_id: StringName) -> void:
	if is_execution_pending(): return
	if _hovered_bar_action == action_id: _hovered_bar_action = &""
	_update_area_preview()
	if action_id == &"restore_armor": _resolve_armor_hover_exit.call_deferred()
	if action_id in [&"guard", &"opportunity_guard", &"counterattack_guard", &"raise_shields"]: _resolve_guard_hover_exit.call_deferred()
	if action_id != &"healing_item" or _item_forecast_kind != &"healing": return
	_resolve_item_hover_exit.call_deferred()

func _update_area_preview() -> void:
	if board_view == null or is_execution_pending(): return
	board_view.area_preview_owner = UnitId.NONE
	if not session is BattleCoreReactionsSession: return
	var show_area := attack_mode
	for button: Button in _action_bar._buttons:
		if button.get_meta("action_id", &"") == _hovered_bar_action and not button.disabled and _hovered_bar_action in [&"attack", &"opportunity_guard", &"counterattack_guard", &"stunning_strike", &"entangling_strike", &"blood_rune", WarriorKit.CLEAVE, WarriorKit.KICK]: show_area = true
	if show_area: board_view.area_preview_owner = session.selected_id
	if board_view._overlay != null: board_view._overlay.queue_redraw()

func _update_action_bar_hover() -> void:
	if is_execution_pending(): return
	if _action_bar == null or not _action_bar.visible: return
	var action_id: StringName = &""
	if _action_bar.get_global_rect().has_point(_pointer_position):
		for button in _action_bar._buttons:
			if button.visible and button.get_global_rect().has_point(_pointer_position):
				action_id = StringName(button.get_meta("action_id", &""))
				break
	if action_id == _hovered_bar_action:
		if (action_id in [&"guard", &"opportunity_guard", &"counterattack_guard", &"raise_shields"] and (_guard_forecast != null or _action_forecast_pending)) or (action_id == &"restore_armor" and (_armor_forecast != null or _action_forecast_pending)) or (action_id == &"healing_item" and (_item_forecast != null or _action_forecast_pending)): _action_bar_hovered(action_id)
		return
	var previous := _hovered_bar_action
	_hovered_bar_action = action_id
	_update_area_preview()
	if previous in [&"healing_item", &"guard", &"opportunity_guard", &"counterattack_guard", &"raise_shields", &"restore_armor"]: _action_bar_hover_left(previous)
	if action_id in [&"healing_item", &"guard", &"opportunity_guard", &"counterattack_guard", &"raise_shields", &"restore_armor"]: _action_bar_hovered(action_id)

func _resolve_guard_hover_exit() -> void:
	if is_execution_pending(): return
	if session == null or (_guard_forecast == null and not (_action_forecast_pending and _action_forecast_kind in [&"guard", &"opportunity", &"counterattack", &"raise_shields"])): return
	if _hovered_bar_action in [&"guard", &"opportunity_guard", &"counterattack_guard", &"raise_shields"] or _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_refresh_inspection()

func _render_guard_forecast_panel() -> void:
	BattleCompactForecastPresenter.publish(self)
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ПАНЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	_forecast_panel.text = BattleForecastText.guard(_guard_forecast, _name_for(_guard_forecast_actor), _action_forecast_kind, tactical_mode)

func _render_reaction_guard_forecast() -> void:
	BattleCompactForecastPresenter.publish(self)
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · РЕАКЦИЯ"
	_log.visible = false
	_log_heading.visible = false
	var actor_name := _name_for(_guard_forecast_actor)
	var target_name := _name_for(_guard_forecast_target) if _guard_forecast_mode == CombatPerksState.Mode.COVER else ""
	_forecast_panel.text = BattleForecastText.reaction_guard(
		_guard_forecast, _guard_forecast_actor, actor_name,
		target_name, _guard_forecast_mode, tactical_mode
	)

func _resolve_item_hover_exit() -> void:
	if is_execution_pending(): return
	if (_item_forecast == null and not _action_forecast_pending) or _item_forecast_kind != &"healing": return
	if _hovered_bar_action == &"healing_item": return
	if _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_forecast_panel.visible = attack_mode
	_forecast_heading.visible = attack_mode

func _render_item_forecast_panel() -> void:
	BattleCompactForecastPresenter.publish(self)
	if is_execution_pending(): return
	if _forecast_panel == null or _item_forecast == null: return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ПАНЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	_forecast_panel.text = BattleForecastText.item(_item_forecast, _item_forecast_kind, _item_forecast_cell, _item_cost_text(_item_action_for_forecast()), tactical_mode)

func _render_raise_forecast_panel() -> void:
	BattleCompactForecastPresenter.publish(self)
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ЦЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	_forecast_panel.text = BattleForecastText.raise_corpse(_raise_forecast, _raise_forecast_cell, tactical_mode)

func _item_action_for_forecast() -> ItemUseAction:
	if _battle == null: return null
	var item := _battle.healing_item() if _item_forecast_kind == &"healing" else _battle.summoning_item()
	return item.get_use_action() if item != null else null

func _show_receipt(receipt: ActionReceipt, target_attempt: bool = false) -> void:
	if is_execution_pending(): return
	# Завершённое применение и отказ по выбранной цели возвращают движение.
	# UI не зависит от того, основное или дополнительное действие оплатила команда.
	if target_attempt or receipt.status != ActionReceipt.REJECTED:
		_clear_action_mode()
	_clear_forecast()
	if not _receipt_already_presented:
		for event in receipt.get_events(): _note(_event_text(event))
	for step: Dictionary in receipt.get_steps():
		if step["status"] == &"SKIPPED" and step["kind"] in [&"stun_apply", &"entangle_apply"]:
			_note(("Оглушение" if step["kind"] == &"stun_apply" else "Путы") + ": наложение пропущено — " + _control_skip_text(step["reason"]) + ".")
	_refresh()
	# Смерть уже исполнена ядром; временная фигура лишь показывает падение в провал.
	for event in receipt.get_events():
		if _receipt_already_presented: break
		if event.get("kind", &"") != &"died": continue
		var source: Dictionary = event.get("source", {})
		if source.get("kind", &"") != &"fall": continue
		var unit := session.board.get_unit_by_id(int(event.get("target_unit_id", 0)))
		if unit == null: continue
		var destination: Vector2i = source.get("origin_cell", unit.cell)
		if session.board.is_in_bounds(destination) and session.board.get_terrain(destination) != TerrainType.Type.VOID: continue
		var origin := unit.cell
		for movement in receipt.get_events():
			if movement.get("kind", &"") == &"moved" and int(movement.get("target_unit_id", 0)) == unit.id:
				origin = movement["from_cell"]
		board_view.animate_fall(unit, origin, destination)
	if receipt.status != ActionReceipt.APPLIED:
		var message := "Действие отклонено" if receipt.status == ActionReceipt.REJECTED else "Исполнение остановлено"
		message += ": "
		if target_attempt and receipt.status == ActionReceipt.REJECTED: message += "недопустимая цель. "
		message += _reason_text(receipt.reason)
		_note(message)
		_log.text = "\n".join(_journal)
		_status.text = message
		if not _refresh_followup.is_empty(): _refresh_followup.receipt_message = message

func _note(message: String) -> void:
	_journal.append(message)
	while _journal.size() > 80: _journal.pop_front()

func _event_text(event: Dictionary) -> String:
	var names: Dictionary[int, String] = {}
	# Имена читаются из текущей доски только для полей, участвующих в строке события.
	for id: int in [int(event.get("actor_unit_id", 0)), int(event.get("target_unit_id", 0))]:
		names[id] = _name_for(id)
	var kind: StringName = StringName(event.get("kind", &""))
	if kind in [&"attacked", &"opportunity_attacked", &"counterattacked", &"elemental_cast"]:
		var modifiers: Dictionary = event.get("modifiers", {})
		for ally_id: int in modifiers.get("surround_ally_ids", []): names[ally_id] = _name_for(ally_id)
		var threat_ids: Variant = modifiers.get("threat_ids", [])
		if int(modifiers.get("sneak_percent", 0)) == 50 and typeof(threat_ids) == TYPE_ARRAY:
			for id: Variant in threat_ids:
				if typeof(id) != TYPE_INT: continue
				names[id] = _name_for(id)
	elif kind == &"guarded" and event.has("reaction_mode") and int(event["reaction_mode"]) == CombatPerksState.Mode.COVER:
		var cover_id := int(event.get("cover_target_id", 0))
		names[cover_id] = _name_for(cover_id)
	elif kind == &"mage_summoned" and int(event.owner_unit_id) != 0:
		var owner_id := int(event.owner_unit_id)
		names[owner_id] = _name_for(owner_id)
	elif kind == &"chain_link":
		var from_id := int(event.get("from_unit_id", 0))
		names[from_id] = _name_for(from_id)
	elif kind == &"collision":
		var blocker_id := int(event.get("blocker_unit_id", 0))
		names[blocker_id] = _name_for(blocker_id)
	var item_label := "флакон"
	if kind == &"item_used":
		var owner := session.state.get_owner(int(event["actor_unit_id"]))
		var item: ItemInstance = owner._items.get(int(event["item_instance_id"])) if owner != null else null
		var action := item.get_use_action() if item != null else null
		item_label = "печать" if action != null and action.get_kind() == ItemUseAction.Kind.SUMMON_ADJACENT else "флакон"
	return BattleEventText.format_event(event, names, session is BattleCoreReactionsSession, bleeding_mode, item_label)

func _name_for(id: int) -> String:
	var unit := session.board.get_unit_by_id(id)
	return unit.debug_name if unit != null else "Окружение"

func _cell_name(cell: Vector2i) -> String:
	return BattleEventText.cell_name(cell)
func _reason_text(reason: StringName) -> String:
	return BattleForecastText.reason_text(reason, tactical_mode)

func _unhandled_input(event: InputEvent) -> void:
	if is_execution_pending() and not (_forecast_preparation_worker.is_started() or _forecast_preparation_recovering or _interactive_refresh_pending):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R: reset_demo()
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE: skip_presentation()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
				if tactical_mode and _action_bar != null:
					var slot := int(event.keycode - KEY_0)
					if slot > _action_bar._buttons.size(): return
					if slot == 1: set_attack_mode(true)
					elif slot == 2: _use_guard()
					elif _action_bar._buttons[slot - 1].get_meta("action_id", &"") == &"summoning_item": _choose_summoning()
					elif _action_bar._buttons[slot - 1].get_meta("action_id", &"") == &"healing_item": _use_healing_item()
					elif _action_bar._buttons[slot - 1].get_meta("action_id", &"") == &"raise_corpse": _choose_raise()
					else: _action_bar.activate_slot(slot)
			KEY_A: set_attack_mode(true)
			KEY_M, KEY_ESCAPE: set_attack_mode(false)
			KEY_R: reset_demo()
			KEY_ENTER, KEY_KP_ENTER: end_turn()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and (board_view == null or not board_view.camera_controls_enabled):
		set_attack_mode(false)

func _item_cost_text(action: ItemUseAction) -> String:
	return BattleInspectionText.item_cost_text(action)

func _item_action_descriptor(item: ItemInstance, action_id: StringName, reason: StringName) -> Dictionary:
	return BattleActionDescriptors.item(item, action_id, reason, _reason_text)

func _summon_hp_text(item: ItemInstance) -> String:
	return BattleInspectionText.summon_hp_text(item)

func _choose_summoning() -> void:
	if _defer_forecast_intent(&"_choose_summoning", []): return
	if is_execution_pending(): return
	if _battle == null: return
	var reason := _battle.summoning_hint_reason()
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	summoning_mode = true
	_refresh()

func _choose_raise() -> void:
	if _defer_forecast_intent(&"_choose_raise", []): return
	if is_execution_pending(): return
	if not environment_mode or not session is BattleEnvironmentSession: return
	var environment := session as BattleEnvironmentSession
	var reason := environment.raise_hint_reason()
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	raising_mode = true
	_refresh()

func _choose_retreat() -> void:
	if _defer_forecast_intent(&"_choose_retreat", []): return
	if is_execution_pending() or not session is BattleCoreReactionsSession: return
	var reason := (session as BattleCoreReactionsSession).retreat_reason()
	if reason != &"":
		_status.text = _reason_text(reason)
		return
	_clear_action_mode()
	retreat_mode = true
	_refresh()

func _resolve_armor_hover_exit() -> void:
	if is_execution_pending(): return
	if (_armor_forecast == null and not (_action_forecast_pending and _action_forecast_kind == &"armor")) or _hovered_bar_action == &"restore_armor" or _forecast_reading_region().has_point(_pointer_position): return
	_clear_forecast()
	_refresh_inspection()

func _render_armor_forecast_panel() -> void:
	BattleCompactForecastPresenter.publish(self)
	if is_execution_pending(): return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОЛЕСО НА ПАНЕЛИ"
	_log.visible = false
	_log_heading.visible = false
	_forecast_panel.text = BattleForecastText.armor(_armor_forecast, _armor_forecast_actor, _name_for(_armor_forecast_actor), tactical_mode)

func _render_elemental_forecast_panel() -> void:
	BattleCompactForecastPresenter.publish(self)
	if is_execution_pending() or _elemental_forecast == null: return
	if _action_forecast_kind == &"mage_card":
		_render_card_forecast_panel()
		return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · ЭЛЕМЕНТАЛЬНЫЙ ЭФФЕКТ"
	_log.visible = false
	_log_heading.visible = false
	var target_name := _name_for(_action_forecast_target_id)
	var event_lines: PackedStringArray = []
	var mana: BattleForecastText.ManaTextValues = null
	if _elemental_forecast.status == ActionReceipt.APPLIED:
		# Повреждённый откат останавливает вывод до строк событий.
		if AbilityDefinition.mage_source_id(_action_forecast_effect) > 0:
			mana = BattleForecastText.spell_mana_values(_elemental_forecast, _action_forecast_effect)
		if mana == null or mana.valid:
			for event: Dictionary in _elemental_forecast.events: event_lines.append(_event_text(event))
	_forecast_panel.text = BattleForecastText.elemental(
		_elemental_forecast, _action_forecast_effect, _action_forecast_target_id,
		_action_forecast_actor, _action_forecast_cell, target_name,
		mana, event_lines, tactical_mode
	)

func _render_card_forecast_panel() -> void:
	var definition := MageCardCatalog.get_card(String(_action_forecast_effect))
	if definition == null: return
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КАРТА МАГА"
	_log.visible = false
	_log_heading.visible = false
	var target_text: String
	if definition.target_policy in ["valid_cell", "corpse_cell"]:
		target_text = _cell_name(_action_forecast_cell)
	else:
		target_text = _name_for(_action_forecast_target_id)
	var event_lines: PackedStringArray = []
	var mana: BattleForecastText.ManaTextValues = null
	if _elemental_forecast.status == ActionReceipt.APPLIED:
		mana = BattleForecastText.card_mana_values(_elemental_forecast)
		if mana.valid:
			for event: Dictionary in _elemental_forecast.events: event_lines.append(_event_text(event))
	_forecast_panel.text = BattleForecastText.card(
		_elemental_forecast, definition.name, target_text, _action_forecast_card_id,
		mana, event_lines, tactical_mode
	)

func _elemental_effect_label(effect: StringName) -> String:
	return BattleEventText.elemental_effect_label(effect)

func _elemental_summary(value: Variant) -> String:
	return BattleEventText.elemental_summary(value)

func _bleeding_skip_text(reason: StringName) -> String:
	return BattleForecastText.bleeding_skip_text(reason)

func _bleeding_summary(value: Variant) -> String:
	return BattleEventText.bleeding_summary(value)

func _can_forecast_turn() -> bool:
	return not is_execution_pending() and session != null and session.get_script() == BattleCoreReactionsSession and _battle != null and _battle.can_player_act() and not _is_deploying()

func _can_forecast_environment() -> bool:
	return _can_forecast_turn() and not session.state.environment.collapse.is_empty()

func _over_environment_button() -> bool:
	return _environment_button != null and _environment_button.is_visible_in_tree() and _environment_button.get_global_rect().has_point(_pointer_position)

func _update_environment_forecast_hover() -> void:
	if _over_environment_button() and _can_forecast_environment():
		if _environment_forecast == null and not _environment_forecast_pending: _request_environment_forecast()
	elif (_environment_forecast != null or _environment_forecast_pending) and not _forecast_reading_region().has_point(_pointer_position):
		_clear_forecast()

func _request_environment_forecast() -> void:
	if not _can_forecast_environment(): return
	_clear_forecast()
	_environment_forecast_pending = true
	_environment_forecast_session = session.get_instance_id()
	_environment_forecast_revision = session.context.get_revision()
	_environment_forecast_actor = session.selected_id
	_forecast_panel.get_v_scroll_bar().value = 0.0
	_render_forecast_panel()

func _environment_request_current() -> bool:
	return _can_forecast_environment() and session.get_instance_id() == _environment_forecast_session and session.context.get_revision() == _environment_forecast_revision and session.selected_id == _environment_forecast_actor and (_over_environment_button() or _forecast_reading_region().has_point(_pointer_position))

func _process_environment_forecast() -> void:
	if is_execution_pending(): return
	var result := _environment_forecast_worker.take_finished()
	if (_environment_forecast_pending or _environment_forecast != null) and not _environment_request_current():
		_clear_forecast()
		return
	if result != null and _environment_forecast_pending and _environment_forecast_job == _environment_forecast_generation:
		_environment_forecast = result
		_environment_forecast_pending = false
		_render_forecast_panel()
	if not _environment_forecast_pending or _environment_forecast_worker.is_started(): return
	_environment_forecast_job = _environment_forecast_generation
	if _start_forecast_preparation(&"environment", &"environment", [], _environment_forecast_generation): return
	_environment_forecast_worker.start((session as BattleCoreReactionsSession).prepare_environment_forecast())

func _render_environment_forecast() -> void:
	BattleCompactForecastPresenter.publish(self)
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · ОКРУЖЕНИЕ"
	_log.visible = false
	_log_heading.visible = false
	var event_lines: PackedStringArray = []
	var names: Dictionary[int, String] = {}
	if not _environment_forecast_pending and _environment_forecast.status == ActionReceipt.APPLIED:
		for event: Dictionary in _environment_forecast.events: event_lines.append(_event_text(event))
		for id: int in _environment_forecast.units_after:
			if _environment_forecast.units_before[id].alive and not _environment_forecast.units_after[id].alive: names[id] = _name_for(id)
	_forecast_panel.text = BattleForecastText.environment(_environment_forecast, _environment_forecast_pending, names, event_lines, tactical_mode)

func _over_end_turn_button() -> bool:
	return _end_turn_button != null and _end_turn_button.is_visible_in_tree() and _end_turn_button.get_global_rect().has_point(_pointer_position)

func _update_turn_forecast_hover() -> void:
	if _over_end_turn_button() and _can_forecast_turn():
		if _turn_forecast == null and not _turn_forecast_pending: _request_turn_forecast()
	elif (_turn_forecast != null or _turn_forecast_pending) and not _forecast_reading_region().has_point(_pointer_position):
		_clear_forecast()

func _request_turn_forecast() -> void:
	if not _can_forecast_turn(): return
	_clear_forecast()
	_turn_forecast_pending = true
	_turn_forecast_session_id = session.get_instance_id()
	_turn_forecast_actor = session.selected_id
	_turn_forecast_revision = session.context.get_revision()
	_forecast_panel.get_v_scroll_bar().value = 0.0
	_render_forecast_panel()

func _turn_forecast_request_current() -> bool:
	if not _can_forecast_turn(): return false
	if session.get_instance_id() != _turn_forecast_session_id or session.selected_id != _turn_forecast_actor or session.context.get_revision() != _turn_forecast_revision: return false
	return _over_end_turn_button() or _forecast_reading_region().has_point(_pointer_position)

func _process_turn_forecast() -> void:
	if is_execution_pending(): return
	var result := _turn_forecast_worker.take_finished()
	if (_turn_forecast_pending or _turn_forecast != null) and not _turn_forecast_request_current():
		_clear_forecast()
		return
	if result != null and _turn_forecast_pending and _turn_forecast_job_generation == _turn_forecast_generation:
		_turn_forecast = result
		_turn_forecast_pending = false
		_render_forecast_panel()
	if not _turn_forecast_pending or _turn_forecast_worker.is_started(): return
	# Подготовка отделяет runtime на кадре; обработчик мыши только записывает запрос.
	_turn_forecast_job_generation = _turn_forecast_generation
	if _start_forecast_preparation(&"turn", &"turn", [], _turn_forecast_generation): return
	_turn_forecast_worker.start(TurnForecast.prepare(session as BattleCoreReactionsSession))

func _render_turn_forecast() -> void:
	BattleCompactForecastPresenter.publish(self)
	_forecast_panel.visible = true
	_forecast_heading.visible = true
	_forecast_heading.text = "ПРОГНОЗ · КОНЕЦ ХОДА"
	_log.visible = false
	_log_heading.visible = false
	var event_lines: PackedStringArray = []
	var names: Dictionary[int, String] = {}
	if not _turn_forecast_pending and _turn_forecast.status == ActionReceipt.APPLIED:
		for event: Dictionary in _turn_forecast.events:
			if event.get("kind", &"") in [&"environment_turn", &"support_collapsed"]: event_lines.append(_event_text(event))
		for id: int in _turn_forecast.units_before: names[id] = _name_for(id)
	_forecast_panel.text = BattleForecastText.turn(_turn_forecast, _turn_forecast_pending, names, event_lines, tactical_mode)
