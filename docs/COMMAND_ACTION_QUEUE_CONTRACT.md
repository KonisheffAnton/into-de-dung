# Исполнение боя: актуальный вход в контракты

Редакция навигации 2026-09-20; игровое поведение не меняется. Прежний draft-2
и addenda §§1–17 целиком находятся в [архиве](COMMAND_ACTION_QUEUE_CONTRACT.history-20260920.md).
Предложенные там методы нельзя принимать за API текущего кода.

## Действующий путь

Session проверяет фазу/выбор и передаёт команду в
`ActionQueue.submit(command: Command, context: ActionContext) -> ActionReceipt`.
Контекст хранит ItemSimulationState, внедрённые RNG/sink/rules, revision и counters.
Команда проверяет допуск и ресурсы при исполнении; UI/BT не оплачивают действие.
Очередь завершает mandatory consequences, реакции и продолжения в определённом
порядке; одно поддерево завершается до следующего. Вложенный внешний submit
отклоняется как BUSY. Ограничения и faults сохраняют уже исполненный prefix;
отката частично выполненной цепи нет. Публикация value events идёт после drain/fault.
Session проверяет исход после полного submit. Точные guards/receipt схемы — в пакетах ниже.

Прогноз нынешней атаки:
`AttackForecast.build(context: ActionContext, queue: ActionQueue, command: AttackCommand) -> AttackForecast`.
Он переносит snapshot/definitions/RNG, использует `copy_for_simulation` для
context/queue и исполняет `submit` на копии. Неподдерживаемое состояние даёт отказ.
Нажатие атаки исполняет свежую команду. Методов `ActionQueue.preview` и
`confirm_preview`, общего `PreviewToken` и общего forecast всех команд сейчас нет.
Подробности и UI — [ATTACK_FORECAST](ATTACK_FORECAST.md).

## Точные спецификации по области

| Область | Сохранённый пакет |
|---|---|
| Смерть/occupancy P01 | §10 [исторического общего контракта](COMMAND_ACTION_QUEUE_CONTRACT.history-20260920.md); последующие HP/spatial правила в P04/P08 |
| Board/stat/unit snapshot P02 | [P02](P02_SNAPSHOT_TASK.md) |
| Ownership предметов P03a | [TASK](P03A_ITEM_OWNERSHIP_TASK.md), [REVIEW](P03A_REVIEW.md) |
| Item snapshot/collector P03b | [TASK](P03B_ITEM_SNAPSHOT_TASK.md), [REVIEW](P03B_REVIEW.md) |
| Очередь Damage/Heal/Death P04 | [TASK](P04_ACTION_QUEUE_TASK.md), [REVIEW](P04_REVIEW.md) |
| Движение P05 | [TASK](P05_MOVE_TASK.md), [REVIEW](P05_REVIEW.md) |
| Оплата и исполнение атаки P06 | [TASK](P06_ATTACK_TASK.md), [REVIEW](P06_REVIEW.md) |
| Balance/push/collision P07 | [TASK](P07_BALANCE_PUSH_TASK.md), [REVIEW](P07_REVIEW.md) |
| Spatial и guards P08 r3 | [TASK](P08_SPATIAL_TASK_R3.md), особенно §4.5; [REVIEW](P08_REVIEW_R3.md) |

Frozen TASK/DEPENDENCIES/REVIEW остаются на прежних путях без изменения байтов.
Их hashes и ограничения относятся к указанному этапу; старый запрет записи в
документы из пакета кодеру не становится вечным запретом отдельного поручения
на редактуру документации. Исторические manifests не переписывать под новый HEAD.

Позднейшие уточнения действующего боя: [TACTICAL_BATTLE](TACTICAL_BATTLE.md),
[ACTION_PANEL_GUARD](ACTION_PANEL_GUARD.md), [HEALING_ITEM](HEALING_ITEM.md),
[SUMMON_ITEM](SUMMON_ITEM.md). Они описывают добавления после P08, а не изменения
его архивного текста. Новая броня и типизированный урон пока обсуждаются в
[DESIGN_DIRECTION](DESIGN_DIRECTION.md); исполняемые формулы остаются прежними.
