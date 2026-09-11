extends Node

## Глобальная шина событий (Autoload "GameEventBus"). Типизированные
## сигналы вместо строкового pub/sub — строгая типизация GDScript даёт
## автокомплит и проверку сигнатур при подписке эффектов предметов/перков.
##
## Перки/предметы (ItemEffect) подписываются на нужные им сигналы здесь,
## не зная друг о друге — это и есть механизм синергий (Модуль 5): новый
## предмет реагирует на уже существующие события старых предметов без
## прямой связи между ними.

## Юнит получил урон. source — источник урона (атакующий/эффект/Variant).
signal unit_damaged(unit: StatsComponent, amount: float, source: Variant)

## Юнит восстановил HP.
signal unit_healed(unit: StatsComponent, amount: float, source: Variant)

## Изменилась шкала Баланса юнита (см. Модуль 6 Damage/Balance).
signal unit_balance_changed(unit: StatsComponent, old_value: float, new_value: float)

## Юнит потерял равновесие (Balance достиг BALANCE_MAX) — триггер толкания.
signal unit_balance_broken(unit: StatsComponent)

## Начался ход конкретного юнита (см. Модуль 8 Battle Flow).
signal turn_started(unit: StatsComponent)

## Ход юнита завершён.
signal turn_ended(unit: StatsComponent)

## Предмет получен владельцем (добавлен в инвентарь/экипирован).
signal item_acquired(item: Item, owner: Node)

## Предмет потерян/снят владельцем.
signal item_removed(item: Item, owner: Node)
