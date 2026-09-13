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
