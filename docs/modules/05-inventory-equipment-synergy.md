> **ИСТОРИЧЕСКАЯ КАРТОЧКА модуля.** Описывает ранний этап, может содержать
> заменённые API/правила и статусы. Не использовать как текущее ТЗ.
> Актуальное устройство — [ARCHITECTURE](../ARCHITECTURE.md),
> действующие контракты — [PROJECT_CONTEXT](../PROJECT_CONTEXT.md).

# Модуль 5: Inventory, Equipment & Synergy System (Event Bus) ✅

## Файлы
- `scripts/core/events/game_event_bus.gd` — Autoload `GameEventBus`
  - Типизированные сигналы: `unit_damaged(unit, amount, source)`, `unit_healed(unit, amount, source)`,
    `unit_balance_changed(unit, old, new)`, `unit_balance_broken(unit)`,
    `turn_started(unit)`, `turn_ended(unit)`, `item_acquired(item, owner)`, `item_removed(item, owner)`
  - Строгая типизация вместо строкового pub/sub — сигналы конкретны, автокомплит работает.
- `scripts/core/items/item_effect.gd` — `ItemEffect : Resource` (абстрактный)
  - `on_equip(owner: Node, stats: StatsComponent) -> void` (virtual)
  - `on_unequip(owner: Node, stats: StatsComponent) -> void` (virtual)
- `scripts/core/items/stat_modifier_effect.gd` — `StatModifierEffect : ItemEffect`
  - `stat_type`, `operation`, `value` — создаёт `StatModifier` с `source_id = item_id` при equip,
    снимает через `remove_modifiers_by_source(item_id)` при unequip.
- `scripts/core/items/triggered_effect.gd` — `TriggeredEffect : ItemEffect` (база для реактивных эффектов)
  - `enum TriggerEvent {UNIT_DAMAGED, UNIT_HEALED, UNIT_BALANCE_BROKEN, TURN_STARTED, TURN_ENDED}`
  - Подписывается/отписывается от `GameEventBus` на equip/unequip. Фильтрует события ТОЛЬКО
    для своего `_bound_stats` (владельца), игнорирует события других юнитов.
  - Наследники переопределяют только `_on_triggered(context: Dictionary)`.
- `scripts/core/items/heal_on_damage_effect.gd` — `HealOnDamageEffect : TriggeredEffect`
  (пример конкретной реализации: лечит `heal_amount` HP при `unit_damaged`)
- `scripts/core/items/item.gd` — `Item : Resource`
  - `id: StringName`, `display_name`, `description`, `effects: Array[ItemEffect]`
  - `apply_to(owner, stats)` / `remove_from(owner, stats)` — прокидывает `item_id` в эффекты и
    вызывает `on_equip`/`on_unequip` для каждого.
- `scripts/core/inventory/inventory_component.gd` — `InventoryComponent : Node`
  - Пассивные предметы (Isaac-style): эффект применяется сразу при `add_item()`.
  - `add_item(item)`, `remove_item(item)`, `has_item(id)`, `get_items()`, сигналы `item_added/item_removed`
- `scripts/core/inventory/equipment_component.gd` — `EquipmentComponent : Node`
  - `enum EquipSlot {WEAPON, ARMOR, TRINKET}`
  - `equip(slot, item) -> Item` (возвращает снятый предмет, если был), `unequip(slot) -> Item`
  - `get_equipped(slot)`, `is_slot_occupied(slot)`

## Ключевая идея синергий
Эффекты не знают друг о друге. `TriggeredEffect`-наследники подписываются на общие события
`GameEventBus`. Пример теста: Item A (`StatModifierEffect`, +2 STRENGTH) и Item B
(`HealOnDamageEffect`, +1 HP при `unit_damaged`) работают независимо на одном юните —
демонстрация того, что новый предмет может реагировать на события, эмитированные ЛЮБОЙ
частью системы (в т.ч. будущим Damage System из Модуля 6), без прямой связи между ними.

## Тестовые ресурсы
- `resources/items/item_a_strength_boost.tres` — id `item_a_strength_boost`, +2 STRENGTH
- `resources/items/item_b_heal_on_damage.tres` — id `item_b_heal_on_damage`, +1 HP on damage

## Тестовые файлы
- `scripts/test/debug_inventory_panel.gd` (`extends Label`) — спавнит юнита (HP=10, STR=3),
  выдаёт оба тестовых предмета через `InventoryComponent`, по клику эмитит `GameEventBus.unit_damaged`
  (просто событие, БЕЗ реального вычитания урона — это будет в Модуле 6), показывает что item_b
  реагирует (+1 HP) и что item_a модифицировал STRENGTH.
- Добавлено в `test_grid_scene.tscn`: `UILayer/InitiativePanel` (перемещена в left, x:20-280,
  добавлен явный белый цвет текста + тень — фикс проблемы "не видно панель" из Модуля 4) и
  новая `UILayer/InventoryPanel` (x:20-420, y:180-320).

## Отложено на потом (по решению пользователя)
Ковка (Forge System / ForgeRecipe) — контракт НЕ реализован, будет сделан позже вместе с
реальным контентом предметов.

## Статус проверки
Headless-прогон чист. Визуальная проверка пользователем — TODO (включая повторную проверку
видимости InitiativePanel после фикса цвета текста).
