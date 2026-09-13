extends ItemEffect
class_name TriggeredEffect

## Только параметр триггера; runtime не подписывается на глобальные шины.
enum TriggerEvent { UNIT_DAMAGED, UNIT_HEALED, UNIT_BALANCE_BROKEN, UNIT_DIED, TURN_STARTED, TURN_ENDED }
@export var trigger_event: TriggerEvent = TriggerEvent.UNIT_DAMAGED
