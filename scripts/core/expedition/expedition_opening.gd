extends RefCounted
class_name ExpeditionOpening

## Каталог стартового полигона входит в сохранённый manifest нового плана.
static func values() -> Dictionary:
	return {
		"id":"opening-threats-v1", "version":1,
		"enemies":[
			{"name":"Страж", "cell":[6,1], "role":"guard", "armor":25},
			{"name":"Щит", "cell":[6,3], "role":"shield", "armor":60},
			{"name":"Дозорный", "cell":[6,5], "role":"sneak", "armor":0}],
		"terrain":[
			{"cell":[3,0], "type":TerrainType.Type.WALL},
			{"cell":[5,6], "type":TerrainType.Type.HAZARD},
			{"cell":[6,7], "type":TerrainType.Type.VOID}],
		"heights":[{"cell":[3,3], "steps":1},{"cell":[4,3], "steps":2}],
		"hazards":[{"cell":[3,2], "effect":"bleeding"},{"cell":[4,4], "effect":"burning"}],
		"collapse":{"turn":0,"marked":[]}}

static func cell(value: Array) -> Vector2i:
	return Vector2i(value[0], value[1])
