# Лечебный предмет — ограниченный срез

Действующий контракт флакона; [SUMMON_ITEM](SUMMON_ITEM.md) описывает отдельную
печать в слоте 4 и item snapshot v3. Лечение не принимает печать. Контракт v2
ниже остаётся действующим для состояний без summon definitions/metadata.
Исходное ТЗ сохранено в [архиве](HEALING_ITEM.history-20260920.md).
Общее описание применения и factory с сохранением этих правил — [M3](ITEM_USE_M3.md).

## Правила

Каждый из трёх союзников тактического боя получает в инвентарь отдельный флакон:
`tactical_healing_flask`, лечение 12 HP, 2 заряда. Стартовое HP не меняется.
Слот 3 / клавиша 3 применяет его на себя за 1 main и 1 заряд. HP ограничен
текущим максимумом; full/over-max HP дают отказ. Bonus не заменяет main.
Стойка, движение, bonus и has_attacked сохраняются. Заряды не пополняются
при выборе, командном refill, переносе/активации предмета. Reset создаёт новый бой.
Пустой флакон остаётся в инвентаре и слоте с 0/2. Полигон и ИИ не используют флакон.
Нет редактора назначений, лечения союзника, призыва или прогноза использования.

## Данные и снимки

ItemDef: `use_heal_amount: float = 0.0`, `max_charges: int = 0`.
Оба нули обозначают прежний предмет; usable требует finite amount > 0 и
max_charges в 1..4096. ItemInstance хранит `_charges_left: int`, getter
`get_charges_left()`. Создание задаёт capacity; восстановление задаёт сохранённый
остаток. Владельцы/экземпляры не разделяют заряды; дефиниции остаются Resource.

ItemSimulationSnapshot writer сохраняет прежнюю v1/bytes при отсутствии usable
definitions. Иначе envelope schema 2, scope `board_items_usable_v2`; owner schema
остаётся 1 (его поля не меняются). В v2 ВСЕ definition records содержат
use_heal_amount:float/max_charges:int, ВСЕ item records charges_left:int.
В v1 эти поля запрещены. В v2 они обязательны, включая нули у старых предметов.
Проверяются пары параметров, диапазон 0..capacity, finite/type, live identity,
catalogue equality до allocation. Reader принимает v1/v2; неизвестные версии
сохраняют UNSUPPORTED. Canonical prefix P03B,1 у v1; P03B,2 у v2.
Instantiate не вызывает equip/refill и восстанавливает остаток, включая 0.
AttackForecast копирует definitions и полный snapshot с зарядами; атака их
не расходует. Legacy Inventory/Equipment resource-path DTO не является save-game
и не обещает runtime charges; общий save-game остаётся вне среза.

## Команда и отказ

`UseHealingItemCommand(actor_id, item_instance_id, expected_revision)` проходит
ActionQueue. Validate/execute проверяют revision, живого actor/occupancy, owner
identity/допуск MoveRules, включённые валидные resources, зарегистрированный
активный предмет в inventory/equipment, usable definition, charge, main, HP deficit.
Отказ не меняет snapshot, RNG, counters или состояние очереди; availability
не меняет last_receipt. Tactical session добавляет gates своей команды/фазы.

Оплата и лечение — один атомарный шаг, без дочернего HealCommand: лимит детей
не может оставить принятую оплату без лечения. До hp_changed уже списаны main
и заряд. Журнал содержит строгий `item_used` (actor/target/item id, main before/
after/cost, charges before/after) и `healed` с источником item и id экземпляра.
Revision растёт на один, RNG не используется. Лимит событий сохраняет исполненный
шаг целиком и ставит FAULTED, без возврата оплаты, согласно текущей очереди.
После hp_changed проверяется ожидаемый полный snapshot; внешняя мутация даёт
FAULTED с собственным исполненным prefix. Sink публикует после drain и не мутирует.

## UI и приёмка

Слот 3 показывает название, остаток/максимум, цену; tooltip — величину и отказ.
Осмотр врага не подменяет флакон выбранного союзника. Нажатие 3 объясняет отказ
даже у выключенной кнопки. После использования сбрасываются forecast/осмотр,
обновляются HP/ресурсы/слот/журнал. Слот 4 занят печатью, места 5–8 пусты; страница одна.

Headless: точный расход/overheal/полное HP/0 charge/0 main при bonus, stale,
dead/closed/busy/faulted/чужой/неактивный item, повтор/два владельца, отказ без
мутаций, callback/лимит prefix, смена/ход/reset; v1/v2 round-trip/canonical,
malformed/unknown/catalogue mismatch, изоляция charges и forecast parity.
UI: настоящий input в SubViewport (кнопка и 3), отказ/смена/осмотр/locked/reset,
неизменность прогноза при чтении, PNG. Полный core, guard, forecast и оба UI runner.

Общие команды проверки — [TESTING](TESTING.md), сдача и передача —
[CODEX_WORKFLOW](CODEX_WORKFLOW.md). Frozen документы, §4.5 и старые отчёты сохраняются.
