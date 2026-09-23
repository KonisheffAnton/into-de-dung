extends RefCounted
class_name StatTypes

## Единый enum типов характеристик (Attributes). Новые статы добавляются
## здесь и сразу доступны через StatsBag без изменения его кода.
##
## ВАЖНО (R-2): здесь ТОЛЬКО "производные" характеристики — те, чьё значение
## вычисляется как `base_value + модификаторы`. Текущие РЕСУРСЫ юнита
## (`hp_current`, `balance_current`) сюда НЕ входят — они живут в `Vitals`.
##
## Почему: раньше здесь были HP и BALANCE, и код писал текущее значение в
## `Stat.base_value` (`set_base_value(get_value() - damage)`). Поскольку
## `get_value()` = база + модификаторы, это ВПЕКАЛО модификаторы в базу.
## Воспроизведение дефекта C-2: HP base=10, амулет +5 -> get_value()=15;
## урон 3 -> set_base_value(12) -> get_value()=17. HP ВЫРОС от полученного
## урона, а снятие амулета оставляло +2 навсегда. Удаление HP/BALANCE из этого
## enum делает такой баг физически невозможным, а не "запрещённым соглашением".
##
## ВАЖНО (R-4): значения enum попадают в сейвы и в .tres.
## Только ДОБАВЛЯТЬ в конец. Никогда не переупорядочивать и не удалять из
## середины — числовые индексы сдвинутся и сломают старые данные.

enum StatType {
	HP_MAX,         ## Максимальный запас здоровья (текущее HP — в Vitals).
	INITIATIVE,     ## Определяет порядок ходов (выше = ходит раньше).
	BALANCE_MAX,    ## Порог, при достижении которого юнит теряет равновесие/толкается.
	STRENGTH,       ## Сила — напрямую влияет на урон атак.
	IMPACT_POWER,   ## Сила импакта — влияет на накопление Баланса цели и толкание.
	MOVE_RANGE,     ## Дальность хода в очках движения (для Pathfinding).
	ARMOR,          ## Плоское снижение получаемого урона (задел под резисты).
	MAIN_ACTIONS_MAX,
	BONUS_ACTIONS_MAX,
	WEAPON_DAMAGE,
	ATTACK_RANGE,
	PHYSICAL_PIERCING_PERCENT, ## Доля физической базы, обходящая броню; ID 11.
}

## Одна проверка raw ID для runtime и снимков; float/bool не приводим к enum.
static func is_valid_id(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and StatType.values().has(value)


## Человекочитаемое имя — для дебаг-панелей и логов (НЕ для локализации UI:
## там будут ключи локализации, см. AUDIT.md D-5.4).
static func to_display_name(type: StatType) -> String:
	match type:
		StatType.HP_MAX: return "HP Max"
		StatType.INITIATIVE: return "Initiative"
		StatType.BALANCE_MAX: return "Balance Max"
		StatType.STRENGTH: return "Strength"
		StatType.IMPACT_POWER: return "Impact Power"
		StatType.MOVE_RANGE: return "Move Range"
		StatType.ARMOR: return "Armor"
		StatType.MAIN_ACTIONS_MAX: return "Main Actions Max"
		StatType.BONUS_ACTIONS_MAX: return "Bonus Actions Max"
		StatType.WEAPON_DAMAGE: return "Weapon Damage"
		StatType.ATTACK_RANGE: return "Attack Range"
		StatType.PHYSICAL_PIERCING_PERCENT: return "Physical Piercing Percent"
	return "Unknown"
