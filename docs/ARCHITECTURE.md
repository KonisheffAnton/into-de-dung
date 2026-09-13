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
| 0.5 | `Command` + `ActionQueue` (Move/Attack/Push) | иначе нечем исполнить ход | ⏳ **next** |
| 0.6 | Battle Flow SM (Player→Preview→Exec→Enemy→VictoryCheck) | это и есть цикл | ⏳ |
| 0.7 | `InputRouter` + Selection/Targeting | иначе нельзя выбрать и подтвердить действие (M-1) | ⏳ |
| 0.8 | `ItemDef`/`ItemInstance` (**один** предмет) | иначе выбор награды сломан (C-3) | ⏳ |
| 0.9 | Минимальный `RunState` + экран награды | замыкает петлю | ⏳ |
| 0.10 | `RngService` | детерминизм новой карты (G-1) | ⏳ |

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
- Коммит при: **зелёный headless-прогон И (визуальная проверка ИЛИ зелёные тесты)**.
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
