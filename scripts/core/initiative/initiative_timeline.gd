extends RefCounted
class_name InitiativeTimeline

## Очередь ходов: хранит участников боя и текущую `TurnOrderStrategy`,
## пересчитывает порядок по запросу.
##
## НЕ управляет фазами боя (PlayerTurn/EnemyTurn/...) — это задача Battle Flow
## State Machine (шаг 0.6). Здесь только порядок и очередь. (Сохранено.)
##
## ЧТО ИСПРАВЛЕНО:
##
## 1. ДЕФЕКТ D-4.6 — смерть посреди раунда ПЕРЕЗАПУСКАЛА раунд.
##    Раньше курсор хранился как `_current_index: int`, а
##    `unregister_participant()` вызывал `recompute_order()`, который сбрасывал
##    `_current_index = -1`. То есть при смерти любого юнита все, кто уже
##    отходил в этом раунде, получали ход СНОВА. Баг не проявлялся только
##    потому, что смерти как понятия не существовало (C-2) и никто никогда не
##    вызывал `unregister_participant()`.
##    Теперь курсор — это `_current_unit_id` (стабильный идентификатор), а
##    удаление участника ПЕРЕСТРАИВАЕТ список, сохраняя позицию курсора.
##
## 2. ДЕФЕКТ D-4.7 — не было границ раунда. `advance_turn()` молча оборачивался
##    через `%` и начинал новый раунд. Без явных `round_started`/`round_ended`
##    tick-based Status Engine (шаг 0.10) нереализуем: статусам вида "горит 3
##    раунда" нечем тикать.
##
## 3. Мёртвые юниты автоматически пропускаются при выдаче хода — раньше
##    очередь выдала бы ход трупу.
##
## Начался новый раунд (все живые участники отходили по разу).
signal round_started(round_number: int)

## Раунд завершён — эмитится ПЕРЕД `round_started` следующего раунда.
signal round_ended(round_number: int)

## Ход передан юниту.
signal turn_started(unit: UnitState)

var _strategy: TurnOrderStrategy
var _participants: Array[UnitState] = []
var _current_order: Array[UnitState] = []

## Курсор по стабильному идентификатору, а НЕ по индексу массива (см. D-4.6).
var _current_unit_id: int = UnitId.NONE

## Номер текущего раунда, начиная с 1. 0 = бой ещё не начат.
var _round_number: int = 0


func set_strategy(strategy: TurnOrderStrategy) -> void:
	_strategy = strategy


func get_round_number() -> int:
	return _round_number


# --- Участники -------------------------------------------------------------

func register_participant(unit: UnitState) -> void:
	if unit == null or _participants.has(unit):
		return
	_participants.append(unit)
	_rebuild_order_preserving_cursor()


## Удаляет участника (смерть, отступление). Позиция курсора СОХРАНЯЕТСЯ:
## раунд не перезапускается, и уже отходившие юниты не получают ход снова.
##
## Особый случай — удаляется ТОТ САМЫЙ юнит, чей сейчас ход. Тогда курсор
## некуда указывать, и если просто оставить его на исчезнувшем id, поиск
## вернёт -1 и следующий `advance_turn()` начнёт очередь С НАЧАЛА (ровно тот
## баг D-4.6, который мы исправляем, только в другой форме). Поэтому курсор
## переставляется на ПРЕДШЕСТВЕННИКА удаляемого — тогда следующий вызов
## штатно перейдёт к тому, кто шёл за выбывшим.
func unregister_participant(unit: UnitState) -> void:
	if unit == null or not _participants.has(unit):
		return

	var was_current := _current_unit_id == unit.id
	var predecessor_id := UnitId.NONE
	if was_current:
		var index := _index_of_current()
		if index > 0:
			predecessor_id = _current_order[index - 1].id

	_participants.erase(unit)
	_rebuild_order_preserving_cursor()

	if was_current:
		# NONE означает "курсор до начала очереди" — следующий advance_turn()
		# выдаст первого в списке, что корректно, если выбыл именно первый.
		_current_unit_id = predecessor_id


func get_participants() -> Array[UnitState]:
	return _participants.duplicate()


func get_alive_participants() -> Array[UnitState]:
	var alive: Array[UnitState] = []
	for unit in _participants:
		if unit.is_alive():
			alive.append(unit)
	return alive


## Живые юниты указанной фракции — для проверки условия победы/поражения
## (шаг 0.6). Раньше это было невозможно: фракции не существовало (C-1).
func count_alive_of_faction(faction: Faction.Type) -> int:
	var n := 0
	for unit in _participants:
		if unit.is_alive() and unit.faction == faction:
			n += 1
	return n


# --- Порядок ---------------------------------------------------------------

## Полный пересчёт порядка со СБРОСОМ курсора. Вызывать на границе раунда
## или при старте боя — НЕ при смерти участника (для этого есть
## `unregister_participant`, который курсор сохраняет).
func recompute_order() -> void:
	_current_order = _compute_order()
	_current_unit_id = UnitId.NONE


func get_current_order() -> Array[UnitState]:
	return _current_order.duplicate()


func _compute_order() -> Array[UnitState]:
	if _strategy == null:
		return _participants.duplicate()
	return _strategy.compute_order(_participants)


## Перестраивает список, но оставляет курсор на том же юните. Нужно, чтобы
## добавление/удаление участника посреди раунда не ломало очередь (D-4.6).
func _rebuild_order_preserving_cursor() -> void:
	var previous_id := _current_unit_id
	_current_order = _compute_order()
	# Если юнит под курсором выбыл — курсор останется на его id, а
	# `_index_of_current()` вернёт -1, и следующий advance_turn() начнёт с
	# начала списка. Это корректно: выбывший не должен "держать" очередь.
	_current_unit_id = previous_id


func _index_of_current() -> int:
	if _current_unit_id == UnitId.NONE:
		return -1
	for i in _current_order.size():
		if _current_order[i].id == _current_unit_id:
			return i
	return -1


# --- Продвижение очереди ---------------------------------------------------

## Начинает бой: считает порядок и эмитит `round_started(1)`.
func start_battle() -> void:
	_round_number = 1
	recompute_order()
	round_started.emit(_round_number)


## Возвращает следующего ЖИВОГО участника, продвигая курсор.
## При достижении конца очереди эмитит `round_ended` -> пересчитывает
## порядок -> эмитит `round_started` (фикс D-4.7: границы раунда больше не
## неявные). Возвращает null, если живых участников нет.
func advance_turn() -> UnitState:
	if _current_order.is_empty():
		return null

	var start_index := _index_of_current()

	# Ищем следующего живого, максимум за один полный обход, чтобы не
	# зациклиться, если все мертвы.
	for step in range(1, _current_order.size() + 1):
		var next_index := start_index + step

		if next_index >= _current_order.size():
			_advance_round()
			# После смены раунда порядок пересчитан — начинаем с начала.
			start_index = -1
			next_index = 0
			if _current_order.is_empty():
				return null

		var candidate := _current_order[next_index]
		if candidate.is_alive():
			_current_unit_id = candidate.id
			candidate.begin_turn()
			turn_started.emit(candidate)
			return candidate

	return null


func _advance_round() -> void:
	round_ended.emit(_round_number)
	_round_number += 1
	_current_order = _compute_order()
	_current_unit_id = UnitId.NONE
	round_started.emit(_round_number)


func peek_current() -> UnitState:
	var index := _index_of_current()
	if index < 0:
		return null
	return _current_order[index]
