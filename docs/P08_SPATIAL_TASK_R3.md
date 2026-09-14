# P08 — полууровни, движение и прямая досягаемость

Редакция 3, 2026-09-14. Статус: спецификация для независимого ревью.
Этот этап готовит документы; runtime НЕ разрешено менять текущим поручением.
Следующий исполнитель получает отдельное поручение на реализацию frozen-пакета.

Результат этого этапа — новый самостоятельный frozen пакет, закрывающий
подтверждённый CONTRACT_GAP S14 редакции2. P01–P08 r2 остаются историей без правок.
Незавершённый paused-substrate не является готовой реализацией или входным patch.
Точные дополнительные контракты checkpoint/receipt/cleanup находятся в §4.5.

## 1. Вход и один наблюдаемый результат

```yaml
task_id: P08-SPATIAL
base_commit: 1e3099e35c342f13298093523dc25f164e66f424
branch: main
goal: >-
  Headless harness исполняет Move и прямую Attack на полууровнях через общую
  геометрию; стоимость, HP, баланс, Push и восстановленные копии согласованы.
dependencies: docs/P08_DEPENDENCIES_R3.json
```

HEAD сам по себе недостаточен. Нужны принятые dirty P01/P02/P06 и untracked
snapshot-скрипты/документы. Сначала сверить files/local_artifacts нового manifest,
HEAD/status и frozen hashes из P08_REVIEW_R3. Допустим документационный потомок base,
сохраняющий все effective hashes. Несовпадение — CONTRACT_GAP до записи.

Приоритет для DECISIONS/TESTING/исходного HANDOFF: final-audit.json остановленной
P08 r2 реализации из test_reports/p08-implementation-362ad64ba4fb41ebb427b16c4355cfb6/.
Он выше historical P08_DEPENDENCIES. HANDOFF mutable: исходные bytes закреплены
в новом preparation handoff-before.md и должны сохраняться точным suffix.
Для остальных зависимостей: фактическая принятая P07 implementation revision1 и final doc addenda
выше исторических входных P07_DEPENDENCIES. Последний принятый прогон ведущего:
1996 passed / 0 failed, import/startup PASS, implementation review APPROVE.
Это базовый регресс, также повторённый в изолированном r2 gap audit;
1996/0 НЕ приёмка P08 и не выполненная S01–S17.

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
либо DeathCommand с internal spatial binding для HAZARD (§4.5); затем реакции, затем Move continuation.
Не выполнять падение вторым публичным root. Main/bonus не расходуются.
Если actor погиб от fall, continuation возвращает прежнее move/actor_dead и
INTERRUPTED; последующие рёбра не исполняются/не оплачиваются. Лечение живого
после fall возможно и не отменяет факт оплаты/падения.

MoveFallCommand — новый internal-only Command (не подкласс DamageCommand),
`_init(binding: Binding = null)`, get_kind=&"move_fall". Вложенный Binding фиксирует context/state/board/unit,
stats/vitals/owner refs, id/cell после входа, HP/alive, move balance после оплаты,
board_origin_version/expected_board_version, исходный from/to/drop_steps и mode.
Для mode=fall обязательны copied DamageRequest/request seal и source/source seal;
для mode=cell_death request и request seal строго null, source/source seal non-null.
Точные формы и проверки определены §4.5.2; MoveFall исполняет только mode=fall.
Binding.copy сохраняет refs и независимо копирует values/request/seals.
При фазовом mismatch — FAULTED move/fall_binding, без дополнительного HP.
Source = DamageSource(&"fall",0,to_cell,0,0), physical/bypass amount уже после брони.
execute вызывает ActionHpExecutor.damage_spatial с checkpoint (§4.5),
сохраняет его events (до2)/state_changed и выполняет terminal postguard.
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
AttackHitCommand/BalanceCommand/PushDamageCommand разрешены для spatial delta:
каждый обязан проверять post-action даже в terminal исходе. Точные checkpoints,
HP receipt и дополнительные необходимые seams заданы §4.5; отсутствие child не
является основанием пропустить guard. Legacy constructors этих трёх команд прежние.

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

### 4.5 Обязательный узкий S14: pinned checkpoints и terminal prefix (r3)

Этот раздел заменяет неопределённость r2, а не отменяет S01–S17. Guards обязательны
ТОЛЬКО в spatial-командах и их mandatory последствиях. Legacy public Damage/Heal/
Death и два старых Attack profiles сохраняют существующее исполнение. Item reactions
исполняются отдельными командами очереди, после завершения mandatory cascade.
Нельзя лечить/повторно симулировать во время validation. Общий S-5 (произвольная
реентрантность, вложенные low-level мутации/revival, транзакции всех подписчиков,
обнаружение change-and-restore любого поля, скрытые записи в private массивы/счётчик
version, произвольные subclass/runtime callbacks) остаётся вне задачи. Вызванная
callback мутация, оставившая mismatch на checkpoint, обязана дать FAULTED даже
на terminal ветке. Исключение S-5 не позволяет пропустить эту проверку.

#### 4.5.1 Владение и ожидаемое состояние

До оплаты/мутации exact spatial binding фиксирует refs context, state, board,
UnitState каждого участника (actor/target, blocker при наличии), StatsBag, Vitals,
Vitals._stats, ItemOwnerState с owner unit/ledger attachment, ActionResources
каждого участника (допустимый null сохраняется null у неактивного участника).
Проверяются state.get_owner(id), owner.get_owner(), owner.is_closed()==false;
для inventory/equipment отдельно пинятся facade identity (включая null), оба
registered/retired флага owner и attachment по следующей точной lifecycle-матрице:

| Lifecycle | registered / retired | Допустимое attachment |
|---|---|---|
| 0 unregistered | false / false | facade отсутствует в state array, getter возвращает null; null является exact pinned state |
| 1 registered | true / false | ровно один exact открытый facade в соответствующем state array, getter возвращает его; facade._state==pinned owner и facade._closed==false |
| 2 retired | false / true | facade отсутствует в state array, getter возвращает null; это законный сохранённый lifecycle |
| invalid | true / true | отказ на admission; внутри callback mismatch |

Закрытый owner, закрытый/лишний/дублированный facade и изменение любого из этих
attachments/флагов внутри callback -> mismatch. Проверяется исходное membership
в state.get_inventories()/get_equipment_facades(), не только getter, который может
скрыть закрытый facade. Сначала безопасное сравнение raw refs/полей, затем getters;
нельзя вызывать метод подменённого facade/owner. Отсутствие facade при lifecycle0/2
не является fault и не требует создания facade. Это точный ledger attachment,
не fingerprint всех items. Actor resources обязательны и valid.
Пинятся исходные id, registry membership, cell, UnitState.height, board height_steps,
HP/alive, balance, move_points_left и main/bonus/owner_id существующих resources.
Geometry: размеры, version и значения использованных endpoint/line/entry клеток;
occupancy участников фиксируется по raw registry/occupancy, не только occupant_at,
который скрывает трупы. Relevant stat values для формул читаются из copies; их
согласованность проверяется на checkpoints без прогрева live cache. Это bounded
сравнение использованных данных, не полный fingerprint всего runtime/предметов.

Все spatial Binding хранят ровно `board_origin_version` и `expected_board_version`
раздельно; дополнительных имён-алиасов нет. References тоже
защищены seal: независимый приватный набор исходных identities; values==_seal
недостаточно. copy сохраняет identities, глубоко копирует values/request/source/
seals; copy никогда не перепечатывает недоверенные live refs. Checkpoint сначала
сравнивает identities, затем значения через PINNED refs; null/replacement -> fault,
не обращение к методам нового объекта. Не ограничиваться actor.main: target/blocker
move/main/bonus и balance тоже не должны незаметно измениться внутри callback.

Для root Attack до оплаты сохраняется main_before; известный debit меняет только
actor.main на main_before-1. Для Move ребра только actor.move уменьшается на cost.
Root fields и anticipated phases вычисляются до callback. После успешной проверки
следующая фаза получается применением РОВНО известных delta к прежним expected
values, затем seal. Никогда не присваивать expected_hp/refs/budget/version из live
после callback. Успешный guard разрешает переход фазы, но не новый baseline.

У Move между ЗАВЕРШЁННЫМИ рёбрами законные queue reactions могут изменить HP/stats,
а новая continuation заново проверяет путь по актуальному состоянию согласно S06.
Это отдельная admission следующего ребра; она не заменяет post-move/fall guard
предыдущего ребра. Attack mandatory hit/balance/push/collision/fall идёт до reactions
и переносит один проверенный binding. Не допускать реакции между двумя HP collision.

#### 4.5.2 Почему три command delta недостаточны; точный HP seam

Текущий ActionHpExecutor._finalize повторно читает unit.vitals/context.board после
hp_changed и может очистить replacement occupancy. Текущий Vitals.apply_damage
эмитит hp_changed ДО alive->dead, add_impact эмитит balance_changed ДО balance_broken.
Только post-return guard не восстанавливает достоверный уже выполненный prefix,
если callback переписал исходный HP/balance или подавил смерть. Поэтому разрешены
дополнительные узкие delta ActionHpExecutor, Vitals и DeathCommand; BattleBoard уже
в allowed и получает защиту адресата death callback. Общие legacy mutators прежние.

Новые ВНУТРЕННИЕ Vitals API (не Resource, не serialized, не root Command):

```gdscript
class SpatialMutation extends RefCounted:
    var reason: StringName = &""
    var hp_before: float = 0.0
    var hp_after: float = 0.0
    var alive_before: bool = false
    var alive_after: bool = false
    var balance_before: float = 0.0
    var balance_after: float = 0.0
    var balance_max: float = 0.0
    var impact: float = 0.0
    var broke: bool = false
    var hp_written: bool = false
    var balance_written: bool = false
    var death_written: bool = false
    var broken_emitted: bool = false
func apply_spatial_damage(amount: float, checkpoint: Callable) -> SpatialMutation
func add_spatial_impact(amount: float, checkpoint: Callable) -> SpatialMutation
```

Checkpoint — внутренний read-only Callable(stage: StringName)->StringName;
пусто = PASS, непусто = fault. Его замыкание содержит sealed expected phases,
а не callback-generated baseline; он не испускает signals, не исполняет commands
и не мутирует runtime. Нет зависимости Vitals от ActionContext/автозагрузок.
Невалидный callable/amount/precondition -> reason, ноль записей/сигналов.
SpatialMutation заполняется только самим mutator, не передаётся подписчикам;
возвращённые числа обозначают собственные уже выполненные записи, не состояние,
которое произвольный подписчик оставил после них. Никакого rollback этих записей.

Receipt инициализируется проверенными before values, after=before, все flags=false.
apply_spatial_damage при живом HP>=0, конечном amount>=0:
1. `before`/alive берутся на проверенном входе. amount0 сохраняет HP/alive (включая
   alive-at-zero), вызывает terminal checkpoint `hp_done`, не создаёт событие.
2. При amount>0 записать `after=maxf(0,before-amount)` в pinned Vitals._hp и receipt.
   Пока alive остаётся прежним. hp_changed испускается с прежним is_equal_approx
   условием; затем ВСЕГДА checkpoint `hp_written`, даже если signal не испускался.
   Ожидается HP=after, alive=alive_before, прежние balance/refs/budgets/version.
   Mismatch: немедленно вернуть receipt.reason, НЕ выполнять свою death запись.
3. Если after<=0 и checkpoint прошёл, записать _is_alive=false; зафиксировать
   death_written/alive_after=false ДО died.emit. После возврата от всех died/
   board_changed callbacks checkpoint `death_written`: expected version+1 за
   собственный cleanup, остальное по §4.5.3. Mismatch -> fault, смерть уже в prefix.
4. Последний `hp_done` checkpoint выполняется и при nonlethal/terminal исходе.
   Это проверка expected после известных действий, не повторный damage/симуляция.

При callback heal/set_hp/revive/nested damage внутри hp_changed выполняются только
их собственные эффекты; наш guard фиксирует mismatch и не продолжает штатную
death фазу. Не отменять callback и не объявлять revival поддержанным. Если HP уже
записан0, alive ещё true и guard faulted, это честный промежуточный prefix: не
«доделывать» смерть ради инварианта и не возвращать HP. Контекст закрывается fault.

add_spatial_impact на checked входе фиксирует maximum из отдельной копии _stats
(StatsBag.from_snapshot_dict), совпадающий с sealed balance_max; live cache не греет;
amount0/immunity/dead -> no-op с terminal `balance_done` guard. Иначе вычисляет
finite sum, broke=sum>=maximum, after=0 if broke else sum, пишет balance и receipt.
Испускает balance_changed по старому approximate условию, затем ВСЕГДА
`balance_written` guard (HP/alive/budgets/version прежние, balance=after).
При mismatch прекращает остаток, не испускает balance_broken. При broke и PASS
фиксирует broken_emitted=true перед balance_broken.emit, затем `balance_done` guard.
При no-break тоже обязательный `balance_done`. Не вычислять after из изменённого
callback balance. При sum==before или reset0->0 не выдумывать balance_changed event.

ActionHpExecutor получает отдельные методы:
`damage_spatial(request: DamageRequest, context: ActionContext, checkpoint: Callable)
-> CommandStepResult` и
`death_spatial(target_id: int, source: DamageSource, context: ActionContext,
checkpoint: Callable) -> CommandStepResult`.
Они доступны только internal spatial calls: после полного caller precheck пинят
Unit/Vitals/board, copied source/id и values ДО первого сигнала, вызывают новый
Vitals mutator и строят draft из receipt. Запрос damage уже physical/bypass, без
повторного lookup после callback. death использует maxf(before,1), как legacy;
безусловный lethal остаётся отдельным видом события. Никаких вызовов старого
_finalize/clear_occupancy после сигнала. Последний caller postguard обязателен
независимо от наличия детей; его fault reason не должен стереть events helper.

DeathCommand получает последний optional `spatial_binding: MoveFallCommand.Binding
= null`, копирует seal/refs и помнит наличие binding. Default public Death прежний.
Spatial Move HAZARD создаёт этот internal child после проверенного moved с binding
и source.kind=cell; child проверяет вход, использует death_spatial и terminal guard.
Queue запрещает публичный Death с spatial binding: `move/internal_death`; там
проверка capability формы, а не event validation/simulation. Binding MoveFall
получает sealed mode `fall`/`cell_death` с точной взаимоисключающей формой:
- `fall`: non-null copied DamageRequest И request seal, physical/bypass,
  amount>0 finite, request.target_unit_id=pinned unit id, source.kind=fall,
  source_instance_id=0, origin_cell=to_cell, instigator/credit=0. Отдельный copied
  source/source seal идентичен request.source; полный source/request сравнивается.
- `cell_death`: request==null И request seal==null, это тоже запечатанные значения;
  non-null copied source/source seal: kind=cell, source_instance_id=0,
  origin_cell=to_cell, instigator/credit=0; target id=pinned unit id, destination
  заранее проверена lethal. Нет неиспользуемого DamageRequest или числового fall.

Mode/target id/source/seals пинятся до queue copy. Binding.copy сохраняет mode и
null/non-null форму в точности, без заполнения missing request; validation требует
эту форму при копировании/перед мутацией. Переданный DeathCommand.source обязан
совпадать с binding source seal. MoveFall принимает только mode=fall; bound Death
только mode=cell_death. Подмена mode/source/request/null seal отклоняется.
Push bounds/VOID/HAZARD вызывает death_spatial внутри самого PushCommand с его
проверенным binding. Нельзя превращать FAULTED death_result в APPLIED.

#### 4.5.3 Board touches и запрет воздействия на replacement

Разрешённые delta version: debit0, hit0 или cleanup1, balance0, успешный move1,
wall damage0/cleanup1, pair collision0/1/2 по уже завершённым смертям, fall0/cleanup1.
Move в lethal клетку = move1 затем cleanup1; bounds death = cleanup1 без move.
Admission reserves максимум известных будущих touches, execution credits только
реально выполненные собственные стадии. Проверять overflow ДО каждой мутации.
Нельзя брать `live_version-origin`, округлять его, разрешать `<=reserve` или считать
любую смерть/board_changed за ожидаемый touch. Extra set_height прежнего значения
тоже лишний touch. Чужая смерть участника до нашей death_written не засчитывается.

До HP участник обязан занимать свою pinned cell в raw occupancy. Собственная
death_written штатно даёт ОДНО удаление этой occupancy и _touch. Повторная очистка
уже пустой клетки не даёт touch и не нужна executor. Проверяется registry тот же
Unit, его cell/height прежние, raw occupancy больше не содержит id, expected
version ровно+1. После смерти blocker это проверяется ДО damage второго участника
или forced entry; после обеих смертей проверяется весь pair без child.

BattleBoard death subscription обязана закреплять исходные Unit/Vitals и identity
регистрации, а не только id. При сигнале старой Vitals сначала сверить current
registry Unit, unit.vitals, id и действующую subscription; mismatch -> no-op без
touch/cleanup чужого объекта. Использовать weak references/registration token,
чтобы не создавать новый ref cycle; disconnect/remove/resize/snapshot restore
сохраняют ровно собственные подписки. clear_occupancy перед записью обязан отвергать
Unit, не совпадающий с registry Unit по identity. Это защита адресата существующего
board operation, не обещание общего reentrancy S-5. После callback replacement
команда всё равно FAULTED; допустим только уже сделанный cleanup старой регистрации.
Если callback сам удалил/добавил Unit, его version increments сохраняются и НЕ
маскируются. Replacement HP/balance/budget/occupancy команда далее не меняет.

#### 4.5.4 Общие переходы и ordered events

| Исполнитель | Обязательные границы и expected delta |
|---|---|
| Attack root/Hit | main debit уже известен до hit. Hit pre, каждый HP checkpoint, post даже I0/immunity/dead; только затем Balance child из checked expected HP/alive |
| Balance | pre after-hit, balance_written, balance_done и post, включая no-break/reset0->0/immunity; Push child только после всех PASS; expected balance=предвычисленный after |
| Push moved | pre, move callbacks, post с destination/cached whole height/steps/version+1, даже flat no-fall terminal; затем sealed fall/death child |
| Push terminal HP | wall/height PushDamage, numeric fall, bounds и in-bounds lethal: HP checkpoints и post; оба inline lethal исхода сохраняют fault/result prefix |
| Collision | pre pair; HP checkpoints первого и guard ВСЕХ участников; HP checkpoints второго и guard ВСЕХ участников; only then after_collision binding. Fault первого исключает второй HP; fault второго сохраняет оба prefix |
| Move | оплаченный edge, post-move включая terminal/no-fall, затем MoveFall или bound Death: HP checkpoints и post до reactions/continuation |

Между первым и вторым collision HP target может законно быть мёртв и очищен;
guard использует expected dead фазу, не старый alive-required binding_reason.
То же после lethal hit/fall: нормальная смерть не является binding mismatch.
Actor/другой участник сохраняют baseline HP/alive/balance и все три бюджета.
После move target.cell и cache height меняются только на предвычисленную destination
(cache=целая часть); origin/event source не переписываются callback значениями.

FAULTED сохраняет main/move оплату, собственные и внешние уже выполненные записи;
не переписывает callback HP/budgets. Возвращает собственные completed drafts в
прежнем порядке с copied ids/source и receipt values; state_changed=true, если
сделана своя HP/alive/balance/position запись с изменением значения либо
broken_emitted (сохранённый P07 break/reset0->0 эффект). Даже если
callback вернул значение назад, факт нашей записи не пропадает. У no-op false,
если собственных изменений не было; чужие записи не повышают revision отдельно.
Queue bump/seq/fault latch прежние. FAULTED очищает mandatory/reactions/continuation,
включая уже приготовленные children; Queue сохраняет events ДО fault latch и
не dispatch-ит reactions этого faulted step. Ранее завершённые steps/ids/events
остаются; отложенные hit/collision reactions после fault не выполняются.

HP damage draft: hp_before/after и amount=before-after из своей записи; alive_after
из своей последней завершённой alive фазы. При остановке после hp_written lethal
damaged имеет hp_after0/alive_after=true, died отсутствует. При death_written
damaged и died имеют alive_after=false даже если callback потом revive: это prefix
наших записей, не snapshot последней внешней мутации. `died` только при собственной
death_written, amount0; никакой фиктивной смерти по одному прогнозу. Для explicit
lethal Death штатно только died; если fault после HP до death_written и before>0,
вернуть damaged как свидетельство уже выполненного HP, без died. При before0 и
отсутствии своей death записи событий нет. Это помещается в существующий cap2.
Balance draft из своей записи: balance_changed iff before!=after, broke отражает
вычисленный reset; balance_broken только если broken_emitted. При callback fault
между сигналами возможен balance_changed(broke=true) без balance_broken/Push.
Обычный успешный порядок/schema/events прежний. Pair cap4 не расширяется.

Точные spatial fault reasons: hit -> `attack/invalid_hit`; balance ->
`balance/invalid_binding`; Push/Collision/PushDamage/inline death ->
`push/invalid_binding`; Move post-edge -> `move/invalid_runtime`; MoveFall и bound
cell Death -> `move/fall_binding`. Preflight arithmetic/version/rejection reasons
из других разделов прежние. Vitals возвращает checkpoint reason; caller не
подменяет его APPLIED/SKIPPED. Новые enum values не требуются.

#### 4.5.5 Расширение S14/S15 без перенумерации S01–S17

Тесты ниже — обязательные подслучаи S14, лимиты/prefix также S15. Каждый прогон
реально включает spatial profile, callbacks одноразовые, не рекурсивно сам себя
вызывающие. Без callback тот же fixture проверяет APPLIED/нормальную смерть.

| Подслучай | Terminal/точка callback | Требуемый результат |
|---|---|---|
| S14a | Hit I0; Hit immunity; Hit lethal | hp_changed height-only, board_changed/died extra touch: FAULTED; attacked/debit и выполненный HP сохранены, Balance нет |
| S14b | Balance no-break, break, reset0->0 | balance_changed/balance_broken меняют HP/balance/refs/бюджет; fault даже без Push; собственный changed/broken prefix согласно checkpoint |
| S14c | Wall/height PushDamage; numeric Push fall; MoveFall | hp_changed и died мутации, nonlethal/lethal; terminal postguard, нет лечения/continuation после fault |
| S14d | Pair collision first/second HP, каждый nonlethal/lethal; оба dead | fault first -> blocker HP нет; fault second -> оба HP prefix; normal death cleanup0/1/2 не fault; entry только после PASS |
| S14e | Push flat terminal/moved/fall/VOID/HAZARD/bounds; Move terminal/HAZARD | position/board_changed/death callbacks; moved/fell prefix, prepaid resources, inline death FAULTED не теряется |
| S14f | В каждой доступной signal точке a–e отдельно refs | context.state/state.board, registry same-id Unit, stats, vitals, vitals._stats, owner/ledger attachment, resources; actor/target/blocker по роли. Новый объект остаётся со своими HP/balance/move/main/bonus/occupancy. Lifecycle inventory/equipment0/1/2 отдельно: null законен при0/2; callback замена/добавление/закрытие/удаление facade, owner и registered/retired flags даёт fault |
| S14g | В каждой доступной signal точке a–e отдельно values | HP/alive/balance/move/main/bonus каждого участника, cell/cache height/height_steps, topology и same-value setter; exact expected comparison, не новый baseline |
| S14h | Death callback замена до/после штатного board listener | old pinned Vitals -> replacement same-id в same/different cell, alive/dead replacement; чужая occupancy не очищена, старый subscription no-op; registry/weakref cleanup без новых удержаний |
| S14i | HP callback set_hp/heal; nested damage; revive в died | остановка на первом mismatch; реальные receipt записи и внешние изменения сохраняются; нет синтетической смерти, rollback, лечения очередью или действий по новым refs |
| S14j | Seals каждой phase/copy, включая new refs/mode/HP/balance/all budgets/board_origin_version/expected_board_version | pre-mutation fault чистый; отдельная подмена каждого version поля; normal copy независим values и идентичен по pinned refs |
| S15a | expected version у MAX_ID, reserve точный/на1 меньше, лишний touch до/между/после HP | overflow до мутации; неожиданная version после callback fault с точным prefix; cleanup credit только своей death phase |
| S15b | event/command/depth/id limit до hit/fall, между collision и entry, перед reactions | точные root/parent/command/event_seq/revision, prefix/caps2/4 прежние; faulted step не dispatch-ит items |
| S15c | Public MoveFall / bound spatial Death; forged mode/binding | pure reject move/internal_fall либо move/internal_death без ids/HP/debit. Internal cell_death request null->non-null и request seal null->non-null отдельно; fall request/seal non-null->null отдельно; несовпадение DeathCommand.source с seal, cross-mode copy -> чистый binding fault; законные copies проходят |

Сравнивать ordered drafts целиком и post-state pinned/replacement объектов; один
status FAULTED недостаточен. S16 replay дополнительно включает успешный cleanup
и faulted terminal callback с одинаковым injected callback fixture на двух copies.
S16 также восстанавливает lifecycle0/1/2 inventory/equipment (включая смешанные
0/2,1/0,2/1): законные отсутствующие facade не создаются и не fault-ят Move/Attack;
callbacks, меняющие соответствующий attachment, дают одинаковый fault/prefix.
Новые Vitals methods не являются общим revival API и не меняют legacy тесты.

## 5. Allowed paths и ответственность

Только следующие 28 path разрешены будущему кодеру (точно, без directory globs):

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
  - scripts/core/actions/attack_hit_command.gd
  - scripts/core/actions/balance_command.gd
  - scripts/core/actions/push_damage_command.gd
  - scripts/core/actions/action_hp_executor.gd
  - scripts/core/units/vitals.gd
  - scripts/core/actions/death_command.gd
  - tests/run_tests.gd
```

read_paths: allowed исходники и UnitState/Faction/ActionResources,
ActionContext/Command/CommandStepResult/DamageSource/DamageRequest/ItemOwnerState/
ItemSimulationState. Все файлы вне exact allowed_paths остаются read-only.
Их effective hashes — P08_DEPENDENCIES_R3. Дополнительные шесть paths необходимы
для terminal postguards, pinned HP receipt и bound Move lethal. Board уже разрешён
и защищает адресата death cleanup. ActionContext/CommandStepResult/UnitState/
DamageCommand менять не нужно: typed Callable и nested receipt/binding укладываются
в существующие связи; event cap/schema уже позволяют faulted completed drafts.
Новые .uid только для двух новых classes r2; nested Vitals receipt нового файла не требует.
Пакет задаёт все новые API; за старым API адресно читать код, не всю библиотеку docs.

Ведущий владеет спецификацией, QA, snapshot/queue/guards архитектурой и интеграцией.
Один game_coder/Luna/medium пишет runtime в общем checkout; не коммитит, не
делегирует и не откатывает чужое. Самодостаточные подзадачи: (1) board/provider/
snapshot substrate, (2) geometry/pathfinder, (3) commands+regression; это стадии
одного пакета, не отдельные автоматически создаваемые задачи. Зависимые стадии
последовательны. Ведущий продолжает независимые oracle/QA/provenance проверки.
После двух неудач одной причины сверить полноту ТЗ; разрешён fallback Terra/high
с инструкциями game_coder по AGENTS, без подмены read-only reviewer.

Нельзя переписывать frozen P01–P08 r2 или этот пакет после фиксации APPROVE. Изменение
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
Не запускать никакие старые check-скрипты (включая p07/p08 check): их фиксированные имена перезапишут артефакты.
Из корня проекта, новый уникальный каталог на КАЖДЫЙ прогон:

```powershell
$ErrorActionPreference = 'Stop'
$p08PriorAppData = $env:APPDATA
$p08PriorGodot = $env:GODOT_BIN
$p08Run = Join-Path 'test_reports' ('p08-r3-run-' + [guid]::NewGuid().ToString('N'))
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
создаёт P08_REVIEW_R3, обновляет HANDOFF и коммитит только свои отделимые новые docs.
Прежний untracked HANDOFF целиком в staging не включать; сохранить его прежний текст.
Не делать push, не создавать sidebar задачи или расписания.
