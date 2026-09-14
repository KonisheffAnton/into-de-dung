# P08 — полууровни, движение и прямая досягаемость

Редакция 2, 2026-09-14. Статус: спецификация для независимого ревью.
Этот этап готовит документы; runtime НЕ разрешено менять текущим поручением.
Следующий исполнитель получает отдельное поручение на реализацию frozen-пакета.

## 1. Вход и один наблюдаемый результат

```yaml
task_id: P08-SPATIAL
base_commit: c12cbcacf70f1b04018659d7cbf6f90c4ba39ba4
branch: main
goal: >-
  Headless harness исполняет Move и прямую Attack на полууровнях через общую
  геометрию; стоимость, HP, баланс, Push и восстановленные копии согласованы.
dependencies: docs/P08_DEPENDENCIES.json
```

HEAD сам по себе недостаточен. Нужны принятые dirty P01/P02/P06 и untracked
snapshot-скрипты/документы. Сначала сверить files/local_artifacts нового manifest,
HEAD/status и frozen hashes из P08_REVIEW. Допустим документационный потомок base,
сохраняющий все effective hashes. Несовпадение — CONTRACT_GAP до записи.

Приоритет: фактическая принятая P07 implementation revision1 и final doc addenda
выше исторических входных P07_DEPENDENCIES. Последний принятый прогон ведущего:
1996 passed / 0 failed, import/startup PASS, implementation review APPROVE.
Это исторические проверки P07, не результат исполнения P08.

Новый профиль Attack `spatial_melee_balance_v1` и новый профиль Move
`spatial_move_v1` включаются явно. Старые профили P05/P06/P07 на целых досках
сохраняют прежнее поведение. Никакого автоматического включения в сцене, UI или AI.

Non-goals: отрисовка/клики/редактор полууровней, подключение UI/AI/BT/Flow,
полный preview/token/confirm и save-game, очередь в snapshot, новые factions,
уклонение/статусы, item activations, terrain HP/шипы, цепной Push, прыжки,
диагональные/L-образные атаки, общий 3D LOS и произвольный немонотонный рельеф.
Пакет не закрывает общие C-3/S-5/T10/T11.

## 2. Согласованные игровые правила

Последнее подтверждение пользователя заменяет прежние x1.5 и /1.5 для баланса.
Фразы ниже о поведении относятся к новому spatial-профилю, не к legacy fixtures.

### 2.1 Высота, движение и стоимость

Высоты кратны 0.5 полного уровня. Board — источник геометрии.
Добровольное движение только по четырём соседним клеткам: подъём до +1 включительно,
спуск на любую высоту. WALL/VOID не являются путём; HAZARD проходим и летален.
За вход платится terrain cost, плюс полные уровни подъёма текущего ребра:

`edge_cost = terrain_cost(destination) + floor(max(0, destination_h - source_h))`.

Пользователь отдельно уточнил ПОЛНУЮ стоимость обычного соседнего перехода:
на +1 всего 2 очка, на +0.5 всего 1 очко. Полуровень не делает горизонтальный
переход бесплатным. Плоское ребро/спуск стоят 1; HAZARD сохраняет базовую цену 3.
Два последовательных подъёма по 0.5 стоят 1+1, один подъём на 1 стоит 2.
Ограничение подъёма проверяется на каждом ребре, не по суммарной высоте пути.

### 2.2 Прямая атака

R = конечный целый ATTACK_RANGE от 1 до 4096. Actor и target различны и лежат
на одной строке ИЛИ колонке. d — число горизонтальных рёбер между ними, d>=1.
`required_range = d + floor(abs(target_h - actor_h))`; доступно при <=R.
R1 на одной высоте достигает первого соседа, R2 — первого и второго по прямой.
Ограничение симметрично вверх/вниз; особое правило «цель на краю» отменено.

| d | abs перепад | required_range |
|---:|---:|---:|
| 1 | 0 / 0.5 | 1 |
| 1 | 1 / 1.5 | 2 |
| 2 | 0 / 0.5 | 2 |
| 2 | 1 / 1.5 | 3 |

Внутренние клетки линии проверяются от actor к target; endpoints не являются
промежуточными препятствиями. Живой промежуточный occupant пропускает атаку
только при `occupant.is_friendly_to(actor)`. Существующая Faction считает
дружественными равные factions, включая NEUTRAL/NEUTRAL. PLAYER/NEUTRAL и
ENEMY/NEUTRAL не дружественны. Труп не блокирует. Равная faction не разрешает
саму цель: прежний pair allowlist AttackRules остаётся отдельным admission.

WALL внутри линии блокирует. Неподтверждённый общий LOS не угадывать: для этого
ограниченного профиля внутренний VOID и немонотонный рельеф дают явное
`attack/terrain_shape_unsupported`, не новое игровое правило невозможности атаки.
Поддерживаемый рельеф линии (включая endpoints) — монотонный по высоте:
неубывающий при target выше, невозрастающий при target ниже, постоянный при равных.
FLOOR/HAZARD внутри такой линии поддержаны; HAZARD не вызывает entry effect от атаки.
Сложный луч через яму/гребень требует следующего пространственного расширения.

### 2.3 HP и баланс удара

Пусть signed_steps = H(actor)-H(target), где H измерен в половинах уровня.
`m = max(0.0, 1.0 + float(signed_steps) * 0.1)` — ЛИНЕЙНЫЙ множитель.
Полуровень даёт +/-10%, полный уровень +/-20%. Это не степень 1.2.
Ограничение m снизу нулём не даёт отрицательной силе и отрицательному множителю
превратиться в положительный сильный удар. Итоговый минимум применяется отдельно.

Порядок float-операций фиксирован:

1. `B = STRENGTH + WEAPON_DAMAGE` (прежняя сумма, без отдельного base damage).
2. `scaled = B * m`; `hit = max(1.0, scaled - ARMOR(target))`.
3. Для исходного I=IMPACT_POWER: I<0/NaN/Inf — отказ; I==0 -> impact0;
   I>0 -> `impact = max(1.0, I * m)`. Броня на impact не влияет.
4. BALANCE_MAX<=0 сохраняет immunity. Impact только пережившей hit цели.
   Один break/reset0 без переноса избытка, ровно один бесплатный Push.

HP минимум1 — величина запроса до clamp по оставшемуся HP; предмет может её вылечить.
При m0 удар запрашивает минимум1, положительный impact тоже1; исходный impact0
не становится единицей. На равной высоте положительный I<1 также получает минимум1
в spatial-профиле; legacy P07 эту новую нормализацию не получает.
Отрицательные конечные armor/B допускаются прежними контрактами; не вводить clamp
самих stats. Проверять finite каждой суммы/произведения/разности до root мутации.

Высотный множитель применяется к прямому удару. Статусные эффекты вне scope.
Для wall/collision сохраняется НЕМАСШТАБИРОВАННЫЙ B: каждому получателю отдельно
`max(1.0, B - его ARMOR)`. Не передавать scaled/hit вместо B в BalancePushRules.

### 2.4 Push и падение

Push остаётся на одну клетку ОТ actor в сторону target, независимо от R/d.
Направление = нормализованный осевой знак, не полный вектор до удалённой цели.
Подъём Push разрешён до +0.5, спуск любой. Порядок P07 сохраняется:
bounds -> WALL -> слишком высокий подъём -> живой blocker -> lethal -> floor.

Для drop_steps=max(0,H(from)-H(to)) число полных уровней `n = drop_steps / 2`
(целочисленное деление неотрицательного int). Половинки не накапливаются между
рёбрами. Для Push n0 -> нет fall damage; n>=1 -> прежняя формула
`max(1.0, (HP_MAX * 0.25) * float(n) - ARMOR)`.
Для добровольного Move fall damage есть только при drop_steps>2; затем та же
формула по ВСЕМ полным уровням n, не по n-1. Клеточный lethal заменяет числовое
падение; не выдавать одновременно fall damage и terrain death.

| Спуск | Move fall | Push fall |
|---:|---:|---:|
| 0.5 | нет | нет |
| 1 | нет | за 1 |
| 1.5 | за 1 | за 1 |
| 2 / 2.5 | за 2 | за 2 |

Collision/fall не добавляют balance и не запускают новый Push. Оба HP collision
исполняются одним step до лечения; если blocker погиб, выжившая цель входит,
entry/fall/lethal завершаются до collision item reactions, затем hit reactions.
Выживший blocker оставляет цель на месте, без фиктивного moved/entry.
HAZARD/VOID/край летальны независимо от брони. За край corpse остаётся на исходной
допустимой cell с прежним UnitState.height; occupancy очищается, registry сохраняется.

## 3. Представление и совместимость (решение ведущего)

Не удваивать молча существующий `_heights`. Сохраняются PackedInt32Array целых
уровней и старые значения карт. Добавляется `_height_half_steps: PackedByteArray`,
ровно width*height элементов 0/1. Физическая высота = целая часть + bit/2.
Целая часть — математический floor: -0.5 представляется (-1,1).

Новые API BattleBoard:

```gdscript
func get_height_steps(cell: Vector2i) -> int
func set_height_steps(cell: Vector2i, steps: int) -> bool
func has_half_heights() -> bool
func make_spatial_data_provider(moving_unit: UnitState = null) -> GridDataProvider
```

get_height_steps = int(get_height(cell))*2 + bit; диапазон [-4294967296,4294967295].
Для out-of-bounds get возвращает0 как legacy getter; все геометрические проверки
обязаны проверить bounds ДО getter. set принимает только этот диапазон/in-bounds,
при отказе false и ноль мутаций. Успех меняет обе части атомарно и делает один
_touch, включая запись прежнего значения как существующий set_height. При
board_version==MAX_ID отказ без мутации. set_height(cell,old_integer) сбрасывает
bit в0 с одним _touch; resize обнуляет оба массива. Новые mutators не являются
командами terrain editing, их нельзя вызывать внутри drain через внешние callbacks.

Старый get_height возвращает целую часть. UnitState.height остаётся int64 cache
целой части: add/move присваивает старый get_height. Он не источник геометрии,
его независимое snapshot значение и int64 extremes сохраняются. Fractional cache
юнита/новая Unit schema НЕ нужны: fractional geometry принадлежит клетке board.
Новые SpatialRules/Move/Attack/Push никогда не читают UnitState.height для геометрии.

Legacy command profiles на любой доске с bit1 отклоняются до геометрии/оплаты:
`move/height_units_unsupported` / `attack/height_units_unsupported`.
Legacy make_data_provider/make_terrain_only_provider на такой доске возвращают
провайдер с walkable=false для всех клеток. Это явный отказ старого пути; spatial
провайдер создаётся отдельным API. Новые полууровневые доски доступны только
headless harness этого пакета; старые direct DamageCalculator/ActionPreview и
рендеринг на них не поддерживаются, не объявлять их исправленными.

### 3.1 Snapshot

Board schema1 и его exact keys сохраняются на доске, где все bits0.
Board schema2 имеет те же поля плюс `height_half_steps: Array[int]`, точной длины
width*height, только TYPE_INT 0/1; хотя бы один1 (иначе неканоническая форма INVALID).
`heights` и в v2 остаётся Array int32 ПОЛНЫХ уровней; Unit snapshots v1/v2 прежние.
Все лимиты board/units/raw graph/stats/cache и ownership P02/P03b/P06 сохраняются.

SimulationSnapshot envelope/scope/codec prefix P02S1 остаются; версия вложенного
board явно различает формат. ItemSimulationSnapshot envelope/scope/owners также
прежние; его дублирующий _board_structure и live shape validation понимают bits.
Новые данные проверяются ДО allocation/copy/restore; INVALID для неправильной
формы/типов/размеров/bit, UNSUPPORTED для целой неизвестной версии с корректной
известной формой. Расширить _find_unsupported для обеих board shapes; не ослаблять
приоритет malformed vs unsupported для Unit/ActionResources/Stats.

Восстановление v1 создаёт нулевой parallel array, v2 — независимый массив.
board_version/registry/occupancy/corpses и независимый Unit.height восстанавливаются
без add_unit/move/refill/equip/UnitId allocator. DTO не хранит live refs.
Canonical bytes/hash видят каждый bit; old whole-board bytes остаются побайтно
прежними. Capture -> instantiate -> capture сохраняет canonical values/bytes.
Переход последнего bit1 в0 при обычном редактировании закономерно возвращает v1.

Legacy BattleBoard.to_dict не должен терять halves: на fractional board возвращает
пустой Dictionary; from_dict при наличии height_half_steps либо schema_version
возвращает null ДО старого allocating/UnitId пути. На старых немаркированных
whole-board DTO поведение прежнее. Полный save-game этим не реализован.

## 4. API и точные интеграционные швы

Все новые имена ниже — ТРЕБУЕМЫЕ API будущей реализации, сейчас их нет.
Resource остаётся определением, mutable результаты/Binding — RefCounted.

### 4.1 Общая геометрия

Новый `SpatialRules extends RefCounted` в scripts/core/actions/spatial_rules.gd:

```gdscript
class EdgeCheck extends RefCounted:
    var reason: StringName = &""
    var cost: float = 0.0
    var drop_steps: int = 0
static func inspect_edge(provider: GridDataProvider, from: Vector2i, to: Vector2i) -> EdgeCheck
static func height_multiplier(signed_steps: int) -> float
static func fall_amount(hp_max: float, armor: float, drop_steps: int, voluntary: bool) -> float
```

inspect_edge получает уже in-bounds ортогональные клетки, проверяет spatial
provider capability, walkability destination, delta<=2, конечную terrain cost>=1,
конечную итоговую цену. reasons: move/height_units_unsupported, move/blocked,
move/height_step, move/invalid_cost, move/cost_overflow. Ошибка возвращает cost0/drop0.
drop_steps=int64, максимум8589934591; никакой разности Vector2i высот или int32 cast.
fall_amount возвращает0 без урона, NAN при неверных обязательных stats/арифметике;
HP_MAX>=0, ARMOR конечна. На no-fall/lethal пути не требовать ненужные stats.

GridDataProvider получает четвёртый optional Callable `p_get_height_steps` и методы
`has_spatial_heights()->bool`, `cell_height_steps(cell)->int`. Старые три args и
cell_height сохраняются. Нет скрытой конверсии отсутствующего callback: новый
профиль явно требует capability; только свой BattleBoard выдаёт его для commands.
Callback возвращает TYPE_INT в диапазоне tile steps; неверная форма — ошибка
проверки, не int(float) с усечением. Удобный внутренний валидатор может вернуть
sentinel вне разрешённого диапазона; inspect_edge обязан его отклонить.

MoveRules._init получает третий `profile: StringName = &"legacy_move_v1"`;
разрешены legacy_move_v1/spatial_move_v1. Для spatial max_height_step должен быть1,
copy/validate сохраняют профиль. Добавить get_profile(). ActionContext уже копирует
MoveRules; расширять его публичный конструктор не требуется.

MovePathCheck.inspect получает последний optional profile с legacy default.
Spatial использует board.make_spatial_data_provider(actor) и inspect_edge на
каждом ребре; legacy — прежний алгоритм. Bounds/соседство/длина2..33/старт/budget,
точность debit и ownership costs DTO прежние. Полный path и budget до мутации.

GridPathfinder.configure получает четвёртый optional profile с тем же default.
Spatial branch использует ТУ ЖЕ inspect_edge и её cost для find_path/reachable;
legacy ветка остаётся прежней. Bounds проверяются caller до inspect_edge.
Spatial frontier tie-break (cost,cell.y,cell.x), соседи в прежнем порядке
[(1,0),(-1,0),(0,1),(0,-1)], equal-cost predecessor не заменяется. Spatial invalid
profile/capability -> пустые результаты. Путь включает start, start cost0.

### 4.2 Move и обязательное падение

MoveCommand передаёт profile в root/path и per-edge validation. Для spatial root
проверить fall arithmetic на КАЖДОМ потенциальном nonlethal drop ребре на copies
stats до первого move; не выполнять предварительный HP damage/лечения. Это
проверка возможности числового исполнения, не доверенный прогноз будущего HP.
Version reserve root = число рёбер +1, если возможна смерть от fall/HAZARD,
иначе число рёбер; per-edge =1 плюс возможный death cleanup. Не переполнять суммы.

Перед actual edge заново проверить геометрию/budget/refs и вычислить fall request.
Spatial ветка требует exact BattleBoard/UnitState (как snapshot gate). Сначала
spend_move_points(cost), сразу затем board.move_unit — единственный position owner.
Так position callback уже видит оплаченное ребро. Если exact move_unit вернул false,
он ещё не мутировал доску и не вызывал callback: восстановить исходный move budget
и fault без moved/HP. Между оплатой и вызовом board не исполнять другого кода.
На успехе выдать прежний moved event с сохранёнными before/after debit значениями.
Затем mandatory `MoveFallCommand` (если fall amount>0)
либо прежний DeathCommand для HAZARD; затем реакции, затем Move continuation.
Не выполнять падение вторым публичным root. Main/bonus не расходуются.
Если actor погиб от fall, continuation возвращает прежнее move/actor_dead и
INTERRUPTED; последующие рёбра не исполняются/не оплачиваются. Лечение живого
после fall возможно и не отменяет факт оплаты/падения.

MoveFallCommand — новый internal-only Command (не подкласс DamageCommand),
`_init(binding: Binding = null)`, get_kind=&"move_fall". Вложенный Binding фиксирует context/state/board/unit,
stats/vitals/owner refs, id/cell после входа, HP/alive, move balance после оплаты,
board_version, исходный from/to/drop_steps, copied DamageRequest и source seal.
Binding.copy сохраняет refs и независимо копирует values/request/seals.
При фазовом mismatch — FAULTED move/fall_binding, без дополнительного HP.
Source = DamageSource(&"fall",0,to_cell,0,0), physical/bypass amount уже после брони.
execute вызывает ActionHpExecutor.damage и возвращает его events (до2)/state_changed.
ActionQueue отклоняет любой публичный MoveFallCommand как move/internal_fall.

Callback мутация после authoritative move не должна стирать завершённый prefix.
В spatial ветке сохранить expected refs/HP/budget/board version ДО move. После
успеха проверить, что callback не подменил unit/state/refs, expected destination,
HP/balance/budget или topology. При нарушении — fault с moved и фактом завершённого
ребра; уже сделанную оплату сохранить, не исполнять fall по новым refs.
Не переписывать callback-мутации бюджета значением after: event отражает ранее
завершённый debit, а факт неподдержанной внешней мутации остаётся наблюдаемым.
Не объявлять общий rollback/revival поддержанным. Внешняя callback мутация не
должна маскироваться под новую легальную фазу за счёт снятия нового baseline.

### 4.3 Attack, баланс и Push

AttackRules принимает новый профиль spatial_melee_balance_v1 и копирует его как
два старых. Определение AttackDefinition остаётся id/profile, stats задают числа.
AttackReachCheck.inspect сохраняет legacy. Добавить inspect_spatial с той же
сигнатурой; проверки: runtime -> range domain -> bounds -> одна ось/не совпадают
-> required_range -> внутренние клетки от actor -> terrain shape. Reasons:
attack/invalid_runtime, attack/invalid_range, attack/out_of_bounds,
attack/not_aligned, attack/out_of_reach, attack/line_blocked,
attack/terrain_shape_unsupported. Наличие хотя бы одной WALL/недружественного
occupant даёт line_blocked до terrain_shape_unsupported. Полный список bounded
размерами board (<=1024 по оси), не внешним значением R.

AttackCommand сохраняет P06 порядок ids/runtime/revision/positions/placement/
allowlist/resources/stats/reach/main/arithmetic. Spatial вычисляет m/hit/impact
по §2 на проверенных copies stats, без прогрева live cache. Стоимость1 main.
Не вычислять effects будущего Push, если hit заведомо убивает цель.

BalancePushRules.prepare_attack получает последний optional
`spatial: bool = false`; true передаётся только новым профилем. Сам helper
вычисляет effective impact из копии исходного I и board heights, чтобы root и
children не имели двух формул. Сохраняются аргументы raw_attack=B и hit_amount
(уже масштабированный hit); bound values включают spatial flag, actor/target
height_steps, multiplier и effective impact. Seal/copy защищают ВСЕ новые поля.
В фазовых guards spatial-ветки сверять height_steps и topology version; mutation
высоты без перемещения не должна менять уже оплаченную атаку незаметно.
Binding содержит board_origin_version и expected_board_version; оба исходно равны
текущей version. Ожидаемая version меняется только на известное число завершённых
board touches, никогда не переустанавливается чтением live version после callback.

В PushResolver добавить resolve_push_steps(board,unit,cell,direction,max_rise_steps=1)
с прежним порядком ветвей и typed PushResult. Существующий resolve_push остаётся
целочисленным legacy. В PushResult добавить fall_steps:int=0; старый fall_height
по-прежнему полные уровни. Spatial MOVED заполняет оба, например drop3 -> steps3,
fall_height1. Legacy результат заполняет fall_steps=2*fall_height без смены масштаба.
Для branches COLLISION/BLOCKED/OUT_OF_BOUNDS падение не выдумывать; будущий вход
после смерти blocker считается отдельно по from/to в admission.

BalancePushRules.prepare_push использует resolve_push_steps только при bound
spatial=true; осевой unit direction вычисляется через compute_push_direction.
Legacy P07 ограничение d1 сохраняется; spatial допускает любую разрешённую прямую
дистанцию. В forced entry после collision и его admission использовать один
SpatialRules.fall_amount, одинаковые steps и n, без временной очистки occupancy.
Board touches/HP prediction/guard/sealed first+second requests и порядок предметных
реакций P07 сохраняются. Hit bonus не попадает в collision B; fall не зависит от m.

CollisionDamageCommand разрешено расширить только spatial stage guards: между
двумя HP и после второго проверить expected version плюс завершённые cleanup
(каждый alive->dead даёт один), pinned refs/клетки/высоты. На callback-fault вернуть
уже выполненные HP/events, не исполнять остаток. Для after_collision child обновить
expected_board_version на проверенное число cleanup и seal; если оба погибли,
child нет. Legacy collision не менять. Нормальная смерть blocker не должна
выглядеть как посторонняя topology mutation.

PushCommand сохраняет оба death/moved атомарных исхода P07 и guards префикса;
новые fields/height guards обновляются после РЕАЛЬНОГО перемещения целиком, затем
seal. Нельзя сохранять прежнюю target_height_steps после successful entry.
Ожидаемая version после move = предыдущая+1, проверенная до создания child;
target steps = заранее вычисленная destination height, не новый callback baseline.
AttackHitCommand/BalanceCommand/PushDamageCommand должны
работать с обновлённой Binding без смены внешних API; если нужен их delta —
CONTRACT_GAP ведущему, не обход guards.

### 4.4 Queue/event contracts

Форма существующих value events и сериализуемые enums прежние.
Расширить attacked validator: для spatial attack event допустима одна ось с d>=1;
для двух legacy definition profiles остаётся d1. Проверять профиль по definition
из context и id, не ослаблять все attacked events до произвольной геометрии.
Текущему _valid_draft helper передать context явным параметром
через единственный call site; неизвестный definition -> malformed/fault.
Геометрия досягаемости и эффекты уже проверены командой; валидатор не повторяет
полное исполнение после изменения HP/позиции.

Предел2 events остаётся для всех новых/прежних commands кроме exact
CollisionDamageCommand с cap4. MoveFall имеет damaged+died, движение — отдельный
step. Command/event/depth limits сохраняют выполненный оплаченный prefix без
лечения, которое не успело исполниться. BUSY, ids, revision, parent_event_seq,
reaction order и fail-closed semantics P04/P07 не ослаблять.

## 5. Allowed paths и ответственность

Только следующие 22 path разрешены будущему кодеру (точно, без directory globs):

```yaml
allowed_paths:
  - scripts/core/board/battle_board.gd
  - scripts/core/actions/simulation_snapshot.gd
  - scripts/core/actions/item_simulation_snapshot.gd
  - scripts/core/pathfinding/grid_data_provider.gd
  - scripts/core/pathfinding/grid_pathfinder.gd
  - scripts/core/actions/move_rules.gd
  - scripts/core/actions/move_path_check.gd
  - scripts/core/actions/move_command.gd
  - scripts/core/actions/attack_rules.gd
  - scripts/core/actions/attack_command.gd
  - scripts/core/actions/attack_reach_check.gd
  - scripts/core/actions/balance_push_rules.gd
  - scripts/core/actions/push_command.gd
  - scripts/core/actions/collision_damage_command.gd
  - scripts/core/combat/push_resolver.gd
  - scripts/core/combat/push_result.gd
  - scripts/core/actions/action_queue.gd
  - scripts/core/actions/spatial_rules.gd
  - scripts/core/actions/spatial_rules.gd.uid
  - scripts/core/actions/move_fall_command.gd
  - scripts/core/actions/move_fall_command.gd.uid
  - tests/run_tests.gd
```

read_paths: перечисленные исходники плюс UnitState/Vitals/Faction/ActionResources,
ActionContext/Command/CommandStepResult/ActionHpExecutor/DamageSource/DamageRequest,
AttackHitCommand/BalanceCommand/PushDamageCommand/CollisionDamageCommand и
ItemSimulationState. Их effective hashes — P08_DEPENDENCIES; это read-only dependencies.
Пакет задаёт все новые API; за старым API адресно читать код, не всю библиотеку docs.

Ведущий владеет спецификацией, QA, snapshot/queue/guards архитектурой и интеграцией.
Один game_coder/Luna/medium пишет runtime в общем checkout; не коммитит, не
делегирует и не откатывает чужое. Самодостаточные подзадачи: (1) board/provider/
snapshot substrate, (2) geometry/pathfinder, (3) commands+regression; это стадии
одного пакета, не отдельные автоматически создаваемые задачи. Зависимые стадии
последовательны. Ведущий продолжает независимые oracle/QA/provenance проверки.
После двух неудач одной причины сверить полноту ТЗ; разрешён fallback Terra/high
с инструкциями game_coder по AGENTS, без подмены read-only reviewer.

Нельзя переписывать frozen P01–P07 или этот пакет после фиксации APPROVE. Изменение
зависимости/API вне allowed_paths — CONTRACT_GAP и новая редакция до исполнения.
Все старые 1996 assertions сохранить по смыслу и числу. Единственный планируемый
поправляемый старый fixture: unknown board schema2 в P02 A10 (run_tests.gd около
2480) заменить на3, потому что2 становится поддерживаемой. Добавить отдельный тест
known v2 without bits -> INVALID; не удалять проверку UNKNOWN/UNSUPPORTED.

Документационные addenda реализации пишет ведущий отдельно в ARCHITECTURE,
DECISIONS, TESTING, COMMAND_ACTION_QUEUE_CONTRACT и HANDOFF; старые bytes/hunks
сохранять, не включать весь dirty файл в commit автоматически. Эти документы
не входят в write ownership кодера и frozen input исключаются из runtime delta.

## 6. Приёмка (нужны поведение, границы и чистота отказа)

| ID | Обязательные сценарии |
|---|---|
| S01 | Старые whole heights не сменили масштаб. Steps -1=(-1,1),0,1,2,3; int32 endpoints/max odd; invalid steps/bounds/version дают false без мутации. Reset битов set_height/resize; одна version на setter |
| S02 | Board v1 bytes/codec oracle прежние; v2 half round-trip board и item snapshots, независимые A/B/live/DTO arrays. Unit.height отдельно, включая int64 extremes и corpse/live в одной клетке. Allocator/equip/refill не вызываются |
| S03 | Malformed bit TYPE_FLOAT/bool/-1/2/длина/лишнее поле/нет bits/все0/schema, oversized/cycle raw graph; INVALID vs UNSUPPORTED. Unknown board3 и Unit3/ledger2 прежние; legacy save half отказ без ids/allocation |
| S04 | Профили opt-in/copy immutable, legacy Move/Attack на half board pure reject. Whole legacy весь regression. Оба прямых пути make_data_provider и make_terrain_only_provider -> legacy GridPathfinder дают пустые find_path/reachable на любой bit1 доске; все их клетки unwalkable. Spatial capability строго обязательна |
| S05 | Четыре направления: подъём0.5 cost1,1 cost2,1.5 blocked; спуск1/1.5/2/2.5 разрешён. HAZARD base3+подъём. Path/reachable/Move одинаковый cost/границы; exact budget, invalid float и переполнение без debit |
| S06 | Два +0.5 против одного +1; deterministic equal paths tie-break. Путь2..33, цикл/повтор посещения без refund. Root inspect не меняет cache/DTO/board; изменить высоту между continuation -> прерывание на актуальной геометрии |
| S07 | HP100 armor3: Move drop1 ->HP100;1.5 ->78;2/2.5 ->53. Push соответственно78,78,53;0.5 damage нет. MaxHP0 fall min1. Два спуска0.5 не суммируются; Move1+0.5 безопасны каждый |
| S08 | Voluntary moved -> fall damaged/died -> heal reactions -> continuation. Fall death occupancy cleared и INTERRUPTED на следующей continuation; corpse in bounds, остаток не оплачен. HAZARD moved/death без двойного числового fall |
| S09 | R1 первый сосед, R2 первый/второй; все четыре оси, d2+delta1 требует3, d1+delta0.5 требует1,delta1.5 требует2. Равные endpoints/диагональ/L/invalid R0,1.5,NaN,Inf,4097; range4096 bounded scan |
| S10 | Промежуточный friend пропускает без урона/Push ему; enemy/neutral-to-player блокируют; corpse пропускает; target всё равно требует pair admission. WALL block; VOID/nonmonotone unsupported; monotone plateau/Hazard supported. Чистый отказ без main/cache/ids |
| S11 | B10 armor3 I10: сверху0.5 hit8 impact11; сверху1 hit9 impact12; снизу1 hit5 impact8; снизу2 hit3 impact6; снизу>=5 hit1 impact1. На flat I0.5->1 только spatial; I0->0. Равный B<=0/negative armor, finite overflow branches, min/max immunity, HP-dead hit без impact |
| S12 | Дальний удар d2..3 толкает ровно1 по осевому знаку; +0.5 Push проходит, +1 blocked before occupant. Ranged attacked проходит queue validator только spatial; legacy malformed long attacked остаётся fault |
| S13 | Высотный hit не меняет B collision: B10/armor3 даёт7 независимо от m. Разная броня blocker учитывается отдельно; оба HP до healing; blocker death ->half entry/fall/lethal ->collision reactions ->hit reactions. Admission/execution те же n/version reserve |
| S14 | Tampered spatial flag/steps/m/impact/direction/request/source/copy seals отклоняются. Height-only изменение после оплаты, actor/target/blocker replacement, callback HP/refs/budget/version mutation -> fault с точным уже завершённым prefix, без эффекта по новой цели |
| S15 | MoveFall public root reject; copied binding/source/request tamper reject; death/lethal без fake movement. Board version/MAX ids/event capacity2/Collision4, command/event/depth границы до fall/между effects/reactions сохраняют prefix и оплату |
| S16 | Две свежие восстановленные item snapshots + одинаковые injected RNG/context/rules: Move->Attack->Push дают равные canonical state, ordered events/steps/counters/RNG. После N sandbox прогонов исходные state/items/cache/UnitId/RNG/live queue неизменны |
| S17 | Полные P01–P07 assertions, Godot import/startup/runner, UID для2 новых classes, diff/preservation/allowed paths. UI не проверялся и не объявляется готовым |

Минимум1 относится к запросу; при remaining HP<1 фактический damaged.amount меньше.
Float результаты сравнивать согласно принятым арифметическим примерам/допуску
из runner, exact equality обязательно для сериализованных одинаковых replay.
В S07 HP100 — начало конкретного падения, без предшествующего attack damage.

## 7. Команды проверки будущей реализации

Сначала fresh hashes/status, сохранить baseline diff и все старые test_reports.
Не запускать старые p07-check.ps1: их фиксированные имена перезапишут артефакты.
Из корня проекта, новый уникальный каталог на КАЖДЫЙ прогон:

```powershell
$ErrorActionPreference = 'Stop'
$p08PriorAppData = $env:APPDATA
$p08PriorGodot = $env:GODOT_BIN
$p08Run = Join-Path 'test_reports' ('p08-run-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $p08Run | Out-Null
try {
    if (-not $env:GODOT_BIN) {
        $env:GODOT_BIN = 'D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
    }
    if (-not (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) { throw 'GODOT_BIN missing' }
    $p08Profile = Join-Path $p08Run 'godot-profile'
    New-Item -ItemType Directory -Path $p08Profile | Out-Null
    $env:APPDATA = (Resolve-Path $p08Profile).Path
    & $env:GODOT_BIN --path . --headless --import --log-file (Join-Path $p08Run 'import.log')
    if ($LASTEXITCODE -ne 0) { throw 'P08 import failed' }
    & $env:GODOT_BIN --path . --headless --quit-after 3 --log-file (Join-Path $p08Run 'startup.log')
    if ($LASTEXITCODE -ne 0) { throw 'P08 startup failed' }
    & $env:GODOT_BIN --path . --headless --script tests/run_tests.gd --log-file (Join-Path $p08Run 'tests.log')
    if ($LASTEXITCODE -ne 0) { throw 'P08 tests failed' }
} finally {
    $env:APPDATA = $p08PriorAppData
    $env:GODOT_BIN = $p08PriorGodot
}
git diff --check
if ($LASTEXITCODE -ne 0) { throw 'P08 whitespace failed' }
```

Путь fallback — только текущая машина из TESTING, не production hardcode.
Env меняется только процессно и восстанавливается. Проверить scan DONE и class/UID,
нет SCRIPT/parse/runtime errors, весь runner минимум1996 старых плюс S01–S17,
0 failed, exit0. Сравнить exit diagnostics с P07 (45 ObjectDB/18 resources),
дополнительные удержания выяснить; одинаковый exit0 сам по себе не acceptance.

После остановки записи ведущий фиксирует SHA-256 runtime/test diff, acceptance map
и новые логи. Независимый game_reviewer/Terra/high получает fork_turns=none,
точные files/manifest hashes/base и этот пакет; только чтение, без делегирования.
Нужен APPROVE; REQUEST_CHANGES устраняются до нового fixed review. Reviewer не
выдаёт чтение логов за собственный прогон. Ведущий проверяет критические contracts,
очередь, snapshots, детерминизм и изолированное исполнение лично.

Для ТЕКУЩЕЙ подготовки документов Godot запускать не требуется: hashes/provenance,
numerical oracle, согласованность allowed_paths/ссылок/acceptance и diff check,
затем независимый review фиксированного TASK+DEPENDENCIES. После APPROVE ведущий
создаёт P08_REVIEW, обновляет HANDOFF и коммитит только свои отделимые новые docs.
Прежний untracked HANDOFF целиком в staging не включать; сохранить его прежний текст.
Не делать push, не создавать sidebar задачи или расписания.
