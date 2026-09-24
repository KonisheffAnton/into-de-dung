# Текущая архитектура intoDeDung

Базовая сверка: `dcac6da4afb0d3583db79409c8f2fe1f06593968`, 2026-09-20;
расчёт прямого удара обновлён этапом [D1](ATTACK_DAMAGE_D1.md), новый отдельный профиль брони — [D2](ARMOR_DAMAGE_D2.md), 2026-09-21. Этот файл описывает реализацию;
направление разработки находится в [DESIGN_DIRECTION](DESIGN_DIRECTION.md).

## Рабочий срез

Есть законченный сценарий боя 3v3 с ИИ, командными ходами и свободным выбором своих
без пополнения ресурсов. Движение, main и bonus разделены; атака стоит 1 main.
Работают высота, равновесие, толчки, столкновения/падения, осмотр, прогноз атаки,
охранная стойка, флакон и призыв помощников, прогноз двух применений M3 (K3). Точное поведение — [TACTICAL_BATTLE](TACTICAL_BATTLE.md)
и специализированные контракты из [индекса](PROJECT_CONTEXT.md).

Это один тактический бой. Новая расходуемая броня с двумя ветвями сопротивлений
доступна в K2 и D4; 2026-09-21 пользователь сообщил, что тест брони ок.
Первый ограниченный цикл подготовки и забега описан в [D4](EXPEDITION_D4.md).
Первый сценарий среды и нескольких тел на клетке описан в [D5](ENVIRONMENT_D5.md).
Поведение крита/спины и контроля описано в [C1](CRITICAL_BACKSTAB_C1.md).
Общий игровой сценарий [K2](CORE_READINESS.md#k2--общий-игровой-сценарий-c1d3d5)
соединяет C1 с D3/D5 через `BattleCoreCombinationSession`; ядро команд не меняется.
K2 — основной вход F5. Отдельные сцены D2/D3/D5/C1 перенесены в
`tests/fixtures/demo/`; их сессии сохранены как зависимости K2/D4 и регрессии.
Старая сцена сетки и восемь debug-визуализаторов удалены; LegacyItemDemoSink
остаётся зависимостью frozen-тестов. Уникальные игровые входы — [запуск](REPOSITORY_STATE.md).
Отдельное [сравнение порядка ходов](INITIATIVE_COMPARISON.md) добавляет инициативу
только в экспериментальную session; основной бой остаётся командным.
Профиля мага с метахарактеристиками и общего движка статусов/клеток пока нет.

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
| Прогноз | `AttackForecast`, `ItemUseForecast`, `ForecastSimulation` в `scripts/core/actions/` | Настоящие атака и две команды M3 на изолированных state/context/queue/RNG; общий helper изоляции, отдельный DTO нового помощника; не forecast произвольных действий |
| Командный ход и исход | `scripts/demo/battle_tactical_session.gd`, `battle_demo_session.gd`, `battle_turn_refill.gd` | Управление игроком/врагом, refill, динамический состав, reset/cleanup |
| Совместный сценарий C1/D3/D5 | `BattleCoreCombinationSession`, `core_combination_battle.tscn` | Истечение контроля исходящей команды → унаследованный D3 tick входящей → исход → refill; терминальный результат останавливает переход |
| Сравнение темпа ходов | `BattleInitiativeSession`, `BattleInitiativeDemo` | Одинаковый бой в двух режимах; собственный ход/очередь только в эксперименте |
| Нынешний ИИ | `scripts/demo/battle_demo_bt.gd` | BT выбирает BattleAIIntent; исполнение через команды. Старый Utility AI остаётся в `scripts/core/ai/` |
| Представление | `scripts/demo/battle_demo.gd`, `battle_demo_iso_visual.gd`, `battle_action_bar.gd` | Ввод/UI; общий ENTITIES Y-sort реальных тайлов, стен и фигур |

BattleDemo перенаправляет колесо над текущей целью в прокрутку диагностической
панели прогноза; это только UI, без нового вызова preview/команды. Контракт ввода
и очистки — [ATTACK_FORECAST](ATTACK_FORECAST.md#ui-и-приёмка).
Возврат в движение после действия/отказа по цели также принадлежит BattleDemo,
без изменения оплаты/выбора в сессии; [управление](TACTICAL_BATTLE.md).
BattleDemoBoard включает существующую стрелку тыла для C1 и K2, в том числе
помощников без ControlState; направление остаётся у AttackModifiers.

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
рюкзаком D4. Полная экономика, выбор состава и метакомната ещё не реализованы.

## Опасная клетка и поднятие тела — D5

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
Предметный призыв старого сценария не изменён. D4 не читает D5 и сохраняет свой формат.
