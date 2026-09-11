extends Resource
class_name IsoGridConfig

## Конфигурация изометрической сетки.
## Выносится в Resource, чтобы разные сцены/уровни могли иметь свою геометрию
## без хардкода параметров в коде.

## Полный размер тайла в пикселях (ширина/высота ромба).
@export var tile_size: Vector2 = Vector2(128.0, 64.0)

## Визуальный сдвиг по экранной оси Y на 1 уровень высоты клетки.
@export var height_step: float = 32.0

## Смещение начала координат сетки (grid (0,0)) на экране/в мире.
@export var origin_offset: Vector2 = Vector2.ZERO
