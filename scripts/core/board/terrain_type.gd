extends RefCounted
class_name TerrainType

## Типы поверхности клетки.
##
## ПОЧЕМУ ENUM, А НЕ `TileDef : Resource` (нарушение R-1?). Осознанный
## компромисс на время вертикального среза (R-7). Data-driven тайлы нужны,
## когда у клеток появятся уникальные свойства (урон за вход, статусы,
## разрушаемость, спрайты) — то есть на шаге Tile Effects. Сейчас требуется
## ровно четыре различимых состояния, и enum в `PackedByteArray` даёт
## компактное хранение поля 32x32 в 1 КБ вместо массива объектов.
## В `AUDIT.md` заведён P2-пункт на замену.
##
## ВАЖНО (R-4): значения попадают в сейвы карт — только ДОБАВЛЯТЬ в конец.

enum Type {
	FLOOR,   ## Обычный проходимый пол.
	WALL,    ## Непроходимо и блокирует толкание.
	HAZARD,  ## Проходимо, но смертельно/опасно (пропасть, лава, вода).
	VOID,    ## Вне карты / дыра. Непроходимо, но НЕ блокирует толчок:
	         ## толкнуть В пустоту можно (юнит падает) — в отличие от стены.
}


## Можно ли войти в клетку по своей воле (pathfinding).
## HAZARD проходим: игрок имеет право сознательно рискнуть, а ИИ
## отговаривает `SelfSafetyConsideration` через VETO. Если запретить его
## здесь, исчезнет тактика "толкнуть врага в пропасть через клетку".
static func is_walkable(type: Type) -> bool:
	return type == Type.FLOOR or type == Type.HAZARD


## Блокирует ли клетка ТОЛКАНИЕ (в отличие от прохода).
## Различие принципиально для механики жанра: в стену цель упирается и
## получает урон от столкновения, а в пропасть — улетает и погибает.
static func blocks_push(type: Type) -> bool:
	return type == Type.WALL


## Убивает/калечит ли попадание в эту клетку.
static func is_lethal(type: Type) -> bool:
	return type == Type.HAZARD or type == Type.VOID


static func to_string_name(type: Type) -> StringName:
	match type:
		Type.FLOOR: return &"floor"
		Type.WALL: return &"wall"
		Type.HAZARD: return &"hazard"
		Type.VOID: return &"void"
	return &"unknown"
