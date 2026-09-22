# Прогноз одной атаки и панель осмотра

Действующий прогноз нынешней атаки с её последствиями, стойкой и влияющими
предметами. Стойка — [ACTION_PANEL_GUARD](ACTION_PANEL_GUARD.md); лечение/заряды —
[HEALING_ITEM](HEALING_ITEM.md); helpers и item snapshot v3 — [SUMMON_ITEM](SUMMON_ITEM.md).
Прогноз не расходует live-заряды. Прогноза применения предмета, движения или
нескольких команд нет. Будущий дизайн TACTICAL_DESIGN_NEXT не включается автоматически.
Происхождение срезов — [архив](ATTACK_FORECAST.history-20260920.md).

## Контракт исполнения

`AttackForecast.build(context, queue, command: AttackCommand)` возвращает RefCounted
с `status: StringName`, `reason: StringName`, `units: Dictionary` (ключ int unit id),
`events: Array[Dictionary]`, `steps: Array[Dictionary]`. Только APPLIED является
готовым прогнозом. Отказ, неизвестная capability или незавершённый каскад не дают
полос ожидаемого HP. В DTO нет ссылок на live/изолированные UnitState.

Каждая запись units содержит `before` и `after`: словари `hp`, `hp_max`, `balance`,
`balance_max` (float), `cell` (Vector2i), `alive` (bool), `main`, `bonus` (int),
`move` (float). Записи включают всех участников, UI выделяет изменившихся.
Записи также содержат `guard_stance` (bool); полный snapshot
переносит состояние в Unit schema v3 без refill. Снятие стойки атакующего совпадает
с настоящим исполнением. Проценты защиты не применяются к столкновению/падению.
`snapshot_before/after: Dictionary`, `rng_after: Dictionary`, `counters_after:
Dictionary` сохраняются для проверки parity. DTO не является save-game/token.

Снимок ItemSimulationSnapshot переносит доску, занятость, предметы, активность,
runtime эффектов и ресурсы без equip/refill. Определения копируются из каталога.
RNG клонируется отдельным объектом с совпадающим состоянием. Точный базовый
ActionRngPort допускается как порт без случайных чисел; неизвестный неклонируемый
порт отклоняется. Очередь сохраняет лимиты, контекст — revision и три счётчика.
Исполняется настоящая AttackCommand через ActionQueue с изолированным sink до
завершения mandatory/reactions. Копия закрывается на всех путях после создания.
Live состояние, сигналы, sink, счётчики, RNG и last_receipt не меняются.
Произвольные внешние мутирующие callbacks не входят в capability этого среза;
игровые реакции обязаны быть представленными в item runtime/командах.

`BattleDemoSession.preview_attack(id)` строит ту же команду, что атака, без submit
в live очередь. Tactical session применяет те же input/friendly gates без _reject
(он меняет last_receipt). Прогноз не завершает ход и не вычисляет исход боя.

## UI и приёмка

В режиме A наведение на фигуру показывает отказ либо итог всего каскада, включая
HP/равновесие, толчок, столкновение, падение, смерть и лечение. Конечный HP отмечен
на существующей полосе каждой затронутой фигуры; потеря красная, лечение зелёное,
числа показывают текущий и итоговый HP. Стрелка идёт из from_cell к to_cell или
attempted_cell, исход объясняется текстом. События берутся из receipt, не формул.
Hover не меняет selection/осмотр. Клик исполняет свежую команду с текущим состоянием.
Переход мыши прямо на панель сохраняет результат для прокрутки; выход из неё или
уход с поля в другое место очищает его. Смена режима/выбора, receipt, reset, смена сцены, смерть и блокировка
не оставляют устаревшего прогноза. Пересчёт допустим при refresh/смене клетки,
но не каждый кадр неподвижного hover. Refresh сбрасывает кэш также при изменении
состояния вне revision. Реальные сущности сохраняют ENTITIES Y-sort.

Закреплённая панель описывает осматриваемого врага, иначе выбранного союзника;
при A-hover временно показывает цель. Поля: HP, накопленная потеря равновесия,
движение/main/bonus, броня, базовое оружие и его урон, текущая атака, эффекты.
Эффекты читаются из runtime, без hardcoded проверки номера персонажа; действие,
величина и срок активности понятны, технический источник по умолчанию скрыт.
Неизвестные эффекты обозначаются как неизвестные, не пропускаются молча.

Проверки ведущего: import/startup; headless parity полных snapshot/receipt/RNG/
counters с реальным исполнением; repeated no-mutation, stale/locked/friendly,
нет main, недосягаемость, предметное лечение после всего каскада и lethal,
collateral союзник, толчок в стену/void/с уступа, queue limits/busy/fault,
неклонируемый RNG, изоляция определений/DTO и cleanup. Затем весь core и demo/battle
runner; viewport hover/exit/selection/phase/reset и PNG, независимое review.


## Призванные участники (2026-09-15)

[SUMMON_ITEM.md](SUMMON_ITEM.md) добавляет item snapshot v3 с use_summon,
зарядами и metadata владельца/ожидания первого хода. AttackForecast сохраняет
полную доску с helpers, их предметных владельцев и admission rules копии контекста.
Заряд печати не расходуется атакой. Совпадение полного snapshot, receipts,
counters/RNG проверяется для атак с pending/готовым helper, включая атаку на
него. Прогноза призыва нет. Unit snapshot v3 стойки не меняется.

## Новая броня D2

Профиль armor_spatial_v1 исполняется тем же forecast. Unit/ItemSimulation v4
переносят E, перки/сопротивления, a_i/ключи экземпляров; CombatRng клонируется.
В units добавлены armor_state, armor_current, armor_max только для новой capability.
События armor_changed/hit_resolved дают фактический расход и по типам D/защиты/
HP-damage/healing; старые damaged/healed отражают net HP. Панель и синяя полоса
читают эти значения без своей формулы. Завершение боя и истечение E также
исполняются очередью на копии; внешние callbacks по-прежнему не копируются.
Полный контракт и ограничения — [ARMOR_DAMAGE_D2](ARMOR_DAMAGE_D2.md).

## Кровотечение D3

Unit v5 переносит BleedingState внутри ItemSimulation v4. Поле units.before/after
`bleeding` содержит значения состояния. Допуск прямого hit (physical HP-damage
до лечения или явный bypass) виден в hit_resolved; результат наложения — в
bleeding_changed и шаге bleeding_apply, включая SKIPPED по иммунитету/смерти/gate.
Прогноз включает spatial → статус → item reactions; будущие ходы и их тики
не моделируются этим API. Изоляция и parity тиков проверяются отдельно через
настоящую BleedingTurnCommand на восстановленной копии. [Пакет D3](BLEEDING_D3.md).

## Среда D5

ItemSimulation v5 переносит огненные клетки, тела, их ID и обработанные смерти.
При нестандартном определении печати [M1](SUMMON_DEFINITION_M1.md) использует
ItemSimulation v6: все stats/параметры имени, включая неиспользованную печать,
копируются и проверяются тем же codec. Forecast исполняет прежнюю команду атаки;
нестандартный шаблон не включает armor capability у старого призыва.
Толчок в огонь исполняет тот же EnvironmentCommand/ArmorHitExecutor на копии;
события fire hit и corpse_created видны в прогнозе. Состав среды включён в
snapshot_before/after и проверку live isolation. Прогноза движения и поднятия
тела этот API не добавляет. Правила транзита и потребления — [D5](ENVIRONMENT_D5.md).
