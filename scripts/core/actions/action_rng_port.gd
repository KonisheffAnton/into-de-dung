extends RefCounted
class_name ActionRngPort

func next_int(_stream: StringName, _upper_exclusive: int) -> int:
	return -1

func clone() -> ActionRngPort:
	return null

func to_dict() -> Dictionary:
	return {}

func from_dict(_data: Dictionary) -> bool:
	return false
