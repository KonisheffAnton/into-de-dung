extends RefCounted
class_name Faction

## Принадлежность юнита к стороне конфликта (часть дефекта C-1: до рефакторинга
## понятия фракции не существовало вовсе, из-за чего AIDecisionContext был
## вынужден получать enemy_cells/ally_cells заполненными ВРУЧНУЮ снаружи —
## никакая система не могла сама ответить на вопрос "кто мне враг").
##
## Отношения вычисляются функцией, а не таблицей: для MVP достаточно правила
## "PLAYER враждебен ENEMY, NEUTRAL не враждебен никому". Когда понадобятся
## сложные отношения (временные союзы, фракции-паразиты), здесь появится
## матрица отношений — БЕЗ изменений в вызывающем коде, т.к. все системы
## спрашивают через is_hostile()/is_friendly(), а не сравнивают enum напрямую.
##
## ВАЖНО (R-4): значения enum попадают в сейвы — только ДОБАВЛЯТЬ в конец,
## никогда не переупорядочивать и не удалять из середины.

enum Type {
	PLAYER,   ## Юниты под управлением игрока.
	ENEMY,    ## Враждебные игроку юниты (управляются Utility AI).
	NEUTRAL,  ## Не участвует в конфликте (декорации-препятствия, мирные NPC).
}


## true, если `a` считает `b` врагом (и наоборот — отношение симметрично).
static func is_hostile(a: Type, b: Type) -> bool:
	if a == Type.NEUTRAL or b == Type.NEUTRAL:
		return false
	return a != b


## true, если юниты на одной стороне. NEUTRAL дружественен только NEUTRAL.
static func is_friendly(a: Type, b: Type) -> bool:
	return a == b


static func to_string_name(faction: Type) -> StringName:
	match faction:
		Type.PLAYER: return &"player"
		Type.ENEMY: return &"enemy"
		Type.NEUTRAL: return &"neutral"
	return &"unknown"
