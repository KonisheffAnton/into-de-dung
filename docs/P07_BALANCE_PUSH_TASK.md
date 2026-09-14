# P07 — Balance / Push

Редакция 1, 2026-09-14. **Пакет проектирования; реализация — отдельное поручение.**
Статус независимого ревью и frozen SHA-256 — в P07_REVIEW.md. Этот документ
специализирует предложения draft-2 о Balance/Push; старые TASK/manifests не меняются.

## 1. Вход и наблюдаемый результат

```yaml
task_id: P07-BALANCE-PUSH
base_commit: 3819cb50c360247d1994ee7fde49a1936f37e3e2
branch: main
requires_dirty_p01_p02_p06_dependencies: true
goal: Оплаченная плоская атака накапливает баланс и при сломе исполняет один толчок с HP/death, входом после гибели blocker и настоящими предметными реакциями.
```

Проверить HEAD/status, hashes TASK/DEPENDENCIES из P07_REVIEW и все `files` плюс
`local_artifacts` P07_DEPENDENCIES.json. Допустим документационный потомок base,
сохранивший эффективные зависимости. HEAD сам по себе не идентифицирует baseline.
Вход подготовки: 31/31 SHA-256 revision1 реализации P06 и 5/5 артефактов итогового
аудита совпали; status совпал с p06-final-audit.json. Reverse-check residual/staged
patches прошёл без применения. Из118 исторических dependencies P06 104 неизменны,
10 замещены принятой реализацией, 4 — финальными doc addenda с сохранёнными prefixes.
140 эффективных файлов перечислены в новом manifest; история не перехеширована.

Сохранить dirty/untracked P01/P02 и остаток P06: Unit snapshot v2, stat domain,
SimulationSnapshot, две fixtures runner, COMMAND_ACTION_QUEUE_CONTRACT и HANDOFF.
Сохранить процессные файлы и старые test_reports. Чистого checkout недостаточно.
Не включать прежние/чужие hunks в commit автоматически; новые артефакты — `p07-*`.

Scope: новый явный профиль headless Attack, Balance и один внутренний Push;
стена/уступ, столкновение с UnitState и вход на его место при гибели, целочисленный
спуск, lethal terrain/край, существующее heal_on_damage. P06 reach неизменен:
одно ортогональное ребро, ATTACK_RANGE=1 и равные board heights actor/target;
allowlist пар задаёт harness, нового Faction admission service нет.

Non-goals: полууровни/перекодировка высот, расширение reach/LOS, dodge/status runtime,
криты/RNG атаки, новые эффекты/активации предметов, шипы/разрушаемые terrain objects,
UI/AI, Battle Flow/BT, полный preview/token/confirm, снимок ActionContext/pending,
save-game, общий C-3/S-5/T10/T11. Legacy ActionPreview остаётся calculate-only.

## 2. Принятые игровые решения

Источник — ответы пользователя на шесть вопросов, три уточнения формул и отдельное
уточнение о занятии клетки погибшего blocker. «Пока так» утверждает правило текущего
среза. Последнее «Да» относится также к blocker-персонажу: если он погиб от collision,
выжившая толкаемая цель входит на его клетку. Это заменяет более раннюю договорённость
об отсутствии движения после смерти blocker; frozen документы P06 не переписываются.

Обозначения: `B = STRENGTH + WEAPON_DAMAGE` атакующего до вычитания брони;
`A(u) = ARMOR` получателя, `M(u) = HP_MAX`, `h` — число полных уровней спуска.
Все значения float без нового округления. ARMOR может иметь любое конечное значение
по прежнему stat-контракту; отрицательная броня арифметически увеличивает damage.

| Воздействие | Запрошенный HP damage |
|---|---|
| Исходная атака | `max(1.0, B - A(target))` — прежний P06 |
| Стена/высокий уступ | `max(1.0, B - A(target))` |
| Collision: толкаемый | `max(1.0, B - A(target))` |
| Collision: blocker | `max(1.0, B - A(blocker))` |
| Реальный спуск на `h >= 1` | `max(1.0, (M(target) * 0.25) * float(h) - A(target))` |
| HAZARD/VOID/край | Явная смерть, без числового «бесконечного урона» и без armor |

`B` не ограничивается минимумом1, остатком HP, фактически снятым HP или бронёй первой
цели. Сила не прибавляется повторно. Подтверждённый пример: B=10, armor цели=3,
blocker armor=2 → атака7, collision цели7, blocker8. Даже если цели осталось2 HP,
blocker получает запрос8. Vitals ограничивает фактически снятое HP, и damaged.amount
отражает именно его. Минимум1 действует и при collision, и при падении. При h=0
fall damage вообще не возникает; минимум1 не создаёт самостоятельное воздействие.

Impact атаки равен IMPACT_POWER независимо от armor/HP damage. Положительный impact
добавляется только выжившей цели. BALANCE_MAX≤0 — иммунитет; impact0 ничего не делает.
При достижении порога один слом и reset0 без переноса избытка, даже если превышено
несколько порогов. Один слом порождает один Push на одну клетку от атакующего, без
новой оплаты поверх attack=1 main и без публичного root Push. Wall/collision/fall
не добавляют impact, не создают новых толчков; blocker дальше не проталкивается.

При сохранившемся BLOCKED/COLLISION цель остаётся на исходной клетке: нет временного
входа/возврата, position_changed/moved/entry. Если blocker погиб, а толкаемый выжил,
после обоих HP применений цель входит в освободившуюся клетку. Это завершение того же
одноклеточного Push, не второй толчок. При смерти обоих движения нет. Вход на нижнюю
или lethal клетку имеет обычные последствия спуска/летального входа.

Порядок: HP атаки → Balance выжившему → Push/последствия → item reactions атаки.
Collision: HP target, HP blocker, затем возможный вход/падение выжившего target,
затем предметные реакции collision, затем исходной атаки. Предметное лечение не
спасает уже погибшего. Collection/binding реакции может происходить раньше mandatory
subtree по существующему dispatcher; её **исполнение** ждёт subtree и revalidation.

Игровой подъём разрешён максимум на +0.5 уровня. В P07 сохраняется исходный запрет
на полууровни: board heights — целые уровни, без удвоения старых значений. Поэтому
любой положительный целый delta блокируется: resolver вызывается с max_height_step=0.
Возможность +0.5 реализует следующий пакет высот. Целый спуск на1/2/3 уровня даёт
25/50/75% HP_MAX до брони; нет safe-level вычитания. HAZARD сохраняет действующий
смысл летальной поверхности, VOID — пропасти; это не система несмертельного огня/воды.

Для будущего окружения: прямой damage шипов складывается с collision до armor;
препятствие со своим HP тоже получает collision damage и освобождает клетку при
разрушении. В P07 есть только WALL и UnitState blocker. Terrain HP, шипы, их source,
snapshot и правила дробного спуска остаются следующему пакету, не считаются готовыми.

## 3. Реальные API на входе

| API | Значимый контракт |
|---|---|
| Vitals.add_impact(float)->bool | Owner balance, один reset0 при сломе; локальные balance_changed/broken; сам Push не выполняет |
| ActionHpExecutor.damage/heal/death | Общий HP pipeline; damaged/healed по фактической дельте, died по переходу жизни; cleanup; heal не воскрешает |
| AttackCommand / AttackHitCommand | Root платит1 main и пишет attacked; Hit sealed, bound actor/target/ledger/cells; physical+bypass |
| AttackDefinition: Resource | Поля id/profile, оба задаются явно; default пустой |
| AttackRules: RefCounted | Копии definitions/allowlists; сейчас профиль только flat_melee_v1 |
| ActionContext.new(state,rng,sink,unsupported_runtime_ids,move_rules=null,attack_rules=null) | Копии rules, guards/counters, без enable/refill |
| ActionQueue.submit | Guards до copy/validate, P03b capture до root id; mandatory → item reactions → explicit reactions → continuation, depth-first |
| CommandStepResult | status/reason/events/mandatory/reactions/continuation/state_changed; сейчас до2 events |
| BattleBoard.move_unit / clear_occupancy | Единственный позиционный owner; move меняет cell/height/version и сигнал; cleanup идемпотентен, corpse остаётся в registry |
| PushResolver.resolve_push(board,unit,cell,direction,max_height_step)->PushResult | bounds → wall → высокий подъём → живой occupant → lethal → floor; fall_height целый |
| ItemReactionCollector / Adapter | damaged → реальный heal_on_damage; stable binding/revalidation, умерший не лечится |
| P02 / P03b snapshots | Vitals.balance уже включён; Unit v1/v2 и ledger; corpse.cell обязан быть в bounds |

Legacy resolver принимает null board/zero direction как success без сдвига. Новый
Push отвергает такие входы. Legacy DamageCalculator не вызывается новым pipeline:
иначе появился бы второй путь HP/Balance. Высоты board signed int32; их разность
считать в int64, диапазон drop0..4294967295. UnitState.height не источник геометрии.

## 4. Allowed paths и ответственность

Кодер не один в checkout, не сбрасывает чужие edits и не коммитит. Одновременно
только один кодер пишет. Пути открываются при отдельном поручении на реализацию.

```yaml
allowed_paths:
  # Существующие файлы, только расширения ниже.
  - scripts/core/actions/attack_rules.gd
  - scripts/core/actions/attack_command.gd
  - scripts/core/actions/attack_hit_command.gd
  - scripts/core/actions/action_queue.gd
  - tests/run_tests.gd
  # Новые классы и их UID.
  - scripts/core/actions/balance_push_rules.gd
  - scripts/core/actions/balance_push_rules.gd.uid
  - scripts/core/actions/balance_command.gd
  - scripts/core/actions/balance_command.gd.uid
  - scripts/core/actions/push_command.gd
  - scripts/core/actions/push_command.gd.uid
  - scripts/core/actions/push_damage_command.gd
  - scripts/core/actions/push_damage_command.gd.uid
  - scripts/core/actions/collision_damage_command.gd
  - scripts/core/actions/collision_damage_command.gd.uid
```

AttackRules добавляет второй профиль; Attack/Hit — opt-in P07. Queue — запрет
внутренних roots, строгие новые events и адресную ёмкость collision. Runner — новые
_test_p07_*, вызовы и test-only helpers; старые assertions/fixtures не переписывать.
UID существующих файлов не менять. Прочие runtime пути закрыты: Vitals, Board,
HP executor, snapshot codecs, stats/items, P06 reach. Другой нужный API — CONTRACT_GAP
ведущему, не самостоятельное расширение scope. После приёмки ведущий отдельно
обновляет ARCHITECTURE/DECISIONS/TESTING/COMMAND_ACTION_QUEUE_CONTRACT/HANDOFF addenda.

Read set: existing allowed actions + action_context, command_step_result/receipt,
action_hp_executor, damage_request/source, item_reaction_collector/adapter,
item_simulation_state/snapshot, board/terrain_type, units/vitals/unit_state,
stats/stat/stat_types/stats_bag, combat/push_resolver/push_result. Hashes — manifest.
Кодеру дать TASK и адресные фрагменты, не всю библиотеку документов.

## 5. Новый API и владение

AttackCommand/ActionContext публичные сигнатуры прежние. flat_melee_v1 сохраняет
P06 HP-only semantics, события и шаги. `AttackRules.BALANCE_PROFILE =
&"flat_melee_balance_v1"` — второй профиль того же AttackDefinition, без новых полей
Resource. Constructor/copy/structure checks принимают оба, другие отвергаются.
Это версия harness, не новое правило Faction. Production UI ещё не подключён.

Новые типы — RefCounted/Command. Все команды реализуют прежние get_kind,
copy_for_queue, validate(context)->StringName, execute(context)->CommandStepResult.

| Новый API | Контракт |
|---|---|
| BalancePushRules.prepare_attack(context: ActionContext, actor: UnitState, target: UnitState, raw_attack: float, hit_amount: float, main_after: int)->Dictionary | Чистый preflight; точные ключи reason:StringName и binding:Binding (null при отказе) |
| BalancePushRules.Binding (вложенный RefCounted), copy()->Binding | Внутренние seal/identity/stage values; не сериализуется |
| BalancePushRules.prepare_push(binding: Binding, context: ActionContext, admission: bool=false)->Dictionary | Чистый актуальный resolve/HP preflight; admission только для ещё не исполненных HP/Balance |
| BalanceCommand.new(binding: BalancePushRules.Binding=null) | kind=&"balance", копия binding; post-Hit child |
| PushCommand.new(binding: BalancePushRules.Binding=null) | kind=&"push", initial phase, копия binding; post-break child |
| PushCommand.after_collision(binding: BalancePushRules.Binding)->PushCommand (static) | Внутренняя after_collision phase того же единственного входа; mandatory child пары HP |
| PushDamageCommand.new(request: DamageRequest=null, binding: BalancePushRules.Binding=null) | extends DamageCommand, kind=&"push_damage"; sealed один wall/fall request |
| CollisionDamageCommand.new(first: DamageRequest=null, second: DamageRequest=null, binding: BalancePushRules.Binding=null) | extends Command, kind=&"collision_damage"; sealed target/blocker пара, один step |
| AttackHitCommand.new(..., p07_binding: BalancePushRules.Binding=null) | Необязательный аргумент в конец, прежние вызовы без изменений |

prepare_push возвращает точные поля: reason:StringName, outcome:int,
blocked_reason:StringName, from_cell:Vector2i, attempted_cell:Vector2i,
fall_height:int, first:DamageRequest, second:DamageRequest, binding:Binding,
board_touches:int. При отказе reason непуст, остальные поля нейтральны/refs=null,
не исполняются. Outcome — неизменённый PushResult enum, requests только для ветки §7.
Blocker фиксируется отдельными refs в binding; cached PushResult не authority.

Binding по значениям: B (конечный signed float), impact, balance_before/max,
expected post-Hit HP/alive, post-Balance value/broke, ids/cells/direction,
main_after, копия исходного DamageSource и phase. Refs: context/state/board,
actor/target, их StatsBag/Vitals/ItemOwnerState, actor ActionResources.
После resolve добавляются blocker refs/id/cell/HP и копии damage requests; для
HP children — ожидаемые HP/cells stage. After-collision copy ожидает post-collision
HP цели, погибший исходный blocker и пустую destination. После move отдельная
копия ожидает target на destination. Исходный root binding детьми не мутируется.

Binding имеет отдельный исходный seal значений. Мутация payload не пересоздаёт seal
при copy; sources/requests/value dictionaries копируются, refs сохраняются для
identity. Имена приватных полей/helpers выбирает кодер; перечисленные refs/values
обязательны. Это защита доверенного command framework от stale/mutation, а не
криптографическая capability для произвольного кода. Ни refs, ни seals не выходят
в events/receipts/snapshot. Никаких новых subscriptions, исполняющих gameplay.

## 6. Валидация и guards

**Root admission:** прежние queue BUSY/fault/limits/context/copy/P03b gate → запрет
внутренних roots → прежний порядок P06 Attack validation. После успешного P06
_prepare только новый profile вызывает prepare_attack до оплаты/ids:

1. Проверить и сохранить точные script types и identity context/state/board,
   actor/target/stats/vitals/owner/ledger, vitals._stats, registry/живые occupancy/cells.
   P06 revision/admission/reach/resources уже должны пройти.
2. Явные IMPACT_POWER actor и BALANCE_MAX target обязательны. Читать validated
   StatsBag copies: impact конечен и>=0, max конечен (<=0 иммунитет), balance конечен
   и>=0, в том числе over-max snapshot. B/hit_amount/expected HP конечны, hit_amount>=1.
3. При impact>0/max>0 проверить конечность balance+impact, даже если затем reset0;
   зафиксировать ожидаемый break/after. Impact0/max≤0 ничего не делают даже over-max.
4. Только если цель переживёт hit и будет break, выполнить prepare_push(...,true).
   Он проверяет текущую геометрию и необходимые collateral stats без требования
   post-Hit/Balance values от ещё не изменённого root; ledger на admission должен
   иметь main_after+1, после оплаты main_after. Wall — ARMOR target;
   collision — ARMOR обоих; реальный drop — ARMOR и явный конечный HP_MAX>=0 target.
   Если collision прогнозирует смерть blocker и выживание цели, preflight также
   проверяет будущий вход/drop/lethal по terrain/height destination БЕЗ временного
   удаления blocker или правки occupancy. Если входа не будет, fall stats не нужны.
5. Проверить каждое промежуточное вычитание/умножение до max1. Итоговые requests
   physical+bypass, конечный amount>=1, validate_damage/death успешны. Запас version
   на известные direct mutations: hit death1 ИЛИ цепь Push; collision deaths0..2,
   возможный entry1 и entry death1. Максимум цепи3 (blocker death+move+target death).
   Считать required в малом int, board_version>=0 и<=MAX_ID-required.

Если collateral не возникнет (kill/нет break/иммунитет), неиспользованный blocker
или fall HP_MAX не причина rejection. Отказ не меняет HP/balance/ledger/позиции,
cache/RNG/ids/counters/events. Нет UnitId/refill/equip/autoload calls. Направление
соседей P06 — target.cell-actor.cell, одно ортогональное ребро; null/zero/diagonal/
multi-cell payload отвергается. Admission не резервирует budgets/counters всей цепи.

**После admission:** Hit проверяет старый seal и новый binding до HP. Execute не
доверяет ранее выполненному validate. Тот же context/state/board, refs stats/vitals/
owner/ledger, ids/cells/occupancy/main_after обязательны. До Balance ожидаются
post-Hit HP/alive, исходный balance и effective BALANCE_MAX; до initial Push —
post-Hit HP/alive и post-Balance value. Их подмена даёт fault, не перенос эффекта.
B и impact заморожены при оплате; STR автора не вычисляется повторно.

Destination topology не заморожена: initial Push повторяет resolver на актуальной
доске и читает актуальные collateral stats через копии. Requests фиксируются при
resolve; HP children проверяют seal/refs/HP/cells, но armor второй раз не вычитают.
Нормально погибший от Hit не получает Balance child. Неожиданно missing/dead/
replaced участник внутреннего child — fault, не обычный skip.
After-collision phase проверяет target alive/post-collision HP, исходный blocker
в registry именно тем же мёртвым объектом, destination без живого occupant, from
прежняя и one-edge destination. Новый blocker/wall/уступ → push/entry_obstructed,
без повторного damage или продвижения; это stale runtime, не новая атака.

Существующие P06/P04 причины/precedence сохраняются. Новые причины:
`balance/missing_stat`, `balance/invalid_stat`, `balance/nonfinite_sum`,
`balance/invalid_binding`; `push/invalid_binding`, `push/invalid_direction`,
`push/invalid_geometry`, `push/invalid_stat`, `push/nonfinite_damage`,
`push/invalid_request`, `push/board_version_exhausted`, `push/board_move_failed`,
`push/entry_obstructed`. Wall/collision/fall — успешные исходы, не root rejection.

Прямо submitted внутренние команды после copy и до root id отвергаются причинами
`balance/internal_command`, `push/internal_command` (обе phases),
`push/internal_damage`, `push/internal_collision`. Проверка через `is` охватывает
subclasses, как у AttackHit. Общий whitelist trusted test roots не вводится.
BUSY действует из Vitals balance/hp/died, board signals и sink, включая другую queue
с тем же context. Fault защёлки обеих сохраняются. Общий S-5 (произвольные внешние
мутирующие callbacks/revive) вне support; это не отменяет перечисленные guards.

## 7. Исполнение и очередь

1. **Attack** после preflight создаёт sealed Hit/binding до единственной оплаты1 main;
   has_attacked=true, прежний attacked, bonus/move прежние.
2. **Hit** применяет прежний ActionHpExecutor.damage. При прямой смерти только
   damaged/died/cleanup. Выжившему при impact>0/max>0 ставит mandatory Balance;
   иначе Balance child отсутствует. Собранное лечение исходного hit исполняется
   после mandatory subtree и становится stale, если Push убьёт цель.
3. **Balance** вызывает Vitals.add_impact ровно1. Journal: balance_changed при точном
   before!=after, затем balance_broken при break. Approx-сигнал Vitals не определяет
   журнальную дельту. При break mandatory initial Push, без второго reset.
   state_changed=true при numeric delta ИЛИ break (включая0→0), иначе false.
4. **Initial Push** заново prepare_push(...,false), проверка requests/version до мутации:

| Ветка | Один Push step и его дети |
|---|---|
| MOVED h0 | Один board.move_unit, forced moved, без HP child |
| MOVED h>=1 | Один board.move_unit, forced moved, mandatory sealed PushDamage fall |
| BLOCKED wall/height | Только push_blocked; mandatory PushDamage collision; движения нет |
| COLLISION | Только collision marker; mandatory CollisionDamage пара; до её результата движения нет |
| FELL свободный HAZARD/VOID | В одном step board.move_unit, moved, затем ActionHpExecutor.death/died/cleanup |
| FELL bounds | В одном step fell(attempted_cell), ActionHpExecutor.death/died/cleanup; нет move_unit, cell/height остаются исходными |

Летальный Push атомарен для очереди: между входом и death нет child, проверки queue
limit, collection или реакции. Максимум2 events. Новый BattleBoard.finish_fall из
draft-2 не нужен: штатный death path сохраняет corpse в bounds и убирает occupancy.
Не добавлять позиционного/HP owner, не публиковать вторую смерть из Vitals callback.

5. **PushDamage** проверяет request seal и stage binding, один HP executor.damage
   physical+bypass без impact. Damage/death и настоящие item reactions прежние.
6. **CollisionDamage** перед первым HP проверяет ОБА bindings/requests и общий запас
   version для0..2 смертей. Применяет target HP, затем blocker HP в одном execute;
   state_changed через OR, events target damaged/died, затем blocker damaged/died.
   Если blocker погиб и target выжил, mandatory PushCommand.after_collision с новой
   stage copy. Если blocker выжил или target погиб — такого child нет.
7. **After-collision Push** повторяет geometry check, но допускает только MOVED/FELL
   в прежнюю attempted destination. Исполняет соответствующую строку таблицы выше:
   moved один раз, при drop один fall child, lethal death атомарно. Никогда не создаёт
   collision/wall damage повторно и не продвигается на вторую клетку. Его обязательные
   последствия исполняются до item reactions collision, затем до reactions hit.

Только после возврата CollisionDamage queue собирает реакции его HP events; оба HP
применения уже завершены. Нельзя заменить пару двумя Damage siblings: subtree первого
исполнил бы heal до второго HP. Обязательный entry subtree предшествует выполнению
этих реакций; погибший после entry не лечится ранее собранным binding.

Если незаконный callback повредил blocker после первого HP, повторно проверить его
binding перед вторым HP и вернуть FAULTED с уже применёнными events/state_changed
первого; replacement не повреждать. Проверка второго не требует, чтобы первый остался
жив. Ошибка после move сохраняет реальный moved/state_changed. Для такого fault нужен
явный CommandStepResult: factory faulted(reason) отбрасывает prefix. Rollback нет.

## 8. Строгие события, source и ёмкость

Queue добавляет root_id/command_seq/event_seq/parent_event_seq. Точные keys, без extra;
StringName не подменяется String; Object refs отсутствуют. Новые schemas отдельно от
неизменных legacy voluntary moved/attacked/HP schemas. Отдельного entry события нет.

Общие поля новых событий: kind:StringName, actor_unit_id:int (автор атаки),
target_unit_id:int (толкаемый), оба в1..MAX_ID-1 и разные.

| kind | Дополнительные точные поля |
|---|---|
| balance_changed / balance_broken | balance_before:float, balance_after:float, balance_max:float, impact:float, broke:bool |
| moved forced | from_cell:Vector2i, to_cell:Vector2i, movement_kind:StringName (ровно &"push"), move_cost:float, move_before:float, move_after:float |
| push_blocked | from_cell:Vector2i, attempted_cell:Vector2i, reason:StringName (&"wall" либо &"height") |
| collision | from_cell:Vector2i, attempted_cell:Vector2i, blocker_unit_id:int |
| fell bounds | from_cell:Vector2i, attempted_cell:Vector2i, reason:StringName (ровно &"bounds") |

Balance floats конечны, before/after>=0, max>0, impact>0, sum конечна. При sum>=max
broke=true/after0, иначе broke=false/after=sum. Changed требует before!=after,
broken требует broke=true. Forced moved: разные клетки, одно ортогональное ребро;
cost=0.0, before/after конечны>=0 и равны (move_points_left цели). Blocked/collision/
fell: attempted на одном ребре от from. Blocker id допустим и отличен от actor/target.
Bounds/terrain/occupancy проверяет command; stateless _valid_draft проверяет форму/
арифметику, не существование клетки. После смерти blocker moved идёт отдельным step;
collision marker не является moved. Pushed-дубликат moved не добавлять.

HP schema прежняя. Source последствий: instigator=credit=actor.id, instance0.
Hit: kind=attack/origin=actor_cell. Wall/unit collision обоих: kind=collision/
origin=attempted_cell. Спуск/lethal/край: kind=fall/origin=destination/attempted_cell.
Out-of-bounds origin уже разрешён DamageSource. Нет фиктивного source unit WALL.

**Collision capacity:** приватный `_event_capacity(command)->int` возвращает4 только
для command.get_script()==CollisionDamageCommand, иначе2. Result cap и event_seq
reserve используют один helper. Subclasses/произвольный command не получают cap4.
`_can_step(context,event_capacity:int=2)` сохраняет command/revision bounds и требует
1<=next_event_seq<=MAX_ID-event_capacity. На root admission capacity2; перед каждым
entry/command_seq/execute drain передаёт capacity entry. Глобально cap не увеличивать.

Обе collision deaths сохраняют4 events как один step/одна revision delta. При event
limit остаются ВСЕ events завершённого step, затем fault до collection/детей. Это
может оставить погибшего blocker и живую цель в исходной клетке до entry: префикс,
а не завершённое действие. _take_event_seq не переполняется. Остальные budgets,
children order/parent_event_seq прежние: mandatory0, item привязан к damage event.

## 9. Fault prefix и snapshots

| Остановка | Что уже остаётся |
|---|---|
| Root rejection | Ничего: root0, нет events/steps/мутаций/расходов |
| До Hit | Оплата1 main, has_attacked, attacked; HP/balance/position прежние |
| До Balance | Оплата и HP/events hit; balance/position прежние |
| До initial Push | Оплата, HP, balance/reset/broken; position прежняя |
| После wall/collision marker до HP child | Marker без collision HP и без движения |
| После CollisionDamage до entry | Оба HP результата, deaths/cleanup; живой target ещё в исходной клетке |
| После обычного moved до fall child | Реальный move, без ещё не исполненного fall damage |
| Летальный Push выполнен | moved либо fell и died вместе, corpse cleanup; queue limit не оставляет живого между ними |

Нет возврата main/HP/balance/move при fault и нет повторной оплаты/возобновления
faulted context. Marker сам по себе revision не увеличивает; balance break увеличивает
даже0→0. Board_version отражает только реальные move/occupancy touches, не pay/marker.

Snapshot schema/enum неизменны: balance внутри Vitals, Unit v1/v2/ledger поддержаны,
board.height единицы прежние. Over-max HP/balance не clamp при import, правило действия
применяется только при воздействии. После любого Push corpse.cell в bounds; после
края сохраняется также независимое исходное UnitState.height, при real move height
берётся с board. Мёртвый blocker и вошедший target могут иметь одну cell в registry,
occupancy принадлежит только живому target — этот P02 случай уже допустим.

Нет новых runtime registries/listeners/hidden refill/equip. Bindings/rules/queue
не добавляются в P02/P03b DTO. Две симуляции — два независимых restore, два context с
равными копиями AttackRules/RNG. Равенство receipts/fingerprints harness не объявляется
полным preview/token. Dirty baseline snapshot files по-прежнему нужны для запуска.

## 10. Приёмка A01–A17

Точные числовые/event-order assertions в новых _test_p07_*, не только APPLIED.
Основа примеров: допущенная соседняя атака B10/impact5/max_balance5/balance0,
достаточный main. Иные values заданы явно. Items через прежние APIs до context.

| ID | Сценарий и oracle |
|---|---|
| A01 | Оба profiles copy/isolation; flat_melee_v1 сохраняет весь старый регресс; unknown profile reject. Оплата1 main, без bonus/move/refill |
| A02 | Impact2+2+1/max5 →balance2,4,0/один Push; impact12 →один Push/reset0. Из0/impact5 только broken без changed, revision растёт; impact0/max0/max<0 ничего; дробные и over-max balance |
| A03 | Lethal hit при большом impact: damaged,died/cleanup, без Balance/Push. Alive-at0 получает died без fictitious damaged. Stats bases не меняются |
| A04 | Четыре направления flat forced move1, один position_changed/moved, cost0.0, target move/main/bonus прежние. P06 diagonal/height/range>1 reject; unit.height не подменяет board |
| A05 | WALL/+1 уступ: targetHP100/armor3 →attack93→wall86. Только blocked, нет moved/entry/position_changed, прежние cell/height. Уступ с occupant не ранит occupant; blocked death очищает occupancy |
| A06 | Blocker выжил: targetHP100/armor3 и blockerHP100/armor2 →86/92, никто не движется. Target post-hit HP2: фактический collision2/death, blocker всё равно запрос8; no impact от collision |
| A07 | Оба с heal_on_damage2, blocker выжил: оба HP86/92 до первой collision heal; затем target88, blocker94, target исходного hit90. Events доказывают порядок. При target dead старое attack heal skipped, revival нет; оба dead — два died, без heal/движения |
| A08 | Полная броня →attack/wall/collision каждому1; B0/negative сохраняет max1 после armor; нет двойного STR/armor. NaN/INF/finite-operation overflow reject до main; negative impact reject, negative max immune |
| A09 | M100/armor3/HP100 →hit93, drop1 damage22→71, drop2 damage47→46, drop3 damage72→21. h0 без fall child. M10/armor0/h1 damage2.5 без round. Armor1000/h1 damage1; M со stat modifiers, не currentHP |
| A10 | Свободный HAZARD/VOID: moved,died одним step; bounds: fell,died без moved/position_changed, original cell/height corpse, occupancy пуста. Armor не спасает; occupant на lethal даёт collision первым, corpse не блокирует |
| A11 | Missing/invalid stats, stale clean cache, refs/types/owner, stale revision, internal roots →rejection без mutations/cache/RNG/ids. Copy/getter/input mutation не меняет принятое |
| A12 | Sealed payload/source/B/impact/request mutations и missing/dead/displaced/replaced actor/target/blocker, stats/vitals/owner/ledger replacement/paid counter change →fault/prefix, replacement цел. Topology destination hook до initial Push →актуальный resolve |
| A13 | Command/depth/event limits на каждой границе §9; обе collision deaths пересекают event limit →все4 events/обе HP мутации. Collision next_event_seq=MAX-4 допускает4, MAX-3 fault до HP/command_seq; другие commands не cap4. Version exhaustion до moves/deaths, запас0 не требует1 |
| A14 | Nested submit из balance/hp/died/board/sink через ту же/другую queue →BUSY до copy; malformed new schemas/types/semantics →fault; latch. Живой HP0 в collision корректен; cap4 — максимум, не минимальное число events |
| A15 | P02 Unit v1/v2 и два P03b restore с balance/modifiers/items/ledger: равные rules/commands/RNG →равные receipts/steps/events/fingerprints/counters; двусторонняя isolation. Corpse после bounds и corpse+live в одной cell round-trip; allocator/refill/equip не вызваны |
| A16 | BlockerHP8/armor2 умирает, targetHP100/armor3 выживает →target86, затем ровно1 moved в blocker.cell, труп остаётся, occupancy target. При обоих dead движения нет. На floor ниже на1 после collision86→fall64; при blocker выжил падения нет. На HAZARD target входит/умирает до любого item heal |
| A17 | Entry child limits сохраняют пару HP до moved; destination занята replacement/новой стеной перед entry →fault без повторного collision/движения. Повреждение blocker callback после первого HP сохраняет первый prefix, replacement цел. Полный старый регресс, source/credit/origin, отсутствие новых binding leaks |

Seams: существующие P06AttackHitHook/P06AttackBindingHook, P05MoveHook — шаблоны для
новых test-only wrappers, не причина переписывать старые helpers. Реальное healing
обязательно; fake collector не заменяет приёмку. Число прежних assertions —1633.

## 11. Проверки реализации и передача

Проектирование не запускает Godot. При реализации из корня PowerShell, только
process environment; локальный Godot путь брать из TESTING.md, user/system env
не менять. Создать новый test_reports/p07-check.ps1, порядок:

```powershell
$p07PreviousAppData = $env:APPDATA
try {
    if (-not (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) { throw 'GODOT_BIN missing' }
    New-Item -ItemType Directory -Force test_reports/p07-godot-profile | Out-Null
    $env:APPDATA = (Resolve-Path test_reports/p07-godot-profile).Path
    & $env:GODOT_BIN --path . --headless --import --log-file test_reports/p07-import.log
    if ($LASTEXITCODE -ne 0) { throw 'P07 import failed' }
    & $env:GODOT_BIN --path . --headless --quit-after 3 --log-file test_reports/p07-startup.log
    if ($LASTEXITCODE -ne 0) { throw 'P07 startup failed' }
    & $env:GODOT_BIN --path . --headless --script tests/run_tests.gd --log-file test_reports/p07-tests.log
    if ($LASTEXITCODE -ne 0) { throw 'P07 tests failed' }
} finally {
    $env:APPDATA = $p07PreviousAppData
}
git diff --check
if ($LASTEXITCODE -ne 0) { throw 'P07 whitespace failed' }
```

Если GODOT_BIN назначается helper-ом, сохранить/восстановить его процессное значение
аналогично APPDATA. Старый p06-check не запускать: он перепишет принятые logs/hashes.
Проверить scan DONE, пять новых class/UID, A01–A17, весь runner без failures/SCRIPT/
parse/runtime errors. Exit0 один недостаточен. Историческая опора P06 —1633/0;
known occupied-cell ERROR и45 ObjectDB/18 resources сравнивать с P06/P05 logs,
новые leaks не списывать на baseline. UI не подключён/не проверяется пакетом.

Ведущий фиксирует runtime/tests/UID/log hashes и diff после прекращения записи
единственным кодером; самостоятельно проверяет contracts/queue/snapshot, затем
независимый game_reviewer Terra/high читает фиксированный результат. После APPROVE
обновить HANDOFF/контракты, проверить чужой baseline, stage только свои отделимые
hunks и логический Conventional Commit; не push. Dirty P01/P02 не включать автоматически.
TASK/dependencies не переписывать под новый код: implementation manifest фиксирует
принятый результат и замещает effective inputs следующего этапа.
