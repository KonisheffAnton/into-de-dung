extends Resource
class_name AIConsideration

## Абстрактная база Utility AI "фактора оценки" (см. Strategy-подобный
## паттерн TurnOrderStrategy в Модуле 4). Каждая конкретная considerration —
## отдельный небольшой Resource-скрипт, оценивающий ОДНУ грань кандидата
## AIAction в диапазоне [0..1]. Новые типы поведения добавляются простым
## созданием новой considerration + подключением в AIBehaviorProfile.tres,
## без изменения UtilityAIController.
##
## weight настраивается ПО ЭКЗЕМПЛЯРУ (в конкретном .tres AIBehaviorProfile),
## поэтому одна и та же considerration может иметь разный вес у разных
## ролей врагов (Aggressor/Blocker) без дублирования кода.

@export var weight: float = 1.0

## action: кандидат хода/атаки, который нужно оценить.
## context: общий снимок ситуации (см. AIDecisionContext).
## Возвращает score в диапазоне [0..1]. Переопределяется в наследниках.
func score(_action: AIAction, _context: AIDecisionContext) -> float:
	push_error("AIConsideration.score() is abstract, override in a subclass")
	return 0.0
