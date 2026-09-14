# Как проверять проект

## Headless-проверка (без открытия окна)
Используется для быстрой проверки ошибок компиляции/выполнения после
правок, прямо из терминала (агентом или пользователем).

Путь к бинарю Godot задаётся **переменной окружения `GODOT_BIN`**, а не
хардкодится (P-5: абсолютный путь к конкретной машине ломается у любого
другого человека и в CI). Один раз на машину:

```powershell
# Разово, для текущего пользователя:
[Environment]::SetEnvironmentVariable("GODOT_BIN",
  "D:\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
  "User")
# После этого перезапустить терминал.
```

Проверка (запускать из корня проекта — путь относительный):
```powershell
& $env:GODOT_BIN --path . --headless --quit-after 3
```
Если вывод содержит только строку версии движка — всё ок, ошибок нет.

### ВАЖНО: кэш class_name
После добавления НОВОГО скрипта с `class_name` headless-запуск может упасть
с ошибкой `Identifier "X" not declared in the current scope` — это не баг
кода, а непересобранный кэш глобальных классов Godot. Фикс: один раз
прогнать редактор в headless-режиме, чтобы он пересканировал проект:
```powershell
& $env:GODOT_BIN --path . --headless --editor --quit-after 5
```
После этого обычная headless-проверка отработает корректно. Делать это
каждый раз, когда добавляется новый `class_name`.

## Регрессионные тесты (обязательны перед коммитом)

```powershell
& $env:GODOT_BIN --path . --headless --script tests/run_tests.gd
```
Ожидаемый результат — последняя строка `=== N passed, 0 failed ===`.
Код возврата 1 при любом падении (годится для CI).

Тесты покрывают ТОЛЬКО чистую детерминированную логику — там, где визуальная
проверка бессильна: конвейер `Stat`, клампы и смерть в `Vitals`, чистота
`DamageCalculator.calculate()`, геометрия `PushResolver`, границы раунда и
поведение очереди при смерти, round-trip координат, согласованность
`find_path`/`get_reachable_cells`, агрегация оценок ИИ (ABSTAIN/VETO/
детерминизм). UI и игровой флоу проверяются глазами.

Ключевые тесты — регрессии на дефекты аудита:
- `_test_damage_does_not_corrupt_base_value` — C-2 (HP росло от урона);
- `_test_death_does_not_restart_round` — D-4.6 (смерть перезапускала раунд);
- `_test_abstain_excluded_from_average` — S-3в (нули топили перемещения);
- `_test_path_and_reachable_agree_on_height_rule` — инвариант модуля 3.

Новый тест добавляется в `_initialize()` соответствующей секции.
Раннер самодельный (`SceneTree`-скрипт), gdUnit4 подключим после работающего
вертикального среза (R-7): сейчас важнее, что регрессии ловятся вообще, чем
что это красиво.

### ВАЖНО: headless НЕ достаточен для статуса Verified
Headless-прогон проверяет только компиляцию и отсутствие рантайм-ошибок в
первые секунды. Он **не выявил** ни C-2 (порча HP через `base_value`), ни
C-3 (hard error при выдаче предмета второму юниту) — оба дефекта уехали в
статус «Done». Поэтому:

**`Implemented` = headless чист. `Verified` = ещё и unit-тесты и/или
подтверждённая визуальная проверка.** См. `docs/AUDIT.md` → P-1.

## Визуальная проверка в редакторе
Открыть `scenes/test/test_grid_scene.tscn` (это `run/main_scene`, F5/F6
запускает именно её).

### Модуль 1 — Input & Grid
- Мышь без нажатия — hover подсвечивается синим, текст `Hover:` обновляется.
- ЛКМ/тап — выбор клетки (жёлтая подсветка), консоль печатает `Selected cell:`.
- ПКМ-драг / touch-драг одним пальцем — панорамирование камеры с инерцией
  (после отпускания едет по инерции и плавно тормозит).
- Колесо / pinch — плавный зум.
- После зума/пана клики должны продолжать точно попадать в клетку под
  курсором (проверка `affine_inverse()` конвертации).
- Приподнятые тестовые клетки (3,3),(4,3),(3,4) — hover/select не должны
  "дёргаться" на границе уступа.

### Модуль 2 — Y-Sorting
- Слева/центр сетки — 4 цветных круга (юниты-плейсхолдеры) + жёлтая точка
  (снаряд), летающая по синусоиде поверх всех юнитов.
- Снаряд всегда рисуется НАД юнитами, независимо от их взаимной глубины.
- Возвышенные клетки (3,3),(4,3),(3,4) теперь отрисованы как объёмные блоки
  (`ElevatedTileVisual`) с верхней и боковой гранью, а не плоские ромбы.
  UnitFar (3,2) должен визуально скрываться ЗА платформой (4,3), если она
  логически "перед" ним по глубине сетки — проверить на глаз в редакторе.

### Модуль 3 — Pathfinding
- Белая клетка (1,1) — тестовый старт юнита. Зелёная область — зона хода
  (flood-fill, `unit_move_range=4.0`).
- Красные клетки — стены; зона хода и путь должны их огибать.
- Клик по любой клетке — белая линия показывает путь от (1,1) до неё,
  обходящий стены и не пересекающий перепад высоты >1 уровня.

### Модуль 4 — Stats & Initiative
- Панель `InitiativePanel` (Label, CanvasLayer) справа от сетки — список
  4 тестовых юнитов, отсортированных по `INITIATIVE` (убывание).
- Клик по ОБЛАСТИ ПАНЕЛИ (текст, offset_left=420..offset_right=620,
  offset_top=16..offset_bottom=160 в экранных координатах) — пересчёт
  очереди, при равных `INITIATIVE` порядок может измениться (случайный
  tiebreak).
- Пользователь подтвердил: клик меняет только порядок среди юнитов с
  одинаковой INITIATIVE (случайный tiebreak), сами значения INIT/STR не
  меняются — это ОЖИДАЕМО и корректно.
- ФИКС (Модуль 5): панель была почти не видна из-за отсутствия явного цвета
  текста. Добавлен `theme_override_colors/font_color = white` + тень, панель
  перемещена в x:20-280 (левый верхний угол, под сеткой).

### Модуль 5 — Inventory & Synergy
- `InventoryPanel` (Label, x:20-420, y:180-320) — показывает HP/STRENGTH
  тестового юнита с двумя выданными предметами.
- Клик по панели эмитит `GameEventBus.unit_damaged` (2 урона) — HP должен
  вырасти на +1 (эффект item_b), счётчик "Damage events emitted" растёт.
  ВАЖНО: реального вычитания урона нет — это будет в Модуле 6, демо
  проверяет только реакцию TriggeredEffect на событие.
- STRENGTH должен показывать 5.0 (base 3 + 2 от item_a) сразу при старте,
  без необходимости клика.

### Модуль 6 — Damage/Balance/Push Preview
- `CombatPanel` (Label, y:340-480) — тестовый атакующий/цель, НЕ привязан к
  визуальным юнитам на сетке (чистая демонстрация чисел).
- ЛКМ по сцене (любой клик primary_action) — пересчитывает превью (безопасно,
  не меняет HP/Balance). Должно показывать `Preview dmg: 4.0` (base 1 + STR 3).
- ПКМ (secondary_action) — применяет атаку: HP цели уменьшается на 4 каждый
  раз, Balance растёт на 40. После 3 применений (120 >= 100) Balance
  сбрасывается в 0, `would_break_balance=true` и показывается push direction
  (клетка (3,1)->(4,1), т.к. attacker (1,1) левее target (3,1) → push направо).
- Проверить: `Hits applied` растёт только по ПКМ, не по ЛКМ.

## Общая рекомендация
После КАЖДОГО нового модуля: headless-проверка на ошибки → визуальная
проверка в редакторе пользователем → фиксация результата в
`docs/modules/NN-название.md` и обновление статуса в `docs/ARCHITECTURE.md`.

## P03a — Item ownership, редакция 2 (2026-09-13)

В tests/run_tests.gd добавлен suite `P03a Item ownership`: реальные кэшированные .tres,
две копии/два владельца, повторённый subresource, все stat operations и float order,
identity/registry, no-op, replacement/clear/close, общий guard, невалидные определения,
переполнение ids, source collision и атомарный legacy load, EventSink и P02 UNSUPPORTED.
Прежние 484 assertions сохранены. Итог ведущего: **722 passed, 0 failed** (238 новых),
import/startup exit 0, независимое ревью фиксированного кода **APPROVE**. Дополнительный
owner harness — 37/0, panel harness — 20/0. Полная передача — CODEX_HANDOFF.

Ведущий выполняет import, startup и tests командами из ТЗ; логи —
`test_reports/p03a-{import,startup,tests}.log`. Вспомогательные owner/panel harness,
baseline и фиксированный manifest/diff для ревью лежат в игнорируемом test_reports.
Проверяются также allowed_paths и сохранность всех прежних строк tests/run_tests.gd.

Headless-проверка реального узла панели отправляет gui_input, проверяет HP 10 -> 7,
текст, силу 5/base 3, два открытия и teardown с удержанными runtime-ссылками.
Это проверка интеграции, не визуальной вёрстки: окно/ручной клик остаются UI unverified.
Известные certificate-store и ожидаемый P01 occupied-cell error проверяются отдельно
от новых parse/compile/runtime ошибок. P03b/P04 и полный preview здесь не проверяются.

## P03b — item snapshot/collection, редакция 1 (2026-09-13)

В runner добавлены B01–B14 из P03B_ITEM_SNAPSHOT_TASK: roundtrip live/A/B и mutable
identity, detached/ids/exhaustion, lifecycle 3×3/closed, links всех 7 stats/3 operations
и malformed graph, exact capability, catalogue, чистые повторные descriptions.
Включены literal fixture целого P03B envelope, high int64/Unicode/-0, semantic order,
владение вложенными DTO и raw caps (граница/+1), alias/cycle/depth/value-node budget.
Лимит owners 65536 проверен на уровне структуры: полный валидный граф с таким числом
юнитов раньше ограничивает общий бюджет 2 млн values; boundary test не обходит его.

Проверки ведущего: Godot 4.7.2 import/startup/tests exit 0, **1008 passed, 0 failed**
(722 прежних + 286 новых assertions). Все 2197 прежних строк runner сохранены в порядке.
В class cache есть пять новых global classes; новых parse/compile/runtime ошибок нет.
Логи: `test_reports/p03b-{import,startup,tests}.log`; baseline, fixed hashes/diffs для
независимого ревью — `test_reports/p03b-implementation-baseline*`, `p03b-review-*`.
Результат независимого ревью и commit фиксируются в CODEX_HANDOFF.

Проверка purity сравнивает UnitId напрямую без next/reset, stat cache/slots и P02 DTO,
живые signals/subscriptions/provider после повторных capture/instantiate/collect.
BUSY проверяется внутри item_added callback; mixed invalid/unsupported проверяет
глобальный raw/live preflight. Restore call graph не содержит equip/activation,
legacy load, create_item/create_runtime или add/remove_modifier.

Known certificate-store и ожидаемый P01 occupied-cell error остаются известными.
UI/ручной клик старого демо по-прежнему unverified. P03b не исполняет лечение, не
подключает очередь/P04, RNG или полный preview; прежний fresh-equip regression сохранён.

## P04 — headless очередь Damage / Heal / Death (2026-09-14)

Выполнены C01–C12 редакции 1 P04_ACTION_QUEUE_TASK. Полный runner:
**1275 passed, 0 failed** (1008 прежних + 267 новых assertions, включая reused fixtures).
Godot 4.7.2 import/startup — exit 0; scan DONE, 14/14 новых global classes в cache.
Новых SCRIPT/Parse/Compile/runtime ошибок нет. Единственный ERROR регресса — прежний
ожидаемый P01 отказ занятой клетки. UI/ручной клик демо остаётся unverified.

C01–C04 проверяют cell/NONE source, flat/bypass без STRENGTH/impact/resource costs,
actual damage/heal, damaged→died, один Vitals.died, occupancy/corpse/idempotence,
root rejection/child skip, alive-at-zero, full/zero/over-max и отказ invalid payload
без изменения counters/RNG/dirty cache. Item cases проверяют две копии общей def,
порядок и parent_event_seq, сохранение modifiers/ids, отсутствие чужого и lethal heal.

C05–C08 проверяют binding после mandatory mutations: detach/reactivate, закрытие,
смерть, remove/replace unit/item/effect/definition, inactive, guard/ledger faults;
depth-first trace и shuffled registry order; BUSY из copy/validate/execute/Vitals/sink,
независимый context; replay/duplicate/new-event keys и изоляцию payload/description/receipt.

C09–C10 проверяют command/event/depth boundary и +1, SKIPPED в лимите, цикл,
атомарный event overshoot и честный prefix, оба fault latch, preflight/collector/child
errors, malformed step и int64 reservation до мутаций. C11 проверяет fail-closed порт,
точные String/type/keys RNG DTO, atomic import/alias/clone/overflow, реальные random
children на двух P03b instantiate: совпадают outcomes, events, steps, counters и RNG;
live, соседняя копия и loot не меняются от исполнения первого контекста.

Сохранены 3123 исходные строки runner в прежнем порядке; 186 закрытых baseline файлов,
включая P01/P02, прежние .uid/.tres и процессные настройки, совпадают по SHA-256.
Прежние тексты смешанных docs сохранены полностью; новые разделы добавлены отдельно.
Логи: `test_reports/p04-{import,startup,tests}.log`; baseline/audit/frozen manifest
и P04-only patches: `test_reports/p04-implementation-baseline*`, `p04-audit.ps1`,
`p04-review-*`. Результат независимого ревью и локальный commit — CODEX_HANDOFF.

GODOT_BIN отсутствовал в process/user environment; найден указанный выше Godot и задан
только для проверочных процессов. APPDATA временно направлялся в test_reports/godot-profile
и восстанавливался. Пользовательские настройки окружения не изменялись. Эти проверки
не подтверждают Move/Attack/Push, экономику, Flow/BT, общий C-3/S-5 или полный preview.

## P05 — MoveCommand и явный путь (2026-09-14)

Выполнена приёмка M01–M12 принятой редакции 1 P05_MOVE_TASK и весь прежний регресс.
Итог ведущего: **1421 passed, 0 failed**; предыдущие 1275 assertions сохранены.
M01–M12 вызываются общим runner. Дополнительно до завершения P05 tests сохранённый
baseline runner отдельно прошёл на новом runtime: 1275 passed, 0 failed.

Команда ведущего из корня: `& test_reports/p05-check.ps1`. Godot 4.7.2:
headless import (scan DONE, MoveCommand/MoveRules/MovePathCheck зарегистрированы),
startup `--quit-after 3`, затем `--script tests/run_tests.gd` — exit 0.
Логи: test_reports/p05-import.log, p05-startup.log, p05-tests.log.
Новых parse/compile/runtime errors нет. В тестовом логе остаётся только ожидаемый
старый occupied-cell ERROR P01.
APPDATA направлялась только на время процесса в test_reports/godot-profile и восстановлена.
UI не прогонялся: пакет проверяет headless ядро.

M01–M04: владение payload/rules, точные admission/rejection reasons, bounds/occupancy/
height/full-tail checks, отсутствие мутаций/caches/counters/RNG, finite и точное списание
float. M05–M08: реальные рёбра Move и trusted children, terminal interruption, смерть/
смещение/замена/изменение пути и бюджета, добровольный HAZARD → mandatory Death,
damage/item healing и прежний depth-first порядок. M09–M12: строгие value schemas и
copies, reentrancy из board signals/final sink, sibling drain/fault precedence,
лимиты/overflow и сохранение оплаченного prefix, два независимых P03b fixtures.

Проверка сохранности `& test_reports/p05-audit.ps1`: закрытые paths совпали с baseline,
все прежние 3812 строк runner сохранены по порядку, прежние документы сохранены целиком,
новые файлы ограничены allowed_paths. `git diff --check` прошёл. Frozen P05 task/manifest
не переписаны. Новые hashes результата и логи переданы независимому game_reviewer;
окончательный код получил **APPROVE**. Manifest: test_reports/p05-result-review-manifest.json.

Move не подключён к UI/AI. Проверка парных fixtures не означает полный preview/token,
snapshot ActionContext или save-game. Цена атаки, повторное переключение персонажей,
движение после атаки и refill остаются открытыми. C-3/S-5/T10/T11 и 0.5/0.8 не закрыты.

## P06 — AttackCommand / ActionResources (2026-09-14)

Ведущий выполнил A01–A14 и весь P01–P05 регресс: **1633 passed, 0 failed**,
exit0. Команда `& test_reports/p06-check.ps1`: Godot 4.7.2 headless import (scan
DONE, шесть новых классов зарегистрированы), startup --quit-after 3, полный
tests/run_tests.gd. Логи p06-import.log, p06-startup.log, p06-tests.log и полный
stdout/stderr p06-final-run.log; исходный общий вывод p06-accepted-extension-run.log.
APPDATA перенаправлялась только на время процесса и восстанавливалась.

Новых parse/compile/runtime errors нет. Ожидаемый P01 occupied-cell ERROR сохранён.
45 ObjectDB / 18 resources при выходе воспроизводятся в историческом
p05-lead-final-check.log; новая callback-утечка теста P06 устранена. Эти сообщения
не скрываются за exit0. UI не проверялся: P06 ограничен headless harness.

A01–A06: copied rules/payload/definitions и bounded invalid markers; чистые отказы
с exact reasons, cache/counters/RNG; flat geometry; signed/fractional/minimum damage
и overflow; один main ledger, независимые move/bonus, explicit atomic refill.
A07–A10: настоящий Attack→Hit→Heal, lethal/alive-at-zero/overkill, Move→Attack→Move,
смешанные Unit v1/v2 и P02/P03b roundtrip, modifiers7..10, malformed DTO/version
classification, ledger ownership/subclass, legacy export refusal и старый oracle.
A11–A14: original request seal после corruption+copy, registry/cell/ledger bindings,
строгий attacked и независимые DTO, BUSY из HP/death/board/sink на обеих queues,
limits/sequence/version и оплаченный prefix, два независимых restored исполнения
с одинаковыми snapshots/journals/counters и нулевыми RNG draws.
Защитный invalid_damage_request недостижим после валидного admission и создания
request из конечных значений/literals; искусственный обход ради coverage не добавлен.

Вход: HEAD a73bd9fe4f709de1f89441882e3360baea4ce881, 118/118 dependencies и два
frozen hashes совпали. Baseline всех 232 файлов и старого diff сохранён в
test_reports/p06-implementation-baseline/ и соседних .json/.patch. Исторические
manifest не переписывались. При сверке 217 закрытых файлов сохранили hashes;
единственное расширение — разрешённая пользователем строка item_owner_state.gd
stat_type >6 -> >10. Два прежних FAIL A09 устранены реальным item pipeline.
В старом runner изменены только negative stat7 ->11 и unknown Unit2 ->3;
остальные исходные строки сохранены, новые тесты добавлены отдельно.

Независимый game_reviewer Terra/high: итог **APPROVE**, все 31 SHA256 совпали с
test_reports/p06-implementation-review-manifest.json revision1. Отчёт
test_reports/p06-independent-implementation-review.md сохраняет исходное
REQUEST_CHANGES и итоговое addendum. Reviewer не запускал Godot и не писал файлы.

Граница Git: прежний dirty P02 не включён в коммит. Полное проверенное рабочее
дерево включает P06 snapshot-правки, которые остаются вне индекса: UnitState
snapshot v2 methods, StatsBag stat-domain guards, SimulationSnapshot и две
негативные P02 fixture-строки runner. Ранее untracked COMMAND_ACTION_QUEUE_CONTRACT
и CODEX_HANDOFF также обновлены локально. Полный accepted manifest и сохранённый
P06 residual patch перечислены в передаче. Чистого checkout коммита недостаточно
без этих прежних P02 зависимостей и указанного P06 остатка.

## P07 — Balance/Push, принятая реализация (2026-09-14)

Frozen TASK редакции 1: [P07_BALANCE_PUSH_TASK.md](P07_BALANCE_PUSH_TASK.md).
Новые _test_p07_* проверяют A01–A17; прежние 1633 assertions/fixtures сохранены.
Финальный прогон ведущего: **1996 passed / 0 failed**, exit0. Godot 4.7.2
headless import (scan DONE, все пять новых class/UID) и startup успешны.
SCRIPT/parse/runtime ошибок нет. Итоговые 45 ObjectDB /18 resources совпадают
с прежним P06 baseline; новых утечек по диагностике выхода нет. UI не подключён.

Новый test_reports/p07-check.ps1 запускает import → startup → весь runner →
diff --check. APPDATA и GODOT_BIN задаются только процессу и восстанавливаются.
Логи: p07-import.log, p07-startup.log, p07-tests.log, p07-check-output.txt.
Первичные неуспешные прогоны сохранены отдельно; старые check scripts/logs не
перезапускались. Все 774 прежних test_reports артефакта сохранены побайтно.

Приёмка включает реальные item reactions, четыре направления, wall/height,
collision обоих HP одним step, вход после гибели blocker и fall/lethal до лечения,
точные формулы и min1, иммунитет/over-max, строгие schemas, BUSY, лимиты и faults.
Матрицы подмены refs/HP/cells/ledger/source/request/seals проверяют оплаченный
prefix и неповреждение replacement. Проверены полные board-version chains до3,
capacity4 только exact CollisionDamageCommand, event_seq край и реальный dirty
stat cache при root rejection. P02/Unit v1/v2 и два P03b restore сохраняют
balance/items/modifiers/ledger, дают равные receipts/fingerprints и изоляцию.

Независимый game_reviewer / Terra high дал **APPROVE** фиксированному revision1:
26/26 hashes совпали, блокирующих замечаний нет. Manifest —
test_reports/p07-implementation-review-manifest.json; ответ —
p07-independent-implementation-review.md; карта A01–A17 — p07-acceptance-map.md.
Frozen P07 TASK/DEPENDENCIES/REVIEW не переписаны. Для следующего этапа исходные
hashes заменяются только принятым implementation manifest; dirty P01/P02/P06
по-прежнему являются необходимыми зависимостями checkout.
