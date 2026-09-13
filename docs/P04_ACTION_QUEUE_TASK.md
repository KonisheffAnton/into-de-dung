# P04 — минимальная очередь Damage / Heal / Death

Редакция 1, 2026-09-14. **Это ТЗ, игровой код P04 ещё не реализован.**
Реализация запускается отдельным поручением. Пакет специализирует draft-2 контракта
0.5, §§3–5, 7, 9 и 13; не подтверждает старое утверждение draft-2 о цене атаки.

## 1. Вход и границы

- task_id: `P04-ACTION-QUEUE`; base: `main`,
  `006fe1eaeca9fe19e97eed1b9030c0d565286b3a`.
- Обязателен сохранённый dirty checkout P01/P02 и процессные документы. Чистого HEAD
  недостаточно. Проверить файлы по `P04_DEPENDENCIES.json`, hashes пакета — по `P04_REVIEW.md`.
  Коммит документации P04 может быть потомком base; между ними допустимы только документы
  P04. При других изменениях входов вернуть CONTRACT_GAP, не подгонять hashes.
- Входной gate уже проверен: 17/17 hashes таблицы принятого P03b в передаче и 43/43
  неизменённых зависимостей P03B_DEPENDENCIES. Исторический manifest P03b не переписывать:
  таблица результата замещает его входные hashes, включая новые actions/.uid.
- Результат: headless harness исполняет одну цепь с реальным HP/death, двумя существующими
  item effects и детерминированным value-журналом. Нет интеграции UI/старого демо.
- Non-goals: MoveCommand, AttackCommand, Push/impact/balance, геометрия/стоимости,
  ActionResources, preview/token/confirm, snapshot контекста/очереди, Battle Flow, BT,
  новые статусы, награды, revival, save-game и миграция общего RNG/legacy callbacks.
  Стоимость атаки, переключения персонажей и Push не нужны P04 и остаются открытыми.

## 2. Владение и существующий шов

`ActionContext` — новый RefCounted composition root. Он удерживает **те же** объекты
одного `ItemSimulationState`, инжектированные RNG-порт и value sink, явный список
`unsupported_runtime_ids`. Не клонирует и не переэкипирует runtime. Board владеет
registry/occupancy/позициями; Vitals — HP/alive; ItemOwnerState — item ledger.
Контекст владеет sequence counters, revision, busy/fault latch. Очередь — work stack,
processed events/reaction keys и журнал текущего root. Один writer на контекст; две
очереди на одном контексте не могут обойти BUSY или FAULTED. Сами ссылки нельзя менять
во время drain; внешняя мутация боя в callbacks запрещена контрактом harness.

До root выполняется `ItemSimulationSnapshot.capture(state, unsupported_runtime_ids)`:
проверяются состав, capability и guards, без restore и без изменения live cache.
INVALID/UNSUPPORTED → REJECTED с reason; BUSY → REJECTED/BUSY. Это ограниченный gate
P03b, не автоматическое обнаружение всех внешних gameplay callbacks (общий C-3 открыт).
После изменения открытых inventory/equipment facades caller создаёт новый
ItemSimulationState и новый idle контекст вне цепочки. P04 не вводит hot-swap API.

Адресные существующие API (не менять их):

| API | Использование |
|---|---|
| `ItemSimulationState.get_board/get_owner/get_inventory/get_equipment` | Свои board/owner/facades; retired facade даёт null |
| `BattleBoard.get_unit_by_id`, `clear_occupancy`, `board_version` | Повторный lookup; очистка idempotent, труп остаётся в registry |
| `UnitState.is_alive`, `Vitals.get_hp/get_hp_max/apply_damage/heal` | Только эти HP mutators; no direct fields |
| `ItemReactionCollector.collect_damage(state, event) -> ItemReactionResult` | Ровно `{event_seq:int,target_unit_id:int,dealt:float}`; нельзя передать весь ActionEvent с лишними полями |
| `ItemReactionResult.code/reason/descriptions` | OK/INVALID/UNSUPPORTED/BUSY; описания — копируемые значения |
| `ItemOwnerState.get_owner/is_closed`, `_items`, `_guard`, `_is_registered_item` | Внутреннее чтение ledger допустимо только в reaction adapter, без записей |
| `ItemInstance.get_definition/get_definition_id/get_item_instance_id/get_owner_unit_id/get_effects/is_active` | Массив effects копируется, объекты runtime прежние |
| `ItemEffectRuntime.get_owner_unit_id/get_item_instance_id/get_effect_instance_id/get_effect_index/is_active` | Проверка конкретного occurrence |
| `HealOnDamageEffectRuntime.get_heal_amount/get_trigger_event` | ON_DAMAGE_TAKEN и сумма из принятого runtime |

P03b preflight гарантирует owner на каждый unit, включая умерших; не обходить его перед
collector. Legacy `DamageCalculator.apply` и `LegacyItemDemoSink` не вызываются новым
исполнителем: первый добавляет balance и использует ссылочный EventSink, второй лечит
синхронно. Старые API/тесты остаются. Общее для новых HP-команд выполнение сосредоточить
в новом `ActionHpExecutor`; не копировать HP arithmetic из Vitals.

## 3. Новый API (всё ниже планируется)

Все runtime/DTO — строго типизированные RefCounted, без Node/autoload. Числовые ids
в payload; private underscore — контракт внутреннего API, не security sandbox.
Принятый payload, source, результаты и event dictionaries рекурсивно копируются;
value DTO не содержат Object/Resource/Callable. Runtime identity refs допустимы только
в приватной pending reaction binding и никогда не попадают в receipt/journal.

| Тип / сигнатура | Обязательный контракт |
|---|---|
| `ActionContext.new(state: ItemSimulationState, rng: ActionRngPort, sink: ActionEventSink, unsupported_runtime_ids: Array[StringName])` | rng/sink обязательны (нулевой sink — базовый ActionEventSink); копирует список ids; counters=1, revision=0, idle; getters state/rng/revision/is_busy/is_faulted |
| `Command.copy_for_queue() -> Command` | Самостоятельная копия payload конкретного типа; null означает отказ входа |
| `Command.validate(context: ActionContext) -> StringName` | Пусто=OK, иначе reason; ни мутаций, ни draws/events. Базовая реализация возвращает unknown_command |
| `Command.execute(context: ActionContext) -> CommandStepResult` | Только очередь; базовая реализация — явная ошибка, не успех. Builtins делегируют ActionHpExecutor |
| `CommandStepResult` | status APPLIED/SKIPPED/FAULTED, reason; `events: Array[Dictionary]` drafts; `mandatory`, `reactions`: Array[Command]; `continuation: Command` nullable. Всё копируется до постановки в work stack |
| `ActionQueue.submit(command: Command, context: ActionContext) -> ActionReceipt` | Синхронно до drain/fault, без await/рекурсии; внешнего enqueue/push/process_event API нет |
| `ActionReceipt` | status APPLIED/REJECTED/FAULTED; reason; root_id, revision_before/after; steps/events через возвращающие копию getters. root_id=0 при отказе до admission |
| `ActionEventSink.publish(event: Dictionary) -> void` | Новый value-only presentation порт, базовый no-op; каждый вызов получает отдельную копию. Не старый EventSink |
| `ActionHpExecutor` | Внутренние damage/heal/death методы, общий finalize перехода смерти; точные внутренние сигнатуры выбирает кодер без расширения public API |
| `ItemReactionAdapter` | Внутреннее преобразование P03b descriptions в HealCommand + приватную identity binding; revalidate перед execute |

Steps содержат command_seq, parent_event_seq, kind, status/reason; skipped тоже шаг.
INTERRUPTED пока не требуется (нет многошагового движения); новые строковые статусы
не меняют старые сериализуемые enum. Builtins: DamageCommand, HealCommand, DeathCommand.
Для проверки scheduler разрешены тестовые subclasses Command только в runner. Контракт
их copy/validate/execute тот же, с явными ошибками; это доверенные реализации, не пользовательский
код. Дефолтный Command отклоняется. Не добавлять универсальный scripting/plugin registry.

### Payload HP

`DamageSource` — value DTO: `kind:StringName`, `source_instance_id:int`,
`origin_cell:Vector2i`, `instigator_unit_id:int`, `credit_unit_id:int`.
Разрешённые kind: attack/collision/fall/cell/status/item/test (это метки происхождения,
не реализованные системы). source_instance_id >= 0, unit ids >= UnitId.NONE (=0);
ненулевой instigator/credit обязан существовать в board, но может быть мёртв.
root/parent provenance выдаёт очередь, caller не может подделать его в source.

- `DamageRequest`: target_unit_id:int, amount:float, damage_type:StringName,
  armor_mode:StringName, source:DamageSource. `DamageCommand.new(request)` копирует запрос.
  damage_type только `physical`; armor_mode только `flat`/`bypass`.
  flat: `max(0, amount - target.stats.get_value(ARMOR))`, bypass: amount.
  Ни прибавления STRENGTH, ни impact. Конечность armor и результата проверить до mutator.
  Для чистой validate производное ARMOR читать через копию stat/snapshot, не прогревать
  live dirty cache. Отрицательная конечная ARMOR сохраняет текущую формулу, не clamp броню.
- `HealCommand.new(target_unit_id:int, amount:float, source:DamageSource)` — обычное
  лечение harness. Reaction variant создаёт только adapter, caller не передаёт binding.
- `DeathCommand.new(target_unit_id:int, source:DamageSource)` — явный летальный исход,
  без armor/фиктивного атакующего. Внутри вызывает Vitals.apply_damage(max(hp, 1.0)):
  величина получается из текущего HP, а не константы «999999». Для alive-at-zero тоже
  фиксирует переход. Генерирует только died, не damaged; это не удар и не триггер лечения.

Root Damage/Heal/Death допускаются только harness как внутренние эффекты: это не будущий
игровой ввод атаки. Target должен существовать, иметь stats/vitals и быть жив до admission;
иначе REJECTED. Числа amount — finite >= 0, ids positive < MAX_ID=9223372036854775807
(для NONE разрешён 0). После admission исчезнувшая/умершая цель дочернего HP command
даёт SKIPPED; неверный payload внутренней команды — FAULTED, а не SKIPPED.
Ни одна из команд не расходует/пополняет ресурсы действий и не проверяет активную команду.

## 4. Атомарный шаг, события и последовательности

1. При submit первым проверить queue/context busy, затем fault latch. BUSY возвращает
   REJECTED/BUSY, latch — REJECTED/CONTEXT_FAULTED, без изменения активной цепи.
   Поставить оба guards **до copy/validate/capability**, снять при ожидаемом отказе.
2. Validate/capability успешны → выдать root_id; REJECTED не расходует ни один counter,
   revision, RNG, HP/stat cache/item/board state и не публикует domain events.
3. Выполнить один шаг. Damage снимает HP через Vitals. P01 Vitals.died немедленно
   очищает occupancy; общий finalize дополнительно вызывает idempotent clear_occupancy
   только при зафиксированном alive→dead. Не удалять unit, не закрывать owner/items,
   не повторять cleanup со сменой version. Зафиксировать HP before/after/dealt и died
   до любых callback sink/collector. При dealt>0 draft damaged; затем draft died при
   переходе. Нулевой damage допустим, без damaged; alive-at-zero + положительный урон
   может дать died без damaged. Повторный damage/death трупу не публикует смерть.
4. Heal при hp >= hp_max или amount=0 — APPLIED без mutator и без события. Это сохраняет
   допустимый P02 over-max HP: Vitals.heal иначе может уменьшить HP до максимума.
   В остальных случаях Vitals.heal; только actual>0 даёт healed. Мёртвых не лечить.
5. Очередь, а не command/collector, нумерует event drafts в порядке damaged→died либо
   healed/died. `event_seq` глобально для контекста, без повторов между roots;
   `command_seq` также контекстный и выдаётся перед каждым выполненным/skipped шагом.
   `root_id` глобален внутри контекста, parent_event_seq=0 у root/не событийных детей.
   Реакция получает seq вызвавшего её события; её дочерние события наследуют этот parent.
6. После финализации всего шага собрать реакции всех его событий. Только damaged
   передаётся ровно раз collector в узком DTO §2; healed/died в P04 item реакций не имеют.
   Lethal damaged уже видит мёртвую цель и свободную клетку → descriptions пусты.
7. Work stack: mandatory → reactions → continuation; каждое поддерево завершить до
   следующего sibling. Реакции отсортированы по `(event_seq, priority ASC,
   owner_unit_id, effect_instance_id, local_index)`; обратная укладка в LIFO сохраняет
   этот порядок. Для тестовых `StepResult.reactions` сохраняется явный порядок массива;
   они идут после отсортированных item reactions данного шага. Dictionary order не нужен.

Каждый ActionEvent — ровно value fields: event_seq/root_id/command_seq/parent_event_seq:int,
kind:StringName (damaged/healed/died), actor_unit_id:int (=source.instigator),
target_unit_id:int, source:Dictionary указанной схемы, hp_before/hp_after/amount:float,
alive_before/alive_after:bool. Для died amount=0; HP поля относятся к вызвавшему переход
шагу. Нет ссылок на unit; нет балансных/позиционных событий в P04.
Очередь ведёт processed_event_seq и reaction key set на root. Повторный внутренний
dispatch уже обработанного события — no-op; дубли ключей **в одном новом batch** —
FAULTED/duplicate_reaction_key (не замалчивать malformed collector). Ключ реакции —
полный sort key; другой event_seq вправе вызвать тот же effect снова. Обработанные
ключи не удаляются при SKIPPED. Эти sets очищаются после root; публичного replay API нет.

revision увеличивается на 1 за шаг, изменивший HP/alive/occupancy или RNG/runtime
в тестовой команде; не за отдельное событие. No-op/SKIPPED revision не меняет.
Это revision только записей через очередь P04, не полный fingerprint боя/preview token.
StepResult дополнительно имеет `state_changed:bool`; builtins вычисляют по факту,
fixture обязана сообщить RNG draw. Нумерация сама revision не меняет.

После drain либо FAULTED опубликовать копии выполненного event prefix в sink в порядке
event_seq, сохраняя guards до завершения публикации. Sink не влияет на сбор реакций;
его reentrant submit получает BUSY. Receipt и sink copies независимы. Никаких
GameEventBusSink/LegacyItemDemoSink/глобальных подписок. Низкоуровневые Vitals signals
остаются; общий S-5 для произвольных callback мутаций не объявляется закрытым.

## 5. Повторная проверка реакции

Adapter после collect связывает description со своим owner/unit/item/runtime по ids;
сохраняет их object identity и immutable definition identity в приватной binding.
Binding создаётся после cleanup, до mandatory children. Перед **каждым** Heal execute:

1. Board lookup owner/target — тот же UnitState, state.get_owner(id) — тот же owner;
   owner.get_owner() — именно этот board unit; target id == owner id, target alive.
2. Owner open, `_guard == false`; `_items[item_id]` — тот же item и
   `_is_registered_item(item)` true. Item owner/id/definition_id/definition object
   совпадают с binding, item active и placement != 0.
3. В item.get_effects() ровно один прежний runtime с этим effect_instance_id;
   совпадают owner/item/effect ids, effect_index, конкретный HealOnDamageEffectRuntime,
   active, trigger ON_DAMAGE_TAKEN и конечный heal_amount == description.heal_amount.
4. Соответствующий placement открытого inventory/equipment по-прежнему принадлежит
   owner, lifecycle registered и не closed/retired. Inventory placement тоже активен:
   P03a активирует эффекты там, не требовать исключительно equipment.

Удаление/замена identity, detach, close/retire, неактивность или смерть → SKIPPED/
stale_reaction без HP/RNG/events. Никакого поиска «похожего предмета» взамен и повторного
collect при skip. Внешняя мутация definition/сломанный ledger/owner guard во время
drain — нарушение invariant: FAULTED, кроме явно перечисленных stale состояний.
Detach→reactivate **того же** runtime до исполнения допускает реакцию при выполнении
всех проверок; поколения активации P03a не имеет, новое правило здесь не вводить.
Object identity — локальная защита pending; порядок/журнал/детерминизм от адресов не зависят.

## 6. Лимиты, fault и RNG-порт

`ActionQueue.new(max_commands:int=256, max_events:int=512, max_depth:int=32)` копирует
лимиты; допустимы 1..4096, 1..8192, 1..64 соответственно. Невалидная конфигурация
даёт REJECTED/invalid_limits до admission. Root depth=0. Лимиты одинаковы для всех
roots экземпляра; не менять во время исполнения. Считаются выполненные и SKIPPED
commands, все emitted events, глубина parent-child (sibling не увеличивает depth).
Перед следующим шагом проверять command/depth capacity; при превышении FAULTED и
никаких мутаций этого шага. Event overflow после атомарного шага: сохранить **все**
его события и мутации, FAULTED до детей (разрешён overshoot не более размера этого
шага). Поэтому каждый шаг выдаёт не более 2 drafts; больший batch — invariant fault.
Это не скрытое обрезание журнала. Для fixtures ограничение также обязательно.

Для sequence int64 использовать диапазон 1..MAX_ID-1. До admission/каждого шага
резервировать возможность root/command/revision increment и максимум 2 event ids,
не расходуя неиспользованные ids. Нехватка до root — REJECTED/sequence_exhausted;
после начала — FAULTED/sequence_exhausted до следующей мутации. Без wrap/clamp.
Reserve revision консервативен даже для возможного no-op.

FAULTED сохраняет выполненный prefix/diagnostics и очищает pending, latch контекста
и очереди запрещает новые roots; guards освобождаются после выдачи prefix в sink.
Нет rollback, refund, retry/reset/clear_fault API; новый запуск — новый контекст/очередь
из заведомо корректного состояния harness. Ошибка collector после мутации, неизвестный
внутренний command, malformed step или violation контракта → FAULTED. GDScript не имеет
общего catch runtime exceptions: перехват произвольных script errors не обещать;
все штатные отказы представлены явными результатами, engine errors проваливают тесты.

`ActionRngPort : RefCounted` — минимальный инжектируемый интерфейс, не глобальный сервис:

```gdscript
func next_int(stream: StringName, upper_exclusive: int) -> int # [0, upper), -1 = ошибка
func clone() -> ActionRngPort # независимое mutable состояние; null = неподдержано
func to_dict() -> Dictionary # отдельный value DTO со schema_version и streams
func from_dict(data: Dictionary) -> bool # атомарная загрузка В ЭТОТ экземпляр
```

Base fail-closed: draw=-1, clone=null, to_dict={}, from_dict=false. Конкретный production
генератор не нужен: тестовый наследник реализует versioned состояние именованных потоков
и детерминированные draws, clone/round-trip. Порт гарантирует отсутствие draw/изменений
при неизвестном stream/upper<=0/невалидном import; caller трактует -1 как step FAULTED.
Для однозначной fixture: streams combat/loot, по одному int cursor>=0; последовательность
draw `(cursor % upper)`, затем cursor+1; int64 overflow — -1 без изменения. DTO
`{schema_version:1, streams:[{name:String, cursor:int},...]}` по имени (combat, loot),
exact keys, без duplicates/unknown names/negative/counter>=MAX_ID. Обе записи обязательны.
clone и from_dict не draw; импорт не alias; неизвестная версия — false с прежним состоянием.
Damage/Heal/Death/collector не потребляют RNG. Тестовая случайная дочерняя команда draw
из combat и порождает DamageCommand с amount=float(draw), чтобы проверить очередь.
Паритет двух независимых P03b instantiate + clone RNG проверяет этот шов, **не** preview.
Нельзя global rand/randomize, shared mutable streams, генерация карт/loot или RNG snapshot
контекста. Статический from_dict не требуется: это намеренно instance method порта.

## 7. Allowed paths и пакет исполнителю

Новые файлы (только перечисленные и их генерируемые `.gd.uid`):

```text
scripts/core/actions/action_context.gd
scripts/core/actions/action_queue.gd
scripts/core/actions/command.gd
scripts/core/actions/command_step_result.gd
scripts/core/actions/action_receipt.gd
scripts/core/actions/action_event_sink.gd
scripts/core/actions/action_rng_port.gd
scripts/core/actions/damage_source.gd
scripts/core/actions/damage_request.gd
scripts/core/actions/damage_command.gd
scripts/core/actions/heal_command.gd
scripts/core/actions/death_command.gd
scripts/core/actions/action_hp_executor.gd
scripts/core/actions/item_reaction_adapter.gd
```

Изменяемый существующий путь: `tests/run_tests.gd` — только отдельные `_test_p04_*`
функции/fixtures и их вызовы; сохранить все прежние строки/ожидания. Документацию
ARCHITECTURE/DECISIONS/TESTING/COMMAND_ACTION_QUEUE_CONTRACT/CODEX_HANDOFF обновляет
ведущий адресными новыми разделами после реализации; кодеру они закрыты. ТЗ/manifest/review
этого пакета не менять при реализации. Все остальные файлы, старые `.uid/.tres`, project,
demo и .codex/AGENTS закрыты. `test_reports/p04-*` — игнорируемые логи/QA ведущего.

Ведущий передаёт кодеру это ТЗ, base/manifest gate, адресные фрагменты §2; не всю библиотеку.
Рекомендуемое деление последовательных поручений: DTO/RNG port; очередь + HP/adapter;
затем tests. Одновременно только один coder; критические ownership/order/fault решения
проверяет ведущий. Не хватает API/allowed path — CONTRACT_GAP с точным местом; не расширять
scope самостоятельно. Помощники не делегируют/не коммитят. Независимый reviewer — после
завершения всех записей и import/tests на зафиксированных hashes.

## 8. Приёмка C01–C12

| ID | Проверяемый результат (все обязательны) |
|---|---|
| C01 | cell source с NONE instigator/credit: bypass и flat с ARMOR, no STRENGTH; actual overkill; source сохраняется; нет balance/action-resource изменений |
| C02 | damage→died порядок, одна domain смерть и один Vitals.died; occupancy свободна до collector; труп зарегистрирован; повторный cleanup не меняет version; root трупу REJECTED, child SKIPPED; DeathCommand и alive-at-zero |
| C03 | Heal partial/full/zero/over-max/dead, actual clamp, no revive/negative heal; zero damage no event; negative/NaN/INF/unknown damage type/armor mode/source/id — отказ без мутаций/cache/draw/counters |
| C04 | Две копии heal def у одного owner + общий def у другого, stat modifier сохранён: после damage точные две HealCommand по effect id, без повторного equip/modifiers; другой owner не лечится; lethal не лечится; heal_amount=0 сохраняет no-op step |
| C05 | Pending binding после collect: controlled fixture через mandatory children detach/close facade/close owner/kill target/remove или заменить unit/item/effect теми же ids — SKIPPED; active inventory работает; full identity/definition mismatch и guard fault различены. Приватный adapter seam тестируется прямо, не через запрещённые gameplay callbacks |
| C06 | Scheduler fixture: root, mandatory A с child A1, mandatory B, reactions R1 с child R1a, R2, continuation K → точный depth-first trace; shuffled insertion owners/items даёт тот же item/event trace |
| C07 | Вложенный submit из validate, execute, Vitals signal и final sink; та же/другая очередь с тем же context получают BUSY; чужой независимый context исполняется; pending/journal/counters внешней цепи не повреждены |
| C08 | Повторный внутренний dispatch seq не дублирует heal; два одинаковых ключа в новом batch FAULTED; тот же effect при новом damage event/root срабатывает снова. Caller меняет payload/description/receipt/sink copy — принятые значения не меняются |
| C09 | max_commands/events/depth ровно boundary и +1; цикл fixture даёт FAULTED, честный prefix/overshoot, pending очищен, latch запрещает следующий root даже из другой queue; нет end_turn/победы/rollback |
| C10 | preflight INVALID/UNSUPPORTED/BUSY не мутирует state; явный ошибочный child/collector failure после root даёт FAULTED prefix; неизвестный root REJECTED. Пограничные counters MAX_ID-1/нехватка 2 event slots без переполнения; no-op не расходует revision/events |
| C11 | RNG clone/from_dict isolation и atomic invalid import; порядок stream entries в допустимом input нормализуется; две P03b копии + свои RNG/queues дают равные outcomes/events/counters/RNG при случайном child; live и второй stream неизменны. Production HP/no-op/REJECTED/SKIPPED не draw |
| C12 | Весь прежний P01/P02/P03a/P03b runner (исторически 1008 assertions) сохранён, новые C01–C11 исполняются; все старые исходники/ресурсы вне allowlist совпадают с baseline; никаких preview/UI/новых правил в коде |

Для C05/C08/C09 разрешён доступ fixtures к внутренним underscore методам/данным,
но не публичный mutation/debug bypass в production API. Сценарии смерти/identity проверяет
ведущий по фактическому call graph, а не только количеству passed.

## 9. Точные проверки из корня (PowerShell)

Перед реализацией — gate (после неё manifest исторический, сравнивать закрытые пути):

```powershell
git rev-parse HEAD
git status --short
$p04 = Get-Content docs/P04_DEPENDENCIES.json -Raw | ConvertFrom-Json
foreach ($f in $p04.files) {
    if ((Get-FileHash -LiteralPath $f.path -Algorithm SHA256).Hash -ne $f.sha256) {
        throw "P04 dependency changed: $($f.path)"
    }
}
git diff 006fe1eaeca9fe19e97eed1b9030c0d565286b3a..HEAD --name-only
```

До любых записей сохранить tracked/untracked список и SHA-256, status и binary diff
в test_reports/p04-implementation-baseline*. Для tests/смешанных docs сохранить отдельные
копии. Не делать git add . и не включать прежние hunks автоматически.

После реализации (в этой documentation-only задаче **не запускалось**):

```powershell
$p04Godot = $env:GODOT_BIN
if (-not $p04Godot) { $p04Godot = [Environment]::GetEnvironmentVariable('GODOT_BIN', 'User') }
if (-not $p04Godot -or -not (Test-Path -LiteralPath $p04Godot)) { throw 'Set process GODOT_BIN per docs/TESTING.md' }
$p04AppData = $env:APPDATA
New-Item -ItemType Directory -Force test_reports/godot-profile | Out-Null
try {
    $env:APPDATA = Join-Path (Get-Location) 'test_reports/godot-profile'
    & $p04Godot --path . --headless --import --log-file test_reports/p04-import.log
    if ($LASTEXITCODE -ne 0) { throw 'P04 import failed' }
    & $p04Godot --path . --headless --quit-after 3 --log-file test_reports/p04-startup.log
    if ($LASTEXITCODE -ne 0) { throw 'P04 startup failed' }
    & $p04Godot --path . --headless --script tests/run_tests.gd --log-file test_reports/p04-tests.log
    if ($LASTEXITCODE -ne 0) { throw 'P04 tests failed' }
} finally { $env:APPDATA = $p04AppData }
Select-String -Path test_reports/p04-import.log,test_reports/p04-startup.log,test_reports/p04-tests.log -Pattern 'SCRIPT ERROR|Parse Error|Compile Error|=== .* passed, .* failed'
git diff --check
```

Требуются scan DONE/new global classes, отсутствие parse/compile/runtime ошибок и
`N passed, 0 failed` (N > 1008), а не один exit 0. Известны certificate-store и ожидаемый
P01 occupied-cell push_error; новые ошибки не списывать на них. UI не проверяется и
не получает Verified. Затем зафиксировать hashes всего изменённого кода/tests и новые
документационные разделы, провести независимое ревью и повторно сверить frozen hashes.
Перед локальным Conventional Commit проверить staged diff/`git diff --cached --check`;
stage только новые файлы P04 и добавленные P04 hunks tests/docs. Push запрещён без поручения.

Блокирующих вопросов геймдизайна для этого среза нет. Следующий этап после принятой
реализации — отдельный пакет; не запускать P05/P06/P07 или preview автоматически.
