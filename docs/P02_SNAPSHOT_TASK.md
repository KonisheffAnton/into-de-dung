# P02 — изолированный снимок stats / units / board

Дата: 2026-09-13. Редакция: 2 (исправления независимого ревью). **Пакет для будущего запуска game_coder; реализация не разрешена этой задачей.**
Специализирует разделы 3, 6, 9 [контракта 0.5 draft-2](COMMAND_ACTION_QUEUE_CONTRACT.md).
P01 уже реализован в рабочем дереве. Не повторять, не откатывать, не коммитить.

## 1. Пакет и владение

```yaml
task_id: P02-BOARD-SNAPSHOT
role: game_coder # gpt-5.6-luna / medium; fork_turns=none
base_commit: b102678b28957e6d17282878dea19d3946d9f570
branch: main
goal: Повторно создавать независимую доску из value-снимка, сохраняя все поддерживаемые данные и порядок вычислений, не затрагивая live UnitId counter.
allowed_paths:
  - scripts/core/stats/stat.gd
  - scripts/core/stats/stats_bag.gd
  - scripts/core/units/unit_state.gd
  - scripts/core/board/battle_board.gd
  - scripts/core/actions/simulation_snapshot.gd
  - scripts/core/actions/simulation_snapshot.gd.uid
  - scripts/core/actions/board_snapshot_result.gd
  - scripts/core/actions/board_snapshot_result.gd.uid
  - tests/run_tests.gd
read_paths:
  - scripts/core/stats/stat_modifier.gd
  - scripts/core/stats/stat_types.gd
  - scripts/core/units/vitals.gd
  - scripts/core/units/unit_id.gd
  - scripts/core/units/faction.gd
  - scripts/core/board/terrain_type.gd
  - scripts/core/pathfinding/grid_data_provider.gd
  - scripts/core/combat/damage_calculator.gd
  - scripts/core/events/recording_event_sink.gd
contracts: ["Этот документ, разделы 2–7"]
acceptance: ["A01–A12, раздел 8"]
checks: ["Последовательность команд в разделе 9"]
non_goals: [P01, C-3, предметы, ActionContext, ActionQueue, Command, RNG, экономика, UI, полный preview, старый save-game, коммит]
```

Кодер — единственный писатель перечисленных исходников и тестов. Новые `.uid` только для
двух новых скриптов; генерация Godot допустима. Ведущий владеет документацией, архитектурой,
проверками и интеграцией. Не писать в другие исходники/документы/config; логи и временный
профиль проверки допустимы только в игнорируемом `test_reports/`. Ты не один в checkout:
не сбрасывай чужие изменения, адаптируйся к ним. Не делегируй дальше, не коммить.
При нехватке API — NEED_CONTEXT; при конфликте требований — CONTRACT_GAP, без расширения scope.

Принятые незакоммиченные зависимости P01 (SHA-256 содержимого на момент подготовки):

| Файл | SHA-256 |
|---|---|
| `scripts/core/board/battle_board.gd` | `498ED3B712813972F77921C67BED56118FEB119C6B5F0F9FDEB87D7E48E763F9` |
| `scripts/core/combat/damage_calculator.gd` | `FF1C6AB654414EAC7652AD17CA7D7D0D78EC8A0C14B794EB4EB7B530F22C9BBB` |
| `tests/run_tests.gd` | `262A95E0761DAE1648385975B6366057BE9F4643526CC0769801A3D81F952E81` |

Остальные входные исходники — из base commit. До запуска ведущий сверяет HEAD, status,
эти hashes и diff остальных входов. Изменение зависимости требует пересборки пакета.
Существующие изменения ARCHITECTURE/DECISIONS/TESTING, AGENTS/config/roles, WORKFLOW,
MECHANICS_REQUIREMENTS, контракта и передачи сохраняются. Сам пакет передаётся целиком;
кодеру достаточно его и перечисленных исходников, вся библиотека docs не нужна.

## 2. Границы поддерживаемого состояния

Это **низкоуровневый board snapshot**, а не `SimulationSnapshot.capture(ActionContext)`
из полного контракта. Новые имена ниже не выдавать за существующие API. Будущий фасад
контекста сможет использовать этот шов, но сигнатуры `capture(context)` и `instantiate()`
с возвратом ActionContext не занимать временными несовместимыми реализациями.

Поддержаны точные базовые классы BattleBoard, UnitState, StatsBag, Stat, StatModifier,
Vitals; пользовательские подклассы с дополнительным runtime — UNSUPPORTED.
В P02 `unit.ai_profile` должен быть null: непустой профиль отклонять, не терять его,
не загружать Resource по пути и не разделять его изменяемое дерево. Это явное ограничение
среза, а не изменение существующего ИИ. Доска может быть пустой.

У UnitState сейчас **нет** inventory/equipment: отсутствие полей не доказывает отсутствие
внешних эффектов. `capture_board` имеет обязательный аргумент `unsupported_runtime_ids`:
вызывающий владелец передаёт все известные неподдерживаемые runtime id. Пустой список
разрешён только в специально собранном headless harness без предметов, глобальных
gameplay callbacks, статусов и внешнего runtime. P02 не подключать к игровой сцене/UI.
Этот аргумент — явная декларация владельца, не автоматический детектор C-3; не обходить
будущий capability gate передачи пустого массива из настоящей сцены.

Все уже присутствующие StatModifier копируются, включая одинаковые источники, пустой
source_id и повтор одного Resource. Source_id сам по себе не позволяет определить,
есть ли предметная реакция. Числовой модификатор фикстуры допустим; влияющий предмет
в реальной сцене требует C-3 даже при успешном копировании его чисел.

**C-3 открыт.** P03 должен ввести Def/Instance, stable item/effect ids и локальный runtime
реакций, восстановление без повторного on_equip. P04/P08 добавляют очередь, RNG,
ActionContext, полный capability gate и preview/confirm. В P02 нет их фиктивных заглушек.
Не отключать реакции ради успеха snapshot. T09/T11 здесь проверяются только в части
изоляции/round-trip данных; parity полного execute/preview и T10 остаются незакрытыми.
Старые `move_points_left`/`has_attacked` копируются буквально; это не утверждение
стоимости атаки, правил повторного выбора или будущих move/main/bonus.

## 3. Точные новые API и ошибки

Все новые классы — RefCounted. В существующие классы добавить только отдельный путь:

```gdscript
# Stat / StatsBag / UnitState / BattleBoard — в каждом свой тип результата from:
func to_snapshot_dict() -> Dictionary
static func from_snapshot_dict(data: Dictionary) -> Stat # соответственно StatsBag / UnitState / BattleBoard

# SimulationSnapshot — отдельный файл, владеет только проверенными value-данными:
static func capture_board(board: BattleBoard, unsupported_runtime_ids: Array[StringName]) -> BoardSnapshotResult
static func from_dict(data: Dictionary) -> BoardSnapshotResult
func to_dict() -> Dictionary
func instantiate_board() -> BattleBoard
func canonical_values() -> Array
func canonical_bytes() -> PackedByteArray
func fingerprint() -> String

# BoardSnapshotResult — отдельный файл:
enum Code { OK, SNAPSHOT_UNSUPPORTED, SNAPSHOT_INVALID }
var code: Code
var reason: String
var unsupported_ids: Array[StringName]
var snapshot: SimulationSnapshot # non-null только при OK
```

`to_snapshot_dict()` возвращает новый value-граф; при неподдерживаемом/некорректном
состоянии возвращает `{}`. `from_snapshot_dict()` при ошибке возвращает null, никогда
частично восстановленный объект. Внутренние helpers для проверок допустимы в allowed_paths;
низкие слои не импортируют actions. Внешний фасад предварительно проверяет capability:
непустые unsupported ids, subclass, ai_profile дают UNSUPPORTED и диагностический id;
null board, неверные значения/структура дают INVALID. `reason` содержит путь поля/причину;
точный текст не закреплён. unsupported ids уникальны и отсортированы по Unicode code point;
для профиля использовать `unit/<id>/ai_profile`, для subtype — путь объекта + `/subclass`.
При отказе snapshot=null; никаких событий или изменений live. UNSUPPORTED проверять
раньше сериализации. Импорт неподдержанной версии/scope — UNSUPPORTED, сломанной схемы — INVALID.

Snapshot хранит private convention `_data`, не отдаёт его наружу; вход и каждый выход
копируются рекурсивно. Result не хранит board/live refs. `instantiate_board()` каждый
раз возвращает новую доску из уже проверенных данных; его null — внутренняя ошибка,
не штатный частичный успех. Не использовать публичные поля snapshot как DTO для мутации.
Проверка raw Dictionary — граница Variant; после проверки использовать явные типы,
typed arrays/локальные переменные. Не добавлять динамические Node/Callable/Resource в DTO.

## 4. Схема v1 (отдельно от старого save)

Каждая запись — Dictionary со **строго указанными строковыми ключами**, все обязательны;
неизвестные ключи/пропущенные значения отвергать, не подставлять defaults.
`int` не принимать вместо `float` и наоборот, bool не принимать как int. Схема — in-memory
Variant round-trip, не JSON. Массивы ниже обычные Array значений, без объектов/packed arrays.

| Запись | Поля и типы |
|---|---|
| Envelope | `schema_version: int = 1`, `scope: String = "board_only_no_items_v1"`, `board: Board` |
| Board | `schema_version: int = 1`, `width: int`, `height: int`, `board_version: int`, `heights: Array[int]`, `terrain: Array[int]`, `units: Array[Unit]`, `occupancy: Array[Occupant]` |
| Occupant | `x: int`, `y: int`, `unit_id: int` |
| Unit | `schema_version: int = 1`, `id: int`, `faction: int`, `cell_x: int`, `cell_y: int`, `height: int`, `debug_name: String`, `ai_profile_path: String = ""`, `move_points_left: float`, `has_attacked: bool`, `stats: Bag`, `vitals: VitalsRecord` |
| VitalsRecord | `hp: float`, `balance: float`, `is_alive: bool` |
| Bag | `schema_version: int = 1`, `stats: Array[StatEntry]` |
| StatEntry | `stat_type: int`, `stat: StatRecord` |
| StatRecord | `schema_version: int = 1`, `base_value: float`, `next_modifier_slot: int`, `modifiers: Array[ModifierRecord]` |
| ModifierRecord | `source_id: String`, `instance_id: int = 0`, `local_slot: int`, `evaluation_order: int`, `operation: int`, `value: float` |

`Stat.to_snapshot_dict` возвращает StatRecord, Bag/Unit/Board — свои записи.
`SimulationSnapshot.to_dict` возвращает Envelope. `canonical_values` описан в разделе 7.
VitalsRecord использует существующие `Vitals.to_dict/from_dict(data, cloned_stats)`:
последний создаёт Vitals(p_stats,false) и напрямую восстанавливает hp/balance/alive без
clamp и событий. Vitals менять не нужно. Проверять, что исходный `Vitals._stats` — тот
же bag, что `UnitState.stats`; иначе INVALID (прямое чтение только для этого инварианта).

Проверки значений: finite floats во всех полях, включая вычисленный результат каждого
Stat (вычислять на временной копии, не трогая live cache). Если live `_cache_dirty == false`,
требовать точного числового равенства временного результата и `_cached_value` (не
is_equal_approx; -0/+0 равны). Несовпадение или non-finite clean cache — INVALID:
`Stat.to_snapshot_dict()` возвращает `{}`, фасад — SNAPSHOT_INVALID, snapshot=null и
reason с путём stat/cache. Dirty cache не сравнивать: его содержимое уже не используется.
Не вызывать live get_value и не исправлять кэш/модификаторы при проверке.
Остальные ограничения: hp/balance/move >= 0,
board_version >= 0; id >= UnitId.FIRST; faction 0..2, stat_type 0..6, operation 0..2,
terrain 0..3. Высоты тайлов — signed int32. Ограничения формата P02: `MAX_BOARD_SIDE = 1024`,
`MAX_CELLS = 65536`; каждый размер в 0..MAX_BOARD_SIDE. Сначала проверить тип и предел
каждой стороны, затем безопасное произведение (при width > 0 проверить
height <= MAX_CELLS / width целочисленно), только после этого вычислять width*height
и сверять точные длины heights/terrain. Весь raw граф валидировать до Board.new/resize,
копирования крупных массивов и публикации объектов. Overflow/oversize — INVALID,
без аллокации доски; проверять одинаково capture и import. Это предел snapshot v1,
не новое правило размеров игровой карты; BattleBoard.resize вне snapshot не менять.
Не clamp при восстановлении. HP может превышать новый HP_MAX после снятия
модификатора, balance — текущий максимум; is_alive хранится отдельно, не выводить из HP.
Дубли id/stat_type/occupancy cell/modifier slot недопустимы. Evaluation_order — полная
перестановка 0..N-1. next_modifier_slot >= 0 и строго больше всех занятых local_slot >= 0.
Instance_id=0 — зарезервированный namespace legacy numeric modifier; другие значения
пока UNSUPPORTED (их владельца/семантику задаст P03).

## 5. Modifiers: владение, стабильные ключи и арифметика

Текущий StatModifier — Resource с source_id/operation/value; у него **нет** instance/slot id.
Не придумывать `get_modifiers()` как существующий API и не менять Resource-схему.
Stat владеет параллельным `_modifier_slots: Array[int]` и `_next_modifier_slot: int = 0`:
каждый успешный add ненулевого modifier выдаёт очередной slot, затем увеличивает локальный
счётчик. remove-by-source удаляет соответствующие slots, оставшиеся не перенумеровывает;
clear удаляет записи, но не сбрасывает счётчик. Это локальный счётчик Stat, не UnitId.
Его начальная пустота гарантирована новыми Stat после запуска; hot-reload прежних живых
объектов не входит в пакет. В snapshot сохраняется next_modifier_slot даже пустого Stat.

Ключ occurrence: `(source_id, instance_id=0, local_slot)` внутри конкретного unit/stat.
Один Resource, добавленный дважды, — две записи с разными slots; не дедуплицировать по
source_id, значению или instance_id движка. evaluation_order равен индексу в текущем
`_modifiers`. Сериализованные records сортируются по ключу, а при восстановлении массив
`_modifiers` собирается **по evaluation_order** с сохранёнными slots/counter.

Каждый restored occurrence получает `StatModifier.new(source, op, value)`. Никаких
разделяемых mutable Resources между live, snapshot и двумя копиями. Это явный value-copy
трёх полей, не `Resource.duplicate(true)` и не миграция C-3. Cache не сериализуется:
восстановленный Stat dirty, исходный cache при capture не менять. Проверка clean cache
из раздела 4 обязательна: прямое изменение mutable Resource не инвалидирует текущий
кэш и не должно давать успешный snapshot с другим вычисленным значением. Исправление
общей игровой инвалидизации кэша за пределами P02. Формула и порядок
сумм/произведений остаются текущими `(base + Σ flat) * (1 + Σ percent) * Π multiply`.
Заявление старого комментария о независимости от порядка не означает битовую
коммутативность float; каноническая сортировка не должна менять порядок операций.

## 6. Unit / Board: восстановление и подписки

UnitState.from_snapshot_dict использует `UnitState.new()`, присваивает сохранённый id,
новый StatsBag и Vitals с ссылкой на этот новый bag. Запрещены UnitState.create,
UnitState.from_dict, UnitId.next/set_counter/reset_counter, даже временно с restore.
UnitId counter не включать в этот снимок. begin_turn/refill/equip/load не вызывать.
Поля cell/height присваиваются только при сборке ещё не опубликованного объекта;
после публикации перемещение идёт через BattleBoard.

Board владеет registry, terrain/heights, occupancy и восстановлением своих подписок P01.
Восстанавливать отдельные массивы и словари, а не копировать `_death_callbacks` и listeners.
`BattleBoard.new()` допустим: после сборки **точно** установить сохранённый board_version,
не использовать финальный `_touch()`. На непубликуемом объекте разрешена внутренняя
гидратация полей без сигналов; не использовать add_unit/move_unit для загрузки — они
меняют version/height и могут отвергнуть общую клетку трупа и живого юнита.

Occupancy сохраняется **явно**, а не достраивается из всех живых: существующий
`clear_occupancy` способен оставить живого в реестре вне occupancy. Для каждой записи
требовать существующего живого юнита с совпадающей cell в bounds; одному id максимум
одна запись. Каждый unit.cell в P02 должен быть в bounds; трупы могут делить клетку
с живым и друг с другом. Не требовать unit.height == tile height: set_height в текущем
API не обновляет unit.height, snapshot обязан сохранить оба значения точно.
Не исправлять эти состояния в P02 и не менять правила P01.

После проверки и сборки всей доски вызвать существующий `_register_death_callback`
для каждого её юнита ровно один раз. Восстановление не испускает died/hp_changed/
stat_changed/board_changed наружу; копируются только данные, не live listeners.
Смерть копии очищает только её occupancy; remove/resize снимают её собственные
подписки как в P01. Provider получать заново через `clone.make_data_provider(clone_unit)`;
не переносить замыкания live-доски. Snapshot не хранит provider/сигналы/callbacks/cache.

## 7. Canonical order / bytes / fingerprint

На входе from_dict/from_snapshot_dict разрешён любой порядок map-полей и несемантических
массивов records; валидировать и нормализовать. Units — по числовому id (2 раньше 10),
stats — по числовому stat_type, occupancy — по (y,x), heights/terrain — row-major y*width+x.
Modifiers — по (source_id Unicode code point, instance_id численно, local_slot численно).
Evaluation_order и next_modifier_slot входят в состояние; перестановка арифметики меняет
canonical values и fingerprint. Равенство статистических итогов не равно равенству снимков.

`canonical_values()` рекурсивно превращает каждый Dictionary в Array пар `[key, value]`,
ключи схемы String сортируются по Unicode code point. Массивы сохраняют уже определённый
порядок. Листья только String/int/float/bool; -0.0 нормализовать в +0.0. Возвращается новая
копия. Смешанные map-ключи невозможны по схеме; numeric-key maps в DTO не использовать.

Точный P02 codec: bytes начинаются UTF-8 `P02S`, затем byte `1` (версия codec).
Рекурсивно кодировать canonical_values: bool tag=1 и byte 0/1; int tag=2 и signed int64
little-endian; float tag=3 и IEEE-754 binary64 little-endian; String tag=4, uint64 LE
длина UTF-8 в байтах, затем UTF-8; Array tag=5, uint64 LE число элементов, затем элементы.
Не кодировать runtime objects, Dictionary, Vector2i, NIL; схема их не допускает.
Не применять JSON/stringify, var_to_bytes, locale или округление к float. Все floats
конечные, -0.0 кодируется как +0.0. fingerprint — lowercase hex SHA-256 этих bytes.
Это fingerprint только scope P02, не token действительности полного боя/команды/rules.

## 8. Обязательные поведенческие тесты

Добавлять в `tests/run_tests.gd`, регистрировать в `_initialize()` отдельную suite P02;
сохранить все проверки P01. Existing `_check_eq` приблизителен: для canonical и
float-order использовать `_check(actual == expected, ...)`/bytes equality.

- **A01 — полный round-trip:** фикстура 3x2, разные высоты/все terrain, units с id 2 и 10,
  живой и труп на общей клетке, ненулевая board_version; неполные HP, баланс, движение,
  has_attacked, debug_name, все объявленные stats, отсутствующий stat и объявленный
  нулевой stat различимы. Capture → to_dict → from_dict → две instantiate → recapture:
  точное равенство value-полей/canonical values/bytes/fingerprint. Проверить ожидаемые
  значения напрямую, не только равенство двух вызовов одного сериализатора.
- **A02 — все modifiers:** ADD_FLAT/ADD_PERCENT/MULTIPLY, несколько одинаковых и пустых
  source_id, повтор одного Resource дважды, удалённый slot и пустой Stat после clear.
  Сохранить multiplicity, base, slots, next slot, eval order, computed value. После
  restore add использует следующий сохранённый slot; remove-by-source работает у копии.
- **A03 — float order:** ADD_FLAT в порядке source z:1e16, a:-1e16, m:1.0, base=0.
  Исходный результат ровно 1.0, сортировка по source даст 0.0. Round-trip сохраняет 1.0.
  Перестановка records без изменения evaluation_order даёт прежние bytes; изменение
  evaluation_order при сохранении валидной перестановки меняет результат и fingerprint.
- **A04 — двусторонняя изоляция:** после capture менять live base/modifier Resource,
  HP/баланс, движение/has_attacked, terrain/height, occupancy; snapshot и копии сохраняют
  прежнее. Затем менять копию A теми же способами, remove/add modifier и move_unit:
  live, snapshot и копия B неизменны. Проверить разные identity Unit/Bag/Vitals/Stat/
  каждого modifier; white-box чтение в тесте допустимо, production Stat наружу не выдавать.
- **A05 — владельцы Vitals:** изменить HP_MAX только A, затем heal(A); предел берётся
  из A.stats, live/B.stats и HP не меняются. Сохранить также HP выше уменьшенного HP_MAX,
  баланс выше максимума, alive=true при hp=0 без автоматической коррекции.
- **A06 — UnitId:** снять counter до вызовов, snapshot юнита с id значительно выше
  counter создать через UnitState.new в fixture; многократные capture/from_dict/
  instantiate и ошибочные входы сохраняют counter. Следующий явный UnitId.next()
  возвращает исходный counter, затем counter увеличен ровно на 1. Дополнительно ревью
  call graph подтверждает отсутствие временных next/set/reset, которых финальный assert
  не ловит. Тест не «лечит» вызовы reset/restore вокруг операции snapshot.
- **A07 — сигналы/P01:** счётчики на live stats/vitals/board не растут при capture/load
  и смерти копии. Смерть клона чистит его клетку, сохраняет труп и допускает реальный
  move другого клона на неё; version live/B неизменна. remove/resize копии и поздняя
  смерть удалённого юнита не трогают её version. Provider A читает новые данные A.
- **A08 — value ownership:** изменить входной Dictionary после from_dict, возвращённые
  to_dict/canonical_values/bytes и массив unsupported ids после вызова — сохранённый
  snapshot/result неизменен. Вложенные modifiers/occupancy проверять отдельно.
- **A09 — canonical:** переставить units, stats, occupancy, modifiers records и порядок
  вставки Dictionary-ключей, сохраняя eval order/counters/version: values/bytes/hash
  равны. Проверить units 2,10 и slots 2,10 численно, sources с кириллицей по code point.
  Изменить по одному hp, modifier.value, board_version: values/bytes/hash различны.
  Проверить bool/int/float tags, UTF-8 byte length, little-endian int/double, -0/+0;
  ожидаемые байты отдельных листьев/префикса задать литерально, без второго вызова codec.
- **A10 — отказы:** null/missing stats или vitals/несвязанный vitals bag, неизвестная
  версия/scope, ai_profile и subclass, непустой runtime id, NaN/INF/overflow итога Stat,
  неправильный тип/ключ/enum, длина terrain, duplicate id/slot/stat/cell, сломанный
  eval order, next slot <= занятый, occupancy мёртвого/несуществующего/чужой клетки.
  Отдельно: width/height = максимальному int64 и сторона MAX_BOARD_SIDE+1; стороны
  в пределах лимита, но произведение MAX_CELLS+1 или больше — INVALID до аллокации.
  Проверить допустимые границы 0, MAX_BOARD_SIDE и ровно MAX_CELLS.
  Прочитать Stat.get_value (cache clean), напрямую изменить modifier.value, затем
  capture: INVALID/snapshot=null, stale cache остаётся прежним, Resource не исправляется,
  сигналы и UnitId неизменны. Dirty Stat с конечным новым результатом успешно копируется.
  Возвращаются заданные INVALID/UNSUPPORTED, snapshot=null; counter/live не меняются.
- **A11 — границы board:** пустая доска; живой без occupancy после clear; труп+живой
  на одной клетке; unit.height отличается от tile после set_height. Всё сохраняется
  точно. Unit.cell вне bounds отклоняется явно, не молча обрезается/перемещается.
- **A12 — совместимость:** старые to_dict/from_dict не менять; старый bag.to_dict
  по-прежнему только bases. Все прежние 156 assertions проходят; новые проверки не
  должны превращать реентрантность S-5, предметы или полный preview в заявленный успех.

## 9. Проверки и сдача будущей реализации

Сейчас проверяется документ, Godot-тесты P02 ещё не существуют. При реализации ведущий
до ревью запускает полный import, startup и регресс. Из корня проекта, PowerShell:

```powershell
git status --short
git rev-parse HEAD
# GODOT_BIN ведущий назначает процессу по docs/TESTING.md; глобальные настройки не менять.
New-Item -ItemType Directory -Force test_reports/godot-profile | Out-Null
$p02OldAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path (Get-Location) 'test_reports/godot-profile'
    & $env:GODOT_BIN --path . --headless --import --log-file test_reports/p02-import.log
    if ($LASTEXITCODE -ne 0) { throw 'P02 import failed' }
    & $env:GODOT_BIN --path . --headless --quit-after 3 --log-file test_reports/p02-startup.log
    if ($LASTEXITCODE -ne 0) { throw 'P02 startup failed' }
    & $env:GODOT_BIN --path . --headless --script tests/run_tests.gd --log-file test_reports/p02-tests.log
    if ($LASTEXITCODE -ne 0) { throw 'P02 tests failed' }
} finally {
    $env:APPDATA = $p02OldAppData
}
git diff --check
```

Помимо exit 0 проверить завершённый scan/classes, отсутствие GDScript ошибок и финальное
`N passed, 0 failed` (прежние 156 + новые). Ожидаемый push_error теста занятой клетки P01
и известное сообщение root certificate store отделять от новых ошибок. Нужны содержательные
assertions A01–A12, не только headless startup; визуальная проверка этого пакета не требуется.

Кодер возвращает статус, файлы, покрытые A01–A12, команды/exit codes, итог passed/failed,
непроверенное/блокеры. После окончания записи ведущий фиксирует hashes diff, проверяет
владение/counter/canonical вручную и запускает game_reviewer (Terra/high, только чтение,
без дальнейшего делегирования). APPROVE пакета не заменяет ревью будущего кода.
