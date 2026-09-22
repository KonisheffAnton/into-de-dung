# Исполнение боя: актуальный вход в контракты

Актуальная навигация с дополнением D5 от 2026-09-22. Прежний draft-2
и addenda §§1–17 целиком находятся в [архиве](COMMAND_ACTION_QUEUE_CONTRACT.history-20260920.md).
Предложенные там методы нельзя принимать за API текущего кода.

## Действующий путь

Session проверяет фазу/выбор и передаёт команду в
`ActionQueue.submit(command: Command, context: ActionContext) -> ActionReceipt`.
Контекст хранит ItemSimulationState, внедрённые RNG/sink/rules, revision и counters.
Команда проверяет допуск и ресурсы при исполнении; UI/BT не оплачивают действие.
Очередь завершает mandatory consequences, реакции и продолжения в определённом
порядке; обычно одно поддерево завершается до следующего. Для атаки с источником
кровотечения D3 optional item reactions всех spatial-потомков откладываются:
mandatory spatial → наложение исходного hit → реакции в порядке сбора.
Вложенный внешний submit
отклоняется как BUSY. Ограничения и faults сохраняют уже исполненный prefix;
отката частично выполненной цепи нет. Публикация value events идёт после drain/fault.
Session проверяет исход после полного submit. Точные guards/receipt схемы — в пакетах ниже.

D5 добавляет внутренние последствия событий moved/died. Они следуют за
существующим mandatory-поддеревом и перед continuation; item reactions D3-атаки
по-прежнему отложены до завершения пространственных и статусных последствий.
Обычное движение сохраняет реакции своего fall-поддерева перед огнём входа.
Формат отдельной среды, тела и поднятие — [ENVIRONMENT_D5](ENVIRONMENT_D5.md).

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
| Движение P05 | [TASK](P05_MOVE_TASK.md), [REVIEW](P05_REVIEW.md); позднейший пространственный [проход союзников](ALLY_TRANSIT.md) |
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
его архивного текста. [D1](ATTACK_DAMAGE_D1.md) выделяет чистый расчёт прямого удара,
сохраняя исполнение и receipts. Новая броня и типизированный урон приняты в
[D0](ARMOR_DAMAGE_D0.md) и реализованы отдельным профилем [D2](ARMOR_DAMAGE_D2.md).
[Проход союзников](ALLY_TRANSIT.md) добавляет атомарный пространственный сегмент
и поле transit_path его события moved, сохраняя прежний формат соседнего шага.
[D3](BLEEDING_D3.md) добавляет внутренние BleedingApply/Tick и корневую
BleedingTurnCommand. Внешняя подача Apply/Tick отвергается. Событие
bleeding_changed несёт before/after состояния и applied/refreshed/tick;
hit_resolved прямого источника дополнительно сохраняет policy/physical_hp_damage/eligible.
Лимиты, counters и реальные события префикса учитывают эти команды.
