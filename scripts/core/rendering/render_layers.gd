extends RefCounted
class_name RenderLayers

## Явные слои отрисовки для изометрической сцены. Порядок слоёв фиксирован
## через z_index; ВНУТРИ слоя ENTITIES дополнительно используется Y-sort
## (см. YSortable) для сортировки юнитов/пропсов друг относительно друга.
##
## GROUND_EFFECTS < TILES < ENTITIES < PROJECTILES < VFX_OVERLAY < UI_PREVIEW

enum Layer {
	GROUND_EFFECTS, ## Пятна огня/яда/дыма на полу — всегда под тайлами замет.
	TILES,          ## Сама сетка/тайлы.
	ENTITIES,       ## Юниты, укрытия, интерактивные пропсы (Y-sorted).
	PROJECTILES,    ## Снаряды в полёте — всегда над юнитами.
	VFX_OVERLAY,    ## Взрывы/искры/частицы поверх всего игрового мира.
	UI_PREVIEW,     ## Стрелки Push Vectors, подсветка зоны хода, UI-превью.
}

const LAYER_Z_STEP: int = 100

static func z_index_for(layer: Layer) -> int:
	return int(layer) * LAYER_Z_STEP
