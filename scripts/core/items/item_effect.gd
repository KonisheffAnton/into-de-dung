extends Resource
class_name ItemEffect

## Определение эффекта. Runtime создаётся владельцем, поэтому Resource остаётся
## неизменяемым и безопасно разделяется между предметами.
func create_runtime(owner_id: int, item_id: int, effect_id: int, effect_index: int) -> ItemEffectRuntime:
	return null
