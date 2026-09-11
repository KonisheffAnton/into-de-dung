# Модуль 6: Damage, Balance & Push Preview System ✅

## Файлы
- `scripts/core/combat/damage_info.gd` — `DamageInfo : Resource` (DTO)
  - Вход: `attacker`, `target`, `attacker_cell`, `target_cell` (ГИПОТЕТИЧЕСКИЕ позиции
    в момент удара, не "текущие живые" — см. DECISIONS.md про Move+Attack комбо),
    `base_damage`, `impact_power`, `damage_type`
  - Выход (заполняется `calculate()`): `final_damage`, `balance_added`,
    `would_break_balance`, `push_direction`, `push_target_cell`, `push_blocked`, `push_blocked_reason`
- `scripts/core/combat/balance_system.gd` — `BalanceSystem` (static)
  - `would_break(stats, added_impact) -> bool` — НЕ мутирует (для превью)
  - `apply_impact(stats, added_impact) -> bool` — МУТИРУЕТ, сбрасывает BALANCE в 0 при "сломе"
  - `reset(stats)`
- `scripts/core/combat/push_resolver.gd` — `PushResolver` (static)
  - `compute_push_direction(attacker_cell, target_cell) -> Vector2i` — проекция на 4 оси (без диагоналей)
  - `compute_push_target(target_cell, direction, distance:=1) -> Vector2i`
  - `validate_push(target_cell, push_target_cell, data_provider, max_height_step) -> Dictionary`
    `{success, final_cell, blocked_reason}` — `blocked_reason`: `&"wall"`/`&"height"`/`&""`
    ПРИМЕЧАНИЕ: столкновение с ДРУГИМ юнитом на клетке толкания не проверяется —
    нет occupancy-слоя (появится в Модуле 9/аналогичном), сейчас только геометрия/стены/высота.
- `scripts/core/combat/damage_calculator.gd` — `DamageCalculator` (static)
  - `calculate(attacker, target, attacker_cell, target_cell, base_damage, impact_power, data_provider, max_height_step) -> DamageInfo`
    — ЧИСТАЯ функция, без побочных эффектов (безопасна для превью)
  - `apply(info: DamageInfo) -> void` — МУТИРУЕТ: вычитает HP, вызывает `BalanceSystem.apply_impact`,
    эмитит `GameEventBus.unit_damaged`/`unit_balance_broken`. НЕ двигает юнита по сетке физически —
    это ответственность будущего Модуля 10 (Action & Visual Execution Queue), только возвращает
    `push_target_cell` в `info` для вызывающего кода.
- `scripts/core/combat/action_preview.gd` — `ActionPreview` (static)
  - `build(...)` — тонкий фасад над `DamageCalculator.calculate()`, никогда не вызывает `apply()`.

## Ключевые решения
- **STRENGTH** прямо добавляется к `base_damage` → `final_damage` (см. Модуль 4: STRENGTH = прямой урон).
- **IMPACT_POWER** атакующего = `balance_added` цели, НЕ влияет на `final_damage` напрямую.
- Push — только 4 направления (проекция на ближайшую ось), совпадает с правилом Pathfinding.
- Один `DamageInfo` для превью и реального применения — невозможно расхождение расчётов.

## ВАЖНОЕ ПРАВИЛО ГЕЙМДИЗАЙНА (см. DECISIONS.md, влияет на Модули 6/8/10)
Move и Attack — раздельные действия с общим пулом очков хода. Ближний бой = радиус атаки 1 клетка.
Два потока: (A) move → attack → остаток очков хода снова доступен; (B) UI-комбо — таргет врага в
пределах (остаток хода + радиус атаки) → авто-подход + атака одним подтверждением. ПОЭТОМУ
`DamageCalculator`/`ActionPreview` принимают `attacker_cell`/`target_cell` ЯВНО, не читают
текущую позицию юнита — контракт уже это учитывает.

## Тестовые файлы
- `scripts/test/debug_combat_panel.gd` (`extends Label`) — тестовый "атакующий" (1,1) и
  "цель" (3,1), ЛКМ = пересчитать превью (безопасно), ПКМ = применить атаку (реально вычесть HP,
  накопить Balance). IMPACT_POWER атакующего = 40, BALANCE_MAX цели = 100 → баланс сломается
  на 3-м ударе (40*3=120>=100), после чего покажет push direction/target.
  Добавлено в `test_grid_scene.tscn` как `UILayer/CombatPanel` (offset y:340-480).

## Статус проверки
Headless-прогон чист. Визуальная проверка пользователем — TODO.
