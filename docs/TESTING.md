# Проверка проекта

Актуальный порядок 2026-09-22, сверенный с `tools/demo/isolate.py`.
Это инструкции проверки; прежние прогоны не считаются результатом нового изменения.

## Среда

Нужны Python 3 и Godot; путь к Godot передаётся в GODOT_BIN либо `--godot`.
Запуск проекта — [REPOSITORY_STATE](REPOSITORY_STATE.md). Команды выполняются из корня.
Launcher создаёт отдельную копию текущих исходников и профиль, исключая
`test_reports/` и `.godot/`; пишет manifest, логи и при render — PNG в новый
`test_reports/demo-<id>/`. Старые отчёты не импортируются и не перезаписываются.

## Изменение игрового кода

После адресных тестов выполнить:

```powershell
python tools/demo/isolate.py --check --full
python tools/demo/isolate.py --render-check
```

Оба режима включают новые D2 runner (расчёт, snapshot, integration, recovery, UI).
Первая команда включает import/startup, attack_calculation/attack_d1, forecast, guard, summon_snapshot,
summon, healing, core и headless demo/battle. Вторая повторяет import/startup
и отдельные механические runner, затем запускает demo/battle с рендерингом и PNG;
core без `--full` в неё не входит. Повторять более широкие прогоны после успешных
проверок только при новых изменениях, сбоях или конкретном непроверенном риске.

| Область | Адресный runner в `tests/` |
|---|---|
| Ядро | `run_tests.gd` |
| Совместная атака C1/M4/D3/D5 (K1) | `test_core_combinations.gd`, `test_core_combination_turns.gd` (full/render); тестовая композиция — `tests/fixtures/core_combination_session.gd` |
| Игровая сессия C1/D3/D5 (K2) | `test_core_combination_session.gd`, `test_core_combination_battle.gd` (full/render); production-сессия, обе границы хода/AI, helper, terminal/FAULTED, два preview/live, restore, ввод/reset/PNG |
| Выделенный расчёт / эквивалентность до D1 | `test_attack_damage_calculation.gd`, `test_attack_damage_d1.gd` |
| Спина, крит и состояния контроля C1 | `test_attack_modifiers.gd`, `test_critical_control.gd`, `test_control_battle.gd` (full/render, ввод/scroll/PNG) |
| Броня D2 | `test_armor_hit_calculation.gd`, `test_armor_snapshot.gd`, `test_armor_integration.gd`, `test_armor_recovery.gd`, `test_armor_battle.gd` |
| Пробивание оружием M4 | `test_armor_piercing_calculation.gd`, `test_armor_piercing.gd`; ввод/осмотр/прогноз — `test_d4_ui.gd` (full/render) |
| Кровотечение D3 | `test_bleeding_snapshot.gd`, `test_bleeding.gd`, `test_bleeding_battle.gd` (full/render, шесть PNG): накопление срока, fixed tick, v1→v2, overflow/prefix, прогноз и ввод; production K2 — `test_core_combination_session.gd` |
| Забег D4 | `test_d4_run.gd`, `test_d4_integration.gd`, `test_d4_ui.gd` (full/render, восемь PNG) |
| Среда и трупы D5 | `test_d5_state.gd`, `test_d5_integration.gd`, `test_d5_ui.gd` (full/render; ввод, прогноз, поднятие, PNG) |
| Проход союзников | `test_ally_transit.gd` (full/render; два PNG в render) |
| Прогноз атаки | `test_attack_forecast.gd` |
| Прогноз двух предметов K3 | `test_item_use_forecast.gd`, `test_item_forecast_ui.gd` (full/render): две копии/live, полные snapshots/events/steps/RNG/counters/admission, новый helper, отказы/FAULTED/cleanup; ввод и PNG |
| Прогноз движения K4 | `test_move_forecast.gd`, `test_move_forecast_ui.gd` (full/render): полная preview/live и worker parity, транзит/падение/шипы, INTERRUPTED/FAULTED, helper/admission, изоляция/restore/cleanup; ввод и инвалидация во время расчёта, scrolling, shutdown и четыре PNG |
| Прогноз поднятия K5 | `test_raise_corpse_forecast.gd`, `test_raise_forecast_ui.gd` (full/render): изоляция/preview/live D5/K2, потребление тела и новый pending helper, отказы/DTO/restore; ввод, cache/refresh, свежий клик, сбросы/scroll и четыре PNG |
| Стойка | `test_guard_stance.gd` |
| Прогноз стойки K6 | `test_guard_forecast.gd`, `test_guard_forecast_ui.gd` (full/render): изоляция/preview/live tactical/K2, ресурсы/guard, отказы/FAULTED/restore; hover слота 2, свежие клик/клавиша, cache/refresh, сбросы/scroll и четыре PNG |
| Флакон | `test_healing_item.gd` |
| Общее описание применения M3 | `test_item_use_action.gd` (full/render); UI и фактическое лечение — `test_tactical_battle.gd` |
| Призыв / снимки призыва | `test_summoning_item.gd`, `test_summon_snapshot.gd` |
| Определение помощника M1 / legacy v3–v5 / v6 | `test_summon_definition.gd` (включён в full/render) |
| Полигон / нынешний бой | `test_battle_demo.gd`, `test_tactical_battle.gd` |
| Сравнение ходов / инициатива | `test_initiative_session.gd`, `test_initiative_battle.gd` (full/render, ввод/очередь/PNG) |

Пример адресного headless-запуска после импорта новых class_name:

```powershell
& $env:GODOT_BIN --path . --headless --editor --quit-after 5
& $env:GODOT_BIN --path . --headless --script tests/test_attack_forecast.gd
```

## Что считать приёмкой

Раздельные UI-расстановки D2/D3/D5/C1 находятся в `tests/fixtures/demo/`.
Они используют общий BattleDemo и прежние сессии, но отсутствуют в игровом меню.
K2 UI runner проверяет основной вход F5 и отсутствие старых кнопок; удаление
демонстраций не удаляет механическую регрессию или их проверки ввода.

Проверять exit code, summary и отсутствие ошибок/неожиданных leaks. Launcher
проверяет маркеры результатов, `0 failed`, Parse/SCRIPT ERROR; для non-legacy
runner также ERROR/ObjectDB. Известные diagnostics старого core не разрешают
новые leaks в изменённом коде. Результаты записывать с commit/составом исходников.
Preview сравнивать с настоящим исполнением, включая события, последствия,
предметы, resources, RNG и counters; отдельно проверять неизменность live.
UI проверять настоящими событиями ввода/кликами/scrolling в отдельном SubViewport
и осмотром PNG. Headless и PNG не заменяют пользовательский плейтест удобства/баланса.
Armor UI runner отдельно проходит исходную карту: прогноз/удар у пропасти,
восстановление, переключение, ответ ИИ и reset во время его хода. Полные партии
с бронёй до победы/поражения выполняются через session API; это отдельная проверка,
а не ручное управление всем боем. Проверяются завершение временной брони и исход в UI.
После тестов содержательного кода — независимое ревью фиксированного результата
по [AGENTS](../AGENTS.md). Frozen acceptance расширять новым контрактом, не переписывать задним числом.

## Документация и история проверок

Для текста/процесса достаточно проверки diff; при реорганизации дополнительно
проверять ссылки, сохранность архива/frozen и отсутствие изменений кода/ассетов.
Godot ради таких изменений не нужен. Исторические логи и counts вынесены в
[TESTING history](TESTING.history-20260920.md) и [историю передач](CODEX_HANDOFF.history-20260920.md).
Последняя игровая приёмка и её ограничения собраны в [HISTORY](HISTORY.md).
