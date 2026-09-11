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

## Список модулей и статус

| № | Модуль | Статус |
|---|---|---|
| 1 | Universal Input & Grid System | ✅ Done |
| 2 | Y-Sorting & Z-Ordering | ✅ Done |
| 3 | Pathfinding | ✅ Done |
| 4 | Modular Stats & Initiative Engine | ✅ Done |
| 5 | Inventory, Equipment & Synergy System (Event Bus) | ✅ Done (Forge deferred) |
| 6 | Damage, Balance & Push Preview System | ✅ Done |
| 7 | Extensible Utility AI | ✅ Done |
| 8 | Battle Flow State Machine | ⏳ Next |
| 9 | Tile Effects & Status Engine | Not started |
| 10 | Action & Visual Execution Queue | Not started |
| 11 | Run State & Procedural Generation | Not started |
| 12 | Profile System & Meta-Progression | Not started |

Подробности по каждому реализованному модулю — в `docs/modules/`.
Ключевые архитектурные решения и правила — в `docs/DECISIONS.md`.
Как проверять проект (headless Godot) — в `docs/TESTING.md`.

## Быстрый старт для новой сессии
1. Прочитать этот файл целиком.
2. Прочитать `docs/DECISIONS.md` — там правила, которые нельзя нарушать.
3. Прочитать карточку последнего Done-модуля в `docs/modules/`.
4. Открыть `scenes/test/test_grid_scene.tscn` — это единая тестовая песочница
   для всех модулей, в неё добавляются новые дебаг-элементы по мере
   реализации модулей.
5. Спросить пользователя: "Продолжаем с модуля N?" и следовать плану.

## Хендофф между сессиями (правило)
В конце КАЖДОГО ответа ассистент указывает приблизительный процент заполнения
контекстного окна текущей сессии (оценка "на глаз", без точного инструмента),
чтобы пользователь мог вовремя перейти в новый чат до достижения лимита.
При приближении к ~80-90% — явно предупредить и напомнить обновить эти
файлы документации перед переходом в новую сессию.

## Структура репозитория
```
scripts/
  core/                  <- чистая игровая логика, без привязки к конкретным сценам
    input/               <- Модуль 1: InputManager (autoload)
    grid/                <- Модуль 1: IsoGridConfig, IsoGridUtils
    rendering/            <- Модуль 2: RenderLayers, YSortable
    pathfinding/          <- Модуль 3: GridPathfinder, GridDataProvider
    stats/                <- Модуль 4: StatTypes, Stat, StatModifier, StatsComponent
    initiative/           <- Модуль 4: TurnOrderStrategy, SimpleInitiativeStrategy, InitiativeTimeline
    events/               <- Модуль 5: GameEventBus (autoload)
    items/                <- Модуль 5: Item, ItemEffect, StatModifierEffect, TriggeredEffect, HealOnDamageEffect
    inventory/            <- Модуль 5: InventoryComponent, EquipmentComponent
    combat/               <- Модуль 6: DamageInfo, DamageCalculator, BalanceSystem, PushResolver, ActionPreview
    ai/                   <- Модуль 7: AIAction, AIDecisionContext, AIConsideration, AIBehaviorProfile,
                              UtilityAIController, AIGridMath, considerations/*
  gameplay/
    camera/               <- IsoCameraController (inertia pan/zoom)
  test/                   <- Дебаг-скрипты ТОЛЬКО для test_grid_scene.tscn, не финальная архитектура
resources/
  grid/default_grid_config.tres
  initiative/default_initiative_strategy.tres
scenes/
  test/test_grid_scene.tscn   <- единая тестовая песочница, растёт с каждым модулем
docs/
  ARCHITECTURE.md   <- этот файл
  DECISIONS.md      <- зафиксированные правила и договорённости
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
