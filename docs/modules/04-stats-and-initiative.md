# Модуль 4: Modular Stats & Initiative Engine ✅

## Файлы
- `scripts/core/stats/stat_types.gd` — `StatTypes.StatType` enum:
  `HP, HP_MAX, INITIATIVE, BALANCE, BALANCE_MAX, STRENGTH, IMPACT_POWER, MOVE_RANGE`
  - **STRENGTH** = прямой урон атак. **IMPACT_POWER** = толкание/накопление Баланса цели.
    Это РАЗНЫЕ характеристики, не объединять.
- `scripts/core/stats/stat_modifier.gd` — `StatModifier : Resource`
  - `source_id: StringName`, `operation: Operation{ADD_FLAT,ADD_PERCENT,MULTIPLY}`, `value: float`, `priority: int`
- `scripts/core/stats/stat.gd` — `Stat` (RefCounted)
  - `base_value`, `add_modifier()`, `remove_modifiers_by_source(id) -> bool`, `clear_modifiers()`
  - `get_value() -> float` — кэшируется, пересчёт только при изменениях (`_cache_dirty`)
- `scripts/core/stats/stats_component.gd` — `StatsComponent : Node`
  - `signal stat_changed(type, old_value, new_value)`
  - `set_base_value(type, value)`, `get_stat(type) -> Stat`, `get_value(type) -> float`
  - `add_modifier(type, modifier)`, `remove_modifiers_by_source(source_id)` (снимает со ВСЕХ статов)
- `scripts/core/initiative/turn_order_strategy.gd` — `TurnOrderStrategy : Resource` (абстрактный)
  - `compute_order(participants: Array[StatsComponent]) -> Array[StatsComponent]` (virtual)
- `scripts/core/initiative/simple_initiative_strategy.gd` — `SimpleInitiativeStrategy`
  - Выше `INITIATIVE` → раньше ходит. При равенстве — случайный tiebreak (по требованию пользователя).
- `scripts/core/initiative/initiative_timeline.gd` — `InitiativeTimeline` (RefCounted)
  - `set_strategy(strategy)`, `register_participant(stats)`, `unregister_participant(stats)`
  - `recompute_order()`, `get_current_order() -> Array[StatsComponent]`
  - `advance_turn() -> StatsComponent`, `peek_current() -> StatsComponent`
  - НЕ управляет фазами боя — это Модуль 8.
- `resources/initiative/default_initiative_strategy.tres`

## Найденный баг (важно для будущего кода)
`var x := dict[key]` не работает для строгой типизации при чтении из Dictionary.
Исправление: `var tmp: Type = dict[key]`, затем использовать `tmp`. См.
`docs/DECISIONS.md` → "Общие правила GDScript".

## Тестовые файлы
- `scripts/test/debug_initiative_panel.gd` (`extends Label`) — спавнит 4 юнита
  со случайными статами, показывает очередь ходов, клик по панели — реролл.
  Добавлен в `test_grid_scene.tscn` как `UILayer(CanvasLayer)/InitiativePanel`.

## Статус проверки
✅ ПОДТВЕРЖДЕНО пользователем. Панель найдена и клик работает: при реролле
значения INIT/STR у юнитов НЕ меняются (корректно — это базовые статы),
меняется только порядок между юнитами с ОДИНАКОВОЙ инициативой (случайный
tiebreak) — именно так и задумано. Stats/Initiative логика работает верно.
