# Проверка проекта

Актуальный порядок 2026-10-05, сверенный с `tools/demo/isolate.py`.
Это инструкции проверки; прежние прогоны не считаются результатом нового изменения.

## Среда

Нужны Python 3 и Godot; путь к Godot передаётся в GODOT_BIN либо `--godot`.
Запуск проекта — [REPOSITORY_STATE](REPOSITORY_STATE.md). Команды выполняются из корня.
Launcher создаёт отдельную копию текущих исходников и профиль, исключая
`test_reports/` и `.godot/`; пишет manifest, логи и при render — PNG в новый
`test_reports/demo-<id>/`. Старые отчёты не импортируются и не перезаписываются.

## Изменение игрового кода

До запуска выбрать проверки по затронутому поведению и ближайшим зависимостям.
Размер diff не определяет риск: одна строка codec/queue может требовать широкой
регрессии, а изменение подписи — только осмотра/diff. Полные прогоны не обязательны
для каждой правки; выбранный набор и непроверенные области указать в отчёте.

```powershell
python tools/demo/isolate.py --list-checks
python tools/demo/isolate.py --check --only battle_camera_ui
python tools/demo/isolate.py --render-check --only battle_camera_ui --screen 0
python -m unittest discover -s tools/demo -p test_isolate.py
```

`--only` принимает несколько меток через пробел и повторяется. Неизвестная метка,
отсутствие режима или сочетание с `--full` — ошибка до копирования. Import/startup
всегда выполняются; пропуск не считается PASS. `core` можно выбрать явно через
`--only core`. Итог подтверждает исполнение всех заказанных меток. `timing.json`
содержит время копирования, каждого выполненного runner, статус и общее время;
ошибка/timeout сохраняет уже полученные результаты и логи. Таймаут runner — 120 с,
core — 600 с. Это предел ожидания, не разрешение обрезать проверки до PASS.

Выбор `current_art_zoom`, `art_trial_battle` или `battle_view_reuse` автоматически
добавляет `visual_scene_contract`, `environment_visual_contract`, `unit_visual_contract`,
`presentation_consequences`, `presentation_environment`, `battle_camera_ui`, `battle_execution_ui`:
защита от пересоздания поля и сбоев поз, ловушек, камеры и worker/ИИ при смене пресета.
Прямой запуск только lifecycle:
`python tools/demo/isolate.py --render-check --only visual_scene_contract environment_visual_contract unit_visual_contract --screen 0`.
Счётчики/identity — hard gate, frame median/p95/max/>25ms — диагностика без
машинозависимого порога PASS. [Контракт и границы](BATTLE_VISUAL_SCENE_CONTRACT.md).

| Изменение | Достаточная начальная область |
|---|---|
| Только документы/процесс, подписи без поведения | Diff и ссылки; Godot не нужен для чистого текста. Для Python launcher — его unittest/CLI |
| Сцена, геометрия, авторские настройки | Соответствующий authoring runner и один render затронутого экрана; механические suites не повторять |
| Пробное поле/два Защитника | `--render-check --only art_trial_battle presentation_foundation --screen 0`: сцены, варианты/опоры, стороны/отражение, worker движения, показ и PNG. Ручная арт-приёмка отдельно. |
| Пробный арт в текущем походе/zoom | `--render-check --only current_art_zoom art_trial_battle battle_camera_ui --screen 0`: настоящий HeroHubBattleView с сессией фабрики, PNG/A-B75/100/125%, resize, стыки, picking, HUD и изоляция state/RNG. Это fixture, не ручной F5 и не GPU benchmark. |
| Ввод, камера, последовательность показа | Адресный UI runner + затронутый worker/forecast; render только этих сценариев |
| Поход, каталог/профиль, сохранение | Генератор/переходы/codec и соответствующий сквозной поход; UI при изменении маршрута; legacy-совместимость адресно |
| Core queue/board/RNG/общая сериализация/неясный радиус воздействия | Адресные проверки плюс `--check --full`; render затронутых видов, весь render при общем изменении представления |

Обычная локальная правка: начать с 1–3 связанных runner (плюс import/startup).
Если нужны больше — записать конкретные затронутые границы; это ориентир, не
лимит покрытия. После сбоя повторять исправленный runner и зависимые проверки.
Не запускать повторно уже зелёный широкий набор без новой правки или нового риска.
Глобальное число «всего PASS» не цель, тайминги не заменяют корректность.

Полная регрессия по указанным выше основаниям или отдельному поручению:

```powershell
python tools/demo/isolate.py --check --full
python tools/demo/isolate.py --render-check
```

Оконные прогоны можно направить на нужный монитор:
`python tools/demo/isolate.py --render-check --screen 0`.
Индекс Godot можно также передать через `GODOT_TEST_SCREEN`; headless его игнорирует.
На рабочем месте пользователя 2026-10-01 экран слева, не основной, имеет индекс 0;
после изменения конфигурации экранов индекс следует перепроверить.

Исследование текущих снимков: `python tools/demo/isolate.py --check --only snapshot_strategies --screen 0`.
Этот opt-in benchmark не входит в full/render. Сравнивать последовательные прогоны
одного fixture без других Godot-нагрузок; первые три вызова — прогрев, затем 21 sample.
Рост 6/24/96 относится к доске, не ко всему походу. Производственный кадр измеряет
`tools/demo/profile_snapshot_preflight.py --godot <exe> --output <new-dir> --screen 0`;
вложенные времена не складывать. Контракт — [BATTLE_SNAPSHOT_CURRENT](BATTLE_SNAPSHOT_CURRENT.md).

После успешных import/startup в новой изолированной копии доступен парный режим:
`<Godot> --headless --path <изолированный-project> --screen 0 --script tools/demo/profile_snapshot_strategies.gd -- --clone-breakdown`.
Для второго порядка добавить `--reverse` после `--clone-breakdown`. Каждый процесс
запускать последовательно с отдельным APPDATA внутри нового отчёта; основной
checkout/профиль не использовать. Сохранять весь stdout, exit code и diagnostics,
проверять маркер `SNAPSHOT CLONE BREAKDOWN DONE`. Режим выводит 21 сырой sample
после трёх прогревов на каждую стратегию/размер, total/capture/build/cleanup в мкс,
summary в мс. `direct_parts` — отдельная инструментированная проба без аудита,
не самостоятельная безопасная альтернатива capture. Её времена не складывать
с вложенным build. Тайминги не имеют машинозависимого порога PASS; допуск,
DTO/изоляция, live/RNG/counters/UnitId и снятие death callbacks проверяются assert.

Свежий аудит без board/unit/stats/modifier DTO проверяется отдельно:
`python tools/demo/isolate.py --check --only board_audit_probe --screen 0`.
Runner opt-in, вне full/render; включает import/startup и `--verify-only`:
матрицу допуска/причин/IDs, purity live/cache/signals и изоляцию вложенных копий.
После успешного импорта в этой изолированной копии запустить
`<Godot> --headless --path <изолированный-project> --screen 0 --script tools/demo/profile_board_audit.gd`.
Для обратного порядка размеров добавить `-- --reverse`. Каждый процесс —
последовательно, отдельный APPDATA внутри нового отчёта, весь stdout/exit code.
Требовать `BOARD AUDIT PROBE DONE`, `BOARD AUDIT PROBE RESULTS: ... 0 failed`,
exit0 и отсутствие ERROR/SCRIPT ERROR/ObjectDB diagnostics. Три стратегии:
capture/restore, clone с capture-аудитом, clone с runtime-аудитом; 3 прогрева,
21 sample, шесть перестановок порядка. Сырые total/capture либо audit/build/cleanup
выводятся после серии; медианы/p95/max — в мс. Фазы вложены в total, не складывать
их медианы. Малые DTO компонентов сохранены; допуск не является снимком или кэшем.
Fixture-only clone не покрывает весь допустимый capture-граф: границы —
[контракт снимков](BATTLE_SNAPSHOT_CURRENT.md#эксперимент-свежего-runtime-аудита).

Оба режима включают новые D2 runner (расчёт, snapshot, integration, recovery, UI).
Первая команда включает import/startup, attack_calculation/attack_d1, forecast, guard, summon_snapshot,
summon, healing, core и headless demo/battle. Вторая повторяет import/startup
и отдельные механические runner, затем запускает demo/battle с рендерингом и PNG;
core без `--full` или явного `--only core` в неё не входит. Повторять более широкие прогоны после успешных
проверок только при новых изменениях, сбоях или конкретном непроверенном риске.

| Область | Адресный runner в `tests/` |
|---|---|
| Обычная атака кликом | `test_click_attack.gd` (`--only click_attack`): подход, отказ без расхода, изоляция планирования, порядок move/attack, worker/sync и маршрутизация UI. Камера/отмена — `test_battle_camera_ui.gd`. |
| Редактируемые сцены боя | `test_battle_hud_authoring.gd` (full/render): main/H1 до _ready, overrides и identity после binding/refresh/after-кадров, один обработчик, сохранность runtime/RNG, legacy/.new(), PNG; карта — [BATTLE_HUD_SCENES_V1](BATTLE_HUD_SCENES_V1.md). |
| Редактируемые сцены хаба | `test_hub_scene_authoring.gd` (full/render): узлы до _ready, сохранность настроек и экземпляров после refresh/ошибки, один обработчик на кнопку, профиль неизменен при редактировании/отмене; карта сцен — [HUB_SCENES_V1](HUB_SCENES_V1.md). |
| Колода мага V1 | `test_mage_deck_models.gd`, `test_deck_ability_state.gd`, `test_mage_deck_expedition.gd`, `test_mage_deck_battle.gd`, `test_expedition_playthrough.gd -- --deck`, `test_mage_deck_ui.gd` (full/render): codecs/legacy/барьеры записи, рука/мана, все12 эффектов, sync/preview/workers, FAULTED prefix, реальный поход и UI до сохранённого итога; UI PNG через `-- --captures=<dir>` |
| Поддержка верховного мага R14 | `test_mage_r14.gd`, `test_battle_mage_bar.gd`, `test_mage_ui.gd` (full/render): лечение/командный призыв/поднятие/щит, полный preview/live и worker, отказы, pending/тело/зона помощников, schema9/legacy, H1 с артефактами, обе страницы 8+4 и межкадровые клики. PNG — mage-r14-screenshots/. |
| Щит R14 | `test_spell_shield.gd`, `test_push_chain.gd` (full/render): schema1/2 roundtrip, mage preview/live, обновление/замена, ноль/смешанный урон/overflow/несколько ударов, броня/горение/кровотечение/шипы, callback FAULTED prefix, летальный тик и 11 событий парного столкновения. |
| Предметы и появление R14 | `test_presentation_support.gd` (full/render): реальные флакон/печать/поднятие и верховный маг, before/after, привязка к root/шагу, промежуточный контакт/поднятие/щит/pending, камера/×3/skip. PNG — support-presentation-screenshots/. |
| Показ V1 | `test_presentation_capture.gd`, `test_battle_presentation.gd` (full/render): value-only кадры, preview/live parity, пустые события/refill, FAULTED prefix, настоящий UI/HP/порядок, пропуск/скорость/resize, multi-root ход/маг, цепное падение, задержка исхода H1, reset/exit и PNG |
| Повторное использование поля | `test_battle_view_reuse.gd` (full/render): identity штатных и trial-опор/стен/накладок, свежие высоты/VOID/огонь/подсветка/тела/ловушки, сброс и resize поз, удаление истёкших накладок/стен, новая доска/размер, переключение сцен, custom/procedural fallback; trial-трава/стык при zoom/fractional canvas; неизменность live/RNG/counters. Порядок показа и ввод проверяют прежние presentation/UI runners. |
| Варианты ближней атаки R02 | `test_presentation_attack_styles.gd` (full/render): реальный разбойник H1, четыре направления/сцена и fallback, отделённый класс без session при playback, нижняя подготовка/дуга/контакт, прежний дальний выстрел и базовый выпад, класс атакующего реакции, камера/resize/×3/skip/cancel/FAULTED, полная preview/live parity и порядок after. PNG — attack-style-screenshots/. |
| Падение, тела и окружение R12/R13 | `test_presentation_environment.gd` (full/render): реальные цепи на нижний пол/в VOID/за край, moved+died в одном кадре, смерть/тело/несколько тел, вход в шипы/огонь, обвал с жертвой и реальный FAULTED без смерти; полный preview/live и порядок after, изоляция показа, камера/resize/×3/skip/cancel. Промежуточные PNG — environment-presentation-screenshots/. Main/H1 worker/reset/exit дополнительно покрыты прежними presentation runners. |
| Внешний маг R07 | `test_presentation_mage.gd` (full/render): огонь/лечение main/H1, подготовка/доставка/контакт, HP/мана/откат по after, броня/ноль/смерть/capped heal, полные preview/live snapshots/events/steps/RNG/counters, камера/resize/×3/skip/reset/exit, отказ и реальный FAULTED prefix; cast-only — отделённая фикстура. PNG — mage-presentation-screenshots/ |
| Стойки и реакции R10 | `test_presentation_reactions.gd` (full/render): guard/режимы/доп. действие/refill, Прикрытие без переноса урона, Оппортунист и Контратака, допустимость/контроль/смерть, полный preview/live parity, порядок всех after, камера/resize/×3/skip/cancel, FAULTED и main/H1 worker/reset. PNG — reaction-presentation-screenshots/ |
| Состояния у фигур R06/R08/R09/R15 | `test_presentation_status.gd` (full/render): лёд/оглушение/корни вместе и в движении, стаки/сроки, смерть/fallback, синтетическое переполнение, настоящий конец хода/×3/skip, preview/live наложения, осмотр main/H1 во время worker/показа и PNG |
| Причины R06/R11 | `test_presentation_consequences.gd` (full/render): реальные receipts/preview parity, истощение/частичный расход/проникновение брони, удержание/пробой/сдвиг/стена/уступ/падение, контакт/отдача от стены/уступа/бойца в четырёх направлениях, цепь/иммунитет, 18/24→18/12 без толчка, FAULTED, отдельные блоки причин, последовательные roots без cancel, ×3/skip/cancel/resize и PNG |
| Дальний показ R03 | `test_presentation_ranged.gd` (full/render): штатный receipt и оба UI, соседний выстрел/обе оси/отказ диагонали, фазы/броня/ноль/крит/смерть, камера/resize, ×3/skip/cancel/FAULTED и parity; ближний контакт/цифры — `test_presentation_contact.gd` |
| Полный цикл U14 | `test_expedition_generator`, `test_expedition_transitions`, `test_battle_artifact_snapshot`, `test_expedition_artifacts`, `test_expedition_playthrough`, `test_expedition_ui` (`.gd`, full/render): граф/seed, фазы/потери/merge/миграция, v8/guards, триггеры/preview/workers, настоящий поход и ввод/PNG. Полная победа — допустимый профиль ветеранов уровня 10; ранний выход и поражение — новички. Баланс новичков runner не утверждает. UI использует terminal fixture; playthrough исполняет обычные действия/ИИ. |
| Хаб H1 | `test_hero_progression.gd`, `test_hero_hub.gd`, `test_hero_hub_ui.gd`, `test_hero_hub_playthrough.gd`: найм/XP/сброс, codecs/изоляция/отказ записи, бой/прогноз, полные бои, ввод/автосохранение/PNG |
| Итоги боя V1 | `test_expedition_postbattle.gd` (full/render): восстановление/потери/резерв, ремонт/цена/ledger, достижения/однократность, schema3/run2 и миграция с checkpoint/RNG, отказ записи, финал/поражение/H1; ввод и PNG — `test_expedition_ui.gd`, `test_hero_hub_ui.gd`. Контракт — POST_BATTLE_V1. |
| Маг и откаты K18 | `test_ability_catalog.gd`, `test_mage_cooldowns.gd`, `test_mage_boundaries_guards.gd`, `test_mage_ui.gd` (full/render): реестр, schema7/часы/skip, цена/FAULTED/guards, полные snapshots/events/steps/RNG/counters, оба worker/TurnForecast, ввод/refresh/PNG. UI оставляет `_process` включённым, разделяет mouse down/up двумя кадрами и проверяет выбор заклинаний и стрелки обеих страниц. |
| Четыре слота, маг и зоны | `test_four_slot_bar.gd`, `test_battle_panels.gd` (full/render): четыре кнопки/нет страниц, legacy, макет 1280×850, шесть эффектов через preview/live worker, snapshots/events/steps/RNG/counters, K18-цены/иммунитеты/опциональный каталог, callback prefix, зоны готовности/источник/копия кадра и реальные клики/PNG |
| Завершающая сверка K10–K17 | `test_core_readiness_status.gd` (full/render): совместные границы команд/раунда, настоящие пространственные пути добивания, restore/preview/live и FAULTED; `test_push_chain_reactions.gd::_death_spikes_and_collapse`: смерть среднего помощника, реакции, кровотечение/шипы и следующий обвал. Карта покрытия — CORE_READINESS. |
| Эффекты K17 | `test_status_state_models.gd`, `test_elemental_snapshots.gd`, `test_status_effects.gd`, `test_status_effects_ui.gd` (full/render): codec/изоляция, источники/armor-gates/сроки, движение/цепи/добивание, guards/FAULTED, workers/preview/live и UI |
| Цепное отталкивание K16 | `test_push_chain.gd`, `test_push_chain_reactions.gd`, `test_push_chain_ui.gd` (full/render): затухание/смерти/геометрия, помощники/вещи/реакции, preflight/guards/FAULTED, полный parity/worker, ввод и PNG |
| Противник первым в K15 | `test_enemy_first.gd` (full/render): старт/расстановка/reset без refill, раунд/контроль, полный круг предупреждения, K13/live worker parity, terminal/FAULTED prefix; настоящий ввод — `test_collapse_ui.gd` |
| Обрушение K15 | `test_collapse_state.gd`, `test_collapse_phase.gd`, `test_collapse_ui.gd` (full/render): legacy/v2 codec, фаза после обеих команд, RNG/задержка/пропасть/тела/помощники, preview/live/worker/FAULTED, BT, ввод/refresh/pending/PNG |
| Безопасный отход K14 | `test_safe_retreat.gd`, `test_safe_retreat_integration.gd`, `test_safe_retreat_ui.gd` (full/render): оплата/перехват/транзит/среда/отказы/FAULTED, helpers, preview/live/worker, настоящий ввод и инвалидация, PNG |
| Прогноз конца командного хода K13 | `test_turn_forecast.gd`, `test_turn_forecast_ui.gd` (full/render): настоящий переход до первого решения ИИ, изоляция/preview/live/worker, terminal/FAULTED, runtime-отказы, реальный hover/click/Enter, refresh без revision, очистка/exit и PNG |
| Восстановление равновесия | `test_balance_recovery.gd` (full/render): -1 на своём командном ходе, clamp, союзники/враги/помощники, мёртвые/выбор, реальный preview/live, без пробоя/RNG, preflight и повреждающие callbacks; `test_presentation_consequences.gd`: eventless refill, шкала/подпись и PNG |
| Компактный прогноз R15 | `test_compact_forecast.gd`: числа/запас равновесия, смена порога, пробой со сбросом, отказ/pending/префикс, цепь/упор/падение, новые участники/переполнение/изоляция; `test_attack_forecast_async_ui.gd`: живой hover, одинаковый запас в карточке/диагностике, stale/clear, закрытая диагностика, 75–250%, выбор/наведение/действующий без runtime; прочие forecast UI runners покрывают адаптеры |
| Исполнение общего боя вне render | `test_battle_execution_worker.gd`, `test_battle_execution_ui.gd` (full/render): владение session, sync parity всех действий/хода, callbacks fallback, pending/resize/публикация/reset/exit/FAULTED и PNG |
| Оптимизация снимков | `test_snapshot_walk_performance.gd`, `test_unit_snapshot_performance.gd` (full/render): parity raw graph/диагностики/лимитов, schema 1–8, HP_MAX; полный и короткий DTO против прежнего producer, 128 сочетаний компонентов, повреждённый runtime, свежесть/изоляция без мутаций; `test_mage_deck_ui.gd`: покадровый отказ/восстановление binding без revision и worker admission |
| Live snapshot/checkpoint | `test_snapshot_value_copy.gd`, `test_live_snapshot_capture.gd`, `test_summon_checkpoint.gd` (full/render): типы/изоляция копий, fresh capture без revision, владение вложенными ветвями доски/определений и порядок отказов, строгий raw/restore, parity checkpoint призыва/поднятия с полным clone и callback FAULTED prefix |
| Плавность вспомогательных прогнозов | `test_action_forecast_worker.gd`, `test_action_forecast_async_ui.gd`: все семь вариантов, sync/worker/live parity, hints против строгого отказа, pending/latest/refresh/exit/phase/close; прежние пять UI runner ожидают готовый результат |
| Немедленный маршрут K4 | `test_move_forecast_ui.gd` (full/render): пунктир до worker, быстрая смена цели, очистка запретов/отмены, замена на исполненный prefix при гибели, PNG предварительного и точного маршрутов |
| Единый боевой пакет K9 | `test_core_batch.gd`, `test_summon_composition.gd`, `test_core_batch_ui.gd` (full/render): расстановка, все восемь слотов, прогноз брони, печать/поднятие/оба хода, два боя до исхода, snapshot/FAULTED и четыре PNG |
| Перки и реакции K10 | `test_combat_perks_state.gd`, `test_core_reactions.gd`, `test_core_reactions_ui.gd` (full/render): владельцы, ближние участники скрытой атаки против дальнего оружия (включая носителя перка), геометрия/помощники, доп. действие/legacy-заряд/защита/перехват, preview/live/restore, смертельный и принудительный сдвиг, транзит/FAULTED, реальный ввод и PNG |
| Ядро | `run_tests.gd` |
| Совместная атака C1/M4/D3/D5 (K1) | `test_core_combinations.gd`, `test_core_combination_turns.gd` (full/render); тестовая композиция — `tests/fixtures/core_combination_session.gd` |
| Игровая сессия C1/D3/D5 (K2) | `test_core_combination_session.gd`, `test_core_combination_battle.gd` (full/render); production-сессия, обе границы хода/AI, helper, terminal/FAULTED, два preview/live, restore, ввод/reset/PNG |
| Клинок M4 в общем бою (K7) | Те же K2 runner: штатная экипировка Бора/источник stats, reset и restore без накопления, изоляция определений, пробивание с C1/D3/D5, отказы/FAULTED; настоящий ввод, осмотр, прогноз и атаки Щита/Дозорного |
| Опутывающий удар K8 | `test_entangle_attack.gd`, `test_entangle_ui.gd` (full/render): наложение/gate/повтор/истечение, порядок push/смертей, preview/live/restore/FAULTED, ввод/прогноз/PNG; осмотр пут/срока реальным кликом по кнопке врага в списке без мутации боя |
| Выделенный расчёт / эквивалентность до D1 | `test_attack_damage_calculation.gd`, `test_attack_damage_d1.gd` |
| Спина, крит и состояния контроля C1 | `test_attack_modifiers.gd`, `test_critical_control.gd`, `test_control_battle.gd` (full/render, ввод/scroll/PNG); осмотр оглушения/тыла кнопкой врага в списке без мутации боя, обновление осмотра после истечения оглушения/пут |
| Броня D2 | `test_armor_hit_calculation.gd`, `test_armor_snapshot.gd`, `test_armor_integration.gd`, `test_armor_recovery.gd`, `test_armor_battle.gd` |
| Пробивание оружием M4 | `test_armor_piercing_calculation.gd`, `test_armor_piercing.gd`; ввод/осмотр/прогноз — `test_d4_ui.gd` (full/render) |
| Кровотечение D3 | `test_bleeding_snapshot.gd`, `test_bleeding.gd`, `test_bleeding_battle.gd` (full/render, шесть PNG): накопление срока, fixed tick, v1→v2, overflow/prefix, прогноз и ввод; production K2 — `test_core_combination_session.gd` |
| Забег D4 | `test_d4_run.gd`, `test_d4_integration.gd`, `test_d4_ui.gd` (full/render, восемь PNG) |
| Среда и трупы D5 | `test_d5_state.gd`, `test_d5_integration.gd`, `test_d5_ui.gd` (full/render; ввод, прогноз, поднятие, PNG) |
| Выдвижные ловушки/кислота | `test_hazards.gd`, `test_acid.gd`, `test_hazards_ui.gd` (`--only hazards acid hazards_ui`): срок команды/выход/повтор, push/wall/fall≥2 halfsteps, lethal/guard/corpse/collapse, прямой armor10 и срок, codec/preview/worker/live/production opening; detached показ/HP/пауза укола/resize/skip/cancel/speed/PNG. UI также проверяет авторские пресеты, 16 шипов, полную грань стены во всех четырёх направлениях и сохранность редактируемых силуэтов при анимации. Правила — [контракт](ENVIRONMENT_HAZARDS_V1.md). |
| Проход союзников | `test_ally_transit.gd` (full/render; два PNG в render) |
| Прогноз атаки | `test_attack_forecast.gd` |
| Контратака K12 | `test_counterattack.gd`, `test_counterattack_ui.gd` (full/render), codec в `test_combat_perks_state.gd`: доп. действие/legacy-заряд, tail после контроля/spatial/items, eligibility/смерть/FAULTED, sync/forecast worker/live worker parity, сохранения, ввод и PNG |
| Контроль K11 | `test_control_perks_codec.gd`, `test_control_package.gd`, `test_control_package_ui.gd` (full/render): perk schema1/2, stun/иммунитеты/истечение/реакции/BT, worker/live/restore, HP-gate/FAULTED; ввод и два PNG |
| Фоновый прогноз атаки | `test_attack_forecast_worker.gd`, `test_attack_forecast_async_ui.gd` (full/render): parity обычного удара/руны/K8, изоляция, pending/готовый PNG, замена цели/режима/фазы/сцены, refresh без revision и свежий клик; `test_spatial_guard_stats.gd` проверяет fast path и прежний fallback guards |
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
| Сравнение ходов / инициатива | Только адресно: `test_initiative_session.gd`, `test_initiative_battle.gd` (ввод/очередь/PNG). Исключены из full/render по решению пользователя о покомандном ходе; сцены и тесты сохранены. |

Пример адресного headless-запуска после импорта новых class_name:

```powershell
& $env:GODOT_BIN --path . --headless --editor --quit-after 5
& $env:GODOT_BIN --path . --headless --script tests/test_attack_forecast.gd
```

## Что считать приёмкой

`test_reaction_bonus.gd` входит в full/render: единый bonus, два ответа при bonus2
и отказ при bonus0, schema5 и точный legacy roundtrip/оплата, строгие события,
callback-guard и полный preview/live parity, настоящий H1 воин/Оппортунист/refill
и опубликованный боковой HUD. Режимы/косвенная оплата Прикрытия/FAULTED/worker
дополнительно покрываются прежними K10/K12/R10 runner на новом источнике.

`test_battle_board_camera.gd` (full/render) проверяет границы масштаба, якорь под курсором,
обратимость координат, reset/resize и нефинитные входы. `test_battle_camera_ui.gd` (full/render)
проверяет реальный ввод, picking после преобразования, неизменность раскладки,
камеру во время worker/движения, сохранение узлов/Tween/чисел, reset и вход H1.
ПКМ сдвигает поле без отмены выбранного действия/осмотра, Esc отменяет;
якорь колеса проверяется после сдвига при приближении и отдалении.
Проверяет базовую геометрию main/H1 при resize, границу 75%, выбор увеличенной
головы, согласование льда и прежнюю подгонку сцен без камеры. Render сохраняет
PNG базового и отдалённого поля. Прежние forecast UI runner проверяют
сохранение прокрутки; камера и прогноз не меняют боевые команды.

`test_presentation_foundation.gd` входит в full/render: сцены с изображениями,
промежуточные позиции/пикинг четырёх направлений, подъём и передняя стена,
накладки огня/льда и их снятие, осмотр во время worker/показа, неподвижная
раскладка при диагностике, запрет новых команд и skip parity. Render сохраняет
PNG стыков/накладок/обычного UI. Точные фазы коротких клипов в presentation runner
фиксируются pause после join и явно возобновляются для естественного завершения;
это исключает зависимость утверждения о начальном кадре от старта GPU.
Тот же runner проверяет спрайты воинов на настоящей стартовой комнате U14:
выбранный воин обеих сторон/остальные классы, стабильные пресеты невоинов,
точная посадка78×73 и верх4:3, классовый приоритет,
отделение от session, движение/лёд/смерть, fallback без группы/при null-текстуре,
обновление класса после playback и неизменность snapshot/RNG; PNG `warrior-*`.

`test_presentation_contact.gd` входит в full/render: реальная пара attack/attack_hit,
подготовка/выпад/отдача, HP и броня без повторного счёта, нулевой/критический/
смертельный удар, лечение предметом и контратака, неизменные snapshot/RNG/counters.
Фаза выпада проверяется до и после короткой границы контакта.
Проверяет независимую жизнь цифр через after/новую команду/×3, размещение нескольких
результатов, resize, пропуск в контакте, отмену и FAULTED без выдуманных эффектов.
Render сохраняет фазы и варианты результата в contact-screenshots/.

`tools/demo/profile_smoothness.gd` запускается в изолированном проекте с рендером.
Он измеряет CPU обработчиков и реальные интервалы кадров для одного сценария
общего боя (refresh, наведение, действие, ход ИИ), записывает fingerprint/RNG/counters.
Для A/B нужны одинаковый runner, машины/режимы и чередование base/current.
CPU и интервалы кадров — разные величины; максимум в окне не равен FPS.
Численные результаты принадлежат отчёту этапа, а не переносимому CI-порогу.

`tools/demo/profile_production_smoothness.gd` — отдельный production fixture
HeroHubBattleView/catalog2/deck с обычным `_process` (кроме явно названного
диагностического окна). Запускать в изолированной копии с render/`--screen 0`.
Окна idle/hover/shield содержат 180 кадров; end-turn/AI продолжается до возврата
игроку. Для A/B использовать один runner и чередовать base/current. Сравнивать
как первые 180 кадров, так и полный ход; JSON `parity` содержит полные начальный/
конечный снимки, RNG/counters/admission и публикации events/steps/after.
Runner проверяет отсутствие live-мутации от hover, но не заменяет F5/редактор.

Разбивка main-thread стоимости снимка/подготовки/аудита worker:
`python tools/demo/profile_snapshot_preflight.py --godot <Godot> --output test_reports/<новый-каталог> --screen 0`.
Инструмент сохраняет исходные и преобразованные hashes, создаёт отдельные
control/probe проекты и APPDATA, последовательно выполняет import/render
и сравнивает полные before/after/publications. `--prepare-only` позволяет
осмотреть копии; `--run-existing` запускает их после проверки hashes один раз.
Таймеры внедряются только в probe-копию, runtime checkout не меняется.
Длительности включают вложенные вызовы: складывать их нельзя. Instrumented
кадры не служат A/B доказательством ускорения; отсутствие вызова в fixture
не означает нулевую стоимость в других сценариях. GPU этим способом не измеряется.

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

CPU-замеры общего боя: `Godot --headless --path . --script tools/demo/profile_core_battle.gd`.
Для K10 добавить `-- --reactions`; без аргумента сохраняется прежний сценарий K9.
Runner измеряет обновление UI, снимки, прогнозы, реальную атаку и три хода ИИ;
выводит JSON с временами и fingerprint/RNG/counters итоговых состояний.
Сравнивать несколько чередующихся прогонов на одном компьютере без других
Godot runner. Это время синхронных операций, не FPS и не приёмка плавности;
жёстких временных порогов в функциональных тестах нет.

`Godot --headless --path . --script tools/demo/profile_attack_forecast.gd`
раздельно измеряет синхронный прогноз и UI-наведение Бор → Щит: input, подготовку,
полное ожидание результата и кадры во время ожидания. Runner можно копировать
в прежний checkout; JSON содержит parity, события/шаги/RNG/counters. Это сценарий
исходной партии с шестью бойцами, а не оценка всех последующих размеров боя.

Для текста/процесса достаточно проверки diff; при реорганизации дополнительно
проверять ссылки, сохранность архива/frozen и отсутствие изменений кода/ассетов.
Godot ради таких изменений не нужен. Исторические логи и counts вынесены в
[TESTING history](TESTING.history-20260920.md) и [историю передач](CODEX_HANDOFF.history-20260920.md).
Последняя игровая приёмка и её ограничения собраны в [HISTORY](HISTORY.md).
