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

var action_resources: ActionResources = null
## Стойка принадлежит runtime; срок командного хода задаёт BattleTurnRefill.
var guard_stance: bool = false
var armor: ArmorState = null
var bleeding: BleedingState = null
var control: ControlState = null


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
	if action_resources == null:
		refill_move_points()
		has_attacked = false
	else:
		try_refill_turn_resources()

func enable_action_resources() -> StringName:
	if action_resources != null:
		return &"resources/already_enabled"
	if id < UnitId.FIRST or id >= ActionResources.MAX_ID or stats == null or vitals == null or stats.get_script() != StatsBag or vitals.get_script() != Vitals or vitals._stats != stats:
		return &"resources/invalid_runtime"
	if not is_alive():
		return &"resources/dead_unit"
	for stat_type in [StatTypes.StatType.MAIN_ACTIONS_MAX, StatTypes.StatType.BONUS_ACTIONS_MAX, StatTypes.StatType.WEAPON_DAMAGE, StatTypes.StatType.ATTACK_RANGE]:
		if not stats.has_stat(stat_type):
			return &"resources/missing_stat"
	# Проверяем производные на отдельном bag: enable не имеет права прогреть
	# cache живого состояния, в том числе при последующем отказе.
	var evaluated := StatsBag.from_snapshot_dict(stats.to_snapshot_dict())
	if evaluated == null:
		return &"resources/invalid_stat"
	for stat_type in [StatTypes.StatType.MAIN_ACTIONS_MAX, StatTypes.StatType.BONUS_ACTIONS_MAX, StatTypes.StatType.WEAPON_DAMAGE, StatTypes.StatType.ATTACK_RANGE]:
		var value := evaluated.get_value(stat_type)
		if not is_finite(value):
			return &"resources/invalid_stat"
		if stat_type == StatTypes.StatType.ATTACK_RANGE and (value != floorf(value) or value < 1.0 or value > 4096.0):
			return &"resources/invalid_stat"
		if (stat_type == StatTypes.StatType.MAIN_ACTIONS_MAX or stat_type == StatTypes.StatType.BONUS_ACTIONS_MAX) and (value != floorf(value) or value < 0.0 or value > 4096.0):
			return &"resources/invalid_stat"
	action_resources = ActionResources.new(id)
	return &""

func try_refill_turn_resources() -> StringName:
	if action_resources == null:
		return &"resources/not_enabled"
	if id < UnitId.FIRST or id >= ActionResources.MAX_ID or stats == null or vitals == null or stats.get_script() != StatsBag or vitals.get_script() != Vitals or vitals._stats != stats:
		return &"resources/invalid_runtime"
	if action_resources.get_script() != ActionResources:
		return &"resources/invalid_runtime"
	if action_resources.validate(id) != &"":
		return &"resources/owner_id" if action_resources.get_owner_unit_id() != id else &"resources/value"
	if not is_alive():
		return &"resources/dead_unit"
	for stat_type in [StatTypes.StatType.MAIN_ACTIONS_MAX, StatTypes.StatType.BONUS_ACTIONS_MAX]:
		if not stats.has_stat(stat_type):
			return &"resources/missing_stat"
	if not stats.has_stat(StatTypes.StatType.MOVE_RANGE):
		return &"resources/missing_stat"
	# Чистая копия исключает прогрев cache live-состояния при отказе refill.
	var evaluated := StatsBag.from_snapshot_dict(stats.to_snapshot_dict())
	if evaluated == null:
		return &"resources/invalid_runtime"
	var main_value := evaluated.get_value(StatTypes.StatType.MAIN_ACTIONS_MAX)
	var bonus_value := evaluated.get_value(StatTypes.StatType.BONUS_ACTIONS_MAX)
	if not is_finite(main_value) or main_value != floorf(main_value) or main_value < 0.0 or main_value > 4096.0:
		return &"resources/invalid_maximum"
	if not is_finite(bonus_value) or bonus_value != floorf(bonus_value) or bonus_value < 0.0 or bonus_value > 4096.0:
		return &"resources/invalid_maximum"
	var move := evaluated.get_value(StatTypes.StatType.MOVE_RANGE)
	if not is_finite(move) or move < 0.0:
		return &"resources/invalid_maximum"
	var main_max := int(main_value)
	var bonus_max := int(bonus_value)
	action_resources._set_for_refill(main_max, bonus_max)
	move_points_left = move
	has_attacked = false
	return &""


func refill_move_points() -> void:
	move_points_left = get_stat(StatTypes.StatType.MOVE_RANGE)


func spend_move_points(amount: float) -> void:
	move_points_left = maxf(0.0, move_points_left - amount)


func can_move() -> bool:
	return is_alive() and move_points_left > 0.0


func can_attack() -> bool:
	if action_resources == null:
		return is_alive() and not has_attacked
	return is_alive() and action_resources.get_script() == ActionResources and action_resources.validate(id) == &"" and action_resources.get_main_left() >= 1


# --- Сериализация (R-4) ----------------------------------------------------

func to_dict() -> Dictionary:
	if action_resources != null or guard_stance or armor != null or bleeding != null or control != null:
		return {}
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
	if data.has("armor") or data.has("bleeding") or data.has("control"):
		return null
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


func to_snapshot_dict() -> Dictionary:
	if get_script() != UnitState or stats == null or vitals == null or stats.get_script() != StatsBag or vitals.get_script() != Vitals or ai_profile != null:
		return {}
	if bleeding != null and (action_resources == null or armor == null):
		return {}
	if bleeding != null and bleeding.get_script() != BleedingState:
		return {}
	if control != null and (control.get_script() != ControlState or action_resources == null or not ControlState.valid(control.to_dict())):
		return {}
	if vitals._stats != stats or id < UnitId.FIRST or int(faction) < 0 or int(faction) > 2 or not is_finite(move_points_left) or move_points_left < 0.0:
		return {}
	var bag := stats.to_snapshot_dict()
	if bag.is_empty():
		return {}
	var vital_data := vitals.to_dict()
	if typeof(vital_data["hp"]) != TYPE_FLOAT or typeof(vital_data["balance"]) != TYPE_FLOAT or typeof(vital_data["is_alive"]) != TYPE_BOOL or not is_finite(vital_data["hp"]) or not is_finite(vital_data["balance"]) or vital_data["hp"] < 0.0 or vital_data["balance"] < 0.0:
		return {}
	var schema := 1
	var result := {"schema_version": schema, "id": id, "faction": int(faction),
		"cell_x": cell.x, "cell_y": cell.y, "height": height,
		"debug_name": debug_name, "ai_profile_path": "",
		"move_points_left": move_points_left, "has_attacked": has_attacked,
		"stats": bag, "vitals": vital_data}
	if action_resources != null:
		if action_resources.get_script() != ActionResources or action_resources.validate(id) != &"": return {}
		result["schema_version"] = 2
		result["action_resources"] = action_resources.to_snapshot_dict()
	if guard_stance:
		if action_resources == null: return {}
		result["schema_version"] = 3
		result["guard_stance"] = guard_stance
	if armor != null:
		if armor.get_script() != ArmorState or action_resources == null or not ArmorState.valid(armor.to_dict()): return {}
		result["schema_version"] = 4
		result["guard_stance"] = guard_stance
		result["armor"] = armor.to_dict()
		if bleeding != null:
			if not BleedingState.valid(bleeding.to_dict()): return {}
			result["schema_version"] = 5
			result["bleeding"] = bleeding.to_dict()
	if control != null:
		result["schema_version"] = 6
		result["control"] = control.to_dict()
	if armor != null or control != null:
		# Проверяем итоговый armor/control формат один раз после сборки полей.
		if not validate_snapshot_dict(result): return {}
	return result


static func from_snapshot_dict(data: Dictionary) -> UnitState:
	if not validate_snapshot_dict(data): return null
	var unit := UnitState.new()
	unit.id = data["id"]
	unit.faction = data["faction"] as Faction.Type
	unit.cell = Vector2i(data["cell_x"], data["cell_y"])
	unit.height = data["height"]
	unit.debug_name = data["debug_name"]
	unit.move_points_left = data["move_points_left"]
	unit.has_attacked = data["has_attacked"]
	unit.stats = StatsBag.from_snapshot_dict(data["stats"])
	unit.vitals = Vitals.from_dict(data["vitals"], unit.stats)
	if data["schema_version"] in [2, 3, 4, 5, 6]:
		unit.action_resources = ActionResources.from_snapshot_dict(data["action_resources"], unit.id)
		if unit.action_resources == null: return null
	unit.guard_stance = data.get("guard_stance", false)
	if data["schema_version"] in [4, 5] or (data["schema_version"] == 6 and data.has("armor")):
		unit.armor = ArmorState.from_dict(data["armor"])
		if unit.armor == null: return null
	if data["schema_version"] == 5 or (data["schema_version"] == 6 and data.has("bleeding")):
		unit.bleeding = BleedingState.from_dict(data["bleeding"])
		if unit.bleeding == null: return null
	if data["schema_version"] == 6:
		unit.control = ControlState.from_dict(data["control"])
		if unit.control == null: return null
	return unit


static func validate_snapshot_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY: return false
	var d: Dictionary = data
	if typeof(d.get("schema_version")) == TYPE_INT and d["schema_version"] == 6:
		if not d.has("control") or not ControlState.valid(d["control"]): return false
		# Ниже меняются только ключи корневого словаря; вложенные данные читаются.
		var prior := d.duplicate(false)
		prior.erase("control")
		prior["schema_version"] = 5 if prior.has("bleeding") else (4 if prior.has("armor") else (3 if prior.has("guard_stance") else 2))
		return validate_snapshot_dict(prior)
	var base_required := ["schema_version", "id", "faction", "cell_x", "cell_y", "height", "debug_name", "ai_profile_path", "move_points_left", "has_attacked", "stats", "vitals"]
	if typeof(data.get("schema_version")) != TYPE_INT or data["schema_version"] not in [1, 2, 3, 4, 5]: return false
	var required := base_required if data["schema_version"] == 1 else base_required + ["action_resources"]
	if data["schema_version"] == 4:
		required.append("armor")
	if data["schema_version"] == 5:
		required.append("armor")
		required.append("bleeding")
	if data["schema_version"] in [3, 4, 5]:
		required.append("guard_stance")
		if typeof(data.get("guard_stance")) != TYPE_BOOL: return false
	if not _has_exact_string_keys(d, required): return false
	for key in ["schema_version", "id", "faction", "cell_x", "cell_y", "height"]:
		if typeof(d[key]) != TYPE_INT: return false
	if d["id"] < UnitId.FIRST or d["faction"] < 0 or d["faction"] > 2 or d["cell_x"] < -2147483648 or d["cell_x"] > 2147483647 or d["cell_y"] < -2147483648 or d["cell_y"] > 2147483647: return false
	if typeof(d["debug_name"]) != TYPE_STRING or typeof(d["ai_profile_path"]) != TYPE_STRING or not d["ai_profile_path"].is_empty() or typeof(d["move_points_left"]) != TYPE_FLOAT or not is_finite(d["move_points_left"]) or d["move_points_left"] < 0.0 or typeof(d["has_attacked"]) != TYPE_BOOL: return false
	if not StatsBag.validate_snapshot_dict(d["stats"]): return false
	if d["schema_version"] in [2, 3, 4, 5] and not ActionResources.validate_snapshot_dict(d["action_resources"], d["id"]): return false
	if d["schema_version"] in [4, 5] and not ArmorState.valid(d["armor"]): return false
	if d["schema_version"] == 5 and not BleedingState.valid(d["bleeding"]): return false
	if typeof(d["vitals"]) != TYPE_DICTIONARY: return false
	var v: Dictionary = d["vitals"]
	if not _has_exact_string_keys(v, ["hp", "balance", "is_alive"]): return false
	if typeof(v["hp"]) != TYPE_FLOAT or not is_finite(v["hp"]) or v["hp"] < 0.0: return false
	if typeof(v["balance"]) != TYPE_FLOAT or not is_finite(v["balance"]) or v["balance"] < 0.0: return false
	if d["schema_version"] in [4, 5]:
		if v["hp"] != floorf(v["hp"]) or v["hp"] > ArmorRuntime.MAX_EXACT_HP: return false
		var maximum := 0.0
		for entry: Dictionary in d["stats"]["stats"]:
			if entry["stat_type"] == StatTypes.StatType.HP_MAX:
				var hp_stat := Stat.from_snapshot_dict(entry["stat"])
				if hp_stat == null: return false
				maximum = hp_stat.get_value()
				break
		if not is_finite(maximum) or maximum < 0.0 or maximum > ArmorRuntime.MAX_EXACT_HP or maximum != floorf(maximum) or v["hp"] > maximum: return false
	return typeof(v["is_alive"]) == TYPE_BOOL


static func _has_exact_string_keys(value: Dictionary, required: Array) -> bool:
	if value.keys().size() != required.size(): return false
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not required.has(key): return false
	return true
