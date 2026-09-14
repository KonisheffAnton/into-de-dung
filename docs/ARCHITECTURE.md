> **Актуализация 2026-09-13:** рабочие правила Codex — `../AGENTS.md` и
> `CODEX_WORKFLOW.md`; краткая передача — `CODEX_HANDOFF.md`. Пользователь заменил
> инициативную очередность командными ходами со свободным выбором персонажей.
> Ниже сохранено описание прежней реализации; не переносить его правило инициативы
> в новый Battle Flow. BT — выбранное направление, ещё не реализовано.

# intoDeDung — Архитектурная документация

> Этот файл — источник правды по прогрессу проекта. Обновляется после
> каждого завершённого модуля. Если начинаешь новую чат-сессию — читай
> ТОЛЬКО этот файл (и при необходимости DECISIONS.md), чтобы восстановить
> контекст без повторного прохождения всей истории чата.

## О проекте
Кроссплатформенная (Mobile & PC) изометрическая пошаговая тактика в стиле
**Into the Breach** с роглайк-элементами (**The Binding of Isaac / Hades**).
Godot 4.7, GDScript (strictly typed), GL Compatibility renderer, Jolt Physics.

Разработка: PC-first engine (быстрая отладка), Mobile-first UX (unified
input, safe areas, крупные хитбоксы) с самого начала.

## Роль ассистента
Principal Game Architect / Lead Godot Developer. Работа СТРОГО пошаговая —
модуль за модулем из списка ниже, с подтверждением пользователя перед
переходом к следующему. Перед кодом — короткое объяснение архитектурного
решения. SOLID, Data/Logic отделены от View/Nodes, `Resource` для
предметов/перков/формул/способностей.

## ⚠️ Текущая фаза: Phase 0 — рефакторинг после аудита

**2026-09-11 проведён архитектурный аудит (см. `docs/AUDIT.md`).** Найдены
4 критических дефекта. Решение: **рефакторить, не переписывать** — все дефекты
имеют природу «не хватает слоя», а не «сделано неверно»; ~60% файлов остаются
почти без изменений.

Baseline-коммит до правок: `49bcbf2` (точка отката).

### Легенда статусов (P-1: `Implemented` ≠ `Done`)
- `Draft` — спроектировано, код не готов.
- `Implemented` — код есть, headless-прогон чист.
- `Verified` — есть unit-тесты и/или подтверждённая визуальная проверка.
- `⚠️ Defect` — содержит известный дефект из `AUDIT.md`.

### Статус модулей (пересмотрено аудитом)

| № | Модуль | Было | Реально | Дефекты |
|---|---|---|---|---|
| 1 | Universal Input & Grid System | ✅ Done | **Verified** | D-1.1..1.3, M-1..M-7 |
| 2 | Y-Sorting & Z-Ordering | ✅ Done | **Verified** | D-2.1..2.3 |
| 3 | Pathfinding | ✅ Done | **Verified** | D-3.1..3.6 |
| 4 | Modular Stats & Initiative | ✅ Done | **Verified** ✅ | C-2/D-4.1/4.2/4.5/4.6/4.7 закрыты; остались D-4.3, D-4.4, D-4.8 |
| 5 | Inventory / Equipment / Synergy | ✅ Done | **P03a: ownership реализован** | Две существующие def разделяются безопасно; P03b runtime snapshot/реакции и общий шаг 0.8 впереди; D-5.1..5.7 |
| 6 | Damage / Balance / Push Preview | ✅ Done | **Verified** ✅ | C-2/C-4/S-2/D-6.1/D-6.4 закрыты; D-6.2/6.3 частично (урон при коллизии — шаг 0.5); S-1, D-6.5 |
| 7 | Extensible Utility AI | ✅ Done | **Verified** ✅ | S-3б/в/г закрыты; остался S-3а (генераторы) |

Почему статусы понижены: модули 5/6/7 были помечены `Done` при «визуальная
проверка — TODO», то есть верифицированы только на «компилируется». Модуль 5
на момент аудита был сломан при выдаче одного предмета двум юнитам (C-3),
а модуль 6 портил данные при первом же уроне юниту с предметом (C-2).
Headless-прогон такое не выявляет. Подробности — `AUDIT.md` → P-1.

### Порядок модулей изменён (G-4)

`Command & Action Queue` перенесён **перед** `Battle Flow State Machine`:
Battle Flow и Tile Effects должны что-то исполнять, иначе они неизбежно начнут
мутировать состояние напрямую и очередь превратится в их рефакторинг.

| № | Модуль | Статус |
|---|---|---|
| 8 | Command & Action Queue *(был 10)* | Draft |
| 9 | Battle Flow State Machine *(был 8)* | Draft |
| 10 | Tile Effects & Status Engine *(был 9)* | Not started |
| 11 | Run State & Procedural Generation | Not started |
| 12 | Profile System & Meta-Progression | Not started |

## Новые требования к механикам — 2026-09-13
Пользователь хочет модульно добавлять пробивание брони, состояния персонажей и
эффекты клеток: поджигание, наложение состояний, урон и смерть.
Подробности и открытые правила — [MECHANICS_REQUIREMENTS.md](MECHANICS_REQUIREMENTS.md).
Учитывать при проектировании 0.5/0.6; это требования к расширению, не готовые модули
и не отмена поэтапного внедрения по R-7.

## План Phase 0 — путь к «уродливому вертикальному срезу»

Цель (R-7): рабочий цикл на квадратах-заглушках —
**игрок ходит → атакует → толкает → враг умирает → все мертвы → экран победы
→ выбор 1 предмета из 3 → новая карта, предмет работает.**

Каждый шаг обоснован не «так правильно», а «без этого срез не работает».
После каждого шага проект **запускается** и проверяем визуально.

| Шаг | Задача | Зачем для среза | Статус |
|---|---|---|---|
| 0.0 | `git init` + baseline | без этого нет отката при рефакторинге | ✅ `49bcbf2` |
| 0.1 | Аудит + правила в документации | фиксация решений | ✅ `997ae8d` |
| 0.2 | `UnitId` / `Faction` / `UnitState` | иначе нет понятия «кто игрок, кто враг» | ✅ `d71b49a` |
| 0.3 | `StatsBag` + `Vitals`, убрать HP/BALANCE из статов | иначе враг не может умереть (C-2) | ✅ `d71b49a` |
| 0.4 | `BattleBoard` (occupancy + hazards) | иначе push сквозь юнитов, нет толчка в пропасть (C-4) | ✅ |
| 0.5 | `Command` + `ActionQueue` (Move/Attack/Push) | иначе нечем исполнить ход | ⏳ P01 и P02 (board snapshot) реализованы; очередь впереди |
| 0.6 | Battle Flow SM (Player→Preview→Exec→Enemy→VictoryCheck) | это и есть цикл | ⏳ |
| 0.7 | `InputRouter` + Selection/Targeting | иначе нельзя выбрать и подтвердить действие (M-1) | ⏳ |
| 0.8 | `ItemDef`/`ItemInstance` (**один** предмет) | иначе выбор награды сломан (C-3) | ⏳ |
| 0.9 | Минимальный `RunState` + экран награды | замыкает петлю | ⏳ |
| 0.10 | `RngService` | детерминизм новой карты (G-1) | ⏳ |

Контракт 0.5 подготовлен как **предложение**; реализованы отдельные пакеты P01 и P02:
[COMMAND_ACTION_QUEUE_CONTRACT.md](COMMAND_ACTION_QUEUE_CONTRACT.md).
Он отделяет очередь последствий от командного Battle Flow 0.6; фиксирует три отдельных
ресурса (перемещение/основное/дополнительное), стоимость атаки 1 основное очко и открытые
уточнения. Для полного preview предложено перенести ограниченное исправление C-3
для влияющих предметов перед завершением 0.5; общая миграция 0.8 этим не объявляется готовой.
P01 обеспечивает однократный unit_died и автоматическую очистку occupancy через Vitals.died,
включая загруженных юнитов. P02 добавляет изолированный value-снимок stats/units/board,
сохраняет modifier occurrences/evaluation_order, occupancy/version и не меняет UnitId counter.
Только harness без предметов/внешнего runtime/AI-профилей; старые save API не меняются.
Регресс ведущего после P02 — 484 passed, 0 failed (156 прежних + 328 новых);
import/startup успешны. Итог независимого ревью — в CODEX_HANDOFF.md. Весь 0.5 не завершён.

**Отложено ДО работающего среза** (не трогать, чтобы не раздувать
неотлаженную систему — R-7): конвейер `DamageModifier` (хватит `base+STRENGTH`),
`Ability : Resource`, Tile Effects / Status Engine, процедурная генерация
(хватит 2-3 рукописных карт), Profile System, heap в pathfinder, пулинг,
локализация, data-driven слоты экипировки, второй предмет, второй тип врага.

Unit-тесты пишем **только на чистую детерминированную логику** (round-trip
координат, согласованность `find_path`/`get_reachable_cells`, конвейер `Stat`,
клампы `Vitals`, `PushResolver`) — там, где визуальная проверка бессильна.
На UI/флоу визуальная проверка эффективнее.

Подробности по каждому реализованному модулю — в `docs/modules/`.
Ключевые архитектурные решения и правила — в `docs/DECISIONS.md` (раздел `R-*`
имеет высший приоритет). Реестр дефектов — `docs/AUDIT.md`.
Как проверять проект (headless Godot) — в `docs/TESTING.md`.

## Быстрый старт для новой сессии
1. Прочитать этот файл целиком.
2. Прочитать `docs/DECISIONS.md` — раздел `R-*` (фундаментальные правила) обязателен.
3. Прочитать `docs/AUDIT.md` — что сломано и почему переделывается.
4. Открыть `scenes/test/test_grid_scene.tscn` — единая тестовая песочница.
5. Спросить пользователя: "Продолжаем с шага N Phase 0?" и следовать плану.

## Git-политика (P-7)
- По умолчанию ведущий фиксирует завершённый этап логическими коммитами без напоминания;
  явный запрет пользователя «не коммитить» имеет приоритет. Полные правила — AGENTS.md,
  раздел «Коммиты». Разные этапы/настройки разделяются, код/его тесты/контракты остаются вместе.
- Коммит при: **зелёный headless-прогон И (визуальная проверка ИЛИ зелёные тесты)**.
- Для содержательного кода обязательно ревью по AGENTS.md; для правок только текста/процесса
  достаточно проверки diff, без запуска Godot и отдельного ревьюера.
- Формат сообщений — Conventional Commits:
  `refactor(units): ...`, `fix(items): ...`, `feat(board): ...`, `test(pathfinding): ...`
- Рискованные шаги (0.3, 0.4, 0.8 — трогают много файлов) — в отдельной ветке,
  мердж после проверки. Откат = `git checkout main`.
- Если правка сломала рабочий код — **не чинить в 5 итераций, а откатываться**
  к последнему зелёному коммиту и заходить с другой стороны.
- TODO пользователю: создать private remote и пушить (локальный git не спасает
  от смерти диска).

## Хендофф между сессиями (правило)
В конце КАЖДОГО ответа ассистент указывает приблизительный процент заполнения
контекстного окна текущей сессии (оценка "на глаз", без точного инструмента),
чтобы пользователь мог вовремя перейти в новый чат до достижения лимита.
При приближении к ~80-90% — явно предупредить и напомнить обновить эти
файлы документации перед переходом в новую сессию.

## Структура репозитория
Порядок папок отражает **направление зависимостей** (R-3). Обратные
зависимости запрещены: `grid → board → units → combat → actions → ai → flow → view`.

```
scripts/
  core/                  <- чистая игровая логика, НЕ ссылается на автозагрузки (R-3)
    grid/                 <- IsoGridConfig, IsoGridUtils                  [M1]
    rendering/            <- RenderLayers, YSortable, ElevatedTileVisual  [M2]
    pathfinding/          <- GridPathfinder, GridDataProvider             [M3]
    board/                <- BattleBoard (SSOT: высоты/террейн/occupancy) [0.4] NEW
    units/                <- UnitId, Faction, UnitState, Vitals           [0.2-0.3] NEW
    stats/                <- StatTypes, Stat, StatModifier, StatsBag      [M4]
    initiative/           <- TurnOrderStrategy, InitiativeTimeline        [M4]
    items/                <- ItemDef/ItemInstance/EffectRuntime (R-1)     [0.8]
    inventory/            <- InventoryState, EquipmentState               [0.8]
    combat/               <- DamageInfo, DamageCalculator, BalanceSystem,
                             PushResolver                                 [M6]
    actions/              <- Command, ActionQueue                         [0.5] NEW
    ai/                   <- AIAction, AIDecisionContext, AIConsideration,
                             AIBehaviorProfile, UtilityAIController,
                             AIGridMath, considerations/*                 [M7]
    flow/                 <- BattleFlowStateMachine                       [0.6] NEW
    input/                <- InputManager (autoload), InputRouter         [M1, 0.7]
    events/               <- GameEventBus (autoload), EventSink           [M5, R-3]
    rng/                  <- RngService                                   [0.10] NEW
  gameplay/
    camera/               <- IsoCameraController (inertia pan/zoom)
  test/                   <- Дебаг-скрипты ТОЛЬКО для test_grid_scene.tscn,
                             не финальная архитектура, можно свободно ломать
resources/
  grid/default_grid_config.tres
  initiative/default_initiative_strategy.tres
  items/                  <- тестовые предметы
  ai/                     <- aggressor_profile.tres, blocker_profile.tres
scenes/
  test/test_grid_scene.tscn   <- единая тестовая песочница, растёт с каждым модулем
docs/
  ARCHITECTURE.md   <- этот файл: статус, план, структура
  DECISIONS.md      <- правила; раздел R-* имеет высший приоритет
  AUDIT.md          <- реестр дефектов и техдолга (аудит 2026-09-11)
  TESTING.md        <- как проверить headless / что смотреть в редакторе
  modules/          <- по одной карточке на модуль с деталями реализации
```

## Автозагрузки (project.godot [autoload])
- `InputManager` = `res://scripts/core/input/input_manager.gd`
- `GameEventBus` = `res://scripts/core/events/game_event_bus.gd`

## Главная сцена
`run/main_scene` = `res://scenes/test/test_grid_scene.tscn`

## Файлы/папки, НЕ нужные для восстановления архитектурного контекста
Экономия токенов в новой сессии: НЕ читать эти файлы, если не идёт речь о
конкретной низкоуровневой проблеме движка/импорта/системных настроек —
они не содержат игровой архитектуры.

- `.godot/` — кэш движка (автогенерируется, никогда не редактируется руками).
- `.import/` — автогенерируемые импорт-данные для ассетов.
- `.vs/`, `.idea/`, `.vscode/` — настройки IDE, не относятся к архитектуре.
- `icon.svg`, `icon.svg.import` — стандартная иконка проекта Godot, не игровой контент.
- `new_script.gd`, `new_script.gd.uid` — дефолтный шаблонный файл, оставшийся
  от создания проекта, НЕ используется ни в одном модуле, можно игнорировать
  (или удалить в будущем — не является частью архитектуры).
- `claudeignore`, `.editorconfig`, `.gitattributes`, `.gitignore` — служебные
  конфиги репозитория/тулинга, не игровая логика.
- `*.uid` файлы рядом с `.gd` — автогенерируемые Godot 4.x идентификаторы
  ресурсов, не содержат смысловой информации.
- `project.godot` — стоит смотреть ТОЛЬКО секцию `[autoload]` (см. выше) и
  `run/main_scene`, остальное (rendering/physics/display настройки) не
  меняется в рамках модулей и не требует повторного изучения.

Если нужно восстановить контекст — читать ТОЛЬКО `docs/ARCHITECTURE.md`,
`docs/DECISIONS.md`, `docs/modules/*.md`, `docs/TESTING.md` и, при
необходимости деталей реализации, конкретные файлы из `scripts/core/**`
упомянутые в карточке нужного модуля.

## P03a — владение двумя существующими эффектами (2026-09-13)

По [ТЗ редакции 2](P03A_ITEM_OWNERSHIP_TASK.md) разделяемые ItemDef/ItemEffect
содержат только определения; каждая копия получает ItemInstance и отдельный runtime
каждого occurrence. Item остаётся совместимым наследником ItemDef для прежних .tres.
ItemOwnerState владеет локальными монотонными ids, registry, размещением и порядком
inventory. InventoryState/EquipmentState — фасады одного state; guard охватывает
мутации и item signals, teardown тихий. Stat source уникален для occurrence.

Core heal runtime хранит параметры без владельца-ссылки, подписок или лечения.
Только scripts/test/LegacyItemDemoSink сохраняет прежний клик 10 HP -> 7 HP;
он не допускается в preview. Старые формы save сохранены как fresh-equip, с preflight
до выдачи ids. Runtime snapshot без повторного equip — отдельный P03b, не начат.
Полный C-3 capability gate, T10 execute/preview, очередь, экономика и весь шаг 0.8
этим этапом не объявляются готовыми. Проверки и итог ревью — в TESTING/CODEX_HANDOFF.

## P03b — снимок предметов и сбор описаний (2026-09-13)

Реализован ограниченный срез [P03b, редакция 1](P03B_ITEM_SNAPSHOT_TASK.md).
ItemSimulationState связывает board, полный owner registry и открытые фасады без
автоматического создания объектов. Это временный composition root, не ActionContext.
После создания или retirement фасада caller оборачивает те же runtime объекты заново
с актуальным списком открытых фасадов; ошибочные/повторные записи не скрываются в map.

ItemSimulationSnapshot хранит отдельный envelope `board_items_two_effects_v1` поверх
неизменного P02. Он сохраняет detached/closed, lifecycle, локальные ids/counters,
ordered definitions/inventory и связь stat runtime с существующим modifier occurrence.
Raw preflight проверяет типы, finite floats, caps/циклы, capability и полный граф до
создания доски. Restore получает явный immutable каталог ItemDef/Item, создаёт новый
runtime и тихие фасады; equip/activation/legacy load и добавления modifiers отсутствуют.
Канонические bytes имеют префикс `P03B` + version 1; encoding использует правила P02.

ItemReactionCollector принимает уже зафиксированный damage event и возвращает
value descriptions heal в порядке stable effect ids. Он не лечит, не подписывается,
не меняет stat cache/ids и не ведёт журнал доставки. Owner guard возвращает BUSY.
External runtime caller декларирует явно; пустой список не доказывает общий C-3.
Реальные HealCommand, очередь, RNG, полный preview и save-game остаются вне P03b.

## P04 — очередь Damage / Heal / Death (2026-09-14)

Реализован ограниченный headless-срез редакции 1 P04_ACTION_QUEUE_TASK. ActionContext
удерживает прежний ItemSimulationState, обязательные RNG/value-sink порты и явные
unsupported runtime ids. Root admission проходит P03b capture без restore/equip;
общие busy/fault guards не позволяют второй очереди писать в тот же контекст.

ActionQueue синхронно опустошает LIFO work stack: mandatory, затем отсортированные
item reactions и явные test reactions, затем continuation. Каждое поддерево завершается
до следующего sibling. Root/command/event sequences принадлежат контексту; revision
меняется один раз на изменивший состояние шаг. Это не полный fingerprint боя.

DamageCommand, HealCommand и DeathCommand используют общий ActionHpExecutor и Vitals.
Damage учитывает только flat armor либо bypass; Death не имитирует удар. Общий finalize
сохраняет труп в board registry, идемпотентно освобождает occupancy и формирует damaged
перед died. Over-max/full/zero heal не вызывает Vitals.heal и не уменьшает HP.

ItemReactionAdapter связывает копию P03b description с конкретными unit/owner/item/effect
и immutable definition. Перед Heal повторно проверяются identity, ledger, placement,
active/closed/alive; stale реакция становится SKIPPED, нарушенный invariant — FAULTED.
Private binding удерживает ссылки только на время pending; value journal их не содержит.

Лимиты команд/глубины останавливают цепь до следующей мутации. Event overflow сохраняет
весь атомарный шаг (до двух events), затем fault latch запрещает новые roots. Выполненный
prefix публикуется отдельными копиями после drain/fault, с guards до конца публикации.
Нет rollback/reset; штатные ошибки явные, произвольные script exceptions не перехватываются.

ActionRngPort fail-closed; concrete cursor RNG существует только в runner для проверки
clone/roundtrip и двух независимых P03b состояний. HP-команды RNG не потребляют. Move,
Attack, Push, ActionResources, полный preview/token, Flow, BT, новые статусы, экономика
и save-game в этот срез не входят. Общие C-3/S-5 и этапы 0.5/0.8 остаются открытыми.

## P05 — явное пошаговое движение (2026-09-14)

Реализован headless-срез принятой редакции 1 P05_MOVE_TASK. Этот раздел уточняет
исторические статусы P04 выше: MoveCommand теперь существует; Attack/Push и полный
preview по-прежнему впереди. Старый GridPathfinder не изменён и не исполняется очередью.

MoveRules — копируемый immutable допуск harness с явным пределом высоты, добавленный
необязательным пятым аргументом ActionContext. Он не задаёт Battle Flow. MovePathCheck
проверяет весь явный путь со стартом через provider своей BattleBoard, включая бюджет,
точную float-оплату и непроходимый VOID. Root также проверяет запас board_version.

MoveCommand исполняет одно ребро через BattleBoard.move_unit и оплачивает только
состоявшийся вход из прежнего move_points_left. После каждого ребра очередь исполняет
последствия и continuation с прежним depth+1. Последняя continuation проверяет итоговое
состояние без нового входа. Смерть, замена, удаление, смещение персонажа или изменившееся
следующее ребро могут прервать оплаченный префикс; хвост не оплачивается и не перестраивается.

HAZARD допускает оплаченный вход и создаёт обязательную DeathCommand с cell source.
Смерть проходит прежний P04 finalize до реакций; corpse остаётся в registry, occupancy
освобождается один раз. Журнал moved → died. INTERRUPTED — результат исполнения,
не игровой эффект: pending siblings продолжаются, следующий fault имеет приоритет.
Строгая moved schema отделена от HP событий; production collector остаётся damage-only.

Не добавлены ActionResources/refill, цена атаки, повторный выбор персонажа, движение
после атаки, UI/AI adapters, Battle Flow/BT, полный preview/token или save-game.
Ограничения single-writer callbacks, fault latch/prefix, общий C-3/S-5 сохраняются.

## P06 — оплачиваемая плоская ближняя атака (2026-09-14)

Реализована и принята редакция 1 P06_ATTACK_TASK с одним явно разрешённым
расширением allowed_paths: item_owner_state.gd допускает stat domain 0..10.
Frozen документы пакета не переписывались. Этот раздел уточняет исторические
утверждения выше об отсутствии Attack/ActionResources и неутверждённой экономике.

ActionResources хранит только main/bonus одного UnitState; движение остаётся
в move_points_left. Новые append-only stats7..10 задают максимумы действий, вклад
оружия и дальность. Enable создаёт нулевой ledger; явный refill до контекста
атомарно заменяет остатки производными максимумами без лечения/RNG. Контекст,
импорт и выбор персонажа не пополняют ресурсы. Unit snapshot v2 включает ledger;
P02/P03b сохраняют поддержку v1 и прежние bytes для null ledger. Legacy Unit/Board
export enabled runtime возвращает {} целиком, чтобы не потерять остатки действий.

AttackRules — копируемый допуск actor/target пар и definitions в шестом optional
аргументе ActionContext. AttackCommand проверяет placement/revision/resources,
ортогональное соседство и равенство board heights при ATTACK_RANGE=1; расширенный
reach и разные heights дают явный отказ. Root готовит событие и sealed Hit до
одной оплаты main. Hit связан с конкретными actor/target/ledger, использует прежний
DamageCommand с physical/bypass и уроном max(1,(STR+WEAPON_DAMAGE)-ARMOR).
Урон и смерть проходят прежний HP executor, затем реальные item reactions.

Attacked имеет отдельную строгую value schema; collector остаётся damage-only.
Ограничения очереди сохраняют оплаченный/выполненный prefix без refund. Main не
дублируется в контексте; has_attacked больше не запрещает второй доступный main.
Move после Attack сохраняет прежний бюджет и P05 rules.

Границы: headless harness без UI/AI, Balance/Push, полууровней/расширенного reach,
dodge/status runtime, item activations, Flow/BT, полного preview/token и save-game.
Приёмка: 1633 passed / 0 failed, независимое APPROVE. Проверенное рабочее дерево
содержит прежний dirty P02; коммит P06 фиксирует лишь отделимые изменения.
Snapshot-остаток и точные hashes перечислены в TESTING и CODEX_HANDOFF.

## P07 — Balance и одноклеточный Push (2026-09-14)

Принятая редакция 1 P07_BALANCE_PUSH_TASK реализована в явном профиле
flat_melee_balance_v1. Прежний flat_melee_v1 сохраняет HP-only P06. Этот раздел
уточняет исторические ограничения выше; UI/AI и Battle Flow не подключены.

Attack по-прежнему стоит 1 main. Impact берётся из IMPACT_POWER независимо от
HP/armor; выжившая цель накапливает balance до BALANCE_MAX. Max<=0 даёт иммунитет.
Один break сбрасывает balance в0 без избытка и создаёт один бесплатный Push на
соседнюю клетку. Wall/collision используют B=STRENGTH+WEAPON_DAMAGE до брони,
max(1,B-ARMOR) отдельно каждому. Спуск на h>=1: max(1,(HP_MAX*0.25)*h-ARMOR).
Целые высоты не перекодированы: любой положительный целый подъём блокирует Push.

Новые RefCounted/Command типы: BalancePushRules с копируемым stage Binding,
BalanceCommand, PushCommand, PushDamageCommand и CollisionDamageCommand. Binding
сохраняет исходный seal, identity и ожидаемые HP/balance/ledger значения; refs
не выходят в receipt/snapshot. Preflight проверяет collateral и запас board_version
до оплаты; дочерние команды повторно проверяют актуальный runtime.

Очередь исполняет HP hit → Balance → Push/последствия → item reactions hit.
Collision HP обоих участников выполняются одним step до любого лечения. Если
blocker погиб, выжившая цель входит на его клетку; entry/fall/lethal последствия
завершаются до item reactions collision. Сохранившийся blocker исключает движение.
Летальный вход и край завершают death внутри Push step. Позицию меняет только
BattleBoard, HP/death — ActionHpExecutor; corpse сохраняется в bounds.

Ёмкость4 и соответствующий event_seq reserve разрешены только точному
CollisionDamageCommand; у других команд осталось2. Fault сохраняет выполненный
prefix без rollback/refund. Новые строгие события не меняют legacy HP/voluntary
moved/attacked schemas. Snapshot/enum версии прежние, P02/P03b отражают balance,
ресурсы и corpse/live в одной клетке без сохранения очереди/bindings.

Границы: полууровни, расширенный reach, terrain HP/шипы, status/dodge, активации
предметов, Flow/BT, полный preview/token и save-game не реализованы этим пакетом.


## P08-SPATIAL r3 — реализация 2026-09-14

Headless opt-in `spatial_move_v1` и `spatial_melee_balance_v1` добавляют half-step геометрию без смены целочисленного legacy масштаба. BattleBoard хранит parallel bits, выдаёт отдельный spatial provider и canonical board snapshot v2 только при наличии bit1. Legacy providers и команды на fractional board закрыты.

SpatialRules объединяет стоимость ребра, fall arithmetic и bounded Guard. Guard фиксирует identities/lifecycle, HP/alive/balance, move/main/bonus, relevant stats из копий, geometry и две версии; последующие фазы вычисляются только известными delta. Vitals spatial receipts/checkpoints и pinned ActionHpExecutor сохраняют собственный prefix при callback mismatch. Board death subscription проверяет weak Unit/Vitals и identity регистрации. MoveFall и bound Death имеют раздельные точные формы binding. Общий S-5, UI/AI/Flow, LOS, полный preview и save-game не реализованы.
