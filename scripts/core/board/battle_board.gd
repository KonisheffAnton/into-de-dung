extends RefCounted
class_name BattleBoard

## ЕДИНСТВЕННЫЙ авторитетный источник правды о состоянии боевой доски —
## фикс критического дефекта C-4.
##
## ПРОБЛЕМА, КОТОРУЮ ЭТО РЕШАЕТ. Раньше не существовало объекта, который знал
## бы "кто где стоит". Последствия были системными:
##  - `PushResolver.validate_push()` не знал о юнитах, поэтому толчок в
##    ЗАНЯТУЮ клетку считался успешным. Это делало невыразимой ГЛАВНУЮ
##    механику жанра: толкнул -> цель врезалась в другого -> оба получили
##    урон (Into the Breach);
##  - `GridPathfinder` не знал о юнитах, поэтому зона хода включала клетки
##    под врагами, и ИИ строил кандидатов на занятые клетки;
##  - `AIDecisionContext` приходилось заполнять вручную снаружи — не было
##    реестра, у которого можно спросить список юнитов;
##  - `GridDataProvider` (правильный DI сам по себе) требовал, чтобы КАЖДЫЙ
##    потребитель собирал замыкания сам, что гарантировало расхождение
##    правил проходимости между системами.
##
## ХРАНЕНИЕ. Высоты и террейн — плоские `Packed*Array` с индексацией
## `y * width + x`, а не `Dictionary[Vector2i, ...]`. Для доски 32x32 это
## 1024 байта против словаря с 1024 объектами-ключами `Vector2i`: важно и для
## памяти на мобилках, и для скорости (pathfinding читает высоту в каждом
## шаге flood-fill).
##
## ВЕРСИОНИРОВАНИЕ. `board_version` инкрементируется при ЛЮБОЙ мутации.
## Нужно для кэша зоны хода (D-3.3): пересчитывать flood-fill можно только
## когда доска изменилась, а не на каждое движение мыши.
##
## ГРАНИЦЫ ОТВЕТСТВЕННОСТИ: доска хранит состояние и отвечает на запросы.
## Она НЕ считает урон, НЕ решает чей ход и НЕ анимирует перемещение —
## мутации выполняют Command'ы (шаг 0.5), которые вызывают `move_unit()`.

## Доска изменилась (для инвалидации кэшей и обновления View).
signal board_changed()

## Юнит переместился (визуализация; `unit_moved` в шине — отдельно, для эффектов).
signal unit_position_changed(unit: UnitState, from_cell: Vector2i, to_cell: Vector2i)

var width: int = 0
var height: int = 0

## Инкрементируется при любой мутации. Ключ для кэшей.
var board_version: int = 0

var _heights: PackedInt32Array = PackedInt32Array()
var _height_half_steps: PackedByteArray = PackedByteArray()
var _terrain: PackedByteArray = PackedByteArray()

## Vector2i -> int (UnitId). Обратный индекс к `UnitState.cell`.
var _occupancy: Dictionary = {}

## int (UnitId) -> UnitState. Реестр всех юнитов на доске, включая мёртвых
## (мёртвые остаются в реестре до явного удаления: эффекты вида "при смерти
## союзника" и экраны результатов должны видеть павших).
var _units: Dictionary = {}


func _init(p_width: int = 0, p_height: int = 0) -> void:
	resize(p_width, p_height)


## Пересоздаёт доску заданного размера, заполняя полом на высоте 0.
func resize(p_width: int, p_height: int) -> void:
	width = maxi(0, p_width)
	height = maxi(0, p_height)
	var cell_count := width * height

	_heights = PackedInt32Array()
	_heights.resize(cell_count)
	_terrain = PackedByteArray()
	_terrain.resize(cell_count)
	_height_half_steps.resize(cell_count)
	for i in cell_count:
		_heights[i] = 0
		_terrain[i] = TerrainType.Type.FLOOR
		_height_half_steps[i] = 0

	_occupancy.clear()
	_units.clear()
	_touch()


# --- Границы и индексация --------------------------------------------------

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func get_bounds() -> Rect2i:
	return Rect2i(0, 0, width, height)


func _index(cell: Vector2i) -> int:
	return cell.y * width + cell.x


# --- Террейн и высота -----------------------------------------------------

## Высота клетки. Вне границ — 0 (нейтральное значение: правило перепада
## высот не должно случайно разрешать/запрещать выход за край, за это
## отвечает `is_in_bounds`).
func get_height(cell: Vector2i) -> int:
	if not is_in_bounds(cell):
		return 0
	return _heights[_index(cell)]


func set_height(cell: Vector2i, value: int) -> void:
	if not is_in_bounds(cell):
		return
	_heights[_index(cell)] = value
	_height_half_steps[_index(cell)] = 0
	_touch()

func get_height_steps(cell: Vector2i) -> int:
	if not is_in_bounds(cell):
		return 0
	return int(_heights[_index(cell)]) * 2 + int(_height_half_steps[_index(cell)])

func set_height_steps(cell: Vector2i, steps: int) -> bool:
	if not is_in_bounds(cell) or steps < -4294967296 or steps > 4294967295 or board_version >= 9223372036854775807:
		return false
	var whole: int = floori(float(steps) / 2.0)
	var half := steps - whole * 2
	_heights[_index(cell)] = whole
	_height_half_steps[_index(cell)] = half
	_touch()
	return true

func has_half_heights() -> bool:
	for bit in _height_half_steps:
		if bit != 0:
			return true
	return false


func get_terrain(cell: Vector2i) -> TerrainType.Type:
	if not is_in_bounds(cell):
		return TerrainType.Type.VOID
	return _terrain[_index(cell)] as TerrainType.Type


func set_terrain(cell: Vector2i, type: TerrainType.Type) -> void:
	if not is_in_bounds(cell):
		return
	_terrain[_index(cell)] = type
	_touch()


## Клетка проходима по СВОЙСТВАМ ТЕРРЕЙНА, без учёта юнитов.
## Отличать от `can_enter()` — их смешение и было источником путаницы.
func is_terrain_walkable(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return false
	return TerrainType.is_walkable(get_terrain(cell))


func blocks_push(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		# Вне доски — не "стена": толкнуть за край можно (юнит падает).
		return false
	return TerrainType.blocks_push(get_terrain(cell))


func is_lethal(cell: Vector2i) -> bool:
	if not is_in_bounds(cell):
		return true
	return TerrainType.is_lethal(get_terrain(cell))


## Все опасные клетки. Заменяет ручной список `AIDecisionContext.hazard_cells`.
func get_hazard_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			if is_lethal(cell):
				result.append(cell)
	return result


# --- Юниты и occupancy ----------------------------------------------------

## Ставит юнита на доску в его `unit.cell`. Возвращает false, если клетка
## занята или непроходима — молчаливое размещение двух юнитов в одной клетке
## порождало бы рассинхрон occupancy и позиций.
func add_unit(unit: UnitState) -> bool:
	if unit == null or _units.has(unit.id):
		return false
	if not is_in_bounds(unit.cell):
		push_error("BattleBoard.add_unit: клетка %s вне границ доски" % str(unit.cell))
		return false
	if _occupancy.has(unit.cell):
		push_error("BattleBoard.add_unit: клетка %s уже занята" % str(unit.cell))
		return false

	_units[unit.id] = unit
	_occupancy[unit.cell] = unit.id
	unit.height = get_height(unit.cell)
	_touch()
	return true


## Убирает юнита с доски полностью (труп унесли, юнит отступил).
func remove_unit(unit: UnitState) -> void:
	if unit == null or not _units.has(unit.id):
		return
	_units.erase(unit.id)
	if _occupancy.get(unit.cell, UnitId.NONE) == unit.id:
		_occupancy.erase(unit.cell)
	_touch()


## Освобождает клетку, но оставляет юнита в реестре — состояние "погиб, но
## его ещё видно в списке участников". Нужно, чтобы мёртвый не блокировал
## клетку для движения и толкания.
func clear_occupancy(unit: UnitState) -> void:
	if unit == null or _units.get(unit.id) != unit:
		return
	if _occupancy.get(unit.cell, UnitId.NONE) == unit.id:
		_occupancy.erase(unit.cell)
		_touch()


## ЕДИНСТВЕННЫЙ штатный способ изменить позицию юнита.
## Обновляет и occupancy, и `unit.cell`, и `unit.height` — поэтому они не
## могут разойтись. Прямая запись `unit.cell = ...` запрещена (см. UnitState).
func move_unit(unit: UnitState, to_cell: Vector2i) -> bool:
	if unit == null or not _units.has(unit.id):
		return false
	if not is_in_bounds(to_cell):
		return false

	var from_cell := unit.cell
	if from_cell == to_cell:
		return true

	var occupant_id: int = _occupancy.get(to_cell, UnitId.NONE)
	if occupant_id != UnitId.NONE and occupant_id != unit.id:
		return false

	if _occupancy.get(from_cell, UnitId.NONE) == unit.id:
		_occupancy.erase(from_cell)
	_occupancy[to_cell] = unit.id

	unit.cell = to_cell
	unit.height = get_height(to_cell)

	_touch()
	unit_position_changed.emit(unit, from_cell, to_cell)
	return true


## Живой юнит в клетке, либо null. Мёртвые не возвращаются: они не должны
## блокировать движение и толкание.
func occupant_at(cell: Vector2i) -> UnitState:
	var occupant_id: int = _occupancy.get(cell, UnitId.NONE)
	if occupant_id == UnitId.NONE:
		return null
	var unit: UnitState = _units.get(occupant_id)
	if unit == null or not unit.is_alive():
		return null
	return unit


func is_occupied(cell: Vector2i) -> bool:
	return occupant_at(cell) != null


func get_unit_by_id(unit_id: int) -> UnitState:
	return _units.get(unit_id)


func get_all_units() -> Array[UnitState]:
	var result: Array[UnitState] = []
	for key in _units.keys():
		var unit: UnitState = _units[key]
		result.append(unit)
	return result


func get_alive_units() -> Array[UnitState]:
	var result: Array[UnitState] = []
	for key in _units.keys():
		var unit: UnitState = _units[key]
		if unit.is_alive():
			result.append(unit)
	return result


## Живые юниты фракции. Заменяет ручное разделение на enemy/ally.
func get_units_of_faction(faction: Faction.Type) -> Array[UnitState]:
	var result: Array[UnitState] = []
	for key in _units.keys():
		var unit: UnitState = _units[key]
		if unit.is_alive() and unit.faction == faction:
			result.append(unit)
	return result


func count_alive_of_faction(faction: Faction.Type) -> int:
	return get_units_of_faction(faction).size()


# --- Проходимость (главный запрос pathfinding) -----------------------------

## Может ли `for_unit` войти в клетку. Объединяет террейн и occupancy —
## ЕДИНСТВЕННОЕ место, где это правило определено (раньше каждый потребитель
## писал своё замыкание, и правила расходились).
##
## `for_unit` может быть null (абстрактный запрос "проходима ли клетка в
## принципе"). Сам юнит себя не блокирует — это закрывает дефект D-3.6.
func can_enter(cell: Vector2i, for_unit: UnitState = null) -> bool:
	if not is_terrain_walkable(cell):
		return false
	var occupant := occupant_at(cell)
	if occupant == null:
		return true
	if for_unit != null and occupant.id == for_unit.id:
		return true
	return false


## Стоимость входа в клетку для расчёта зоны хода.
## HAZARD дороже пола: ИИ и автопуть будут его огибать при прочих равных,
## но пройти через него всё ещё можно (запрет — дело VETO у considerations).
func get_move_cost(cell: Vector2i) -> float:
	if not is_in_bounds(cell):
		return INF
	if get_terrain(cell) == TerrainType.Type.HAZARD:
		return 3.0
	return 1.0


## ЕДИНСТВЕННЫЙ штатный способ получить `GridDataProvider`.
## Именно здесь замыкается Dependency Inversion: `GridPathfinder` и
## `PushResolver` продолжают зависеть только от абстракции, но теперь её
## наполняет один авторитетный источник, а не каждый вызывающий по-своему.
## Благодаря этому `grid_pathfinder.gd` не потребовал НИ ОДНОЙ правки.
func make_data_provider(for_unit: UnitState = null) -> GridDataProvider:
	if has_half_heights():
		return GridDataProvider.new(func(_cell: Vector2i) -> bool: return false)
	return GridDataProvider.new(
		func(cell: Vector2i) -> bool: return can_enter(cell, for_unit),
		func(cell: Vector2i) -> int: return get_height(cell),
		func(cell: Vector2i) -> float: return get_move_cost(cell)
	)


## Провайдер, игнорирующий юнитов целиком (только геометрия/террейн).
## Нужен для запросов вида "куда вообще ведёт эта клетка", где occupancy
## неуместен.
func make_terrain_only_provider() -> GridDataProvider:
	if has_half_heights():
		return GridDataProvider.new(func(_cell: Vector2i) -> bool: return false)
	return GridDataProvider.new(
		func(cell: Vector2i) -> bool: return is_terrain_walkable(cell),
		func(cell: Vector2i) -> int: return get_height(cell),
		func(cell: Vector2i) -> float: return get_move_cost(cell)
	)

func make_spatial_data_provider(moving_unit: UnitState = null) -> GridDataProvider:
	return GridDataProvider.new(
		func(cell: Vector2i) -> bool: return can_enter(cell, moving_unit),
		func(cell: Vector2i) -> int: return get_height(cell),
		func(cell: Vector2i) -> float: return get_move_cost(cell),
		func(cell: Vector2i) -> int: return get_height_steps(cell)
	)


# --- Внутреннее -----------------------------------------------------------

func _touch() -> void:
	board_version += 1
	board_changed.emit()


# --- Сериализация (R-4) ---------------------------------------------------
## Юниты сохраняются как список — occupancy восстанавливается из их клеток,
## чтобы не хранить один и тот же факт дважды (источник рассинхрона).

func to_dict() -> Dictionary:
	if has_half_heights():
		# Старый DTO не имеет поля полу-шага и не должен молча терять геометрию.
		return {}
	var unit_dicts: Array[Dictionary] = []
	for key in _units.keys():
		var unit: UnitState = _units[key]
		if unit.action_resources != null:
			# Legacy export не умеет сохранять ledger без тихой потери действий.
			return {}
		unit_dicts.append(unit.to_dict())

	return {
		"width": width,
		"height": height,
		"heights": Array(_heights),
		"terrain": Array(_terrain),
		"units": unit_dicts,
		"unit_id_counter": UnitId.get_counter(),
	}


static func from_dict(data: Dictionary) -> BattleBoard:
	if data.has("height_half_steps") or data.has("schema_version"):
		return null
	var w: int = data.get("width", 0)
	var h: int = data.get("height", 0)
	var board := BattleBoard.new(w, h)

	var heights: Array = data.get("heights", [])
	var terrain: Array = data.get("terrain", [])
	var cell_count := w * h
	for i in mini(cell_count, heights.size()):
		board._heights[i] = int(heights[i])
	for i in mini(cell_count, terrain.size()):
		board._terrain[i] = int(terrain[i])

	var counter: int = data.get("unit_id_counter", UnitId.FIRST)
	UnitId.set_counter(counter)

	var unit_dicts: Array = data.get("units", [])
	for unit_data_variant in unit_dicts:
		var unit_data: Dictionary = unit_data_variant
		var unit := UnitState.from_dict(unit_data)
		board._units[unit.id] = unit
		if unit.is_alive():
			board._occupancy[unit.cell] = unit.id

	board._touch()
	return board
