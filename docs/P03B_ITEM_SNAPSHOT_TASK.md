# P03b — локальный сбор реакций и снимок runtime предметов

Дата: 2026-09-13. Редакция 1. **Только ТЗ; код P03b не реализован.**
Независимое ревью фиксируется отдельно в [P03B_REVIEW.md](P03B_REVIEW.md).
Нормативная база: принятый P03a, P02 и контракт 0.5 draft-2, разделы 3, 5, 6, 9.
При противоречии общей будущей API и этого ограниченного среза действует этот пакет.
Для реализации необходимо отдельное поручение пользователя и свежий входной gate.

## 1. Пакет исполнителю и сохранность

```yaml
task_id: P03B-ITEM-SNAPSHOT
role: game_coder
model: gpt-5.6-luna
reasoning: medium
base_commit: 2dae04de093ca23e579559767dbda98ffe9b160f
branch_at_preparation: main
dependency_manifest: docs/P03B_DEPENDENCIES.json
goal: Из одного снимка получить независимые board/items A и B с теми же ids, modifiers и описаниями реакций, без повторного equip.
contracts: ["Этот документ, редакция 1", "P02 schema v1 без изменений", "P03a ownership"]
non_goals:
  - Command, ActionEvent, HealCommand, ActionQueue, ActionContext, RNG, revision/sequence allocator
  - Исполнение лечения, подписки gameplay, подключение к сцене/preview/confirm
  - Новый save-game, миграция legacy save, неизвестный контент, cooldown/charges
  - Экономика ходов, Push, BT, общий S-5, полный C-3/T10/0.8
  - Коммиты кодером, дальнейшая делегация, изменение sandbox/доверия
```

Вход подготовки: main/HEAD совпали с передачей, **25/25** SHA-256 принятого P03a
совпали. Исторический P03A_DEPENDENCIES содержит входы до реализации: не подменять им
таблицу принятого результата. Текущие входы P03b перечислены в новом manifest.
P01/P02 остаются частично незакоммиченными зависимостями: чистый checkout base_commit
не является достаточной базой реализации. Их наличие и байты проверяются по manifest.

Перед работой проверить HEAD/status, все hashes manifest и hashes ТЗ/manifest в ревью.
После documentation-only коммита допускается новый HEAD только после проверки diff от
base_commit: ни одного изменения кода, входные hashes по-прежнему совпадают. Любая другая
смена API/hash требует пересборки пакета. Текущий HEAD после подготовки — в передаче.

Начальное рабочее дерево: modified — ARCHITECTURE/DECISIONS/TESTING, board, damage,
Stat/StatsBag/UnitState, tests/run_tests.gd; untracked — .codex/, AGENTS.md, CODEX_HANDOFF,
CODEX_WORKFLOW, COMMAND_ACTION_QUEUE_CONTRACT, MECHANICS_REQUIREMENTS, P02_SNAPSHOT_TASK,
scripts/core/actions/. Полный status и hashes 176 прежних файлов сохранены локально в
игнорируемых test_reports/p03b-preparation-*; они не обязательны для переносимого пакета.

Ты не один в checkout. Сохранять прежние hunks и файлы, не форматировать попутно.
Только один пишущий кодер. Не делегировать. При CONTRACT_GAP/NEED_CONTEXT вернуть
точный вопрос ведущему; не расширять область работы и не угадывать отсутствующий API.

### Разрешённые пути будущей реализации

Изменять только:

- scripts/core/items/item_owner_state.gd
- scripts/core/items/item_instance.gd
- scripts/core/items/item_effect_runtime.gd
- scripts/core/items/stat_modifier_effect_runtime.gd
- scripts/core/items/heal_on_damage_effect_runtime.gd
- scripts/core/inventory/inventory_state.gd
- scripts/core/inventory/equipment_state.gd
- tests/run_tests.gd — добавлять вызовы/функции P03b, сохранять весь прежний регресс.

Создать только следующие `.gd` и соответствующие новые `.gd.uid`:

- scripts/core/actions/item_simulation_state.gd
- scripts/core/actions/item_simulation_snapshot.gd
- scripts/core/actions/item_snapshot_result.gd
- scripts/core/actions/item_reaction_collector.gd
- scripts/core/actions/item_reaction_result.gd

Документы статусов и передачу обновляет ведущий. Definitions, существующие `.uid`,
ресурсы/сцены, legacy demo sink, P02 codec/BoardSnapshotResult, stats/units/board/damage
и проектные настройки закрыты для записи. Если без их изменения задача не решается,
вернуть CONTRACT_GAP. Изолированный wrapper поверх P02 выбран намеренно: не менять
схему P02 и не расширять молча прежний board-only capability promise.

## 2. Факты кода и новый шов

P03a уже хранит один ItemOwnerState на UnitState, registry всех созданных предметов
(включая detached), placements 0/1/100..102, inventory_order и два next-id счётчика.
Inventory и Equipment активируют эффекты одинаково; detached не активен.
Снятие не удаляет registry и не возвращает ids. close контейнера оставляет retired,
close владельца деактивирует все предметы и запрещает повторную регистрацию.
ItemInstance хранит immutable definition reference и копию массива runtime.
Каждый occurrence эффекта имеет собственный id и effect_index исходного массива.

Стат-эффект добавляет один StatModifier с source `p03a/o<unit>/i<item>/e<effect>`.
P02 уже сохраняет этот modifier, его local_slot, evaluation_order и next_modifier_slot;
поле P02 modifier.instance_id сейчас **0**, его нельзя заменить id эффекта.
Heal runtime содержит только amount/trigger/ids/active, не содержит UnitState/подписок.
Текущий get_active_heal_effects сортирует по effect id. LegacyItemDemoSink исполняет
лечение лишь в старом демо; этот объект не переносится в новый state или snapshot.

**Новые типы ниже — требования, не существующие API.** ItemSimulationState — ограниченный
composition root board/items для harness. Упоминание будущего ActionContext в P03a
уточняется: в P03b его обязанность единственного owner registry принимает этот тип;
P04 позже включает его в ActionContext. Ни очередь, ни RNG, ни ресурсы новой экономики
не добавляются. Значения прежних move_points_left/has_attacked сохраняет P02.

## 3. API и владение

Все новые классы — строго типизированные RefCounted. Dictionary только для value DTO
и индексированных реестров с явно проверенными типами ключей/значений.

```gdscript
# ItemSimulationState; конструктор копирует входные контейнеры, не объекты runtime.
_init(board: BattleBoard, owners: Array[ItemOwnerState],
      inventories: Array[InventoryState], equipment: Array[EquipmentState])
get_board() -> BattleBoard
get_owners() -> Array[ItemOwnerState] # новая оболочка массива
get_owner(unit_id: int) -> ItemOwnerState
get_inventory(unit_id: int) -> InventoryState # null, если никогда не было/retired
get_equipment(unit_id: int) -> EquipmentState # аналогично

# ItemSimulationSnapshot
static capture(state: ItemSimulationState,
               unsupported_runtime_ids: Array[StringName]) -> ItemSnapshotResult
static from_dict(data: Dictionary) -> ItemSnapshotResult
to_dict() -> Dictionary
instantiate(definitions: Dictionary) -> ItemSnapshotResult # StringName -> ItemDef
canonical_values() -> Array
canonical_bytes() -> PackedByteArray
fingerprint() -> String # SHA-256, lowercase hex

# ItemReactionCollector — один вызов на одно уже зафиксированное событие
static collect_damage(state: ItemSimulationState, event: Dictionary) -> ItemReactionResult
```

ItemSnapshotResult.Code = {OK=0, SNAPSHOT_UNSUPPORTED=1, SNAPSHOT_INVALID=2, SNAPSHOT_BUSY=3}.
Поля code, reason:String (стабильный путь), unsupported_ids:Array[StringName],
snapshot:ItemSimulationSnapshot, state:ItemSimulationState. При capture/from_dict OK
заполнен только snapshot; при instantiate OK — только state. При ошибке оба null.
diagnostics и их accessor'ы не возвращают заимствованные mutable контейнеры.
Новые enum не меняют BoardSnapshotResult.Code. SNAPSHOT_BUSY означает owner._guard=true,
а не наличие ещё не реализованной очереди. Закрытый owner допустим, busy snapshot — нет.

ItemSimulationState не создаёт UnitState/ItemOwnerState автоматически и не исправляет
переданные данные. capture/collect проверяют его целиком: board, по одному owner на
**каждый** unit в board registry (включая трупы и юнитов вне occupancy), без лишних owners.
owner.get_owner() должен быть тем же объектом, что в board, а не просто иметь тот же id.
В пустой доске все три массива пусты. Повторная передача owner даже тем же объектом — INVALID.
Нельзя скрыть содержимое ошибочного массива предварительным преобразованием в map.

Массивы фасадов содержат ровно по одному открытому фасаду на каждый registered флаг
owner; фасад._state совпадает по object identity. Нельзя передавать closed/retired фасад,
два фасада одного типа одного owner, фасад другого owner или оставить registered без
фасада. Never-created/retired/closed owner не имеют соответствующего открытого фасада.
Состояние хранит копии контейнеров, ссылки board/owner/facade принадлежат данной симуляции.
Live composition не получает подписок и не мутируется при оборачивании.

При instantiate все mutable объекты принадлежат новой симуляции: board/provider/units,
StatsBag/Stat/каждый modifier occurrence, Vitals, owner/item/effect, facade и контейнеры.
Они попарно различны в live/A/B. Допускается разделение только definitions как immutable
Resources. Definitions никогда не содержат per-owner данных; копирование Resource ради
владения не используется. DTO/diagnostics/reaction descriptions содержат только значения.

## 4. Формат snapshot v1

Это отдельный envelope: `schema_version:int=1`,
`scope:String="board_items_two_effects_v1"`, `board_snapshot:Dictionary`, `owners:Array`.
board_snapshot — точный P02 envelope со своим `schema_version=1` и
`scope="board_only_no_items_v1"`; здесь он описывает **только проекцию board**, а items
покрыты внешним envelope. Этот вложенный DTO не является самостоятельным полным снимком
предметного мира. Прежний публичный capture_board с items по-прежнему требует декларации
unsupported; только wrapper после полного собственного preflight вызывает P02 с пустым
списком для уже покрытой им board-проекции. Нельзя просто выкинуть external unsupported ids.

Все перечисленные ключи обязательны и исчерпывающи. Только String keys, не StringName.
Ни null, Object/Resource/Node/Callable/Signal, ни path к ресурсу в DTO не допускаются.
Массивы обычные Array, bool не принимается вместо int, int не принимается вместо float.

Owner record:

| Ключ | Тип / значение |
|---|---|
| schema_version | int 1 |
| owner_unit_id | int > 0, ссылка на board registry |
| next_item_id, next_effect_id | int 1..MAX_INT64, MAX_INT64 — exhausted sentinel |
| closed | bool |
| inventory_lifecycle, equipment_lifecycle | int: 0 never-created, 1 registered, 2 retired |
| inventory_order | Array[int] id активных inventory items, семантический порядок |
| definitions | Array definition descriptors (весь owner._definitions) |
| items | Array item records (весь owner._items, включая detached) |

Definition descriptor: `{id:String, effects:Array}`. id непуст; effects сохраняет исходный
порядок occurrences и допускает повтор одного определения эффекта. Effect definition
descriptor — строго одна из форм:

- `{kind:String="stat_modifier", stat_type:int(0..6), operation:int(0..2), value:float}`;
- `{kind:String="heal_on_damage", trigger_event:int=0, heal_amount:float>=0}`.

Все float конечны. Display_name/description/resource_path не влияют на симуляцию, не
сохраняются и не входят в fingerprint; при restore берутся у инжектированного definition.
Неизвестный concrete script ItemDef/Item (т.е. их пользовательский subclass) либо
effect/runtime subclass — UNSUPPORTED. Допустимы точные ItemDef и совместимый Item,
StatModifierEffect и HealOnDamageEffect с точными runtime классами.

Item record: `{item_instance_id:int, definition_id:String, placement:int, active:bool,
effects:Array}`. Placement строго 0, 1, 100, 101, 102. Active равен placement != 0.
Effects — массив runtime records; нормализуется по effect_instance_id; соответствие
порядку definition задаёт `effect_index`, а при создании ItemInstance его массив собирают
по этому индексу. Нельзя перепутать canonical порядок records с порядком occurrences.

Runtime record имеет общие ключи `effect_instance_id:int`, `effect_index:int`,
`active:bool`, `kind:String`, плюс поля:

- stat_modifier: `stat_type:int`, `operation:int`, `value:float`, `source_key:String`,
  `modifier_link:Array` (пустой для inactive; ровно один record для active);
- heal_on_damage: `trigger_event:int=0`, `heal_amount:float>=0`.

Modifier link record: `{stat_type:int, source_id:String, instance_id:int=0,
local_slot:int}` — ссылка на **уже сохранённый** modifier конкретного owner в P02.
Source_key обязан равняться точной формуле P03a для owner/item/effect. Link.stat_type
равен runtime.stat_type; source_id равен source_key. evaluation_order хранится только
в P02, не дублируется. Heal не имеет modifier link. Runtime owner/item ids выводятся
из вложенности; при capture сравниваются с реальными getters и не теряются при restore.

## 5. Инварианты и fail-closed проверка

До создания новой доски/юнитов/runtime и до глубокого копирования больших массивов
проверить форму, версии, лимиты и весь граф ссылок raw DTO. Не принимать циклический
Dictionary/Array, алиасы контейнеров можно принять и развести копированием; рекурсивный
обход с ограничением глубины. MAX_DEPTH=32; MAX_STRING_BYTES=4096 на каждую строку,
MAX_ITEMS_TOTAL=4096, MAX_EFFECTS_TOTAL=16384, MAX_DEFINITIONS_TOTAL=4096,
MAX_DEFINITION_EFFECTS_TOTAL=16384, MAX_VALUE_NODES=2000000 (каждое посещённое значение,
включая ключ и каждое повторное вхождение alias). Число owners равно числу units и
не больше 65536. Board дополнительно имеет неизменные лимиты P02: side<=1024,
cells<=65536. Эти ограничения применяются ко всему внешнему DTO, включая board_snapshot.
Перебор на preflight допустим; duplicate/resize по непроверенному count запрещён.

1. Item ids уникальны в owner и лежат в 1..MAX_INT64-1; effect ids уникальны во всём
   owner, не лишь в item. Каждый next counter строго больше всех своих ids, включая
   detached, и сохраняет промежутки. При пустом registry next может быть >1. MAX_INT64
   допустим только как counter sentinel; restore не расходует ids. Счётчик эффектов может
   быть exhausted при создании предмета без эффектов по прежнему правилу P03a.
2. Definitions уникальны по id в owner; каждый item ссылается на descriptor, descriptor
   в registry может существовать без item. В разных owners один id обязан описывать одно
   и то же содержимое effects: единый battle catalogue. Разные id могут иметь одинаковый
   контент. При capture definition reference/закэшированный id и owner._definitions
   должны быть согласованы по identity. Редактирование definition после создания runtime
   не поддерживается: расхождение runtime scalars/descriptor даёт INVALID, не silent repair.
3. Effect count равен definition.effects.size; indices — перестановка 0..count-1 без
   дублей. Kind и все скаляры совпадают с definition occurrence. Active каждого runtime
   равен item.active. Неизвестный kind/trigger/enum — UNSUPPORTED; повреждённый тип,
   NaN/Inf, отрицательное heal, неверный id/link — INVALID. Empty effects допустим.
4. Placements и item._placement согласованы, _placements имеет ровно ключи _items.
   Inventory_order содержит каждый placement=1 ровно раз и ничего другого. В одном
   equipment slot не больше одного item. Неактивные detached сохраняются полностью.
   Inventory/equipment placement требует lifecycle=registered. Retired несовместим с
   registered; closed owner требует оба lifecycle=retired, все items detached/inactive,
   inventory_order пуст. Closed не очищает ids, definitions или registry.
5. Каждый active stat runtime имеет ровно один modifier во всём StatsBag своего owner
   с его source_key; проверяются stat_type, operation, value, instance_id=0 и local_slot.
   Дубликат source в другой stat, отсутствие, лишнее occurrence или неверный link — INVALID.
   Inactive source не должен встречаться нигде. Любой source_id с префиксом `p03a/`
   во вложенном board должен соответствовать ровно одному active stat runtime данного
   unit. Осиротевший/чужой/невалидно сформированный reserved source — INVALID.
   Все остальные modifiers чужие: сохраняются точно P02, не удаляются и не присваиваются
   предметам. Неактивный item с конфликтующим чужим reserved source отклоняется.
6. Guard, exact supported classes и ownership проверяются на live capture; malformed
   state отклоняется без сигналов, исправления cache, выдачи ids и подписок. P02 stale
   clean cache остаётся INVALID, dirty cache не входит в DTO. Порядок арифметики сохраняется.
7. Unsupported_runtime_ids — обязательная декларация composition root для внешних
   gameplay listeners/runtime/AI/RNG и прочих непокрытых состояний; непустой список даёт
   UNSUPPORTED, уникальные ids сортируются Unicode code point. Пустой список **не**
   доказывает отсутствие произвольных callbacks: общий C-3 detector не заявляется.
   Известные owner/items/effects wrapper проверяет сам, неизвестные не пропускает даже
   если caller передал []. LegacyItemDemoSink запрещён декларацией внешнего runtime.

При нескольких ошибках приоритет: внешний unsupported list → owner guard BUSY →
лимиты/неверная форма INVALID → неизвестная поддерживаемая форма/версия UNSUPPORTED →
нарушение связности/данных INVALID. Для одинакового DTO диагностический путь стабилен;
выбор первого owner/item/effect при корректных ids идёт по числовому id. Закрытый owner
не busy. Неправильный тип версии INVALID, неизвестное целое version/scope UNSUPPORTED.

## 6. Capture и восстановление без equip

Capture строит value-представление owners, verifies modifier links по board DTO и
возвращает immutable-by-API snapshot. from_dict делает такую же валидацию графа без
ResourceLoader и без необходимости иметь definitions. to_dict/canonical_values всегда
возвращают глубокие value copies; входной DTO после from_dict не заимствуется.

`instantiate(definitions)` получает явный каталог StringName -> ItemDef. Для каждого
descriptor нужен ресурс с точным id и тем же ordered effect content; отсутствующий id
или неизвестный concrete type — UNSUPPORTED, неверные параметры/ключи/тип значения —
INVALID. Дополнительные entries каталога допустимы, не используются и не сохраняются;
их контейнер не заимствуется. Definitions со скалярами NaN/Inf недопустимы.
Никакого поиска по resource_path, fallback на ResourceLoader или пересоздания definitions
из DTO. Одинаковый id во всех owners привязывается к одному объекту каталога.

Последовательность успешного restore:

1. Полностью проверить raw граф и весь требуемый каталог; только затем instantiate_board
   из вложенного P02 snapshot. Не вызывать UnitState.create, UnitId.next/set/reset,
   begin_turn/refill и старые Unit/Board.from_dict.
2. Создать owner каждого нового UnitState, установить его ids/counters/lifecycle/registry
   напрямую через новый внутренний restore путь. Создать ItemInstance и runtime с
   сохранёнными ids/скалярами; привязать owner только к **новому** UnitState.
3. Восстановить placements, ordered effects, inventory_order, active/closed флаги, defs
   registry. Не вызывать create_item, create_runtime definitions, add_item/equip,
   _activate_while_guard, legacy Inventory/Equipment.from_dict, add/remove_modifier.
   Параметры runtime уже валидированы; constructors runtime без побочных эффектов разрешены.
4. Проверить/связать modifier records в новой StatsBag по modifier_link без нового
   modifier и без изменения local_slot/next_modifier_slot/evaluation_order. Отдельная
   ссылка на Resource не обязательна: существующий source key остаётся способом снятия.
   Если она введена, должна указывать только на новый modifier occurrence.
5. Создать ровно один facade для каждого lifecycle=registered внутренней restore factory,
   которая связывает facade._state без register/equip/сигналов. Never-created/retired не
   получают фасадов; retired остаётся неперерегистрируемым, never-created допускает
   обычный InventoryState.new/EquipmentState.new после restore. Обновить composition
   state при последующем создании фасада надо новым оборачиванием тех же runtime объектов.
6. Вернуть целиком собранный ItemSimulationState, без live callbacks/внешнего sink.
   Публикация частичного state на любой ошибке запрещена. Не делать rollback через
   public close/remove, которые меняют modifiers/публикуют signals.

После restore обычные API работают как P03a: remove A снимает только его source;
equip того же item в тот же slot — no-op; detached можно активировать один раз;
clear/close сохраняют ids и чужие modifiers, facade.close retired необратим.
Новый snapshot не используется как legacy fresh-equip save. Runtime-записи versioned
внешним schema и owner.schema_version; отдельно импортировать голый item в live запрещено.

## 7. Локальные описания реакций — без исполнения

Event — точный value Dictionary `{event_seq:int, target_unit_id:int, dealt:float}`.
seq в 1..MAX_INT64-1 выдаёт caller, collector его не расходует; target id >0;
dealt конечное и >=0. Это специализированный damage seam, не новый общий ActionEvent.
Вызов только после фиксации damage и обязательной очистки смерти/occupancy. Состояние
проверяется по тем же owner/runtime/link правилам; guard возвращает BUSY. Caller отвечает
за принадлежность события данной симуляции: event не содержит Godot/live object refs.

ItemReactionResult.Code={OK=0, UNSUPPORTED=1, INVALID=2, BUSY=3}; code, reason:String,
descriptions:Array[Dictionary] с глубоким копированием при выдаче. Ошибка возвращает []
и не выдаёт частично собранные реакции. Нет target в board — INVALID; неизвестный active
runtime — UNSUPPORTED. При dealt=0, dead target или closed owner успешный пустой список.
При alive target и dealt>0 каждый active HealOnDamageEffectRuntime с trigger=0 даёт один
record, даже при heal_amount=0 или полном HP: фактический эффект позднее определяет команда.

Description — строго `{kind:String="heal", event_seq:int, priority:int=0,
owner_unit_id:int, item_instance_id:int, effect_instance_id:int, local_index:int=0,
target_unit_id:int, definition_id:String, heal_amount:float}`. Target — сам owner damage.
Сортировка `(event_seq, priority ASC, owner_unit_id, effect_instance_id, local_index)`
из контракта 0.5; одинаковые полные ключи запрещены (INVALID), не дедуплицировать silently.
Item id/definition id сохраняются для диагностики/валидации. Для двух effects одного
Resource создаются две descriptions с разными effect ids. Inventory и equipment равноправны.

Collector ничего не лечит, не мутирует active/counters/cache, не потребляет RNG, не
подписывается на signals и не хранит descriptions как pending runtime. Повторный collect
одного event возвращает тот же результат без дедупликации между вызовами; ровно-однократную
доставку обеспечивает P04. Никакого EventSink или GameEventBus в новых actions/items.

Шов P04: queue преобразует description в HealCommand, при исполнении снова проверяет
наличие owner/item/effect, identity по registry, active/closed и alive target. Если между
collect и исполнением item сняли, owner закрыли или цель умерла, последствие SKIPPED.
В P03b проверяется только значение описания и отсутствие побочных эффектов; реальные
heal/death/execute-preview parity и глобальные event_seq/priority policy остаются P04+.

## 8. Канонизация

Новая внешняя сигнатура bytes: ASCII `P03B` и один байт версии `1` — hex `50 30 33 42 01`.
После неё кодировать canonical_values теми же правилами type tags P02:
bool=1+байт 0/1; int=2+8 байт signed two's complement LE;
float=3+IEEE754 binary64 LE; String=4+u64 LE длина UTF-8+bytes;
Array=5+u64 LE count+элементы. Dictionary становится Array пар [String key, canonical value],
ключи по Unicode code point; float -0 нормализуется в +0. Других value types нет.
Не использовать JSON/hash()/var_to_bytes как замену codec. P02 bytes/headers неизменны.

Owners/items/effect records сортировать по числовым stable ids; definitions по String id.
Board_snapshot нормализовать ровно как P02. Definition.effects, inventory_order и P02
evaluation_order семантические, не сортировать. Runtime effects восстанавливаются по
effect_index. Lifecycle/counters/detached/closed и все links входят в fingerprint.
Регистрации реакций выводятся из active runtime, не сохраняются отдельным дублирующим
списком; их полный ключ и порядок проверяются тестом collect. Журнал событий не хранится.
Fingerprint покрывает ровно этот scope, не RNG/очередь/правила будущего preview token.

## 9. Критерии приёмки будущей реализации

Проверять значения, object identities, canonical_values **и** bytes, а не один hash.
Сохраняются все прежние 722 assertions; число новых не предписано, каждый пункт обязателен.

| ID | Сценарий / ожидаемый результат |
|---|---|
| B01 | Одна def на двух owners, две копии у одного, повторённый effect Resource: capture→instantiate A/B→capture равен исходнику; modifiers не удвоены (STR base3+2+2=7), HP/balance/остатки/P02 board неизменны |
| B02 | Live/A/B попарно не разделяют mutable objects/arrays/modifiers/facades; мутации в обе стороны, remove A, re-equip/clear/close B, смерть/occupancy A не меняют остальных; immutable definitions могут быть общими |
| B03 | Detached, пустой effects, nondefault inventory order, все equipment slots в порядке, отличном от item ids; ids с промежутками, большие int64, exhausted counters, remove→snapshot→create даёт те же следующие ids, что исходник |
| B04 | Все lifecycle комбинации: never-created, registered, retired, closed owner с удержанными item/runtime; после restore getters/clear/close/re-registration сохраняют поведение P03a; два фасада/пропущенный зарегистрированный/чужой по identity — INVALID |
| B05 | Modifier linkage: все 3 operations/7 stats; чужие source сохраняются; remove одной из копий оставляет другую и чужой modifier. Отсутствующий/дублированный/wrong stat/op/value/slot link, source другого owner, inactive source, orphan reserved prefix отвергаются до instantiate |
| B06 | Raw/live негативные: дубли owner/item/effect ids/indices/slots/order, missing owner для пустого unit/трупа, лишний owner, поддельный UnitState с тем же id; counters<=max/overflow/sentinel id, NaN/Inf/неверные типы, bad placement/active, broken defs registry — INVALID |
| B07 | Exact type capability: неизвестный def/effect/runtime/subclass, неизвестные version/kind/trigger — UNSUPPORTED, external unsupported ids отсортированы/уникальны. P02 AI/subclasses/stale cache правила сохранены; busy сигнал callback capture не снимает guard и не меняет live |
| B08 | Каталог: отсутствующий def, изменённый id/ordered effects/параметры, конфликт same-id между owners отвергаются; in-memory defs без path восстанавливаются; перестановка catalogue/map не влияет; лишние неиспользуемые entries не меняют snapshot |
| B09 | Collect damage: две копии/два occurrences/оба контейнера, порядок ключа, неизменные runtime/stat cache/HP/counters/signals; повтор collect равен; zero damage/dead/closed→[], full HP/amount0→описание, чужой target INVALID, busy/unknown runtime явный отказ |
| B10 | После restore collect live/A/B одного value event даёт одинаковые descriptions; мутация входного event/полученного массива/record не меняет snapshot/runtime/следующий результат. После remove/close/death новые collect не выдают снятые реакции; выполнение лечения не имитировать тестовым production callback |
| B11 | Canonical permutations owners/items/effects/defs/maps равны; перестановки semantic inventory/definition effects/evaluation_order меняют состояние или отклоняются как несовместимые. Literal byte fixture внешнего envelope независимо задан, high int64, Unicode, -0, float order; P02 literal/oracle fixtures прежние |
| B12 | DTO ownership: мутировать вход from_dict, результат to_dict/canonical_values, bytes и diagnostics; повторные instantiate неизменны. Лимиты на границе и +1 для всех caps, циклы/глубина/alias graph, malformed huge array до нового board/runtime allocation |
| B13 | Ни одного equip/legacy load/activation/add_modifier на пути restore; next_modifier_slot, local_slot и evaluation_order неизменны; N capture/instantiate/collect не меняют UnitId allocator, live signals/подписки/P02 provider; unknown input не публикует partial state |
| B14 | Полный прежний регресс P01/P02/P03a, legacy fresh-equip/demo API и .tres/.uid неизменны; корректный лог без новых parse/compile/runtime ошибок; независимое ревью фиксированных hashes реализации |

Обязательные команды из корня после реализации (GODOT_BIN только в окружении процесса;
если необходимо, APPDATA временно в test_reports/godot-profile с восстановлением):

```powershell
& $env:GODOT_BIN --path . --headless --import --log-file test_reports/p03b-import.log
& $env:GODOT_BIN --path . --headless --quit-after 3 --log-file test_reports/p03b-startup.log
& $env:GODOT_BIN --path . --headless --script tests/run_tests.gd --log-file test_reports/p03b-tests.log
git diff --check
```

Нужны exit 0, scan DONE/все новые class_name в cache, N passed/0 failed (весь прежний
регресс и B01–B14). Known certificate-store и ожидаемый occupied-cell P01 error отдельно
от новых ошибок. Ведущий проверяет call graph restore/collect и hashes закрытых файлов;
не подменяет allocator invariance временным next/reset. Визуальный прогон не требуется
для нового pure core среза; прежнее демо UI-unverified не становится verified автоматически.

После проверок остановить запись, передать фиксированные hashes/diff/logs независимому
game_reviewer Terra/high. Он не пишет/не делегирует. Ведущий проверяет snapshot ownership,
modifier linkage, determinism и границу будущей очереди. До приёмки кода нужно отдельное
ревью реализации; одобрение этого документа его не заменяет.

## 10. Завершение и границы следующего этапа

Отчёт исполнителя: статус, изменённые пути, B01–B14 с проверками, команды/exit codes,
непроверенное и точный CONTRACT_GAP. Логи/полный diff не пересказывать.
Ведущий обновляет затронутые статусы/контракты и CODEX_HANDOFF, проверяет сохранность
прежних изменений и делает логический локальный коммит только завершённого этапа.

P03b закрывает snapshot/collection часть предметов для двух эффектов. T10 реального
heal в execute/preview, T11 RNG/idle queue, полный C-3/0.5/0.8 и S-5 остаются открытыми.
Следующий пакет P04 — отдельное поручение в новом чате с актуальной передачей.
Неопределённая экономика ходов и Push здесь не выбираются и не блокируют этот срез.
