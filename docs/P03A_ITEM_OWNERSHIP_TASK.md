# P03a — определения и экземпляры двух существующих эффектов

Дата: 2026-09-13. Редакция 2. Результат независимого ревью — [P03A_REVIEW.md](P03A_REVIEW.md).
**Это пакет на будущую реализацию. Текущая задача разрешает только документацию.**
Никакой код P03a ещё не реализован. Нормативная база: контракт 0.5 draft-2,
разделы 3 (владение), 5 (ключ реакции), 8/T10 и 9/P03a–P04; R-1/R-2/R-3/R-4.
Этот пакет специализирует границу P03a. Полный C-3, T10, preview и шаг 0.8 не закрывает.

## 1. Пакет исполнителю и входной gate

```yaml
task_id: P03A-ITEM-OWNERSHIP
role: game_coder
model: gpt-5.6-luna
reasoning: medium
base_commit: b102678b28957e6d17282878dea19d3946d9f570
branch_at_preparation: main
goal: Два владельца и несколько копий одного определения имеют независимое владение эффектами.
dependency_manifest: docs/P03A_DEPENDENCIES.json
contracts: ["Этот документ, редакция 2", "0.5 draft-2: ownership subset P03a"]
non_goals:
  - P03b snapshot/runtime реакций, Command/HealCommand/ActionQueue/ActionContext/RNG
  - Полное preview/confirm, общий S-5, экономика и командный flow
  - Передача экземпляров между юнитами, награды, новый контент, data-driven слоты
  - Новый save-формат предметов или расширение P02 codec
  - Коммиты исполнителем, другие агенты, изменение доверия или sandbox
```

Ты не один в checkout. Прежние изменения принадлежат другим этапам: не сбрасывать,
не включать в свой результат и не форматировать попутно. Не делегировать дальше.
При отсутствующем API или противоречии вернуть NEED_CONTEXT/CONTRACT_GAP с точным местом;
не расширять allowed_paths самостоятельно. Ведущий запускает только одного пишущего кодера.

При подготовке: main/HEAD совпали с передачей; 11/11 SHA-256 таблицы P02 совпали.
Исторические P01 hashes board/tests **не являются** текущими: P02 изменил эти файлы.
P01 damage совпадает побайтно; сохранность P01 hunks board/damage/tests дополнительно
проверена `git apply --reverse --check` для сохранённого p02-baseline.patch, без применения.
Актуальные P01/P02 и входы P03a перечислены в приложенном JSON manifest.

Начальный status: modified — docs/ARCHITECTURE.md, docs/DECISIONS.md, docs/TESTING.md,
scripts/core/board/battle_board.gd, scripts/core/combat/damage_calculator.gd,
scripts/core/stats/stat.gd, scripts/core/stats/stats_bag.gd,
scripts/core/units/unit_state.gd, tests/run_tests.gd;
untracked — .codex/, AGENTS.md, docs/CODEX_HANDOFF.md, docs/CODEX_WORKFLOW.md,
docs/COMMAND_ACTION_QUEUE_CONTRACT.md, docs/MECHANICS_REQUIREMENTS.md,
docs/P02_SNAPSHOT_TASK.md, scripts/core/actions/.
Новые документы этого пакета добавляются поверх указанного состояния.

Перед запуском реализации ведущий сверяет `git status --short`, `git rev-parse HEAD`
и **все** hashes manifest. Документационный коммит этого пакета может сменить HEAD:
его hash записывается в передачу; допускается только проверенный documentation-only
diff от base_commit, все исходные зависимости должны совпасть. Другой код/API или hash
требует пересборки пакета, а не продолжения по устаревшему ТЗ. Исходный diff/status и
hashes всех прежних файлов сохранены для текущей проверки в игнорируемом test_reports/p03a-*;
эти локальные артефакты не являются обязательной зависимостью переносимого пакета.

## 2. Факты кода и выбранная граница

| Сейчас | Требуемый результат P03a |
|---|---|
| Item : Resource присваивает item_id вложенному эффекту | ItemDef хранит только контент; ItemInstance хранит идентичность копии |
| StatModifierEffect создаёт source_id из Item.id, удаление снимает все копии | Каждое occurrence эффекта получает свой стабильный source key |
| TriggeredEffect хранит UnitState и подписку GameEventBus внутри Resource | Определение содержит только trigger enum; в core нет глобальных подписок |
| HealOnDamageEffect синхронно лечит в callback | Core хранит только параметры/принадлежность реакции; старый демонстрационный путь локализован в debug-адаптере |
| Inventory/Equipment хранят Item и независимо применяют его | Оба используют один ItemOwnerState юнита и размещают конкретные ItemInstance |
| Старый save хранит только пути; UnitState не содержит inventory/equipment | Старые формы сохраняются как legacy fresh-equip API, не snapshot |

Два эффекта: `StatModifierEffect` (+2 STRENGTH в item_a) и `HealOnDamageEffect`
(+1 HP при UNIT_DAMAGED в item_b). `TriggeredEffect` — их существующая базовая
иерархия для триггеров, а не третий реализуемый эффект.

**Шов с последующими пакетами:** P03a делает реакцию данными активного экземпляра.
Нового боевого исполнителя реакций нет. Для сохранения существующего клика в debug-панели
прежнее синхронное лечение переносится в явно временный, локально вызванный test-адаптер
EventSink. Он не слушает GameEventBus, не используется core и никогда не входит в preview.
Это сохранение старого демо, не архитектура исполнения 0.5. P03b вводит локальный сбор
описаний реакций и снимок; P04 исполняет HealCommand. При интеграции P04/P08 адаптер
заменяется маршрутом очереди. Переносить старый callback в новый core runtime нельзя.

## 3. Определения, идентичность и владение

### Неизменяемые определения

- Новый `ItemDef : Resource`: прежние id, display_name, description и
  `effects: Array[ItemEffect]`. id — непустой StringName контента, не id копии.
- Существующий `Item` становится пустым совместимым наследником ItemDef. Старые .tres,
  их script paths и `script_class="Item"` продолжают загружаться. Не переименовывать .uid.
- Существующий `ItemEffect : Resource` становится базой **определения**. Имя остаётся
  для совместимости .tres, отдельный ItemEffectDef alias не нужен. Удалить
  on_equip/on_unequip, Item.apply_to/remove_from/_assign_item_id и runtime поля Resource.
- StatModifierEffect оставляет stat_type/operation/value; TriggeredEffect — TriggerEvent
  с прежними числовыми значениями 0..5 и trigger_event; HealOnDamageEffect — heal_amount.
  Точный поддерживаемый trigger для HealOnDamageEffect — UNIT_DAMAGED (0).
  Другие значения и неизвестные эффекты явно отвергаются до любых мутаций.
- Нельзя duplicate() Resource как способ лечить C-3. Одна def и даже один effect
  subresource могут быть разделены несколькими предметами и повторены в effects.
  Порядок effects семантический: его нельзя сортировать/дедуплицировать.
- Definitions immutable по контракту, Godot не обеспечивает аппаратный freeze.
  Runtime копирует нужные скалярные параметры при создании; не хранит заимствованный
  mutable массив effects. Изменения ассетов во время боя не поддерживаются.

### ItemOwnerState : RefCounted — общий владелец предметов одного юнита

`ItemOwnerState.new(owner: UnitState)` создаётся composition root ровно один раз на юнита
и передаётся в его InventoryState/EquipmentState. UnitState не меняется. Повторное
создание независимых owner states для одного юнита вне контракта; это обязанность
composition root, в P03b её принимает ActionContext. Разные симуляции получают разные
owner states, даже если числовые UnitId совпадают.

Owner state хранит ссылку на свой UnitState, registry всех созданных экземпляров,
их размещение и два монотонных счётчика, начинающихся с 1: item и effect id.
Это единственный источник размещений и порядка inventory. Контейнеры — фасады этого
ledger; своих authoritative массивов/слотов не ведут. Все accessor'ы читают owner state.
Ids положительные int64, никогда не переиспользуются после снятия/удаления.
Полная идентичность предмета `(owner_unit_id, item_instance_id)`, эффекта
`(owner_unit_id, effect_instance_id)`. Это локальные ids юнита; в разных владельцах
числа могут совпадать. Ключ реакции 0.5 уже включает owner_unit_id перед effect_instance_id.
Нельзя использовать Godot get_instance_id(), адрес, resource path, hash(), часы,
UnitId allocator или static/global counter. До snapshot P03b ids сохраняются только
в течение жизни данного runtime; legacy load создаёт новую идентичность.

`create_item(definition: ItemDef) -> ItemInstance` проверяет **всё** определение,
создаёт один detached экземпляр и по одному runtime на каждое occurrence effects.
На ошибке возвращает null без сдвига обоих counters или частичного registry.
Проверить owner != null, owner.id > 0, stats/vitals != null; id def не пуст;
каждый effect не null и ровно поддерживаемого concrete script; stat enum и operation
существуют; числа конечны; heal_amount >= 0 и trigger=0. Отрицательный stat value
допустим (штраф); новые gameplay ограничения на stats не вводить.
Пустой effects допустим. Полная предварительная проверка переполнения обоих counters:
MAX_INT64 служит sentinel exhaustion, максимальный выдаваемый id = MAX_INT64-1.
Одно id определения не может обозначать разные Resource определения в одном owner state:
второй отличающийся объект с тем же id отклонить (кэшированный тот же объект допустим).

Регистрацию InventoryState и EquipmentState также контролирует owner state: максимум
один контейнер каждого типа; повторный конструктор должен быть неработоспособным
(add/equip/load отклоняются), без присвоения себе размещений первого контейнера.
Owner state не хранит сильные ссылки обратно на контейнеры: достаточно kind/slot.
Регистрация закрытого контейнера остаётся retired: второй того же kind в этом state
не создаётся. Закрытие контейнеров/owner state явное, идемпотентное; скрытые reference
cycles запрещены. Для нового набора контейнеров создаётся новый state.

### ItemInstance и ItemEffectRuntime : RefCounted

ItemInstance хранит immutable identity, ItemDef (только для чтения), копию definition_id
и массив собственных runtime. Runtime хранит owner_unit_id, item_instance_id,
effect_instance_id, effect_index (нулевой индекс occurrence), скалярные параметры,
active flag. Внутри core runtime нет Node/Signal/Callable/EventSink/ссылки на UnitState.
ItemInstance/runtime не хранят обратную сильную ссылку на ItemOwnerState.
Поля private с getter API; возвращаемые массивы копируются; никакого публичного setter
для ids/active/params. Мутации делает только owner state через внутренний API.

Два конкретных runtime: `StatModifierEffectRuntime` и `HealOnDamageEffectRuntime`.
ItemEffect предоставляет `create_runtime(owner_id: int, item_id: int, effect_id: int,
effect_index: int) -> ItemEffectRuntime`; база возвращает null, два concrete def
переопределяют. Фабрика не применяет effects и не меняет definition. Проверка поддержки
в owner state ограничена двумя concrete scripts этого среза, без молчаливого fallback.

Для stat runtime source key — ровно StringName из
`"p03a/o%d/i%d/e%d" % [owner_id, item_id, effect_id]` (положительные десятичные int).
Этот namespace зарезервирован для owner state. Перед первой активацией проверяется
отсутствие всех её source keys в StatsBag; коллизия — отказ без удаления чужих modifiers.
На активации создаётся свежий StatModifier(source_key, operation, value), затем
StatsBag.add_modifier(stat_type, modifier). На деактивации удаляется только собственный
source_key через существующий StatsBag.remove_modifiers_by_source. Отдельные Resource
модификаторов не разделяются; после добавления не мутируются. Этот существующий
StatModifier Resource не превращается в RefCounted в P03a.

P02 modifier record.instance_id остаётся 0; source_key — строка в существующем source_id.
Не менять P02 schema, slots/counter/evaluation_order или canonical codec. Это **не**
снимок предметов: P03b свяжет ids/occurrences и восстановленные modifiers без on_equip.

Heal runtime содержит только heal_amount/trigger_event и identity/active.
Активация/деактивация не лечит и ничего не подключает. Выбор активных heal runtime
через `ItemOwnerState.get_active_heal_effects() -> Array[HealOnDamageEffectRuntime]`
возвращает новый массив в порядке возрастания effect_instance_id.

## 4. Контейнеры, отказы и legacy save

Минимальный публичный API после миграции (старых прямых потребителей, кроме панели, нет):

| Тип/API | Семантика |
|---|---|
| `InventoryState.new(state: ItemOwnerState)` | Все пассивные предметы в нём активны |
| `add_item(item: ItemInstance) -> bool` | Только detached item из registry именно этого state; успех активирует один раз |
| `remove_item(item: ItemInstance) -> bool` | Снимает именно эту копию, переводит detached; false для отсутствующей |
| `get_items() -> Array[ItemInstance]`, `size()`, `count_of(id)`, `has_item(id)` | Копия массива; count по definition_id; порядок успешных добавлений |
| `EquipmentState.new(state: ItemOwnerState)` | Сохраняет enum WEAPON=0, ARMOR=1, TRINKET=2 |
| `equip(slot: EquipSlot, item: ItemInstance) -> bool` | Проверка нового item/слота до снятия старого; успех заменяет слот, старый item detached |
| `unequip(slot) -> ItemInstance`, `get_equipped(slot) -> ItemInstance` | null для пустого/недопустимого слота; снятие сохраняет id возвращённого item |
| `is_slot_occupied(slot)`, `get_occupied_slots() -> Array` | Новая коллекция; слоты по числовому enum |
| `clear() -> void` (оба контейнера) | Снять все предметы без сброса счётчиков; контейнер пригоден для reuse |
| `close() -> void` (оба), `ItemOwnerState.close() -> void` | Снять свои/все эффекты, контейнеры после close отклоняют операции; повторный close no-op |

`get_occupied_slots()` всегда возвращает числовой порядок WEAPON, ARMOR, TRINKET,
независимо от порядка equip. `ItemOwnerState.get_owner() -> UnitState` используется
только composition/test-адаптером; `is_closed() -> bool` позволяет проверить teardown.

Повторное add той же instance или equip той же instance в том же слоте — true/no-op,
без signals, modifiers и новых ids. Попытка вставить активную instance в другой контейнер
или слот — false; сначала её нужно явно remove/unequip. Другой state/owner, неизвестный
или вручную созданный item, закрытый state/container — false без изменений.
Отказы не посылают gameplay events, не меняют stats/vitals, расположения или counters.
В выдаче на owner мёртвого юнита дополнительных ограничений нет: owner state не задаёт flow;
лечить мёртвого запрещает Vitals. Перемещение между юнитами вне scope, всегда отказ.

`item_added/removed`, `item_equipped/unequipped` меняют тип payload на ItemInstance.
Посылаются после согласованного изменения; замена слота: unequipped(old), equipped(new),
обе нотификации видят конечное размещение и stats. Идемпотентный no-op не посылает signal.
На время мутации и нотификаций действует один общий busy guard owner state: вложенные
add/remove/equip/unequip/create/clear/close отклоняются/no-op; освобождение guard обязательно.
Это защита этого API, не общий S-5: произвольные внешние мутации StatsBag/Vitals из
низкоуровневых callbacks не поддерживаются. Логика боя не должна жить в таких callbacks.
clear снимает активные предметы в порядке item_instance_id; guard охватывает всю операцию.
Нотификации clear идут после снятия всех предметов и видят конечное пустое размещение.

`container.close()` — тихий teardown: под общим guard снимает только свои активные
эффекты, очищает их размещения и помечает свой kind закрытым, без item signals.
Другой контейнер остаётся работоспособным. `state.close()` также без item signals
снимает все активные effects в порядке item_instance_id/effect_index, очищает placement
ledger, помечает оба kind и state закрытыми. Низкоуровневые stat_changed от реального
снятия modifiers сохраняются; вложенный вызов этого API блокируется guard.
После любого close соответствующие get_items/get_occupied_slots возвращают пустые
массивы, size/count_of — 0, has_item/is_slot_occupied — false, get_equipped/unequip — null,
to_dict — соответственно `{item_paths: []}` / `{slots: {}}`. Сохранённые извне ссылки
на instances/runtime имеют active=false; экземпляры закрытого state нельзя реактивировать.
Последующий container.close после state.close — no-op без повторного снятия/сигналов.
Объекты контейнеров не нужны owner state для teardown; утечек через обратные ссылки нет.

Существующие `to_dict()` сохраняют формы `{item_paths: Array[String]}` и
`{slots: {"0": resource_path, ...}}`; используются definition.resource_path.
Дубликаты путей сохраняются. Runtime без пути пропускается, как сейчас (inventory warning).
Новый snapshot/save schema не вводить. `from_dict(data: Dictionary, state: ItemOwnerState)`
принимает старую форму, загружает `as ItemDef` и выполняет приватную атомарную операцию
создания-и-размещения записи (общие helpers с create_item/add/equip, не вложенные публичные
вызовы под guard). Перед выдачей ids проверяет всё определение, counters, доступность
контейнера/слота и отсутствие ВСЕХ prospective source keys в stats. Только после успешного
preflight выдаёт ids, создаёт registry/runtime, применяет effects и размещает предмет.
До этого наружу не выдаётся ни instance, ни signal. При отказе не нужны rollback modifiers
или откат уже выданных ids: изменений ещё нет. Callback-мутации сторонних stats по-прежнему
вне поддерживаемого контракта. Нельзя сначала вызвать публичный create_item, а затем
потенциально неуспешный add/equip: это расходует ids неуспешной legacy-записи.
Inventory сохраняет порядок массива, Equipment загружает по числовому slot (0..2),
не по порядку Dictionary. Несуществующий путь, неверный тип, неизвестный слот или def
пропускаются, без частичных эффектов/расхода ids для неуспешной записи.
Если контейнер уже зарегистрирован, load отвергается (null), а не добавляет второй.

Это только fresh-equip: вызывающий код передаёт owner с базовыми stats без ранее
применённых item modifiers. Допускается по одному legacy inventory и equipment load
в общий новый state; второй load того же вида отвергается. Не использовать после
P02 snapshot, не вызывать для восстановления preview. Полноценное восстановление
активных modifiers/ids без повторного equip — отдельный P03b. Старые UnitState/Board
to_dict/from_dict и прежние тесты save не менять. Новые заряды/cooldown не придумывать.

## 5. Сохранение демонстрационного пути лечения

Новый `scripts/test/legacy_item_demo_sink.gd`, `LegacyItemDemoSink : EventSink`:
`_init(state: ItemOwnerState, downstream: EventSink)`; state и downstream инжектируются.
Никаких подписок на GameEventBus и autoload обращений. Панель передаёт свой state и
GameEventBusSink.new(), применяет тот же DamageCalculator с этим обёрнутым sink.

unit_damaged сначала отправляет downstream.unit_damaged, затем для **своего** UnitState
(проверка object identity через state, не только числового id) при amount > 0 и alive
берёт активные heal runtime по id; каждый вызывает Vitals.heal(heal_amount).
При фактическом healed > 0 отправляет downstream.unit_healed; source — новый value
Dictionary с owner_unit_id, item_instance_id, effect_instance_id, definition_id.
Перед каждым лечением проверяет, что runtime всё ещё активен, owner жив, state не закрыт.
Смертельное повреждение не лечит/не воскрешает. Базы stats не меняются.
Остальные методы EventSink без потерь делегируются downstream; своих died/balance событий
адаптер не добавляет. Нельзя перехватывать глобальные unit_damaged/unit_healed обратно.

Панель создаёт один state, InventoryState(state), create_item для двух загруженных defs;
на `_exit_tree` явно закрывает state. Экспортируемые Item и два .tres остаются совместимы.
Клик по-прежнему: HP 10 -> 6 после damage=4 -> 7 после heal=1; сила 5, base 3.
Уведомления глобальной шины сохраняются через существующий downstream, но core heal
listeners больше нет. Полный preview с этим адаптером запрещён, порядок реакций 0.5
здесь не заявляется. Пределы reentrancy внешних подписчиков прежние и не скрываются.

## 6. Allowed/read paths и владельцы

**Единственный кодер** может менять только следующие существующие файлы:

```text
scripts/core/items/item.gd
scripts/core/items/item_effect.gd
scripts/core/items/stat_modifier_effect.gd
scripts/core/items/triggered_effect.gd
scripts/core/items/heal_on_damage_effect.gd
scripts/core/inventory/inventory_state.gd
scripts/core/inventory/equipment_state.gd
scripts/test/debug_inventory_panel.gd
tests/run_tests.gd
```

И создавать только эти новые скрипты и соответствующий каждому `<path>.uid`:

```text
scripts/core/items/item_def.gd
scripts/core/items/item_instance.gd
scripts/core/items/item_owner_state.gd
scripts/core/items/item_effect_runtime.gd
scripts/core/items/stat_modifier_effect_runtime.gd
scripts/core/items/heal_on_damage_effect_runtime.gd
scripts/test/legacy_item_demo_sink.gd
```

Запрещено менять существующие .uid, .tres, .tscn, project.godot, config/AGENTS,
stats/units/board/combat/actions/events/pathfinding/AI. В tests/run_tests.gd только
добавить suite вызовы до финального print/quit и адресные helpers/tests; 484 прежних
assertions и P01/P02 hunks сохраняются. Не форматировать весь файл.

Read paths: все перечисленные исходные allowed файлы; resources/items/item_a_strength_boost.tres,
resources/items/item_b_heal_on_damage.tres; scripts/core/stats/{stat,stats_bag,stat_modifier,stat_types}.gd;
scripts/core/units/{unit_state,vitals,unit_id}.gd; scripts/core/events/{event_sink,recording_event_sink}.gd;
scripts/core/combat/damage_calculator.gd; scripts/core/actions/{simulation_snapshot,board_snapshot_result}.gd.
Точные команды и необходимые интерфейсы уже приведены здесь; не загружать библиотеку docs кодеру.

Ведущий владеет этим ТЗ/manifest, docs/CODEX_HANDOFF.md и адресными статусами
ARCHITECTURE/DECISIONS/TESTING/COMMAND_ACTION_QUEUE_CONTRACT после реализации.
До реализации не менять статусы систем на Implemented/Verified.

## 7. Acceptance — обязательные поведенческие тесты

Новый suite `P03a Item ownership`; данные создавать локально. Проверять значения,
identity и отсутствие побочных эффектов; не ограничиваться успешным import.

| ID | Проверяемый сценарий и ожидаемый результат |
|---|---|
| A01 | Дважды load обоих реальных .tres возвращает кэшированные defs; два разных owner state получают отдельные instances/runtime. Snapshot скалярных export-полей/массива до/после create/add/remove/close совпадает; в Resource нет owner/item runtime поля или подписки |
| A02 | У A base STR=3 две копии +2 дают 7, у B одна — 5. Снять одну A ->5, затем вторую ->3; B остаётся 5. Все source keys различны, modifier count уменьшается ровно на нужные occurrences |
| A03 | Два повторения одной StatModifierEffect Resource в effects и два разных defs, разделяющих subresource, дают отдельные runtimes/keys. Снятие одного item не снимает другой; effect_index сохраняет исходный порядок |
| A04 | ADD_FLAT/ADD_PERCENT/MULTIPLY применены через реальные runtime к выбранным stats; снятие не меняет чужой modifier/source или base. Сохраняется порядок арифметики effects; повторный equip no-op не меняет snapshot stat slots/counter/evaluation_order |
| A05 | Shared heal def: A и B получают только своё лечение, две копии A лечат два раза; снятие одной сохраняет другую. Core add/equip сам не лечит и не подключает сигналы. Массив get_active_heal_effects скопирован и отсортирован по id |
| A06 | Registry/identity: монотонные ids с 1, неизменны при detach/readd и inventory->equipment; другой owner, активность в другом слоте/контейнере, вручную созданная instance отвергаются. Совпадающие числовые ids разных owner states не смешиваются; duplicate container не захватывает первый |
| A07 | Контейнеры: duplicate add/same-slot equip no-op; заменить слот снимает только old и активирует new; invalid replacement сохраняет old без signals/stats/counter изменений. get_items/get_occupied_slots можно мутировать без изменения контейнера; count_of отражает копии. Разный порядок equip даёт одинаковый числовой порядок get_occupied_slots |
| A08 | Параметры: null/неизвестный effect/trigger!=0, пустой def id, invalid enums, NaN/INF, отрицательный heal, другой def object с тем же id, exhausted counters — отказ до всех изменений. Последний effect invalid не оставляет первый modifier. Пустой effects и отрицательный finite stat value допустимы; source collision не удаляет чужой modifier |
| A09 | Guard: обработчик item_added/item_unequipped пытается create/add/remove/equip/clear/close; вложенная операция отклонена/no-op, состояние внешней операции согласованно и guard потом снят. clear/close идемпотентны, свои modifiers сняты, чужие сохранены. state.close при заполненных ОБОИХ контейнерах делает все accessors/legacy to_dict пустыми, внешние runtimes inactive; item signals отсутствуют, повторные container.close/state.close ничего не снимают/не посылают. Отдельный container.close оставляет второй работающим; после close нет реактивации |
| A10 | Legacy shapes: реальные два .tres, дубликаты inventory, все слоты equipment; to_dict/load на свежие base stats даёт те же bonuses один раз и новые instances. Иной insertion order slots даёт тот же порядок ids/effects. Missing path/wrong type/invalid slot пропускается без ids/эффектов. Чужой source p03a/o1/i1/e1 блокирует первую запись item_a до выдачи ids: следующий valid item_b получает item_id=1/effect_id=1, чужой modifier сохранён. Повторить для equipment load. Второй load контейнера отвергается; old Unit/Board save tests зелёные |
| A11 | Headless demo sink без globals: реальный DamageCalculator.apply с RecordingEventSink downstream, 10->7 после damage 4/heal 1; base HP_MAX/STR неизменны. Две копии, heal=0, clamp на max, amount=0, чужой owner с тем же числовым id, умершая цель и повторный apply на труп — правильные HP/число damaged/healed/died; все остальные методы EventSink проброшены |
| A12 | Границы P02: при наличии предметов harness объявляет unsupported_runtime_ids и получает UNSUPPORTED; не использовать capture_board(..., []) как полный снимок боя. Повторные операции P03a не меняют UnitId allocator/позиции/board_version/ресурсы действий. Полный старый регресс 484 assertions сохраняется |

Для exhausted counters разрешена только тестовая установка внутренних counters в fixture,
без добавления производственного публичного setter. Коллизии source имитировать реальным
чужим StatModifier с зарезервированным ключом до add_item. Негативные тесты не должны
добавлять неожиданные hard errors Godot; ожидаемые отказы возвращать bool/null.
P03a не обещает T09/T10 end-to-end preview: A05/A11 — только владение и legacy демо.

## 8. Проверки и возврат

При реализации из корня, GODOT_BIN берётся из окружения/TESTING.md только для процесса;
не менять user/global environment. При необходимости перенаправить APPDATA процесса
в игнорируемый test_reports/godot-profile и восстановить в finally.

```powershell
& $env:GODOT_BIN --path . --headless --import --log-file test_reports/p03a-import.log
& $env:GODOT_BIN --path . --headless --quit-after 3 --log-file test_reports/p03a-startup.log
& $env:GODOT_BIN --path . --headless --script tests/run_tests.gd --log-file test_reports/p03a-tests.log
git diff --check
rg -n 'GameEventBus|_bound_unit|func on_equip|func on_unequip|func apply_to|func remove_from' scripts/core/items
```

Import должен закончиться scan DONE и class cache новых типов, startup exit 0;
полный suite — 484 прежних + новые assertions, 0 failed, exit 0, без parse/compile/runtime
ошибок. rg не должен находить исполняемых обращений; пояснительные комментарии допустимы.
Известные certificate store и ожидаемый P01 push_error занятой клетки не считать новыми
дефектами, но проверить остальные строки лога. Визуально проверить существующий demo
клик/текст/повторное открытие и teardown; если недоступно, явно оставить UI unverified,
не выдавать startup за проверку интерактивного пути.

После прекращения записи: ведущий фиксирует hashes/diff, проверяет все acceptance и
передаёт game_reviewer (Terra/high) этот документ, фиксированный diff/manifest и логи.
Ревьюер только читает, не запускает пишущие Godot проверки, не делегирует.
Возврат: APPROVE/REQUEST_CHANGES; файлы/строки, сценарий, последствие и приоритет;
отдельно непроверенное. Ведущий проверяет identity/ownership, совместимость P02,
границу legacy adapter и будущего preview. Ревью ТЗ не заменяет ревью реализации.

Исполнитель возвращает DONE/NEED_CONTEXT/CONTRACT_GAP, список изменённых файлов,
таблицу A01–A12, команды/exit codes/число assertions, ограничения. Не коммитит.
Ведущий обновляет передачу и затронутые контракты; фиксирует только завершённый этап
после проверок/ревью согласно действующей git-политике, сохраняя прежние изменения.
