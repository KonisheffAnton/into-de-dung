> **ИСТОРИЧЕСКАЯ КАРТОЧКА модуля.** Описывает ранний этап, может содержать
> заменённые API/правила и статусы. Не использовать как текущее ТЗ.
> Актуальное устройство — [ARCHITECTURE](../ARCHITECTURE.md),
> действующие контракты — [PROJECT_CONTEXT](../PROJECT_CONTEXT.md).

# Модуль 7: Extensible Utility AI ✅

## Файлы
- `scripts/core/ai/ai_action.gd` — `AIAction` (`RefCounted`, DTO)
  - Один кандидат-намерение ИИ на ход: `action_type` (`&"idle"`/`&"move"`/
    `&"move_and_attack"`), `final_cell`, опционально `target`/`target_cell`/
    `damage_info` (результат `ActionPreview.build()`), `score` (для дебага).
- `scripts/core/ai/ai_decision_context.gd` — `AIDecisionContext` (`RefCounted`)
  - Снимок тактической ситуации, считается ОДИН раз в `decide()`:
    `data_provider`, `max_height_step`, `enemy_cells` (`Vector2i -> StatsComponent`),
    `ally_cells`, `hazard_cells`.
- `scripts/core/ai/ai_consideration.gd` — `AIConsideration` (абстрактный `Resource`)
  - `score(action: AIAction, context: AIDecisionContext) -> float` в `[0..1]`.
    `@export var weight` настраивается по экземпляру в `.tres`.
- `scripts/core/ai/ai_behavior_profile.gd` — `AIBehaviorProfile` (`Resource`)
  - Набор взвешенных `AIConsideration`. `evaluate(action, context)` —
    взвешенное среднее всех considerations.
- `scripts/core/ai/utility_ai_controller.gd` — `UtilityAIController` (static)
  - `decide(unit_stats, unit_cell, profile, pathfinder, context, base_damage, attack_range) -> AIAction`
    — генерирует кандидатов (`move` для каждой достижимой клетки +
    `move_and_attack` для клеток в пределах `attack_range` от врага),
    оценивает через `profile.evaluate()`, возвращает лучшего. Никогда не
    возвращает `null` (пустой список кандидатов -> idle-заглушка).
- `scripts/core/ai/ai_grid_math.gd` — `AIGridMath.manhattan_distance()` —
  общий хелпер для considerations (дешёвая эвристика, не путать с
  `GridPathfinder`, который даёт точную проходимость/стоимость).
- `scripts/core/ai/considerations/*.gd` — конкретные факторы оценки:
  - `BalanceExploitConsideration` — выше при большом накоплении Balance цели.
  - `LowHpTargetConsideration` — приоритет добивания раненых целей.
  - `PushToHazardConsideration` — максимум, если толчок сломает Balance И
    итоговая клетка попадёт в `context.hazard_cells`.
  - `SelfSafetyConsideration` — штраф за клетки рядом с несколькими врагами
    (манхэттен, `danger_radius`).
  - `HoldPositionConsideration` — выше, если `final_cell` ближе к союзникам
    (`context.ally_cells`) — для роли "Блокер".
  - `PreferAttackConsideration` — простой тайбрейк "атака лучше простого хода".
- `resources/ai/aggressor_profile.tres` — роль "Aggressor": PreferAttack +
  LowHpTarget + BalanceExploit + PushToHazard (без HoldPosition).
- `resources/ai/blocker_profile.tres` — роль "Blocker": слабый PreferAttack +
  сильный HoldPosition + SelfSafety.

## Ключевые решения
- **Utility AI (score-based) + Strategy/Resource**, по аналогии с
  `TurnOrderStrategy` (Модуль 4): поведение — данные (`.tres`), не хардкод.
  Новый тип поведения = новый `AIConsideration.gd` + подключение в
  `AIBehaviorProfile.tres`, без изменения `UtilityAIController`.
- **MVP-контракт "Вариант A"**: `decide()` вызывается ОДИН раз за ход юнита,
  возвращает ОДНО намерение (move ИЛИ move+attack одним пакетом) —
  совпадает с UI "Потоком B" (move+attack одним подтверждением, см.
  DECISIONS.md), только решение принимает ИИ.
- **Расширяемость до "Варианта B"** (несколько итераций решения за ход)
  заложена намеренно: `decide()` не хранит состояния между вызовами —
  можно безопасно вызывать в цикле с обновлённым `AIDecisionContext`/
  `unit_cell` после каждого частичного действия, без изменений в этом
  модуле. Генерация кандидатов и выбор лучшего разделены на отдельные шаги
  — новый тип кандидата (способность/предмет) добавляется отдельным
  генератором.
- AI **не мутирует** состояние — использует `ActionPreview.build()` (чистая
  функция) для оценки кандидатов. Реальное применение (`DamageCalculator.apply`
  + физическое перемещение по сетке) — ответственность вызывающего кода/
  будущего Модуля 10 (Action & Visual Execution Queue).
- AI **не управляет фазами боя** — это Модуль 8 (Battle Flow State Machine),
  `UtilityAIController` только принимает решение по запросу.
- Ограничились ДВУМЯ ролями для MVP: Aggressor (агрессивная атака/добивание/
  толкание в опасность) и Blocker (защита позиции/группировка с союзниками,
  избегание размена). Новые роли — просто новые `.tres` профили.

## Тестовые файлы
- `scripts/test/debug_ai_panel.gd` (`extends Label`) — тестовый враг
  (`enemy_cell`, подключаемый `behavior_profile`), тестовый "игрок"
  (`player_cell`) и тестовый союзник (`ally_cell`, релевантен для Blocker).
  ЛКМ по панели — **РАНДОМИЗИРУЕТ** сценарий (позиции player/ally на сетке,
  случайные HP/Balance игрока, переключает профиль Aggressor<->Blocker) и
  пересчитывает `UtilityAIController.decide()`, показывая выбранное действие
  (тип, клетка, score, урон/баланс/пуш при атаке) — наглядная демонстрация
  разных решений без ручного редактирования сцены в инспекторе.
  Добавлено в `test_grid_scene.tscn` как `UILayer/AIPanel` (offset x:480-920,
  y:16-180), профиль по умолчанию — `aggressor_profile.tres`.

## Статус проверки
Headless-прогон чист. Визуальная проверка пользователем — TODO.
