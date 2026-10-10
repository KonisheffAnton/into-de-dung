# Текущий формат боевых снимков

Срез 2026-10-10 по поручению U: единый формат вместо выбора версии по составу
компонентов. Это текущий контракт поверх исторических P02/P03 и последующих
пакетов; frozen-документы не редактируются.

## Формат и граница совместимости

- `UnitState.SNAPSHOT_SCHEMA_VERSION = 9`: базовые поля и `guard_stance` обязательны.
  `action_resources`, `armor`, `bleeding`, `control`, `combat_perks`, `elemental`
  присутствуют только при наличии компонента. Отсутствие не создаёт компонент.
- `ItemSimulationSnapshot.SCHEMA_VERSION = 11`, scope `battle_state_v11`:
  `board_snapshot`, `owners`, `summons` обязательны. Среда, способности, артефакты,
  колода и эффекты карт опциональны с прежними взаимными ограничениями.
  Определения предметов всегда содержат use/charges/armor/summon descriptor;
  записи предметов — charges и armor identity, включая нулевую броню.
- Старые unit1–8 и item1–10 больше не читаются и не записываются runtime codec.
  Переписывание номера не является миграцией. Повреждённые данные отклоняются;
  корректная текущая форма с неподдержанным номером даёт UNSUPPORTED.
- Это **не формат сохранения профиля**: постоянный файл и граница отказа —
  [SAVE_FORMAT_CURRENT](SAVE_FORMAT_CURRENT.md). D4 остаётся отдельным форматом.
- Для миграции допуск/значения всех 128 составов компонентов сопоставлены
  с независимым эталоном предыдущего producer. После сравнения старый codec
  удалён и из тестов; его исходник и результаты остаются только в отчёте этапа.
  Текущая регрессия проверяет матрицу допуска, значения, связи и roundtrip.

### Вложенные формы с 2026-10-11

Каждый владелец пишет и читает одну версию. Старые формы не восстанавливаются;
внешний DTO проходит прежние строгие проверки. Режим задаётся значением,
а не номером схемы. Unit9 и Item11 остаются текущими оболочками.

| Владелец | Форма / признаки режима |
|---|---|
| BattleBoard | board2, `height_half_steps` обязателен, включая все нули и пустую доску; board1 отклоняется |
| ArmorState | armor4; `shield` / `raised_shield` опциональны, отсутствие не включает capability |
| BleedingState | bleeding4; обязательны `stacked:bool` и `stacks:int`; в режиме срока stacks=0, пределы/источники каждого режима прежние |
| ElementalState | elemental3; обязательный `acid_ticks:int`, включая ноль |
| CombatPerksState | perks7; все восемь флагов, `uses_bonus_actions:bool` и `reaction_left:int`; при оплате из bonus старый запас строго 0 |
| CombatEnvironmentState | environment5; `status_effects:bool`, опциональные collapse/hazards; status требует collapse, hazards требует status |
| BattleAbilityState | abilities3; `ruleset_id` пустой для прежней маны либо `u14-deck-v1`, обязательный `first_team`; прежний режим требует first_team=1 |

Вложенные старые номера armor1–3/bleeding1–3/elemental1–2/perks1–6/
environment1–4/abilities1–2 отклоняются. Game modes и их числовые правила
сохранены. Валидаторы событий, guards, UI и колода читают явные признаки режима.
В runtime нет прежних readers и выбора минимальной версии по содержимому.
Неизвестный номер текущей корректной board-формы даёт UNSUPPORTED;
повреждённые типы/массивы не маскируются этим номером. Старые вложенные компоненты
дают отказ валидации, без создания частичного runtime.

## Проверки и владение

Точные runtime-типы, stats/vitals ownership, action owner, диапазоны и связи
компонентов проверяются при каждом capture. Unit validator не копирует DTO и
не спускается рекурсивно через предыдущие схемы. Броня сохраняет проверку целого
HP и effective HP_MAX; наличие elemental требует stacked bleeding4,
а одновременно активные burning/bleeding недопустимы.

Item capture сохраняет свежий аудит live-графа, полный обход raw-значений с
лимитами и проверки owner/item/effect/source/deck связей. Только созданный внутри
того же вызова и уже проверенный board DTO повторно не проходит проверку формы
доски. Он не выдаётся наружу до завершения capture. Внешние `from_dict` и
`instantiate` проходят полную проверку; никакой проверки «только в debug» нет.

При instantiate после проверки envelope доска восстанавливается непосредственно
через `BattleBoard.from_snapshot_dict`, который проверяет свой DTO. Промежуточный
`SimulationSnapshot.from_dict` с дополнительным копированием и нормализацией
больше не нужен. Каталог определения строится один раз на владельца.

Копии runtime, DTO, RNG и счётчиков остаются независимыми. Порядок команд,
события/steps, FAULTED-префикс, summon checkpoint и worker lifecycle не меняются.

## Изоляция каталога штатного прогноза

`ForecastSimulation.prepare` (Attack/Move/Action, restore и opt-in clone) и
`TurnForecast.prepare` после успешного свежего capture используют общий
`ForecastDefinitionCopy.copy_catalog`. Все определения копируются через
`duplicate_deep(Resource.DEEP_DUPLICATE_ALL)`: внешние `.tres` эффектов и
шаблонов призыва больше не остаются ссылками на live. Класс `Item` поддержан
наравне с `ItemDef`; порядок обхода и выбор последнего определения одного ID прежние.

Перед любым дублированием проверяется metadata каждого исходного ItemDef,
его эффектов и ненулевого SummonDefinition, включая повторяющиеся ID владельцев.
Допустимы значения и вложенные контейнеры с такими значениями. Object (также
Resource/RefCounted/Node/Script), Callable, Signal и RID запрещены и в ключах,
и в значениях. Циклы, глубина более 32 и более 50000 посещений metadata всего
каталога дают `preview/unsupported_definition_metadata`; Prepared не содержит
каталога/context/clone и не запускает Thread. Предшествующие guards сохраняют
приоритет отказа, в частности `turn/unsupported_runtime` у TurnForecast.
Value-only metadata сохраняется в независимых контейнерах; live не меняется.
Capture/сверка каталога строят summon descriptor прямо из уже проверенных значений,
без промежуточного `Resource.duplicate`: metadata не входит в DTO и до gate не копируется.

Это граница копирования определений, а не повторный аудит всей доски или кэш.
`instantiate(definitions)` по-прежнему полностью проверяет внешний DTO/каталог,
а builder использует переданные определения. Он сам не обещает копию произвольного
живого каталога: независимость от live обеспечивает prepare. Прямой потребитель
Prepared (`battle_click_attack`) получает тот же отделённый каталог. Правила,
очередь, RNG, worker lifecycle и live execution этим срезом не изменены.
Свидетельства: `test_reports/restore-isolation-20261010/REPORT.md`; команды — TESTING.

## Общий runtime validator

`BoardSnapshotValidator` владеет preflight и порядком code/reason/unsupported IDs
для `SimulationSnapshot.capture_board` и opt-in audit. Проверки формы доски
принадлежат `BattleBoard`, бойца/компонентов — `UnitState`, характеристик —
`StatsBag`/`Stat`; эти же методы используют их snapshot producer. В harness
больше нет отдельной ручной реализации допуска. Проверка статусных источников
общая для runtime и внешнего DTO; preflight по-прежнему предшествует stale-cache.

Аудит свежий и синхронный: не строит board/unit/stats/modifier DTO, сохраняет
малые DTO компонентов и не прогревает кэш. `OK` с null snapshot означает только
проверку текущего графа. Внутренние unchecked builders вызываются сразу после
проверки в том же вызове; reusable token, кэш или worker-разрешение не создаются.
Расчёт HP_MAX runtime чистый, в прежнем порядке операций; внешний DTO сохраняет
полную проверку и restore через Stat codec. Структурные валидаторы внешних DTO
сохранены: они отвечают за отдельную границу недоверенных данных.

Admission и canonical fingerprint сверяются с 236 результатами исходного HEAD
`84cb7b4830f59dafd78569d1895cd4df1f9e0483`, записанными до изменения production:
`tools/demo/board_validator_baseline.json`. Это независимый эталон, поскольку
сравнение capture и audit теперь использует общие правила. Полная матрица и
clone lifecycle остаются opt-in; команды — TESTING, свидетельства —
`test_reports/shared-validator-20261010/`. Clone в игру не подключён.

## Гипотезы производительности

`revision` учитывает команды, `board_version` — изменения доски. Они не покрывают
прямые мутации HP/stats/item/definition/lifecycle и потому не образуют полный ключ
кэша. Полная проверка fingerprint требует свежего capture и сама имеет стоимость.
Долгоживущий кэш этим срезом не вводится. Для него нужен общий механизм инвалидации
всего графа либо действительно неизменяемый опубликованный снимок.

`tools/demo/profile_snapshot_strategies.gd` сравнивает capture/instantiate,
fingerprint guard и прямое копирование доски на 6/24/96 бойцах. Время допуска
включено в audited direct clone. Это эксперимент только с доской: предметы,
колода, реакции и передача полного графа worker ещё не реализованы в clone API.
Он не вызывается из игры. Первый замер с проигрышем на 96 не воспроизведён:
три повтора неизменённого benchmark и четыре парных прогона с прямым/обратным
порядком размеров показали выигрыш и на 96. В парных прогонах медианы audited
clone 62.648–68.294мс, capture/restore 89.665–97.121мс; рост clone 24→96 —
3.98–4.28 раза. Это наблюдение данного fixture, не доказательство асимптотики.
Причина прежних 145.369мс неизвестна: старый лог не сохранял сырые samples/фазы.

Режим `--clone-breakdown` сохраняет сырые парные samples, чередует стратегии,
отдельно измеряет capture/build/cleanup; `--reverse` меняет порядок размеров.
Проверки DTO, независимости stats/vitals и очистки death callbacks вне тайминга.
Отдельная инструментированная проба показывает стоимость direct_unit/add_unit.
На 96 capture-аудит занимает около 81% времени audited clone; это полный capture
с DTO, а не минимальный валидатор. `add_unit` не объясняет прежний скачок.
Свидетельства — `test_reports/clone-growth-20261010/`.

## Эксперимент свежего runtime-аудита

`tools/demo/board_audit_probe.gd` и `profile_board_audit.gd` — отдельный opt-in
эксперимент, не production API. Аудит не строит board/unit/stats/modifier DTO,
не копирует и не нормализует большой снимок. DTO компонентов и их существующие
валидаторы сохраняются; это не отсутствие всех аллокаций. Успешный результат
содержит только допуск (`OK`, `snapshot = null`), не публикует снимок и не может
переиспользоваться после мутации графа или передачи владения.

Сохраняются свежий обход, точные runtime-типы, порядок отказов, stale-cache,
vitals/stats и action ownership, диапазоны, формула в исходном порядке,
зависимости компонентов и ссылки источников. Production capture/restore,
внешние DTO и проверки item/deck/worker не меняются. Ручные дубли исходного
эксперимента заменены общими runtime-проверками по разделу выше; проверки
существующих вложенных форматов не сокращались.

В 224 сценариях (включая 128 сочетаний компонентов) совпали code/reason/IDs;
проверены повторный свежий аудит, отсутствие live/cache/signal мутаций, DTO и
вложенная изоляция клона на совместимых fixture. Четыре парных прогона 6/24/96
сохранили live ItemSnapshot/RNG/counters/UnitId и cleanup. На96 медианы clone
с runtime-аудитом 19.828–20.093мс, с capture-аудитом 63.474–65.235мс,
capture/restore 89.871–92.703мс. Это board-only CPU, не FPS/hover/полный clone.
Сырые samples, методика и проверки — `test_reports/board-audit-20261010/`.

Архитектурная граница: нынешний capture допускает неполную occupancy, совпадающие
cell без occupancy и unit.height, отличный от клетки. Старый `direct_board`
через `add_unit` не сохраняет все эти состояния, поэтому остаётся fixture-only;
допуск нового аудитора не ужесточён ради него. Точный экспериментальный clone
описан ниже; старый fixture остаётся эталоном прежнего benchmark.

## Эксперимент точного board clone

`tools/demo/board_clone_probe.gd` — opt-in harness, не production API.
`clone_board` в одном синхронном вызове заново проверяет текущий граф через
экспериментальный runtime-аудит и при OK создаёт отдельную доску. При отказе
сохраняет code/reason/unsupported IDs, не публикует board или DTO. Допуск нельзя
хранить для следующего вызова либо передавать worker; unchecked builder служит
только фазовым замерам сразу после проверки на принадлежащем harness графе.

Копирование повторяет семантику snapshot restore: сохраняет геометрию, явную
occupancy, регистрацию живых/мёртвых, cell и независимый unit.height, version,
скаляры, состав компонентов и порядок вычисления/локальные slots модификаторов.
`add_unit` не вызывается. Неполная occupancy, несколько бойцов в одной клетке,
полувысоты и нулевая площадь не нормализуются. Stats/vitals/компоненты принадлежат
клону; общие runtime-ссылки исходных бойцов разрываются как при restore. Кэш
характеристик создаётся холодным, внешние подписчики не копируются; каждая
регистрация получает собственный death callback, отключаемый при remove/resize.
Board/unit/stats/modifier DTO не строятся; малые DTO компонентов сохранены.

`profile_board_clone.gd` сравнивает допуск с production capture на всей матрице
эксперимента и каждый успешный случай — с capture/restore, включая пограничную
occupancy/height. Проверяются изоляция, source purity/cache/signals, свежесть после
мутации без изменения version, UnitId, локальные события move/death/remove,
повторная смерть и cleanup. Фазовые замеры 6/24/96 сравнивают capture/restore
с точным клоном под capture-аудитом и runtime-аудитом; проверки вне тайминга.
Результаты — `test_reports/board-clone-20261010/`; команды — TESTING.

Допуск и результат production capture/restore сохранены общим validator.
Локальный board clone не разрешает перенос всего графа/порядка команд в worker.
Полный item-граф и отключаемый потребитель описаны ниже; кэша нет;
локальная parity доски не доказывает очередь, preview/live/worker или ускорение FPS.

## Эксперимент clone полного item-графа после capture

`tools/demo/item_graph_clone_probe.gd` — opt-in эксперимент, без вызовов из игры.
Каждый `clone_state` синхронно выполняет полный `ItemSimulationSnapshot.capture`:
его свежий аудит, DTO, raw-лимиты и проверки межветвевых ссылок сохраняются.
Отказ возвращает исходные code/reason/IDs, без state/snapshot. При успехе точный
board clone читается сразу из того же live-графа, а owners/items/effects/facades,
summons и опциональные ветви собираются по локальному проверенному DTO.
Внешние DTO или каталоги этот вход не принимает; сохранённого допуска нет.
Успешный результат содержит отдельный runtime state и `OK` с null snapshot.

Каталог определений отделяется как при `ForecastSimulation.prepare`; определения
призыва дополнительно разделяются по владельцам, как при instantiate. Новые
владельцы ссылаются на новую доску, facades — на своих владельцев. Опциональные
abilities/environment/artifacts/deck/card_effects используют действующие codecs.
Это гибрид с полным capture, а не runtime-аудит всего графа без DTO. Item-ветвь
собирает один внутренний `ItemSimulationSnapshot._build_checked_state`: тот же
builder вызывает `instantiate` после прежней полной проверки внешнего DTO,
каталога и восстановления доски. Builder не проверяет произвольный вход и не
выдаёт допуск: его вызывают сразу после проверки с соответствующими DTO/board/
definitions. Ручная вторая реализация сборки в harness удалена.

`profile_item_graph_clone.gd` сравнивает полный DTO/canonical bytes, вложенную
изоляцию, свежесть без revision/version, lifecycle и cleanup с capture/restore.
Исполнение команд на восстановленном и клонированном графах сравнивает before/after,
receipt/events/steps/publications/RNG/counters/admission, включая отказ и FAULTED.
Обычный preview/live служит дополнительным контролем. Opt-in
`item_clone_transfer_probe.gd` переносит каждый restore/clone fixture в настоящий
Thread с отдельными context/RNG/rules/queue/command/sink. До передачи проверяются
runtime/Resource/container identity относительно исходника, metadata и сигналы;
разрешены только перечисленные fixture-типы и death callbacks собственной доски.
Это диагностический ownership gate известного графа, не production-разрешение
произвольных объектов. После передачи пакет не читается до join; повторный запуск
отклоняется. Проверены отказ запуска, discard/join, мутация исходника после
передачи и cleanup; FAULTED использует sink, принадлежащий только копии.
Сам harness не меняет входы штатных worker. Отдельный потребитель clone описан
ниже; BattleExecutionWorker по-прежнему получает целую session.
CPU сравнивает две стратегии с одинаковым fresh capture и detached catalogue,
включает cleanup, сохраняет сырые samples; фазы вложены в total. Не FPS/hover.
Единый builder и потоковая parity ограниченных fixtures подготовлены. Этот
harness не включает clone в игре. Команды — TESTING; исходные CPU-свидетельства —
`test_reports/item-graph-clone-20261010/`, сборка/ownership/Thread —
`test_reports/item-clone-worker-20261010/`.

## Отключаемый clone в штатном ActionForecastWorker

Обычный запуск использует capture/restore. Аргумент `--forecast-clone` после
`--` включает эксперимент в `BattleDemoSession.prepare_action_forecast`;
локальный переключатель session — `forecast_clone_enabled`. Он не сохраняется
в profile или snapshot. Атака, движение, TurnForecast и live execution сохраняют
прежние входы. Общий BattleDemo/HeroHubBattleView используют прежний путь
запроса/подготовки/публикации ActionForecastWorker.

`ForecastSimulation.prepare(..., use_clone=true)` выполняет прежние guards,
полный свежий capture и отделение каталога/context/RNG/queue/command. В
opt-in пакете каталог использует `duplicate_deep(DEEP_DUPLICATE_ALL)`, чтобы
отделить также внешние вложенные `.tres` эффектов и SummonDefinition. В том же
синхронном вызове `CheckedBoardClone` копирует проверенную доску, а общий
`ItemSimulationSnapshot._build_checked_state` собирает остальной граф. Board
probe делегирует этому же builder. Capture DTO сохраняется для snapshot_before
и fallback; успешный допуск не переиспользуется, кеша между запросами нет.
Сборка клона оплачивается главным потоком; это отдельная граница замера.

`ActionForecastWorker.start` синхронно переносит Prepared в собственный пакет,
помечая исходный consumed и забирая ссылки. Повторный start/run отвергается до
доступа к графу. Вызывающий не сохраняет и не читает внутренние ссылки во время
исполнения. Непереданный пакет закрывается через `discard_prepared`; отказ
команды/RNG/ОС тоже закрывает готовый клон. Успешное исполнение закрывает граф
в конце run_prepared, а take/close всегда присоединяют Thread.

Для clone-пакета `ForecastCloneGuard` проверяет известные runtime-типы,
script-поля, metadata, сигналы и точный состав реестра death callbacks.
Metadata допускает только значения и их контейнеры: Object любого типа,
Callable, Signal и RID запрещены также во вложенных значениях и ключах.
`Resource.duplicate(true)` сохраняет некоторые RefCounted в metadata по ссылке,
поэтому известного типа здесь недостаточно для доказательства изоляции.
Допускаются только собственные death callbacks доски.
Неизвестные объекты, Node, Script, Callable/Signal и превышение бюджета
отклоняются. Это проверка переносимого пакета, не новый snapshot admission.
При отказе клон закрывается, пакет без него проверяется заново и использует
штатный restore. Если и этот пакет небезопасен, возвращается
`preview/unsupported_worker_graph` без запуска. Отказ ОС остаётся
`preview/worker_unavailable`; синхронного исполнения на main не добавлено.

UI сохраняет generation, проверку текущей session/actor/revision/цели и прежние
проверки свежести. Отмена не прерывает команду: результат отбрасывается после
join; новый запрос готовится только после освобождения worker. Fallback не
перечитывает live и проходит ту же проверку актуальности перед публикацией.

Opt-in `profile_forecast_clone.gd` проверяет целого потребителя, все семейства
его команд, before/after/events/steps/publications/RNG/counters/admission,
FAULTED, ownership, свежесть, refusal/fallback/discard/join. Подписчик для записи
публикаций и внесения fault создаётся только внутри тестового потока после gate.
Парные CPU-замеры включают prepare, admission/launch и execute/join/cleanup;
проверки результата выполняются вне замера. Это CPU fixtures, не FPS/GPU/F5.
Команды — TESTING; результаты — `test_reports/forecast-clone-20261010/REPORT.md`.
Эксперимент выключен по умолчанию; измерения не разрешают включить его автоматически.
Обычный restore не проходит этот полный clone gate. Оба пути используют общую
границу копирования каталога, описанную в разделе «Изоляция каталога штатного прогноза».

Команды — [TESTING](TESTING.md). Свидетельства и измерения с границами сравнения —
`test_reports/snapshot-current-20261010/`. Производственная сцена с `_process`
включённым проверяется отдельно; синтетический рост не является прогнозом FPS,
а технический прогон не закрывает ручной F5/Editor/DPI/GPU.
