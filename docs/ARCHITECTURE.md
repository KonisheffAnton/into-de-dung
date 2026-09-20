# Текущая архитектура intoDeDung

Сверено с кодом на `dcac6da4afb0d3583db79409c8f2fe1f06593968`, 2026-09-20.
После этой сверки меняется только документация. Этот файл описывает реализацию;
направление разработки находится в [DESIGN_DIRECTION](DESIGN_DIRECTION.md).

## Рабочий срез

Есть законченный сценарий боя 3v3 с ИИ, командными ходами и свободным выбором своих
без пополнения ресурсов. Движение, main и bonus разделены; атака стоит 1 main.
Работают высота, равновесие, толчки, столкновения/падения, осмотр, прогноз атаки,
охранная стойка, флакон и призыв помощников. Точное поведение — [TACTICAL_BATTLE](TACTICAL_BATTLE.md)
и специализированные контракты из [индекса](PROJECT_CONTEXT.md).

Это один тактический бой. Хаба, полного забега, профиля мага, новой расходуемой
брони, двух ветвей сопротивлений, общего движка статусов/клеток и модели нескольких
трупов на клетке пока нет. Плейтест последнего боя остаётся открытым.

## Владельцы данных и поведения

| Область | Фактический владелец / вход | Граница |
|---|---|---|
| Геометрия и позиции | `scripts/core/board/battle_board.gd` | Terrain, высоты, occupancy, реестр живых и мёртвых; provider для поиска пути |
| Параметры | `scripts/core/stats/` | StatsBag/Stat/StatModifier; `(base + sum(flat)) * (1 + sum(percent)) * product(multiply)` |
| Текущие ресурсы | `units/vitals.gd`, `actions/action_resources.gd` под `scripts/core/` | HP, накопленный impact до порога balance; остатки движения/main/bonus отдельно от maxima |
| Предметы | `scripts/core/items/`, `scripts/core/inventory/` | Def/Instance/EffectRuntime, один ItemOwnerState и его фасады |
| Команды и последствия | `scripts/core/actions/action_queue.gd`, `action_context.gd` в той же папке | Submit, admission, оплата, обязательные последствия и реакции; подробности в контракте очереди |
| Прогноз | `scripts/core/actions/attack_forecast.gd` | Настоящая AttackCommand на изолированных state/context/queue/RNG; не общий forecast всех действий |
| Командный ход и исход | `scripts/demo/battle_tactical_session.gd`, `battle_demo_session.gd`, `battle_turn_refill.gd` | Управление игроком/врагом, refill, динамический состав, reset/cleanup |
| Нынешний ИИ | `scripts/demo/battle_demo_bt.gd` | BT выбирает BattleAIIntent; исполнение через команды. Старый Utility AI остаётся в `scripts/core/ai/` |
| Представление | `scripts/demo/battle_demo.gd`, `battle_demo_iso_visual.gd`, `battle_action_bar.gd` | Ввод/UI; общий ENTITIES Y-sort реальных тайлов, стен и фигур |

Отдельного готового `scripts/core/flow/BattleFlowStateMachine` нет: фактический
владелец текущего flow — demo session. `core/initiative/` содержит legacy-механику,
но инициатива не управляет нынешним боем. Наличие файла не означает его использование.

## Границы расширяемости

- AttackCommand считает `STRENGTH + WEAPON_DAMAGE`, высоту, вычет ARMOR и стойку
  внутри команды. Legacy `combat/damage_calculator.gd` содержит отдельный расчёт.
  Далее передаётся DamageRequest с bypass, поскольку броня уже применена.
- AttackDefinition/AttackRules знают id/profile и три нынешних профиля;
  это не готовый конвейер произвольных типизированных компонентов урона.
- Vitals хранит HP и balance, но не текущую прочность брони. ARMOR сейчас — stat.
- ItemDef имеет специальные use_heal_amount/use_summon; параметры помощника
  задаются в UseSummoningItemCommand. Общий контракт применения ещё не выделен.
- Снимки проверяют точные схемы и поддерживаемые виды данных. Диапазон stat IDs
  0..10 проверяется в StatsBag, ItemOwnerState и SimulationSnapshot; одного нового
  значения enum недостаточно для расширения. Боевой snapshot не равен save-game.
- Мёртвый UnitState остаётся в реестре без живой occupancy. Это не готовый CorpseState.

Инварианты и обоснования — [DECISIONS](DECISIONS.md); API/пакеты исполнения —
[COMMAND_ACTION_QUEUE_CONTRACT](COMMAND_ACTION_QUEUE_CONTRACT.md).
Запуск и текущая главная сцена — [REPOSITORY_STATE](REPOSITORY_STATE.md).
Прежняя архитектурная хронология сохранена в [архиве](ARCHITECTURE.history-20260920.md).
