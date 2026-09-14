# P06 — AttackCommand, оплата и ресурсы персонажа

Редакция 1, 2026-09-14. **Пакет проектирования. Игровой код этой задачей не меняется.**
Реализация — отдельное поручение по проверенному пакету и рабочим зависимостям.
Этот документ специализирует принятые P04/P05 и заменяет только зависимые предложения
draft-2, перечисленные ниже. Исторические TASK/DEPENDENCIES/REVIEW не редактировать.

## 1. Вход и наблюдаемый результат

```yaml
task_id: P06-ATTACK
base_commit: 2debe807ab48991c7bfab83d293e994aa0eddd7d
branch: main
requires_dirty_p01_p02_dependencies: true
goal: Headless submit оплачивает допустимую плоскую ближнюю атаку одним основным действием и исполняет реальный HP/item pipeline.
```

Сверить HEAD/status, hashes task/manifest из P06_REVIEW и каждый `files` нового
P06_DEPENDENCIES. Допустим потомок base, если diff base..HEAD содержит только три
документа P06. Чистого checkout недостаточно без прежних dirty P01/P02/процессных
зависимостей. Несовпадение — CONTRACT_GAP, не переписывание manifest под новый код.

Вход подготовки: окончательные 11/11 hashes кода/tests P05 и два frozen hashes
P05 task/manifest совпали. В историческом P05 manifest 100/109 входов неизменны,
девять замещены P05: context/queue/step/receipt/runner и четыре итоговых документа.
Review manifest P05: 26/30 совпали; четыре документа сохраняют исходные review
prefixes и принятые финальные addenda. Их старые baseline hashes совпадают с review.
P06 manifest фиксирует именно эффективное текущее дерево, не исправляет историю.

Scope: один реальный root Attack, расход ресурса, связанный HP child, фактические
damaged/died и существующее предметное лечение. Два независимых P03b состояния
должны включать остатки действий и давать одинаковый результат одинаковых команд.
Это headless harness: допускаемые actor/target пары задаёт composition root явно.

Non-goals: баланс/Push, высотные множители и полууровни, расширенная досягаемость,
уклонение/status runtime, криты/RNG атаки, новые эффекты/активации предметов, UI/AI,
Battle Flow/BT, полный preview/token/confirm, снимок ActionContext, save-game,
общий C-3/S-5. Не добавлять фиктивно работающие поля dodge/impact/push в события.

## 2. Принятые правила и технические ограничения среза

Ответы пользователя в текущем согласовании имеют приоритет над устаревшими
формулировками AGENTS/draft-2/архивов о неутверждённой экономике.

- Команды ходят поочерёдно; порядок своих персонажей свободный, инициатива не
  управляет ходами. Возврат к частично походившему персонажу пока разрешён;
  отдельная политика должна позволять позднее включить запрет. Просмотр/выделение
  не тратит/пополняет ресурсы. Детали переключения пользователь оставил ведущему.
- Три ресурса: движение, main, bonus. Атака стоит ровно 1 main, 0 move, 0 bonus.
  Движение после атаки разрешено. Main может быть больше 1: has_attacked не gate.
- Максимумы: MOVE_RANGE, базовые MAIN_ACTIONS_MAX=1 и BONUS_ACTIONS_MAX=1;
  предметы/артефакты могут их менять. В начале хода своей команды все её живые
  персонажи восстанавливаются до максимумов; остаток не накапливается.
- Управление инвентарём/экипировкой происходит до боя. Использование заранее
  взятых зелий/активируемых предметов задумано за bonus; реализации активаций нет.
- HP-урон попадания: max(1, STRENGTH + WEAPON_DAMAGE - ARMOR). Сила прибавляется
  один раз, отдельного base_damage сверх силы/оружия нет. Реакция лечения может
  компенсировать потерю HP: минимум 1 не обещает итоговую потерю после reactions.
- Без способности уклониться атака попадает; критов нет. Будущее уклонение
  предсказуемо, удар в него не наносит урона. Конкретного эффекта P06 не реализует.
- Пользователь явно принял: P06 только на одной высоте; следом баланс+толчок,
  затем высоты/расширенная досягаемость. Базовая ближняя дальность — один тайл.

Техническая специализация минимального harness (не дополнительные игровые rules):
досягаемость P06 — одно ортогональное ребро, равенство board heights, ATTACK_RANGE=1.
ATTACK_RANGE>1 — явный unsupported отказ, не обрезание характеристики до 1.
Правила диагонального reach, линии видимости и атак через промежуточных персонажей
не утверждаются: таких входов срез не исполняет. Поздний spatial-пакет их определит.
Допустимые пары целей перечисляются явно в AttackRules, как допуск MoveRules у P05.
Нет неявного hostile-only/нейтрального/friendly-fire решения; fixture может допустить
PLAYER->ENEMY. Производственного Faction/UI admission service здесь нет.

Main/bonus — целые счётчики 0..4096. Их производные максимумы и ATTACK_RANGE должны
быть конечными целыми float-значениями в этом диапазоне (range минимум 1), иначе
ошибка конфигурации. Не round/floor/clamp: дробные action modifiers не поддержаны
этим срезом. 4096 — инженерная граница, не игровой максимум по умолчанию.
HP/урон/движение сохраняют float без нового округления. Статовые изменения сами
по себе не восстанавливают ресурсы; явное восстановление в harness — вне lifetime
контекстов. Выбор момента хода/команды остаётся будущему Flow.

## 3. Реальные API на входе

| API | Фактический контракт |
|---|---|
| Command.get_kind/copy_for_queue/validate/execute | validate(context)->StringName, пусто при успехе; execute->CommandStepResult |
| ActionContext.new(state, rng, sink, unsupported_runtime_ids, move_rules=null) | Пятый аргумент P05 копируется; общий busy/fault latch, root/command/event counters, revision |
| ActionQueue.submit(command, context)->ActionReceipt | Guards до copy/validate; P03b capture preflight; admission до root id; синхронный drain |
| CommandStepResult.applied(events=[], mandatory=[], reactions=[], continuation=null, state_changed=false) | До двух events/step; дети исполняются через очередь, mandatory перед item reactions |
| ItemSimulationState.get_board/get_owner/get_inventory/get_equipment | Единственный runtime этого контекста; владельцы P03b привязаны к своим UnitState |
| BattleBoard.get_unit_by_id/occupant_at/get_height/is_in_bounds/clear_occupancy | Registry/живая occupancy; corpse остаётся; высота клетки — источник истины |
| UnitState.move_points_left/has_attacked/can_attack/begin_turn/refill_move_points | Сейчас legacy модель: bool одной атаки; P06 добавляет альтернативный авторитет main |
| StatsBag.from_base_values/has_stat/get_value/to_snapshot_dict/from_snapshot_dict | Отсутствующий stat=0, get_value прогревает cache; для чистого чтения использовать копию snapshot |
| DamageRequest.new(target_id, amount, damage_type, armor_mode, source) | physical и flat/bypass; flat вычитает ARMOR, STRENGTH не прибавляет |
| DamageCommand.new(request), validate/execute | Копирует request/source; делегирует ActionHpExecutor |
| ActionHpExecutor.validate_damage/damage | Проверка чистым stat-copy; finalize применяет Vitals, освобождает occupancy, даёт damaged/died |
| DamageSource.new(kind, source_instance_id, origin_cell, instigator_id, credit_id) | Существующий kind=attack, value source DTO, проверка существования ненулевых ids |
| DamageCalculator.calculate/apply | Legacy calculate: max(0,base+STR-ARMOR) плюс balance/push preview; apply мутирует HP и balance. Не путь P06 |
| ItemReactionCollector.collect_damage(state, dto) | Только damaged/dealt>0 у живой цели, HealOnDamage; stale binding проверяет ItemReactionAdapter |

Queue: mandatory subtrees -> item reaction subtrees -> explicit reactions ->
continuation, каждый child depth+1. Collector вызывается по draft events до запуска
детей; это не момент исполнения Heal. Siblings не вклиниваются внутрь поддерева.
Публикация независимых копий prefix после drain/fault под guards. Лимит событий
может сохранять целиком атомарный шаг; fault не откатывает оплату или урон.

## 4. Исчерпывающие расширения контрактов

1. Append-only StatType: MAIN_ACTIONS_MAX=7, BONUS_ACTIONS_MAX=8, WEAPON_DAMAGE=9,
   ATTACK_RANGE=10. Существующие 0..6 не менять. Extend только соответствующие
   stat capability gates P02/P03b/StatsBag до 10, не другие enums/лимиты.
2. Nullable ActionResources у UnitState: единый main/bonus ledger. Движение
   остаётся только в move_points_left; нет копии движения внутри нового объекта.
3. Версия 2 вложенного Unit snapshot с ActionResources DTO. Версия 1 остаётся
   byte/value-совместимой для units без ledger. P02/P03b одновременно понимают обе.
   Никакой скрытой потери ресурсов в legacy save-export (узкий отказ, раздел 5).
4. Новый immutable AttackRules — необязательный шестой аргумент ActionContext.
   Старые четыре/пять аргументов полностью сохраняют HP/Move поведение.
5. Новая строгая схема attacked и запрет внешнего submit внутреннего AttackHitCommand
   после P03b preflight, до root validate. Остальной порядок queue не меняется.

Не менять HP/source schemas, DamageRequest/HP executor, damage-only collector,
item adapter, DamageCalculator, Vitals, Move/PathCheck/MoveRules, RNG или P04 limits.
Если реализация требует иного расширения — CONTRACT_GAP ведущему до записи.

## 5. Ресурсы, определения статов, восстановление и snapshot

Новый `ActionResources : RefCounted`:

```text
ActionResources.new(owner_unit_id: int, main_left: int = 0, bonus_left: int = 0)
validate(expected_owner_unit_id: int) -> StringName
get_owner_unit_id() -> int
get_main_left() -> int
get_bonus_left() -> int
try_spend_main(amount: int) -> bool
to_snapshot_dict() -> Dictionary
static from_snapshot_dict(data: Dictionary, expected_owner_unit_id: int) -> ActionResources
```

Private counters, без сигналов/ссылок на UnitState/Stats/контекст. Конструктор
сохраняет invalid вход как invalid, не clamp. ids 1..MAX_ID-1, counters 0..4096;
validate: resources/owner_id либо resources/value. try_spend_main требует valid
ledger, amount>0 и достаточность, отказ false без мутаций; успех ровно один debit.
Внутренний метод назначения обоих counters нужен только валидированному refill;
он не является публичным игровым grant/reset API. to_snapshot_dict invalid -> {}.

UnitState получает `action_resources: ActionResources = null` и новые методы:

```text
enable_action_resources() -> StringName
try_refill_turn_resources() -> StringName
```

enable: вне lifetime контекста; проверить id/stats/vitals, явное объявление всех
четырёх новых stats, их валидность через отдельный bag, отсутствие существующего
ledger; затем присвоить новый ledger с owner=id, main=0, bonus=0. Не менять bases,
move/HP/balance/has_attacked, не refill. Повторный вызов — resources/already_enabled.
Нет auto-enable у create/from_dict/snapshot import/ActionContext/AttackCommand.

Подготовка P06 fixture: объявить MAIN_ACTIONS_MAX и BONUS_ACTIONS_MAX с base=1,
WEAPON_DAMAGE с явным тестовым вкладом, ATTACK_RANGE с base=1 в StatsBag; создать
юнитов штатным create; до контекста разместить/экипировать предметы; enable и
try_refill_turn_resources. Предметные modifiers остаются существующим механизмом
StatModifierEffect/StatModifierEffectRuntime. Вклад оружия — производный WEAPON_DAMAGE;
команда не читает UI или
готовый DamageInfo. Обязательная декларация базы до equip исключает случай base=0
для предмета, добавляющего +1 к максимуму. Нового оружейного slot/content нет.

try_refill: только живой enabled unit; чисто проверить текущие MOVE_RANGE (finite
>=0), MAIN_ACTIONS_MAX/BONUS_ACTIONS_MAX (integer 0..4096), ownership/runtime. На
успехе одним неэмитящим назначением установить move=max_move, main=max_main,
bonus=max_bonus и has_attacked=false. Не суммировать с остатками, не лечить HP,
не сбрасывать balance, не потреблять RNG. На любой ошибке не менять ни одно поле.
Reasons: resources/not_enabled, resources/dead_unit, resources/invalid_runtime,
resources/missing_stat, resources/invalid_maximum, resources/owner_id, resources/value.
Порядок: runtime/ownership -> alive -> declared stats -> evaluated maxima.
enable использует соответствующие ошибки; значения WEAPON_DAMAGE конечны без
ограничения знака, ATTACK_RANGE finite integer 1..4096, ошибки resources/invalid_stat.

begin_turn(): для null ledger прежнее поведение; для enabled делегировать
try_refill_turn_resources и закончить (на отказе никаких частичных изменений).
Сигнатура void сохраняется; вызывающий новый harness использует возвращающий
reason метод. begin_turn/refill не вызываются очередью, selection или snapshot.
can_attack(): alive и main_left>=1 у valid enabled ledger; при null — прежний bool.
Повреждённый enabled ledger не становится legacy. has_attacked — совместимое
информационное поле: Attack ставит true при оплате, но оно не запрещает второй main.

Snapshot DTO ledger: ровно String keys `schema_version: int=1`, `owner_unit_id:int`,
`main_left:int`, `bonus_left:int`. Owner обязан совпадать с unit.id. Unknown integer
version — UNSUPPORTED в envelope; неверные типы/shape/owner/value — INVALID.
Import возвращает новый ActionResources либо null, без allocator/refill/stat reads.

Unit snapshot v1: в точности прежние 12 keys, ledger отсутствует -> null при import.
Unit v2: прежние keys, schema_version=2, плюс обязательный `action_resources:Dictionary`
с DTO выше; null/лишние/missing keys отклонять. Capture v2 только при ledger!=null.
Нельзя трактовать v1 с дополнительным ledger как v2 или импортировать v2 в legacy.
Тип ledger на live capture ровно ActionResources; subclass -> UNSUPPORTED, invalid
owner/counters -> INVALID. Пустой/новый контекст не заменяет существующий ledger.

Envelope/board/bag/stat versions и P02/P03b magic prefixes остаются прежними:
расширяется явно версионированная вложенная Unit schema и append-only stat domain.
Старые literal bytes/fingerprints для старых данных не меняются. Смешанная доска
v1+v2 допустима. Все structural/version/capability проходы обеих snapshot систем
обновить до allocation, включая raw subtype guard P02 capture и P03b raw board
structure; unknown Unit v3 и ActionResources v2 отличать от повреждённой формы.
Старые enum-invalid tests на значении 7 заменить на первый неподдержанный 11;
это расширение домена, не удаление негативного теста. Guards других enums прежние.
Import ledger не вызывает UnitId.next/set/reset/create, begin_turn/refill/equip.
Два instantiate дают разные units/bags/modifiers/items/ledgers и сохраняют остатки.
Расход одного main меняет fingerprint снимка P03b, даже если HP не изменился.

Legacy `UnitState.to_dict()` и `BattleBoard.to_dict()` для enabled units/boards
возвращают {} ДО построения частичного экспорта: новый runtime не должен молча
сохраниться без ресурсов. Для null ledger старые export/import APIs неизменны.
Legacy from_dict не создаёт ledger/права атаки автоматически. Это narrow unsupported
guard, не новый save-game формат/миграция. Новый P06 использует только snapshot API.

## 6. Определение, rules и чистая геометрия

`AttackDefinition : Resource` — только экспортируемые `id:StringName` и
`profile:StringName`; default пустые, caller задаёт явно. Единственный поддержанный
profile=&"flat_melee_v1". id непустой, UTF-8 длина <=128 bytes. Runtime-владельцев,
Callable/Node, mutable counters и готового damage в определении нет.

`AttackRules : RefCounted`:

```text
AttackRules.new(admitted_actor_ids: Array[int], allowed_pairs: Array[Dictionary], definitions: Array[AttackDefinition])
copy() -> AttackRules
validate() -> StringName
allows(actor_id: int, target_id: int) -> bool
get_definition(id: StringName) -> AttackDefinition
```

Actor ids уникальны и в 1..MAX_ID-1, максимум 65536. Pairs максимум 65536, каждая
ровно {"actor_unit_id":int,"target_unit_id":int}; ids валидны, различны, actor
есть в actor allowlist, пары уникальны. Definitions максимум 256, точный Resource
script AttackDefinition, уникальный валидный id и поддержанный profile. Пустые
списки валидны, разрешений не дают. Неизвестный registry id в rules не создаёт unit.
Проверить outer sizes до крупных копий; oversized/invalid element сохраняется как
маленький invalid marker; validate -> attack/invalid_rules. В конструкторе снять
копии значений Resource, не удерживать caller Resource; getters/copy независимы.
get_definition неизвестного id -> null; нельзя вернуть mutable definition контекста.

ActionContext: добавить в конец `attack_rules: AttackRules = null`, хранить копию,
`get_attack_rules() -> AttackRules` возвращает новую копию или null. Некорректный
attack rules отклоняет только Attack, не ломает HP/Move. Rules не являются ledger,
смена/создание контекста не выдаёт новые действия. Snapshot контекста не добавляется.
У пары изолированных fixtures rules и RNG назначаются отдельно и эквивалентно.
Будущий Flow меняет admission policy, не формулу Attack и не move/HP ядро; сейчас
не хранить selected_actor/активации/чей_ход и не реализовывать альтернативный Flow.

`AttackReachCheck : RefCounted`, только static API:
`inspect(board: BattleBoard, actor: UnitState, target: UnitState, attack_range: float) -> StringName`.
Порядок: non-null -> range finite integer 1..4096 -> range!=1 даёт
attack/reach_unsupported -> обе клетки in bounds -> Manhattan distance==1 ->
board.get_height(actor.cell)==board.get_height(target.cell). Разности координат
через int64. Reasons соответственно attack/invalid_runtime, attack/invalid_range,
attack/reach_unsupported, attack/out_of_bounds, attack/not_adjacent,
attack/height_unsupported. Никакого provider/pathfinding/terrain movement check:
это атака размещённой цели, а не попытка войти в занятую клетку. Для этого короткого
ребра нет промежуточных клеток. Unit.height не заменяет высоту доски; видимое
размещение actor/target до вызова проверяет Attack. Это закрытая геометрия profile,
не произвольный callback-port. Позже новый profile расширит именно эту проверку.

## 7. AttackCommand и точный admission

Новый `AttackCommand : Command`:

```text
AttackCommand.new(actor_unit_id: int, target_unit_id: int,
    expected_actor_cell: Vector2i, expected_target_cell: Vector2i,
    attack_definition_id: StringName, expected_revision: int)
get_kind() -> StringName  # &"attack"
copy_for_queue() -> Command
validate(context: ActionContext) -> StringName
execute(context: ActionContext) -> CommandStepResult
get_actor_unit_id/get_target_unit_id/get_expected_actor_cell/get_expected_target_cell
get_attack_definition_id/get_expected_revision
```

Payload только значения; ids 1..MAX_ID-1, различны, revision 0..MAX_ID-2,
definition id по ограничению раздела 6. Нет доверенного caller damage/цен/range,
UnitState/Resource refs, source, новых counters или execution cursor в payload.
copy/validate не меняют live stats caches, RNG, snapshot graph или counters.

После прежнего queue preflight validate проверяет в следующем порядке:

1. Payload actor id, target id, self-target, definition id, revision.
2. Context/state/board; rules наличие и validate, затем наличие definition.
3. Actor найден -> alive -> target найден -> alive; stats/vitals и identity
   ownership обоих валидны (большинство malformed runtime раньше поймает P03b).
4. Expected revision, expected actor cell, expected target cell, затем обе
   occupancy записи равны соответствующим объектам registry.
5. Явный допуск actor/target пары из rules.
6. Actor.action_resources существует и valid(owner=id). Все четыре actor stats
   объявлены; действующие main/bonus max валидны, weapon finite. Range читать
   здесь, но проверять в AttackReachCheck с его отдельными reasons.
   Target ARMOR/actor STRENGTH читаются как в существующем StatsBag (нет stat=0).
7. AttackReachCheck, затем main_left>=1.
8. На отдельной копии actor bag прочитать STR/WEAPON_DAMAGE, на копии target bag
   ARMOR. Значения, сумма STR+WEAPON, затем разность с ARMOR должны быть finite.
   Вычислить final_damage=maxf(1.0,(STR+WEAPON)-ARMOR) в указанном порядке.
   Не менять знак отдельных stats и не вычитать броню второй раз.
9. Сконструировать DamageSource(attack,0,actor.cell,actor.id,actor.id) и
   DamageRequest(target.id,final_damage,physical,bypass,source); проверить его
   через ActionHpExecutor.validate_damage. source_instance_id=0 означает отсутствие
   отдельного runtime-источника; definition id присутствует в attacked event.
10. Если удар по текущему HP смертелен (включая alive-at-zero), обеспечить
    board_version>=0 и <=MAX_ID-1 до оплаты. Несмертельный удар тоже требует
    board_version>=0, но не резервирует version для неизвестных будущих реакций.

Таблица новых REJECTED reasons (порядок внутри групп соответствует списку выше):

| Причина | Значение |
|---|---|
| attack/invalid_actor_id, attack/invalid_target_id, attack/self_target, attack/invalid_definition_id, attack/invalid_revision | Payload |
| attack/invalid_runtime | Нет нужного state или нарушено владение runtime |
| attack/rules_missing, attack/invalid_rules, attack/unknown_definition | Конфигурация/definition |
| attack/missing_actor, attack/dead_actor, attack/missing_target, attack/dead_target | Участники |
| attack/stale_revision, attack/actor_cell_mismatch, attack/target_cell_mismatch | Ожидания caller |
| attack/actor_not_placed, attack/target_not_placed, attack/not_admitted | Occupancy/допуск |
| attack/resources_missing, attack/invalid_resources, attack/missing_stat, attack/invalid_stat | Ledger, maxima/weapon stats |
| attack/invalid_range, attack/reach_unsupported, attack/out_of_bounds, attack/not_adjacent, attack/height_unsupported | Геометрия |
| attack/insufficient_main, attack/nonfinite_damage, attack/invalid_damage_request, attack/board_version_exhausted | Бюджет/арифметика/HP/version |

Preflight/queue reasons P04/P05 не переписываются под attack/*. REJECTED сохраняет
root_id=0, отсутствие новых steps/events, revision/counters/RNG/resources/cache и
board/items побайтно/значениями. Сначала полный preflight, потом definition/admission.

## 8. Исполнение, внутренняя HP-команда и оплата

Root execute повторяет чистую проверку на актуальном состоянии и до мутаций
готовит request, event и внутренний child. Ошибка между admission и execute —
FAULTED/attack/invalid_runtime (не новый root REJECTED). Прямой execute вне queue
не является API игры. Нет RNG draw, live stat read, Vitals mutation в root.

Успех root: один try_spend_main(1), has_attacked=true; один attacked event,
mandatory=[AttackHitCommand], reactions=[], continuation=null, state_changed=true.
has_attacked уже true не отменяет debit при main_left>=1. Move/bonus/HP/balance,
board_version и инвентарь root не меняет. Неудача списания после валидного admission
даёт FAULTED/attack/invalid_runtime без частичной оплаты.

Новый `AttackHitCommand : DamageCommand` — внутренний child, не публичная команда
атаки. `get_kind()=&"attack_hit"`; конструктор получает подготовленный DamageRequest,
actor/target UnitState refs, actor ActionResources ref, обе клетки и ожидаемый
main_after. copy_for_queue копирует request/source и сохраняет private identities.
Публичные value DTO/receipt не получают эти refs. Никакого произвольного callback.
При создании сохранить отдельную private value-копию исходного request/source
как seal. До execute сравнивать все поля inherited request с seal. Копирование
child сохраняет исходный seal, а не пересоздаёт его из потенциально изменённого
request; иначе мутация amount с последующим copy узаконила бы подмену урона.

В submit после прежнего P03b capture и до root validate reject внешний
`accepted is AttackHitCommand` с attack/internal_hit. P05 continuation guard остаётся.
Внутренний child проходит обычные limits/sequence/depth; очередь видит его как
DamageCommand и вызывает execute без отдельного generic child validate.

Hit execute до HP проверяет неизменность подготовленного payload (physical/bypass,
finite amount>=1, точный source attack/0/origin/actor/credit), ids/request соответствуют
bindings, registry содержит те же живые actor/target, клетки и occupancy совпали,
actor.action_resources тот же valid ledger с прежним main_after. Invalid binding/
подмена/удаление/смещение/смерть в этом закрытом промежутке ->
FAULTED/attack/invalid_hit без HP-мутации; это нарушение runtime, не новый dodge.
Запас board_version для смертельного удара перепроверить перед HP, причина
attack/board_version_exhausted. Прямо между root и hit нет production callbacks,
реакций attacked или других siblings; изменение возможно только повреждением
runtime/trusted fixture, для которых нужен честный fault prefix.

Затем вызвать inherited DamageCommand.execute(context) на подготовленном request.
Это повторное использование того же ActionHpExecutor, без legacy calculate/apply,
второй брони, повторного STR, второй оплаты или nested queue.submit. Не вычислять
request заново в child. Validate override (если нужен) — та же чистая binding+
HP проверка; copy должен сохранять все данные и invalid markers.

Обычный trace: attack(depth0,оплата) -> attack_hit(depth1,HP) -> item Heal(depth2).
Attacked collector ничего не делает. Lethal: attacked -> damaged -> died; owner
уже мёртв, healing не генерируется. Alive-at-zero: attacked -> died, amount в died=0.
Nonlethal heal_on_damage может полностью компенсировать HP-урон; оба события честные.
Смерть/освобождение occupancy выполняет существующий HP finalize ровно один раз.

Revision: +1 за оплату root, +1 за HP child при фактическом изменении HP/alive,
каждый Heal по прежнему правилу. Board.version только при смерти/других mutators;
обычный несмертельный Attack его не меняет. Attacked обязательный даже при будущем
прерывании chain лимитом: это запись принятой оплаченной попытки, не обещание урона.

После root fault до hit (например max_commands=1) оставляет оплату и attacked в
prefix; HP ещё прежнее. После lethal hit event_limit сохраняет оба HP events,
очередь fault-latched. Никаких refunds/reset/rollback. APPLIED означает drain
завершён; FAULTED не означает отмену. Нельзя получить APPLIED со скрытым unbound hit.

## 9. attacked event — строгая value schema

Ровно следующие String keys; enum-like values StringName:

```text
kind: StringName = &"attacked"
actor_unit_id: int
target_unit_id: int
attack_definition_id: StringName
actor_cell: Vector2i
target_cell: Vector2i
main_cost: int = 1
main_before: int                 # 1..4096
main_after: int                  # main_before - 1
```

Ids различны, 1..MAX_ID-1, definition id непустой <=128 UTF-8 bytes, клетки
ортогонально соседние (int64 differences). Не класть computed damage/HP/source,
balance или двусмысленный hit=true. height equality проверяет command, не schema
через live board. Queue добавляет прежние event_seq/root_id/command_seq/parent_event_seq.
Root attacked parent_event_seq=0, mandatory hit также 0; не выдавать 0 за ссылку
на attacked. Item Heal сохраняет реальный parent_event_seq события damaged.
Дополнительные/missing keys, неверные types/ranges/arithmetic -> malformed_event.
Не расширять допуск прежних HP/moved схем. EventSink/get_events/copy DTO независимы.

## 10. allowed_paths будущей реализации

Один coder пишет runtime/tests. Ведущий отдельно интегрирует документационные
addenda. Все прежние dirty hunks сохраняются; файлы вне списка закрыты. UID новых
скриптов создаёт Godot import. Ни один помощник не коммитит.

```yaml
allowed_paths:
  - scripts/core/actions/action_resources.gd
  - scripts/core/actions/action_resources.gd.uid
  - scripts/core/actions/attack_definition.gd
  - scripts/core/actions/attack_definition.gd.uid
  - scripts/core/actions/attack_rules.gd
  - scripts/core/actions/attack_rules.gd.uid
  - scripts/core/actions/attack_reach_check.gd
  - scripts/core/actions/attack_reach_check.gd.uid
  - scripts/core/actions/attack_command.gd
  - scripts/core/actions/attack_command.gd.uid
  - scripts/core/actions/attack_hit_command.gd
  - scripts/core/actions/attack_hit_command.gd.uid
  - scripts/core/actions/action_context.gd
  - scripts/core/actions/action_queue.gd
  - scripts/core/actions/simulation_snapshot.gd
  - scripts/core/actions/item_simulation_snapshot.gd
  - scripts/core/stats/stat_types.gd
  - scripts/core/stats/stats_bag.gd
  - scripts/core/units/unit_state.gd
  - scripts/core/board/battle_board.gd
  - tests/run_tests.gd
lead_documentation_paths:
  - docs/ARCHITECTURE.md
  - docs/DECISIONS.md
  - docs/TESTING.md
  - docs/COMMAND_ACTION_QUEUE_CONTRACT.md
  - docs/CODEX_HANDOFF.md
```

BattleBoard runtime change ограничен legacy export guard; snapshot delegation уже
идёт в UnitState, occupancy/move/height не переписывать. StatsBag — только stat-type
domain guard, не arithmetic/cache/order. В runtime коде не обновлять frozen пакет.
read_paths — `files` P06_DEPENDENCIES; кодеру передать этот task и адресные файлы из
API table, не всю библиотеку документов. По необходимости REQUEST_CONTEXT ведущему.

## 11. Обязательные тесты A01–A14

Новые тесты — в имеющемся runner с префиксом p06, без удаления старого регресса.
Числа fixtures не становятся балансными defaults. Negative fixture на старый
unsupported stat 7 обновляется до 11 с сохранением проверки; прочие старые asserts
сохраняются. Старый снимок без новых stats/ledger имеет прежние literal bytes.

| Группа | Проверяемое наблюдаемое поведение |
|---|---|
| A01 Ownership | Payload/rules/pairs/Resource копируются; caller мутации до/после submit и getter copies не меняют контекст. Oversize lists, duplicate ids/pairs/definition, subtype/invalid marker. Нет hidden defaults |
| A02 Admission | Каждая reason из §7/ReachCheck; пустой допуск/unknown definition; actor/target absent/dead/self/unplaced/stale cells/revision. No ledger не auto-enables. Foreign/invalid ledger. Snapshot-before/after + raw cache/counters/RNG неизменны на каждом rejection |
| A03 Geometry | Четыре направления на любой одинаковой целой board height; unit.height намеренно отличается и не используется. Diagonal/nonadjacent отказ; разные высоты в обе стороны; range0/NaN/Inf/1.5 invalid, range2 unsupported. Attacking placed enemy не путается с заблокированным Move в его клетку |
| A04 Formula | STR=3, weapon=2, armor=1 ->4; armor=99 ->1; STR=-3, weapon=0, armor=0 ->1; negative armor как прежняя signed формула; fractional result сохраняется. NaN/Inf/overflow sum/subtraction отказ без caches. Нет второго STR/armor, нет RNG, balance неизменён |
| A05 Economy | main1->0 и отказ второй атаки; main2->1->0 даже has_attacked=true; bonus/move неизменны. Main item modifier увеличивает максимум. Новый ActionContext на том же state не пополняет ledger. Legacy can_attack без ledger прежний |
| A06 Refill | Явная подготовка до context; enable не refill; повторный enable отказ; base main/bonus1 с предметными +1 даёт2 при refill; движение MOVE_RANGE. Остатки заменяются, не складываются; dead не пополняется, HP/balance/RNG прежние. Fractional/negative/oversized maxima, missing stats/foreign ledger дают атомарный отказ. Snapshot/import/selection/submit не вызывают refill |
| A07 HP/items | Настоящий Attack->Hit->Heal: nonlethal, минимум1+heal1 даёт прежнее HP, heal2 может повысить HP; lethal не лечится, corpse/occupancy/death один раз, alive-at-zero. Вычисленный amount и фактически снятое HP/overkill различаются. Ни legacy bus, ни прямой apply не вызваны |
| A08 Move integration | Move->Attack->Move с остатком, Attack не меняет MoveRules/has_attacked gate; A move, B attack, A move при явном допуске. Два main за ход; P05 paid HAZARD/VOID/terminal interruption unchanged. Не считать fixture выбором active team |
| A09 Snapshots | Null ledger v1 exact roundtrip и старый oracle; v2 roundtrip main0/bonus4096/ownerid, mixed v1/v2 board, two independent P03b copies. Изменение одного main меняет fingerprint, A не меняет live/B. DTO входы/выходы независимы. Нет UnitId allocator/refill/equip при import |
| A10 Snapshot rejection | Все missing/extra/wrong types ledger/Unit keys, bool/float вместо int, wrong owner, отрицательные/4097 counters, unknown unit3/resources2, ledger subclass, swapped ledger; malformed shape INVALID vs supported-shape unknown version UNSUPPORTED. Новые stat7..10 и их item modifiers roundtrip; stat11 invalid/unsupported по прежнему типу gate. Legacy export enabled unit/board ->{} целиком |
| A11 Internal binding | Raw submit Hit rejected до counters; copied Hit сохраняет private refs. Trusted wrapper вставляет перед Hit замену target тем же id, actor replacement/death/displacement, ledger replacement/main change, payload corruption: fault до HP, оплата prefix сохранена, чужой unit не поражён. По отдельному сценарию для каждой проверки binding |
| A12 Events/guards | Strict attacked schema, malformed all types/arithmetic/keys, original HP/moved schema unchanged; copies в receipt и sink; nested submit из HP/died/board signals и final sink даёт BUSY на обеих queues/общем context без второго debit; stat signals при Attack не возникают, attacked не запускает collector |
| A13 Limits | max_commands1 сохраняет только paid attack prefix, max_commands2 может fault перед Heal; event_limit после lethal сохраняет damaged+died; depth cap до нужного child; sequence exhausted до root без оплаты и между root/hit с latch. Lethal board_version MAX отказ до оплаты, MAX-1 ровно один death increment. Несмертельный hit не добавляет board_version |
| A14 Isolation/regression | Две эквивалентные restored P03b fixtures + отдельные одинаковые rules/RNG: одинаковые receipts/final snapshots, исходник неизменён, RNG draws0. Весь P01–P05 регресс; old save для null-ledger и старые DamageCalculator/Move tests прежние. Нет обещания full preview/UI verification |

Тест wrappers — только trusted Command fixtures, выполняют мутации в execute с
честным state_changed; не из presentation sink/низкоуровневых mutating callbacks.
Попытки nested submit в callbacks разрешены для проверки guards, чужие мутации
из этих callbacks не поддерживаются. Не расширять production collector ради тестов.

## 12. Команды проверки и сдача реализации

В текущей подготовке документов: JSON/hashes/preservation и diff; Godot не нужен.
Входной hash gate из корня:

```powershell
git rev-parse HEAD
git status --short
$p06Dependencies = Get-Content docs/P06_DEPENDENCIES.json -Raw | ConvertFrom-Json
foreach ($entry in $p06Dependencies.files) {
  if ((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ne $entry.sha256) {
    throw "P06 dependency mismatch: $($entry.path)"
  }
}
Get-FileHash docs/P06_ATTACK_TASK.md, docs/P06_DEPENDENCIES.json -Algorithm SHA256
git diff --check
```

Оба последних hashes вручную сравнить с P06_REVIEW; HEAD descendant проверяется
по §1. Три независимые последовательные зоны для будущего coder: ресурсы+снимки,
rules+Attack/queue, затем acceptance gaps. Одновременно пишет только один coder;
ведущий проверяет интеграцию и готовит QA. Финальное независимое ревью получает
весь фиксированный результат после прекращения записи, не промежуточную смесь.

После реализации ведущий сначала import/startup/полный runner, затем независимое
ревью зафиксированного runtime, тестов и логов. Исторический P05 результат 1421/0
не подменяет будущий прогон. Число новых assertions не фиксировано, A01–A14 обязательны.

Команды PowerShell из корня (env только процессу, не SetEnvironmentVariable User):

```powershell
$p06PreviousAppData = $env:APPDATA
$p06PreviousGodot = $env:GODOT_BIN
try {
  if (-not $env:GODOT_BIN) {
    $env:GODOT_BIN = 'D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
  }
  if (-not (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) { throw 'GODOT_BIN missing' }
  New-Item -ItemType Directory -Force test_reports/godot-profile | Out-Null
  $env:APPDATA = (Resolve-Path test_reports/godot-profile).Path
  & $env:GODOT_BIN --path . --headless --import --log-file test_reports/p06-import.log
  if ($LASTEXITCODE -ne 0) { throw 'P06 import failed' }
  & $env:GODOT_BIN --path . --headless --quit-after 3 --log-file test_reports/p06-startup.log
  if ($LASTEXITCODE -ne 0) { throw 'P06 startup failed' }
  & $env:GODOT_BIN --path . --headless --script tests/run_tests.gd --log-file test_reports/p06-tests.log
  if ($LASTEXITCODE -ne 0) { throw 'P06 tests failed' }
} finally {
  $env:APPDATA = $p06PreviousAppData
  $env:GODOT_BIN = $p06PreviousGodot
}
git diff --check
```

Проверять не только exit0: import scan DONE и регистрации классов, итог runner
`N passed, 0 failed`, отсутствие новых SCRIPT ERROR/parse/compile/runtime errors.
Известный occupied-cell ERROR P01 учитывать отдельно по существующему тесту.
Ведущий проверяет snapshot compatibility/stat gates, HP one-time arithmetic,
ledger ownership, queue limits/reaction order и no refill call graph. UI не требуется.
Сохранность закрытых hashes и старых tests/docs проверяется относительно нового
baseline будущей реализации, не исторических superseded inputs. Все UID после import
включить в финальный frozen manifest. Только ведущий коммитит после APPROVE,
только scoped изменения; mixed старые dirty hunks отдельно, без push.

## 13. Следующие итерации и уточнение заблокированного толчка

Согласованный порядок: P06 -> баланс/толчок -> высоты/расширенная досягаемость.
В следующем пакете определить отдельное HP и balance воздействие, один push после
слома, порядок impact/push относительно damaged-item reactions, источники и урон
столкновений. Просто поставить Damage и Push соседними children недостаточно:
Damage subtree сейчас завершает healing до следующего sibling. P06 эту семантику
не меняет; следующий пакет обязан назвать нужное расширение явно.

Утверждённое уточнение пользователя: заблокированный толчок в стену, другого
персонажа или запрещающий уступ оставляет толкаемого на исходной клетке. Не делать
временного входа и отката, не выдавать moved/entry за запрещённую клетку. Последствие
столкновения при этом возможно, например урон от шипов стены. Шипы не реализованы;
числа, броня, урон blocker и точный порог подъёма — параметры следующего пакета.
Существующий PushResolver уже различает BLOCKED/COLLISION и исходную final_cell;
это геометрия, не готовое исполнение столкновения. Цепной push пока не начинать.

Далее: полууровни без молчаливой смены масштаба старой карты; reach2 через перепад
1.5 и край уступа со стороны actor; отдельные HP/impact multipliers без утверждения
примерных процентов. Метрика/LOS/диагональ/faction admission требуют своих правил.
Предсказуемое уклонение тоже отдельное расширение: точка проверки до HP/impact,
никакого автоматического урона1 по уклонению; способ снятия/расхода эффекта ещё открыт.
Активации bonus, combat inventory lock и boundaries/refill всех живых — будущий
Flow/content scope. Наличие технического refill метода не объявляет Flow готовым.
