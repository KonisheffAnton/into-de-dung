extends RefCounted
class_name UnitState

## ЕДИНАЯ сущность юнита в игровой логике — фикс корневого дефекта C-1.
##
## ПРОБЛЕМА, КОТОРУЮ ЭТО РЕШАЕТ. До рефакторинга сущности "юнит" не
## существовало вовсе: её роль исполнял `StatsComponent` (мешок характеристик),
## ссылка на который лежала в `DamageInfo.attacker/target`,
## `AIDecisionContext.enemy_cells`, `InitiativeTimeline._participants` и во всех
## сигналах шины. Последствия:
##  - не было понятия фракции -> `AIDecisionContext` получал enemy_cells/
##    ally_cells заполненными ВРУЧНУЮ снаружи, ни одна система не могла сама
##    ответить "кто мне враг";
##  - не было позиции -> её таскали отдельным параметром везде (`unit_cell`,
##    `attacker_cell`), и она не имела владельца;
##  - не было состояния жив/мёртв -> смерть не обрабатывалась нигде;
##  - не было связи юнит <-> инвентарь <-> экипировка (собиралась вручную
##    через @export в сцене, консистентность не гарантировалась);
##  - сериализация была невозможна: `StatsComponent : Node`, стабильного id нет.
##
## ПОЧЕМУ RefCounted, А НЕ NODE (R-1/R-3): это игровое СОСТОЯНИЕ, а не
## представление. Оно должно жить без дерева сцены — чтобы работали unit-тесты,
## изолированная симуляция для AI-lookahead и sandbox-прогон превью (R-6:
## превью = прогон настоящей команды на КОПИИ состояния). Визуальная нода
## (спрайт, анимации) будет ОТДЕЛЬНО и будет ссылаться на `unit_id`.
##
## ПОЧЕМУ НЕ RESOURCE (R-1): `Resource` кэшируется `ResourceLoader` и
## разделяется между всеми владельцами. Хранение изменяемого состояния
## конкретного юнита в `Resource` — ровно тот дефект C-3, из-за которого
## сломалась система предметов.
##
## ГРАНИЦЫ ОТВЕТСТВЕННОСТИ: этот класс — ДАННЫЕ юнита. Он не двигает себя по
## карте (это `MoveCommand` + `BattleBoard`, который обновляет occupancy), не
## считает урон (`DamageResolver`) и не решает, чей ход (`InitiativeTimeline`).

## Стабильный идентификатор (R-4). Неизменен на протяжении жизни юнита.
var id: int = UnitId.NONE

## Сторона конфликта. Заменяет ручное разделение на enemy_cells/ally_cells.
var faction: Faction.Type = Faction.Type.NEUTRAL

## Логическая клетка на сетке.
## ВАЖНО: это ЕДИНСТВЕННОЕ место хранения позиции юнита, но авторитетным
## реестром "кто где стоит" является `BattleBoard.occupancy`. Менять позицию
## нужно ТОЛЬКО через board (иначе occupancy и unit.cell разойдутся).
var cell: Vector2i = Vector2i.ZERO

## Уровень высоты клетки, на которой стоит юнит (дублирует высоту тайла для
## быстрого доступа; источник правды — `BattleBoard.get_height()`).
var height: int = 0

## Производные характеристики (Attributes, R-2).
var stats: StatsBag

## Текущие ресурсы: HP, Balance (R-2). Смерть — здесь.
var vitals: Vitals

## Отображаемое имя для дебага/логов. Для UI будет ключ локализации (D-5.4).
var debug_name: String = ""

## Профиль поведения ИИ (`.tres`). null для юнитов игрока.
var ai_profile: AIBehaviorProfile = null

## Осталось очков движения в текущем ходу. Это РЕСУРС хода (R-2): MOVE_RANGE —
## максимум (производная характеристика), а это — текущий остаток.
## Нужен для правила из DECISIONS.md: move -> attack -> остаток хода снова
## доступен (Поток A).
var move_points_left: float = 0.0

## Юнит уже атаковал в этом ходу (атака — одно действие за ход, движение —
## по очкам). Сбрасывается в begin_turn().
var has_attacked: bool = false


## Фабрика: выдаёт новый id, создаёт Vitals на полном HP и заполняет очки хода.
## Это ЕДИНСТВЕННЫЙ штатный способ создать юнита в бою — гарантирует, что id
## уникален, а vitals ссылается именно на переданный StatsBag.
static func create(
	p_faction: Faction.Type,
	p_cell: Vector2i,
	p_stats: StatsBag,
	p_debug_name: String = ""
) -> UnitState:
	var unit := UnitState.new()
	unit.id = UnitId.next()
	unit.faction = p_faction
	unit.cell = p_cell
	unit.stats = p_stats
	unit.vitals = Vitals.new(p_stats, true)
	unit.debug_name = p_debug_name if not p_debug_name.is_empty() else "Unit#%d" % unit.id
	unit.refill_move_points()
	return unit


# --- Удобные обёртки -------------------------------------------------------

func is_alive() -> bool:
	return vitals != null and vitals.is_alive()


func is_hostile_to(other: UnitState) -> bool:
	if other == null:
		return false
	return Faction.is_hostile(faction, other.faction)


func is_friendly_to(other: UnitState) -> bool:
	if other == null:
		return false
	return Faction.is_friendly(faction, other.faction)


func get_stat(type: StatTypes.StatType) -> float:
	if stats == null:
		return 0.0
	return stats.get_value(type)


# --- Ход юнита -------------------------------------------------------------

## Начало хода: восстановить очки движения и сбросить флаги действий.
func begin_turn() -> void:
	refill_move_points()
	has_attacked = false


func refill_move_points() -> void:
	move_points_left = get_stat(StatTypes.StatType.MOVE_RANGE)


func spend_move_points(amount: float) -> void:
	move_points_left = maxf(0.0, move_points_left - amount)


func can_move() -> bool:
	return is_alive() and move_points_left > 0.0


func can_attack() -> bool:
	return is_alive() and not has_attacked


# --- Сериализация (R-4) ----------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"id": id,
		"faction": int(faction),
		"cell_x": cell.x,
		"cell_y": cell.y,
		"height": height,
		"debug_name": debug_name,
		"move_points_left": move_points_left,
		"has_attacked": has_attacked,
		"stats": stats.to_dict() if stats != null else {},
		"vitals": vitals.to_dict() if vitals != null else {},
		"ai_profile_path": ai_profile.resource_path if ai_profile != null else "",
	}


static func from_dict(data: Dictionary) -> UnitState:
	var unit := UnitState.new()

	var id_int: int = data.get("id", UnitId.NONE)
	var faction_int: int = data.get("faction", int(Faction.Type.NEUTRAL))
	var cell_x: int = data.get("cell_x", 0)
	var cell_y: int = data.get("cell_y", 0)
	var height_int: int = data.get("height", 0)
	var name_str: String = data.get("debug_name", "")
	var mp_left: float = data.get("move_points_left", 0.0)
	var attacked: bool = data.get("has_attacked", false)
	var stats_dict: Dictionary = data.get("stats", {})
	var vitals_dict: Dictionary = data.get("vitals", {})
	var profile_path: String = data.get("ai_profile_path", "")

	unit.id = id_int
	unit.faction = faction_int as Faction.Type
	unit.cell = Vector2i(cell_x, cell_y)
	unit.height = height_int
	unit.debug_name = name_str
	unit.move_points_left = mp_left
	unit.has_attacked = attacked
	unit.stats = StatsBag.from_dict(stats_dict)
	unit.vitals = Vitals.from_dict(vitals_dict, unit.stats)

	if not profile_path.is_empty() and ResourceLoader.exists(profile_path):
		unit.ai_profile = load(profile_path) as AIBehaviorProfile

	# Счётчик id должен обогнать загруженные значения, иначе новый юнит
	# получит существующий id и перезапишет его в occupancy (см. UnitId).
	if id_int >= UnitId.get_counter():
		UnitId.set_counter(id_int + 1)

	return unit
