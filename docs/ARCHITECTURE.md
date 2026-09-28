# Текущая архитектура intoDeDung

Базовая сверка: `dcac6da4afb0d3583db79409c8f2fe1f06593968`, 2026-09-20;
расчёт прямого удара обновлён этапом [D1](ATTACK_DAMAGE_D1.md), новый отдельный профиль брони — [D2](ARMOR_DAMAGE_D2.md), 2026-09-21. Этот файл описывает реализацию;
направление разработки находится в [DESIGN_DIRECTION](DESIGN_DIRECTION.md).

## Рабочий срез

[K17](STATUS_EFFECTS_NEXT.md) включает конечные состояния bleeding/burning/wet/freeze
в основном бою и у помощников. Unit8/ElementalState и bleeding3 изолируют новый
профиль от legacy; Environment3 задаёт физические шипы и горящие клетки.
Схемы Board/Item/D4 прежние. SpatialRules охраняет новые ссылки и значения;
ArmorHitExecutor и admission используют одинаковое добивание замороженного
по gross HP damage. ElementalCastCommand/внутренние тики исполняются очередью,
ForecastSimulation и оба worker сохраняют то же состояние/порядок.
ControlRules блокирует действия/угрозы замороженного; крит frozen распространяется
и на реакции K12, сохраняя исключения обычного контроля у реакций.

[K14](SAFE_RETREAT_K14.md) добавляет `safe_retreat` в MoveCommand: тот же путь,
continuation и очередь последствий, без перехвата Оппортуниста. Первый сегмент
оплачивает main внутри прежнего spatial guard; события строго проверяет ActionQueue.
Вид команды переносится copy/preview, не хранится в состоянии бойца. Общий UI
выбирает действие; MoveForecastWorker и BattleExecutionWorker исполняют его
изолированно и в live соответственно. Save-схемы и выбор намерений ИИ прежние.

[K12](COUNTERATTACK_K12.md) добавляет отдельный перк/режим контратаки с общим
зарядом K10. ActionQueue ставит один внутренний AttackCommand после полного
исходного каскада и реакций вещей; проверяет текущую допустимость, сохраняет
guards/FAULTED prefix и не строит цепь ответов. Counter-hit сохраняет стойку,
не ставит остановку движения и использует прежний pipeline без impact/push.
Крит обычного контроля отключён; исключение заморозки задаёт K17.
Вложенная perk schema3 нужна только counterattack; прежние schema1/2 формы
остаются точными. Forecast и эксклюзивный live worker исполняют тот же хвост.

[K11](CONTROL_PACKAGE_K11.md) добавляет перковый оглушающий удар и независимые
иммунитеты к путам/оглушению. ControlApplyCommand объединяет два конечных
наложения: sealed gate прямого HP-hit → пространственные последствия → контроль
→ реакции предметов. ControlState и Unit schema7 прежние; CombatPerksState
пишет вложенную schema2 только для новых флагов, иначе сохраняет schema1.
BT передаёт ID выбранной атаки, команды проверяют владение и исполняют её.

[K10](CORE_REACTIONS_K10.md) расширяет общий бой перками: скрытая атака,
Оппортунист и Прикрытие. CombatPerksDefinition задаёт способности, nullable
CombatPerksState хранит состояние участника в Unit schema7. MeleeThreat читает
общую AttackReachCheck; GuardCommand выбирает режим, AttackCommand/AttackHit
исполняют обычный или внутренний реакционный удар, MoveCommand перехватывает
до шага. Прикрытие меняет входные дроби ArmorAttack до D0. Дельты перков
проверяют SpatialRules и малый CombatPerkGuard очереди; preview переносит их
штатным ForecastSimulation. Общего runtime произвольных статусов не добавлено.

[K9](CORE_BATTLE_BATCH_K9.md) включает расстановку в K2 до командного боя,
печать в составе брони/среды и прогноз RestoreArmorCommand общим ForecastSimulation.
Session владеет фазой подготовки и включением призыва в конкретный сценарий;
команды/Board/snapshot сохраняют владение исполнением и состоянием.

Есть законченный сценарий боя 3v3 с ИИ, командными ходами и свободным выбором своих
без пополнения ресурсов. Движение, main и bonus разделены; атака стоит 1 main.
Работают высота, равновесие, толчки, столкновения/падения, осмотр, прогноз атаки,
охранная стойка, флакон и призыв помощников, прогноз двух применений M3 (K3),
движения (K4), поднятия тела (K5), самой стойки (K6) и восстановления брони (K9). Точное поведение — [TACTICAL_BATTLE](TACTICAL_BATTLE.md)
и специализированные контракты из [индекса](PROJECT_CONTEXT.md).

Это один тактический бой. Новая расходуемая броня с двумя ветвями сопротивлений
доступна в K2 и D4; 2026-09-21 пользователь сообщил, что тест брони ок.
Первый ограниченный цикл подготовки и забега описан в [D4](EXPEDITION_D4.md).
Первый сценарий среды и нескольких тел на клетке описан в [D5](ENVIRONMENT_D5.md).
Поведение крита/спины и контроля описано в [C1](CRITICAL_BACKSTAB_C1.md).
Общий игровой сценарий [K2](CORE_READINESS.md#k2--общий-игровой-сценарий-c1d3d5)
соединяет C1 с D3/D5 через `BattleCoreCombinationSession`; K7 добавляет Бору
каталоговый клинок M4 через штатную экипировку до боевого lock. Урон оружия
остаётся 4; источник бонуса — предмет. [Контракт K7](ARMOR_PIERCING_M4.md#k7--клинок-в-общем-бою-ядра).
K8 добавляет [наложение пут](ENTANGLE_ATTACK_K8.md): явный флаг определения,
внутренний `EntangleApplyCommand` после spatial-последствий и до реакций предметов.
Admission, sealed binding, guard и валидатор очереди сохраняют отказ без оплаты
и FAULTED prefix; прогноз исполняет ту же атаку. Профиль забега D4 не меняется.
K10–K12 (BattleCoreReactionsSession, наследник K9/K2) — основной вход F5.
Старая сцена K2 сохраняет C1-спину для регрессии. Отдельные сцены D2/D3/D5/C1 перенесены в
`tests/fixtures/demo/`; их сессии сохранены как зависимости K2/D4 и регрессии.
Старая сцена сетки и восемь debug-визуализаторов удалены; LegacyItemDemoSink
остаётся зависимостью frozen-тестов. Уникальные игровые входы — [запуск](REPOSITORY_STATE.md).
Отдельное [сравнение порядка ходов](INITIATIVE_COMPARISON.md) добавляет инициативу
только в экспериментальную session; основной бой остаётся командным.
Профиля мага с метахарактеристиками и общего движка статусов/клеток пока нет.

## Маг и откаты — K18

[Маг и откаты](MAGE_COOLDOWNS_K18.md) реализован в основном командном бою.
`ItemSimulationState.abilities` владеет отдельным `BattleAbilityState`:
каталогом значений, маной, ledger и часами; без capability остаётся legacy codec.
`MageCastCommand` оплачивает отдельный ресурс и использует общую очередь/броню/HP.
`AbilityBoundaryCommand` проводит часы через закрытый переход session;
SpatialRules и queue проверяют значения и identity нового графа.
Schema7, ForecastSimulation, TurnForecast и оба worker переносят capability;
две кнопки и показатели мага находятся отдельно от действий героев.
Точные правила, ограничения и критерии принадлежат K18; приёмка F5 открыта.

## Владельцы данных и поведения

| Область | Фактический владелец / вход | Граница |
|---|---|---|
| Геометрия и позиции | `scripts/core/board/battle_board.gd` | Terrain, высоты, occupancy, реестр живых и мёртвых; provider для поиска пути |
| Проход союзников | `pathfinding/grid_pathfinder.gd`, `actions/move_command.gd` под `scripts/core/` | Транзит через союзников, остановка на свободной клетке; provider от доски, [контракт](ALLY_TRANSIT.md) |
| Параметры | `scripts/core/stats/` | StatsBag/Stat/StatModifier; `(base + sum(flat)) * (1 + sum(percent)) * product(multiply)` |
| Текущие ресурсы | `units/vitals.gd`, `actions/action_resources.gd` под `scripts/core/` | HP, накопленный impact до порога balance; остатки движения/main/bonus отдельно от maxima |
| Предметы | `scripts/core/items/`, `scripts/core/inventory/` | Def/Instance/EffectRuntime, один ItemOwnerState и его фасады |
| Применение предмета | `ItemUseAction`, две команды UseHealingItem/UseSummoningItem | Производное описание цели/параметров/цены и factory; окончательный допуск/оплата у команд, [M3](ITEM_USE_M3.md) |
| Команды и последствия | `scripts/core/actions/action_queue.gd`, `action_context.gd` в той же папке | Submit, admission, оплата, обязательные последствия и реакции; подробности в контракте очереди |
| Расчёт прямого удара | `scripts/core/combat/attack_damage_calculation.gd` | Чистые числа и стадии нынешней формулы; AttackCommand владеет допуском и применением, контракт D1 |
| Спина / крит / контроль | `AttackModifiers`, `ControlState`, `ControlRules`, `BattleControlSession` | Явные опции определения атаки, runtime состояния; контракт C1 |
| Пробивание оружием | `StatTypes`, `AttackCommand`, `ArmorAttack` | Предметный stat → разделение физической базы по политикам D2; [M4](ARMOR_PIERCING_M4.md) |
| Прогноз | `AttackForecast`, `ItemUseForecast`, `MoveForecast`, `RaiseCorpseForecast`, `GuardForecast`, `ForecastSimulation` в `scripts/core/actions/` | Атака, две M3, движение, поднятие и стойка на изолированных state/context/queue/RNG; только движение выдаёт готовый INTERRUPTED и фактический путь. Отдельные DTO, закрытый список команд; [контракт](ATTACK_FORECAST.md) |
| Командный ход и исход | `scripts/demo/battle_tactical_session.gd`, `battle_demo_session.gd`, `battle_turn_refill.gd` | Управление игроком/врагом, refill, динамический состав, reset/cleanup |
| Совместный сценарий C1/M4/D3/D5 | `BattleCoreCombinationSession`, `core_combination_battle.tscn` | Клинок через штатную экипировку; истечение контроля исходящей команды → унаследованный D3 tick входящей → исход → refill; терминальный результат останавливает переход |
| Сравнение темпа ходов | `BattleInitiativeSession`, `BattleInitiativeDemo` | Одинаковый бой в двух режимах; собственный ход/очередь только в эксперименте |
| Нынешний ИИ | `scripts/demo/battle_demo_bt.gd` | BT выбирает BattleAIIntent; исполнение через команды. Старый Utility AI остаётся в `scripts/core/ai/` |
| Представление | `scripts/demo/battle_demo.gd`, `battle_demo_iso_visual.gd`, `battle_action_bar.gd` | Ввод/UI; общий ENTITIES Y-sort реальных тайлов, стен и фигур |

BattleDemo перенаправляет колесо над текущей целью в прокрутку диагностической
панели прогноза; это только UI, без нового вызова preview/команды. Контракт ввода
и очистки — [ATTACK_FORECAST](ATTACK_FORECAST.md#ui-и-приёмка).
Возврат в движение после действия/отказа по цели также принадлежит BattleDemo,
без изменения оплаты/выбора в сессии; [управление](TACTICAL_BATTLE.md).
В командном бою клик атаки по живому союзнику идёт сразу в обычный выбор UI,
очищая прежний прогноз до нового запроса; отклонённая команда не создаётся.
BattleDemoBoard включает существующую стрелку тыла для C1 и K2, в том числе
помощников без ControlState; направление остаётся у AttackModifiers.
Hover движения использует один MoveForecastWorker: основной поток готовит
изолированный ForecastSimulation.Prepared, worker восстанавливает его и исполняет
команду, UI принимает только актуальное поколение. В worker нет session/узлов UI;
hover обновляет прежние визуалы без rebuild доски. До завершения расчёта UI сразу
показывает пунктир штатного path_to для доступной клетки; это запрос, а не итог.
Готовый результат заменяет его фактически пройденным участком. Порядок отмены и границы RNG —
[ATTACK_FORECAST §K4](ATTACK_FORECAST.md#k4--прогноз-движения).
Hover атаки аналогично использует один AttackForecastWorker и одноразовый
Prepared; обычный удар/руна/путы входят в ключ запроса. UI показывает ожидание,
сбрасывает устаревшие результаты и не ждёт расчёта при клике. Заголовок ожидания
и результата использует actor/target ID этого запроса и общую очистку прогноза,
без отдельного кэша имён или мира. Синхронные API
сохранены; контракт — [ATTACK_FORECAST](ATTACK_FORECAST.md#ui-и-приёмка).
Остальные реализованные прогнозы действий обслуживает один ActionForecastWorker
с тем же Prepared и проверкой поколения; UI/BT availability hints не выполняют
снимок всего мира. Они не заменяют строгую авторизацию команды или preview.
Границу командного хода обслуживает `TurnForecastWorker`: `TurnForecast.Prepared`
содержит изолированный snapshot/definitions/context/queue и значения сессии.
В worker оболочка общего боя создаётся без reset, подключает восстановленное
состояние и исполняет настоящий `end_player_turn()` до первого решения ИИ.
Внутренний `_record_receipt` после каждого submit собирает trace лишь в копии;
в live это no-op. Формулы перехода остаются у сессии и команд. Контракт —
[ATTACK_FORECAST §K13](ATTACK_FORECAST.md#k13--прогноз-завершения-командного-хода).
Основной общий бой передаёт session в эксклюзивное владение BattleExecutionWorker;
UI держит value projection и принимает результат после join. Внешние callbacks
и остальные session сохраняют синхронный путь. Контракт владения/публикации —
[BATTLE_EXECUTION_UI](BATTLE_EXECUTION_UI.md); прогнозы — ATTACK_FORECAST,
API предметных подсказок — ITEM_USE_M3, поднятия — D5.
Призыв/поднятие строят ожидаемый checkpoint через SummonMutationProjection из
снимка до действия и того же нового помощника. Полный clone боя для этой проверки
не создаётся; после callback сравнивается весь снимок, admission, RNG/counters и
прежние identity. Прогноз продолжает исполнять настоящую команду в изоляции.
SpatialRules.Guard хранит capture-only копии валидного canonical stats DTO и
выбранных значений. При совпадении обеих частей он не десериализует StatsBag
заново; при изменении работает прежний clone/selected-stat check. Copy переносит
кэш, seal его не обновляет. Это сохраняет допустимые изменения невыбранных
статов, проверки callbacks и FAULTED prefix без записи в live-кэш характеристик.
Поднятие K5 использует тот же изолированный executor и отдельный DTO с изменением
тела/появлением помощника. BattleEnvironmentSession выбирает тело одинаково для
preview/live, BattleDemo показывает текстовый результат; правила остаются у
RaiseCorpseCommand/D5. Контракт — [ATTACK_FORECAST §K5](ATTACK_FORECAST.md#k5--прогноз-поднятия-тела).
GuardForecast K6 исполняет GuardCommand тем же executor и показывает расход/стойку
в отдельном DTO; session сохраняет guard_reason, UI — немедленный клик/клавишу 2.
Контракт — [ATTACK_FORECAST §K6](ATTACK_FORECAST.md#k6--прогноз-охранной-стойки).

Отдельного готового `scripts/core/flow/BattleFlowStateMachine` нет: фактический
владелец текущего flow — demo session. Из `core/initiative/` отдельный эксперимент
использует SimpleInitiativeStrategy; InitiativeTimeline не управляет этим flow.

## Границы расширяемости

- StatsBag/StatModifier уже поддерживают числовые прибавки/проценты/множители
  и снятие по source_id. StatModifierEffect подключает их через предметы.
  Общего runtime временных статусов с ID, сроком и политикой повторного наложения
  пока нет: BleedingState и ControlState — специальные реализации. Изменение
  максимума движения само по себе не определяет изменение его текущего остатка.
- AttackCommand получает `STRENGTH + WEAPON_DAMAGE`, высоту, вычет ARMOR и стойку
  из чистого AttackDamageCalculation ([D1](ATTACK_DAMAGE_D1.md)). Legacy `combat/damage_calculator.gd` содержит отдельный расчёт.
  Далее передаётся DamageRequest с bypass, поскольку броня уже применена.
- AttackDefinition/AttackRules сохраняют три legacy-профиля и добавляют armor_spatial_v1 с проверенными рациональными компонентами physical/fire. Новые операции требуют явной поддержки.
- Vitals хранит HP/balance. Новая ArmorState хранит естественные защиты, перки и E; a_i и ключ создания принадлежат ItemInstance, A_i/сопротивления — ItemDef. Legacy ARMOR остаётся stat.
- ItemDef имеет специальные use_heal_amount/use_summon и SummonDefinition:
  [M1](SUMMON_DEFINITION_M1.md) задаёт базовые stats/имя, фиксирует копию печати
  в ItemOwnerState и переносит нестандартный шаблон в ItemSimulation v6.
  [M3](ITEM_USE_M3.md) даёт общее типизированное описание применения и factory
  двух прежних команд; use_* остаются сериализованным источником, schemas прежние.
- Снимки проверяют точные схемы и поддерживаемые виды данных. Raw stat IDs
  проверяются через `StatTypes.is_valid_id` в StatsBag, ItemOwnerState и
  SimulationSnapshot; M4 добавил ID 11. Новому stat нужны правила потребителя
  и проверки runtime/снимков. Боевой snapshot не равен save-game.
  Успешный raw graph проходит быстрый валидатор без построения путей ошибок;
  при отказе исходный обход сохраняет диагностику и её порядок. UnitState
  проверяет итоговый armor/control DTO один раз, HP_MAX восстанавливает через
  тот же Stat codec после полной проверки StatsBag. Долгоживущего кэша снимков нет.
  ItemSimulationSnapshot.capture использует локальный проверенный board DTO без
  промежуточной копии и повторной проверки его envelope. Общие raw-лимиты/связи
  остаются; from_dict/instantiate всегда проверяют доску заново. Копирование
  рекурсивно только для контейнеров и сохраняет прежние типы значений/изоляцию.
- Мёртвый UnitState остаётся в реестре без живой occupancy. Это не готовый CorpseState.

Инварианты и обоснования — [DECISIONS](DECISIONS.md); API/пакеты исполнения —
[COMMAND_ACTION_QUEUE_CONTRACT](COMMAND_ACTION_QUEUE_CONTRACT.md).
Запуск и текущая главная сцена — [REPOSITORY_STATE](REPOSITORY_STATE.md).
Прежняя архитектурная хронология сохранена в [архиве](ARCHITECTURE.history-20260920.md).

## Первый срез новой брони — D2

BattleArmorSession — основа последующих сессий и отдельного тестового fixture D2.
ArmorFraction/ArmorHitCalculation считают точные числа; ArmorRuntime собирает вещи
и план расхода с клоном CombatRng. ArmorHitExecutor применяет E → условный RNG
commit → a_i → один HP через расширенный SpatialRules.Guard. Collision/fall
получают отдельные hit с будущими запасами; явная смерть не проходит через броню.
RestoreArmorCommand и ArmorRecovery восстанавливают по недостаче; избыток в бою — E.
ArmorEndBattleCommand удаляет временный E в общей очереди, поэтому terminal forecast
совпадает с live. Unit v4/ItemSimulation v4 сохраняют новую capability; legacy bytes
прежние. Призыв в новом сценарии отключён явно; хаб остаётся будущим.
Точные DTO, checkpoints, совместимость и границы — [ARMOR_DAMAGE_D2](ARMOR_DAMAGE_D2.md).

## Одно состояние — D3

BattleBleedingSession — основа D4/D5 и отдельного тестового fixture D3.
BleedingState принадлежит UnitState; Unit v5 сохраняет его вместе с бронёй,
ItemSimulation остаётся v4. AttackDefinition явно выбирает physical_hp или
bypass_hp_gate. AttackHit сохраняет допуск своего прямого hit до лечения;
BleedingApplyCommand исполняется после spatial, перед отложенными item reactions.
Повторное наложение накапливает срок; BleedingState использует прежний v1 для
0..2 тиков и v2 для большего остатка, сохраняя legacy bytes. Очередь проверяет
точное прибавление. Unit/ItemSimulation оболочки прежние.
BleedingTurnCommand создаёт тики по ID в начале хода команды перед refill;
BleedingTickCommand уменьшает срок и исполняет ArmorHitExecutor (physical,
hp_only_natural). Guard проверяет значения и identity состояния; tick не рекурсивен.
Forecast и UI показывают срок/иммунитет/допуск. Это один статус, не общий движок
всех состояний. Точное поведение и границы — [BLEEDING_D3](BLEEDING_D3.md).

## Первый цикл забега — D4

`scripts/core/run/d4_run_state.gd` хранит постоянный реестр предметов, HP трёх
персонажей, фазу/номер боя, материалы и отдельный RNG потерь. Склад/рюкзаки
пассивны. `D4Catalog` создаёт определения предметов, включая клинок [M4](ARMOR_PIERCING_M4.md). `D4BattleSession`
строит новый D3-совместимый бой только из надетого и связывает экземпляры с
ID забега. После полного исхода возвращает HP/износ; snapshots боя не меняются.
`D4Expedition` ведёт подготовку, сбор добычи, отправку и результат. `D4RunStore`
сохраняет проверенную копию до публикации перехода, с checksum и заменой файла.
Сохраняются границы этапов и начало текущего боя, не середина хода.
Нынешний `InventoryState` сохраняет legacy-семантику активации; он не является
рюкзаком D4. Полная экономика ещё не реализована. Выбор постоянного состава,
рост, владение, worker/preview, исходы и отдельное сохранение первого хаба —
[HERO_HUB_H1](HERO_HUB_H1.md); формат D4 не расширяется.

## Цепное отталкивание — K16

В общем бою обычные ARMOR_PROFILE определения включают `chain_push`; другие
режимы и reaction strikes сохраняют прежний путь. `PushChainRules` до оплаты
собирает осевой план и всех достигнутых участников/клетки в SpatialRules.Guard,
проверяет точные дроби и будущие A/HP/RNG/board touches. `PushChainCommand`
исполняет проверки balance, пары столкновений и финальный PushCommand вложенными
mandatory-командами. Это сохраняет переданный импульс при смерти промежуточного
и удерживает среду после пространственного поддерева; item reactions отложены
до его конца, контратака рассматривается один раз. Каждый hit переносит известную
дельту guard; FAULTED сохраняет prefix. Save-схемы не изменены. Полные правила,
затухание и границы — [PUSH_CHAIN_K16](PUSH_CHAIN_K16.md).

## Опасная клетка и поднятие тела — D5

K15 добавляет основному `BattleCoreReactionsSession` фазу после обеих команд:
порядок враги → игрок → окружение; hook `_after_team_end` после ControlTurnEnd
игрока, до bleed/refill врагов. `_first_team` задаёт старт и границу номера раунда;
K2/отдельные режимы сохраняют игрока первым. Старт из расстановки не делает refill.
CollapsePhaseCommand фиксирует случайную новую отметку и порождает обрушение
прежней; CollapseCellCommand меняет terrain через Board и порождает guarded
DeathCommand. Исход проверяется после drain, FAULTED сохраняет prefix.
CombatEnvironmentState v2 хранит ход/отметку; отсутствие capability сохраняет
v1. Preview исполняет тот же корень через ForecastSimulation/worker, а UI
хранит копию отметок. Точные правила и границы — [K15](ENVIRONMENT_COLLAPSE_K15.md).

BattleEnvironmentSession расширяет D3 и служит основой K2; отдельная сцена — fixture D5.
CombatEnvironmentState принадлежит ItemSimulationState: записи fire и corpses,
монотонные ID и обработанные смерти. Geometry/occupancy и Unit codecs прежние.
ActionQueue преобразует moved/died в внутренние EnvironmentCommand после
имеющихся обязательных потомков и до продолжения движения. Шипы вызывают
ArmorHitExecutor; тело создаётся один раз, не занимает клетку. SpatialRules.Guard
проверяет также identity и значения среды. ItemSimulation v5 переносит среду;
v1–v4 сохраняют прежнюю форму. M1 использует v6 при нестандартном определении
печати, сохраняя все поля среды. AttackForecast включает реальные последствия шипов.
С 2026-09-23 изменено только пользовательское название опасности; внутренние fire,
тип урона и снимки прежние. Эффекта горения нет — [контракт D5](ENVIRONMENT_D5.md).
RaiseCorpseCommand расходует тело и main, создаёт нового D2/D3-совместимого помощника
через прежние make_helper/SummonAdmission/register_summon_owner и командный refill.
Предметный призыв композиции K9 добавляет пустые armor/bleeding capabilities по
владельцу; legacy вызов без них прежний. Точные правила — SUMMON_ITEM. D4 не читает D5 и сохраняет свой формат.
