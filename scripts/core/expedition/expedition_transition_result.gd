extends RefCounted
class_name ExpeditionTransitionResult

var profile: HeroHubState = null
var reason: String = ""

func is_ok() -> bool:
	return profile != null and reason.is_empty()
