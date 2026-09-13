# P05 — MoveCommand и явный путь

Редакция 1, 2026-09-14. **Пакет проектирования; реализация не разрешена этой задачей.**
Зависимые правила согласованы пользователем 2026-09-14 (раздел 2).
Пакет специализирует COMMAND_ACTION_QUEUE_CONTRACT §§3–5, T02/T03 и фактический
P04 (§14 общего контракта). Исторические P04_TASK/DEPENDENCIES/REVIEW не изменять.

## 1. Вход, цель и область

```yaml
task_id: P05-MOVE
base_commit: 21e9b8e1ae753d0901d9276dae5a7e2336778ca1
branch: main
requires_dirty_p01_p02_dependencies: true
goal: Headless submit исполняет явный маршрут по одному ребру с оплатой, последствиями и честным прерыванием.
```

До работы сверить HEAD/status, frozen hashes из P05_REVIEW и все `files` нового
P05_DEPENDENCIES. Чистого checkout HEAD недостаточно: принятый вход содержит dirty
P01/P02 и процессные документы. При несовпадении — CONTRACT_GAP, без переписывания
manifest под новый код. Допустим потомок base, если diff base..HEAD содержит только
три документа этого пакета; далее повторно сверить рабочие hashes зависимостей.

Входной gate подготовки: 33/33 SHA-256 результата P04 из первой таблицы передачи,
62/62 неизменённых входов из 67 записей исторического P04_DEPENDENCIES; пять старых
hashes замещены принятым результатом. SHA-256 исторических P04_TASK и manifest
совпадают с P04_REVIEW. Полный baseline: 220 существовавших файлов.

Наблюдаемый срез: caller передаёт actor id, старт и весь маршрут, ожидаемую revision;
один синхронный submit либо отвергает всё до мутаций, либо выполняет оплаченный
префикс через настоящую BattleBoard с consequences/reactions между рёбрами.

Non-goals: Attack/Push, impact/balance, полный preview/token/confirm, UI/демо/AI adapters,
Battle Flow, BT, новые игровые статусы, новые предметные эффекты, ActionResources,
save-game, snapshot ActionContext, refill и миграция общего C-3/S-5. `INTERRUPTED`
ниже — статус результата команды, а не новый игровой status effect.

## 2. Решения пользователя и границы открытых правил

G-P05-MOVE — УТВЕРЖДЕНО: персонаж платит только за клетки, в которые действительно
вошёл; прерванный хвост не оплачивается. Переключения и стоимость атаки разобрать
отдельно. Техническая специализация этого правила в P05: существующий единственный
`UnitState.move_points_left`, явный harness-допуск без Flow и без пополнения.

G-P05-HAZARD — УТВЕРЖДЕНО: добровольный вход в HAZARD разрешён, оплачивается и
приводит к смерти; дальше персонаж не идёт. Ответ пользователя после объяснения
обоих правил: «1 . Да», «2. Да пусть входит». Исполнение — обязательная DeathCommand
после входа, через принятый P04 finalize. VOID остаётся непроходим для Move.
Ответ утверждает эти два правила, но не разрешает реализацию в текущем задании.

Независимые факты: четыре ортогональных направления; стоимость входа, старт не
оплачивается; высота симметрична, предел инжектируется явно; board provider —
единственный источник проходимости/стоимости. Текущие FLOOR=1 и HAZARD=3 — факты
BattleBoard, а не новая формула. Максимальный перепад тестов 1 — значение fixture,
не новая характеристика персонажа. Очередь не ищет кратчайший путь.

Не считать утверждёнными цену атаки из начала draft-2 и старых разделов DECISIONS/
ARCHITECTURE, три новых ledger, G-1 возврат к частично походившему персонажу,
G-2a движение после атаки, G-2b максимумы/пополнение. Они требуют отдельного решения
перед зависимой реализацией. Допуск fixture не утверждает правила командного хода.

## 3. Фактические API и явные изменения P04

| Существующий API | Семантика, на которую опирается P05 |
|---|---|
| `Command.get_kind() -> StringName`, `copy_for_queue() -> Command`, `validate(context: ActionContext) -> StringName`, `execute(context: ActionContext) -> CommandStepResult` | validate возвращает пустую строку при успехе; CommandValidation в коде отсутствует. Copy/validate вызываются под guards, до root id |
| `ActionContext.new(state, rng, sink, unsupported_runtime_ids)`; `get_state/get_revision/get_rng/get_sink` | Удерживает тот же ItemSimulationState; counters/revision и общий busy/fault latch |
| `ItemSimulationState.get_board() -> BattleBoard` | Доска этого контекста, без глобальных ссылок |
| `BattleBoard.get_unit_by_id(id)`, `occupant_at(cell)`, `get_bounds/is_in_bounds/get_height/get_terrain` | Registry и живая occupancy; мёртвый остаётся в registry |
| `BattleBoard.make_data_provider(for_unit: UnitState = null) -> GridDataProvider` | Callables замкнуты на свою доску и actor; собственная клетка не блокирует путь |
| `GridDataProvider.cell_is_walkable/cell_height/cell_move_cost` | Без callback defaults true/0/1; Move всегда получает полный provider доски и не доверяет произвольному caller provider |
| `BattleBoard.move_unit(unit: UnitState, to_cell: Vector2i) -> bool` | Меняет cell/height/occupancy, board_version +1, board_changed и unit_position_changed. Не проверяет alive, identity объекта, соседство, terrain, перепад и бюджет — это обязанность Move |
| `UnitState.is_alive()`, `spend_move_points(amount: float) -> void` | Списание с clamp; до вызова Move обязан проверить конечность и достаточность. `can_move/can_attack/has_attacked` не являются допуском P05 |
| `DeathCommand.new(target_unit_id, source)`; `DamageSource.new(kind, source_instance_id, origin_cell, instigator_unit_id, credit_unit_id)` | Принятый P04 death finalize: Vitals, одно освобождение occupancy, died; без DamageCalculator.apply |
| `ActionQueue.new(max_commands=256, max_events=512, max_depth=32)` | Bounds 1..4096 / 1..8192 / 1..64. Каждый continuation — depth родителя +1, отдельный command_seq |
| `ActionQueue._dispatch_event` | Только damaged → узкий P03b DTO → ItemReactionAdapter. Производственного collect_moved сейчас нет |

Разрешённые расширения P04 перечислены исчерпывающе:

1. Добавить необязательную movement-конфигурацию в конец конструктора ActionContext
   (раздел 4). Старые четыре аргумента сохраняют поведение всех HP-команд.
2. Добавить `INTERRUPTED` в CommandStepResult/ActionReceipt и обработку очередью
   (раздел 7). Это ранее отложенная часть draft-контракта, не существующий API P04.
3. Добавить отдельную строгую схему `moved` в `_valid_draft` (раздел 8), сохранив
   byte/value-форму damaged/healed/died и прежний P03b damage-only dispatch.
4. После успешного P03b preflight, до root validate/admission, отвергать внешний
   submit внутреннего Move continuation: `accepted is MoveCommand` и
   `accepted._is_continuation()` → REJECTED/move/internal_continuation. Это узкая
   защита от повторного запуска внутреннего cursor, без нового Command registry.

Не менять depth semantics, root admission guards/preflight, sequence reservation,
максимум два события атомарного шага, event-limit overshoot, порядок siblings,
родительские event ids, RNG порт, HP/source DTO или item adapter. Нового registry
команд, универсального reaction callback/collector и обхода raw submit не добавлять.
При необходимости другого изменения — CONTRACT_GAP ведущему, не молчаливое расширение.

## 4. Новый точный API и владение

Все новые типы — строго типизированные RefCounted. Payload содержит значения;
private identity refs допустимы только у внутреннего исполнения, как в P04 binding.
Не хранить Resource/Callable/Node/UnitState в публичных payload или журнале.

### MoveRules (новый технический порт, планируется)

`MoveRules.new(admitted_unit_ids: Array[int], max_height_step: int)`;
`copy() -> MoveRules`, `validate() -> StringName`,
`allows(unit_id: int) -> bool`, `get_max_height_step() -> int`.

До копирования проверяет size; более 65536 элементов хранит как маленький invalid
marker, сохраняя отказ через copy/validate. Getters не выдают mutable refs.
ids уникальные, 1..MAX_ID-1,
не более 65536; пустой список валиден и никого не допускает. Неизвестный доске id
в allowlist не создаёт юнита. max_height_step: 0..2147483647. Не clamp и не default 1.
Это immutable конфигурация одного harness-контекста, не ledger/Flow/permission service.
Изменить caller array или исходный объект после создания контекста не значит изменить
контекст; для нового допуска создать новый idle context вне цепочки. Смена допуска
в течение drain запрещена. validate чистый, без RNG и чтения живых stat caches.

Дополнение: `ActionContext.new(state: ItemSimulationState, rng: ActionRngPort,
sink: ActionEventSink, unsupported_runtime_ids: Array[StringName],
move_rules: MoveRules = null)` и `get_move_rules() -> MoveRules` (копия либо null).
Приём копирует rules. Null разрешён для прежних HP-команд; Move даёт
`move/rules_missing`. Некорректный rules — `move/invalid_rules` при Move admission,
не ломает несвязанные Damage/Heal/Death. Нет сериализации rules или обещания полного
preview; в паре изолированных fixtures явно задавать эквивалентные rules отдельно.

### MovePathCheck

`MovePathCheck.inspect(board: BattleBoard, actor: UnitState,
path: Array[Vector2i], max_height_step: int, budget: float) -> MovePathCheck` — static.
`get_reason() -> StringName`, `get_costs() -> Array[float]` (копия),
`get_total_cost() -> float`. Пустой reason означает OK. На ошибке costs=[], total=0.
Проверяет геометрию/цену (раздел 5), не actor admission/revision; не мутирует входы.
`const MAX_PATH_CELLS: int = 33` (не более 32 рёбер). Проверяет size до копирования
или прохода; не строит Dijkstra/reachable и не меняет старый GridPathfinder.

### MoveCommand

`MoveCommand.new(actor_unit_id: int, path: Array[Vector2i], expected_revision: int)`.
`get_kind() -> StringName` = `&"move"`; четыре метода Command с теми же сигнатурами.
`get_actor_unit_id() -> int`, `get_path() -> Array[Vector2i]` (копия),
`get_expected_revision() -> int`. Публичного cursor/resume API нет.

Constructor/copy проверяют ограничение длины до duplicate. Некорректная длина
сохраняется как маленький invalid marker: copy не возвращает null и validate
возвращает `move/path_length`, не unknown_command и не молча усечённый путь.
Остальной payload копируется; source-массив и возвращённый get_path не могут менять
принятую команду. expected_revision: 0..MAX_ID-2, actor: 1..MAX_ID-1.

Внутренняя continuation — новый MoveCommand с приватным index следующего ребра,
тем же замороженным payload и привязкой к принятому actor объекту. Copy сохраняет
index, identity binding и различие root/continuation. Нельзя превратить continuation
в новый root, повторно списать предыдущие рёбра или принять caller resume payload.
Внутренний `_is_continuation() -> bool` читает приватный признак, сохранённый copy;
queue использует его только при root admission (расширение 4 выше). Дочерние
continuations допускаются обычным work stack. Тестовые wrappers доверенные и не
являются публичным способом обхода этого gate.
Underscore — контракт доверенного core, не техническая изоляция GDScript.

## 5. Root validation и полный маршрут

Порядок внешнего submit остаётся P04: BUSY/CONTEXT_FAULTED → guards → copy →
P03b capture/preflight → запрет внешнего continuation → Move.validate → counters/admission. Ошибка preflight имеет
приоритет над Move reason (например NaN в live unit budget уже ловится P03b).

Move.validate root: payload/id/revision range → rules → lookup/жизнь actor →
expected_revision == context.get_revision → allowlist → старт path[0] == actor.cell →
полная проверка маршрута и бюджета. unit.stats/vitals существуют; lookup возвращает
именно связанный с registry объект; actor занимает свою клетку через occupant_at.
Живой вне occupancy валиден для P02, но добровольный Move root отвергает его
`move/actor_not_placed`. Unit.height в P02 может отдельно отличаться от board height:
геометрия читает board provider, успешный board.move_unit синхронизирует unit.height.

MovePathCheck: board/actor не null, provider только board.make_data_provider(actor),
max_height_step в диапазоне, finite budget >=0; 2..33 клетки. Bounds всех клеток
проверяются до coordinate subtraction/provider reads. Старт проходим; каждое ребро
строго ортогонально соседнее (int64 разности компонент, не Vector2i overflow), без
повторения той же клетки подряд. Повторное посещение через несколько рёбер разрешено:
это явный маршрут, каждый вход оплачивается, в том числе возврат в исходную клетку.
Чужой живой occupant запрещён; actor не блокирует собственный будущий возврат.

Проверить walkability и симметричный перепад каждого ребра по provider. Разности
высот вычислять без int64 overflow: board heights int32, сначала считать в int64;
helper не принимает произвольный provider int64. Цена каждого входа finite >=1.0;
старт не включать в costs. Сумма слева направо finite и <= budget; параллельно
последовательно вычитать цены из временной копии budget, каждый шаг должен быть
достаточным (не принимать маршрут, который из-за float rounding нельзя оплатить).
На каждом вычитании new_budget < old_budget и old_budget - new_budget == cost;
иначе `move/unrepresentable_debit`. Так конечный бюджет 1e20 не даёт бесплатный
шаг из-за ULP. Проверка не округляет цену и не меняет сохранённый остаток на отказе.
Ни epsilon, ни clamp некорректных значений. На фактической доске цены 1/3.

Перед root admission проверить запас board_version в int64: N рёбер плюс одно
освобождение occupancy, если среди входов есть HAZARD. Сравнивать с
MAX_ID - required_increments, не складывать с потенциальным overflow. При нехватке
REJECTED/move/board_version_exhausted. Это консервативная проверка полного маршрута,
как бюджет; не резервирование будущих реакций и не изменение BattleBoard/P04 HP.

Полная проверка включает хвост даже после потенциально смертельного входа:
невалидный хвост означает REJECTED всего запроса. Нет автоматической замены пути,
обрезки до бюджета, reroute или RNG. Старый find_path допустим только как внешний
поставщик намерения; caller передаёт найденные клетки явно. Его tie-break не меняется
и не влияет на детерминизм исполнения одного фиксированного payload.

REJECTED: root_id=0, steps/events пусты, нет domain events/sink calls, board/version,
HP/баланс, бюджет/has_attacked, предметы, caches, RNG/revision/counters прежние.
Direct validate тоже ничего не меняет. Ожидаемый отказ не требует rollback.

## 6. Одно ребро и continuation

На первом execute заново проверить динамические условия до первого mutator и
привязать actor identity. Root admission не повторяется после первого ребра.
Если состояние изменилось между успешной root validate и первым execute, это
нарушение single-writer harness: FAULTED/move/invalid_runtime без попытки входа.
На continuation validate проверяет только корректность внутреннего payload/index/
binding; не сравнивает исходную revision, не проверяет allowlist и весь хвост.
Иначе фактическая очередь P04 превратила бы нормальный stale state в FAULTED ещё до
execute. Execute continuation самостоятельно классифицирует актуальное состояние.

Перед каждым ребром lookup по id; missing/replaced/dead/moved actor прекращает Move.
Проверить occupancy и актуальную пару path[index-1] → path[index], terrain/height/
стоимость и оставшийся бюджет; использовать тот же MovePathCheck на двух клетках.
Изменение board_version/revision само по себе не прерывает команду: сравнивается
фактическое состояние. Изменившаяся цена оплачивается по текущему значению, если
оно валидно и бюджет достаточен. Непроходимый более дальний хвост обнаружится перед
соответствующим ребром; он не блокирует уже допустимое следующее ребро.

Одно успешное ребро: сохранить before cell/budget → board.move_unit(actor, to) →
только при true один spend_move_points(cost) → сформировать один moved → вернуть
APPLIED/state_changed=true, необходимые mandatory, reactions и continuation.
HP mutators не вызывать в теле Move. Прямая запись unit.cell/height/occupancy, второго
ledger, begin_turn/refill, has_attacked и global UnitId запрещены.

Для актуального HAZARD добавить первым обязательным ребёнком
`DeathCommand.new(actor_unit_id, DamageSource.new(&"cell", 0, to_cell, 0, 0))`.
Определить lethal terrain перед board mutator; очередные callbacks не меняют бой.
Death выполняется ДО реакций и continuation, использует Vitals и P04 finalize,
без брони, damaged/impact, PushResolver или новой формулы. Журнал: moved → died;
у died actor_unit_id=0, target_unit_id=двигавшийся actor, source.origin_cell=HAZARD,
source_instance_id/instigator/credit=0. Умерший остаётся в registry на достигнутой
клетке, occupancy очищается один раз. Даже HAZARD в конце пути даёт INTERRUPTED/
move/actor_dead на завершающем шаге. Для E оплаченных рёбер до HAZARD без иных детей:
E+2 steps, E+1 events, delta revision=E+1, delta board_version=E+1.
HAZARD на стартовой клетке сам по себе не создаёт последствия: срез обрабатывает
входы. На валидном пути actor может выйти из такой исходной fixture-клетки.

Перед каждым board.move_unit повторить проверку запаса board_version: один increment
для ребра и ещё один для его обязательной смерти на HAZARD. Недостаток после начала
→ FAULTED/move/board_version_exhausted до нового mutator, префикс сохранён.
При FAULTED очереди до исполнения обязательной Death (например command_limit)
в prefix допустим ещё живой actor на HAZARD: это явная неисправная цепь с latch,
а не завершённый успех. Не исполнять смерть в обход queue и не ослаблять её лимиты.

Порядок атомарности такой же ограниченный, как в P04: низкоуровневые сигналы board
могут увидеть позицию до оплаты, но callbacks не меняют бой; презентация читает final
value sink после drain. Оба guards остаются подняты при board signals и sink.
Не обещать S-5/защиту от произвольных runtime callbacks или rollback сигналов.
Если move_unit вернул false после успешной проверки того же состояния — invariant
fault `move/board_move_failed`, не обычный blocked, оплаты нет. Успешное ребро и
оплата должны попасть в prefix при последующей ошибке/лимите.

После КАЖДОГО ребра, включая последнее, возвращается continuation. Когда index
равен path.size(), это терминальная проверка без движения/оплаты/events/revision:
actor ещё тот же, жив и в последней достигнутой клетке → APPLIED; иначе INTERRUPTED.
Так смерть/перемещение реакцией последнего ребра не скрываются статусом APPLIED.
Для N рёбер без последствий будет N+1 steps, N moved и delta revision=N.
В терминальной проверке уже не проверять budget/terrain последней клетки: больше
входов нет. Повреждённый binding или невозможная occupancy остаются invariant fault.

Производственный moved не запускает новые предметные реакции: P04 слушает только
damaged. Для T03 используются доверенные Command fixtures в runner: wrapper делегирует
copy/validate/execute реальному MoveCommand, добавляет children только после выбранного
реального ребра и оборачивает continuation с сохранением состояния. Children делают
Damage/Death либо board.move_unit/set_terrain/set_height внутри execute с корректным
state_changed. Никаких мутаций из low-level signal или presentation sink. Это проверяет
настоящий work stack/Move revalidation, не вводит временный production executor.

## 7. INTERRUPTED, depth, revision и ошибки

Добавить `CommandStepResult.INTERRUPTED` и factory
`interrupted(reason: StringName) -> CommandStepResult`: state_changed=false,
пустые events/mandatory/reactions, continuation=null. Queue строго проверяет эту
форму; malformed interrupted → FAULTED. Добавить `ActionReceipt.INTERRUPTED`.

При INTERRUPTED step сохранить его reason и установить receipt.INTERRUPTED, только
если ранее статус был APPLIED. Не чистить остальные pending siblings, продолжить
обычный drain; interrupted step сам не порождает детей. Дальнейший fault всегда
повышает итог до FAULTED; первый interruption reason сохраняется, если fault нет.
Новые root после INTERRUPTED разрешены (busy снят, fault latch не поднят).
INTERRUPTED никогда не маскируется SKIPPED/FAULTED или APPLIED с текстом причины.
Root-rejection до первого ребра отличается от interruption принятой цепи;
прямые execute вне queue контрактом запрещены.

Сохраняется depth+1 для всех детей, в том числе continuation. Hard cap 32 ребра
позволяет terminal depth=32 при стандартном max_depth=32; root depth=0. Цепи
реакций могут превысить лимит и при коротком пути. Настроенные ниже стандартных
max_commands/max_events/max_depth также могут дать FAULTED после префикса:
queue не резервирует всю будущую цепь и не обещает admission по её полной длине.
Не оптимизировать continuation в цикл/тот же depth; P04 тест циклического
continuation должен по-прежнему завершаться depth_limit.

state_changed=true ровно для реального ребра с оплатой → одна revision, даже если
меняются и позиция, и бюджет. Каждая HP/fixture child увеличивает revision согласно
P04. Terminal/interruption/rejected/unchanged шаги её не увеличивают. Board.version
меняется только mutators доски; нельзя считать его эквивалентом revision.
Move не берёт RNG; deterministic fixture children используют только контекстный порт.

Reason vocabulary (StringName; ошибки до старта REJECTED, если не указано иное):

| Причина | Условие |
|---|---|
| move/invalid_actor_id, move/invalid_revision, move/path_length | Некорректный payload |
| move/internal_continuation | Внутренний cursor передан внешним root submit |
| move/rules_missing, move/invalid_rules, move/not_admitted | Нет согласованного допуска |
| move/missing_actor, move/dead_actor, move/start_mismatch, move/actor_not_placed | Непригодный исходный actor |
| move/stale_revision | Ожидаемая revision не совпала на root |
| move/out_of_bounds, move/not_adjacent, move/blocked, move/height_step | Невалидная геометрия |
| move/invalid_budget, move/invalid_cost, move/cost_overflow, move/insufficient_move, move/unrepresentable_debit | Бюджет/цена/сумма/точность списания |
| move/board_version_exhausted | Не хватает int64 запаса доски: root REJECTED, после начала FAULTED |
| move/actor_missing, move/actor_replaced, move/actor_dead, move/actor_displaced | Continuation: INTERRUPTED, в таком порядке проверок (identity раньше alive) |
| move/path_blocked, move/path_height, move/budget_exhausted | Актуальное ребро после начала: INTERRUPTED |
| move/invalid_runtime, move/invalid_continuation, move/board_move_failed | Invariant после начала: FAULTED |

После начала out-of-bounds после изменения доски → path_blocked; non-finite/negative
budget, invalid cost/unrepresentable_debit или повреждённый payload → invalid_runtime,
не мягкий interrupt. MovePathCheck при null board/actor возвращает move/invalid_runtime,
при неверном max_height_step — move/invalid_rules; no mutators в обоих случаях.
Registry actor тот же и жив, но отсутствует в occupancy текущей клетки → invariant
fault; если он перемещён board-командой, сначала actor_displaced. Невалидный старый
runtime на root обычно ловит P03b preflight, его reason не переписывать.
Сохраняются P04 BUSY, CONTEXT_FAULTED, invalid_limits, command_limit/event_limit/
depth_limit/sequence_exhausted; prefix без общего rollback и refunds, latch обеих сторон.

## 8. Событие moved (новая отдельная schema)

Draft содержит ровно следующие keys, String keys с указанными типами:

```text
kind: StringName = &"moved"
actor_unit_id: int                 # 1..MAX_ID-1
target_unit_id: int                # равен actor_unit_id
from_cell: Vector2i
to_cell: Vector2i                  # ортогонально соседняя клетка
movement_kind: StringName = &"voluntary"
move_cost: float                   # finite >=1
move_before: float                 # finite >=move_cost
move_after: float                  # finite >=0, <move_before, == move_before-move_cost
```

Никаких HP полей, source/фиктивного DamageSource.kind=move, runtime refs, глубины,
caller root/command/event ids или attempted_cell. Только успешный вход создаёт
событие. Проверка draft не читает уже изменившийся runtime, только значения;
разности координат считать через int64. Дополнительные/пропущенные поля, неверные
типы/ids/арифметика (в том числе move_before-move_after != move_cost) → malformed_event;
старые три HP schemas не ослаблять.
Queue добавляет ровно прежние event_seq/root_id/command_seq/parent_event_seq.
Move continuation и mandatory children сохраняют P04 parent_event_seq=0; не выдавать
нулевое значение за связь с moved. Item реакции damaged сохраняют реальную связь.
Предел два draft events/step остаётся; Move обычно выдаёт один. Domain moved и legacy
unit_position_changed — разные каналы, они не вызывают друг друга через адаптер.
get_events/get_steps и каждый sink вызов возвращают/получают независимые копии.

## 9. allowed_paths будущей реализации

Единственный coder пишет только перечисленные runtime/tests paths. Ведущий меняет
только затронутые документационные разделы и проверяет смешанные diff. Никто не
откатывает прежние изменения. Новые uid генерирует Godot; не выдумывать их вручную.

```yaml
allowed_paths:
  - scripts/core/actions/move_command.gd
  - scripts/core/actions/move_command.gd.uid
  - scripts/core/actions/move_rules.gd
  - scripts/core/actions/move_rules.gd.uid
  - scripts/core/actions/move_path_check.gd
  - scripts/core/actions/move_path_check.gd.uid
  - scripts/core/actions/action_context.gd
  - scripts/core/actions/action_queue.gd
  - scripts/core/actions/command_step_result.gd
  - scripts/core/actions/action_receipt.gd
  - tests/run_tests.gd
lead_docs_only:
  - docs/ARCHITECTURE.md
  - docs/DECISIONS.md
  - docs/TESTING.md
  - docs/COMMAND_ACTION_QUEUE_CONTRACT.md
  - docs/CODEX_HANDOFF.md
```

BattleBoard/UnitState/Vitals/Pathfinder/provider/P03 snapshots/HP/item/RNG/legacy UI
закрыты для записи. GridPathfinder из ранней строки плана P05 не требует изменения:
явный payload устраняет поиск пути из исполнения, новый MovePathCheck валидирует
его через board provider. Исправление tie-break/стоимостей старого pathfinder —
отдельная цель. Исторические пакеты и frozen P05 документы не править при реализации.
Read paths зафиксированы hashes в P05_DEPENDENCIES, нужны только разделы этого ТЗ,
P04_TASK §§2–8 и фактические source из таблицы; не загружать кодеру всю библиотеку docs.

## 10. Приёмка M01–M12 (будущие проверки)

| ID | Проверяемое поведение |
|---|---|
| M01 | Payload constructor/copy/getters и MoveRules не разделяют mutable arrays; max path 33 принимается, 34/0/1 отвергаются без большого copy; invalid id/revision/rules/empty admission, oversized allowlist; внешний submit continuation отвергается без counters/mutations; старый четырёхаргументный context исполняет P04 HP и отвергает Move |
| M02 | Два FLOOR ребра: реальные клетки/height/occupancy, два board position signals/version +2, budget -2, events/steps N/N+1, revision +2; возврат через петлю оплачивает каждый вход; повторная клетка подряд/диагональ не проходят |
| M03 | Весь invalid path, включая хвост: bounds, WALL/VOID, occupant, высота вверх/вниз, start/revision, dead/missing/not-placed actor, бюджет. Каждый root REJECTED без изменений canonical P03b state, live raw caches/signals, RNG и всех counters, steps/events/sink пусты |
| M04 | Конечность budget и costs, negative/0/<1/NaN/INF costs, overflow суммы и float sequential-subtraction boundary, finite budget=1e20 отвергается как unrepresentable_debit без бесплатного шага. Реальная board даёт 1/3; невозможные costs проверять узко в тестовом helper seam, не ослаблять production provider и P03b capability gate |
| M05 | Реальное первое ребро → trusted DamageCommand убивает actor → terminal/continuation INTERRUPTED, хвост не оплачен, moved→damaged→died, occupancy свободна один раз, corpse в registry; отдельно смерть на последнем ребре |
| M06 | Children после первого ребра: board перемещает actor; удаление/замена actor (с согласованным fixture owner state); блокирует следующую клетку/меняет высоту; меняет более дальний хвост (следующее допустимое ребро выполняется), уменьшает бюджет. Правильные INTERRUPTED reasons, оплаченный prefix сохранён; смерть/перемещение не превращаются в fault через validate; unrelated revision не прерывает |
| M07 | FLOOR→HAZARD→FLOOR: достаточный для всего пути бюджет, списаны 1+3, события moved→moved→died, один clear occupancy, source cell/ids точны, INTERRUPTED/actor_dead. HAZARD на последнем/первом ребре, alive-at-zero actor, выход из исходного HAZARD. Невалидный/дорогой хвост после HAZARD отвергает root. Children меняют следующий FLOOR в HAZARD: актуальная цена 3 и смерть при достаточном остатке, budget_exhausted без входа/смерти при недостаточном. VOID всегда REJECTED |
| M08 | Полный drain порядка mandatory subtree → item reactions → explicit reactions → continuation, fixture использует настоящие Move steps; нефатальный damage запускает существующий HealOnDamage item через P04, затем следующий вход; moved само не вызывает item collector |
| M09 | Строгая moved schema и arithmetic, reject malformed/лишних полей/refs; неизменность HP схем; mutation receipt/sink copies не меняет журнал/следующий sink; deterministic sequences и parent_event_seq=0 у Move continuations/mandatory |
| M10 | BUSY из board_changed/unit_position_changed и final sink, в том числе другая queue; no inner copy/validate/RNG. After INTERRUPTED новый root допустим; sibling drain после interruption; последующий fault побеждает interruption. Malformed interrupted (events/children/state_changed) fault |
| M11 | 32 ребра+terminal укладываются в default depth; 33 ребра отвергнуты cap. Малые command/event/depth limits, sequence/revision и board_version exhaustion до/после начала; boundary при входе HAZARD. Fault prefix оплаты/events, включая limit перед обязательной Death и после смерти до terminal; последующая блокировка обоих latch. Прежний P04 cyclic continuation depth_limit сохранён |
| M12 | Два независимых P03b instantiate + новые contexts/queues с равными rules и RNG: тот же маршрут и trusted children дают одинаковые canonical states, receipts/events/steps/counters/RNG. Live и соседняя копия неизменны при выполнении первой. Это harness, не полный preview. Весь прежний регресс остаётся |

Fixture M04: в MovePathCheck вынести внутреннюю чистую арифметическую проверку
массива цен/бюджета (private helper; точное внутреннее имя выбирает coder). Тестировать
её synthetic finite/nonfinite arrays; production inspect всегда берёт реальные цены
доски. Не создавать поддельный subclass board в принятом P03b root. M06 removal/
replacement fixture не должна оставлять чужие facades активными или провоцировать
collector на невалидном owner graph; этот тест не объявляет hot-swap поддержанным API.

## 11. Команды проверок и сдача

В этой подготовке Godot не запускать: исходники неизменны, проверяются JSON/hash/diff
и независимое ревью документов. Исторические **1275/0 P04** не результат P05.

Перед реализацией из корня PowerShell:

```powershell
$ErrorActionPreference = 'Stop'
git rev-parse HEAD
git status --short
$p05Deps = Get-Content docs/P05_DEPENDENCIES.json -Raw | ConvertFrom-Json
foreach ($entry in $p05Deps.files) {
  if ((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ne $entry.sha256) {
    throw "P05 dependency mismatch: $($entry.path)"
  }
}
Get-FileHash docs/P05_MOVE_TASK.md, docs/P05_DEPENDENCIES.json -Algorithm SHA256
# Сверить два hashes с P05_REVIEW; исторический manifest не перезаписывать.
```

В будущем после реализации сначала import/startup/M01–M12 и полный runner:

```powershell
$ErrorActionPreference = 'Stop'
$p05Godot = $env:GODOT_BIN
if (-not $p05Godot) {
  $p05Godot = 'D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
}
if (-not (Test-Path -LiteralPath $p05Godot)) { throw 'GODOT_BIN not found' }
$p05AppData = $env:APPDATA
try {
  New-Item -ItemType Directory -Force test_reports/godot-profile | Out-Null
  $env:APPDATA = (Resolve-Path test_reports/godot-profile).Path
  & $p05Godot --path . --headless --import --log-file test_reports/p05-import.log
  if ($LASTEXITCODE -ne 0) { throw 'P05 import failed' }
  & $p05Godot --path . --headless --quit-after 3 --log-file test_reports/p05-startup.log
  if ($LASTEXITCODE -ne 0) { throw 'P05 startup failed' }
  & $p05Godot --path . --headless --script tests/run_tests.gd --log-file test_reports/p05-tests.log
  if ($LASTEXITCODE -ne 0) { throw 'P05 tests failed' }
} finally { $env:APPDATA = $p05AppData }
rg -n 'SCRIPT ERROR|Parse Error|Compile Error|passed|failed|ERROR' test_reports -g 'p05-*.log'
git diff --check
```

Ведущий читает реальные логи: exit 0 недостаточен, import scan DONE,
3/3 новых global classes, ноль новых parse/compile/runtime errors, M01–M12 вызваны
runner, итог failed=0. Ожидаемый старый P01 occupied-cell ERROR отличать от новых.
UI не требуется и не считается проверенным. Нет необходимости писать отдельный
тест каждой строки ТЗ; нужны указанные поведенческие сценарии и regression.

До staging сравнить baseline closed paths, сохранить прежние строки/dirty hunks
runner и смешанных docs; новый manifest результата реализации фиксирует новые hashes
отдельно от исторического P05_DEPENDENCIES. Независимый game_reviewer получает
неизменяемые hashes кода/тестов/docs и логи после окончания записи. До APPROVE
реализации коммит кода не делать. Коммит только P05 hunks/новые файлы, Conventional
Commits, без чужого P01/P02/процессного staging; push не выполнять.

Для этого задания подготовки: после APPROVE документов обновить передачу отдельным
префиксом, сохранив старый untracked архив, и локально закоммитить только
P05_MOVE_TASK.md, P05_DEPENDENCIES.json, P05_REVIEW.md. Для реализации нужен отдельный
запрос пользователя, удобно в новом чате с CODEX_HANDOFF; не создавать его автоматически.
