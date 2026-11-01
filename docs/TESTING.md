# Проверка проекта

Актуальный порядок 2026-10-11, сверенный с `tools/demo/isolate.py`.
Это инструкции проверки; прежние прогоны не считаются результатом нового изменения.

## Среда

Нужны Python 3 и Godot; путь к Godot передаётся в GODOT_BIN либо `--godot`.
Запуск проекта — [REPOSITORY_STATE](REPOSITORY_STATE.md). Команды выполняются из корня.
В режимах `--check`/`--render-check` launcher создаёт отдельную чистую копию текущих исходников и профиль, исключая
`test_reports/` и `.godot/`; пишет manifest, логи и при render — PNG в новый
`test_reports/demo-<id>/`. Старые отчёты не импортируются и не перезаписываются.
Интерактивный кэш из [REPOSITORY_STATE](REPOSITORY_STATE.md) в проверках не используется.

## Изменение игрового кода

Облики и состав классов (2026-11-01): `--check --only class_showcase
character_skins_hub character_skins`; затем `--render-check --only
character_skins character_skins_hub`. Проверяются оба скина Щитоносца/Воин,
вторичный idle без игрового RNG, выбранные кадры/тайминги, lifecycle,
реальные события способности, хаб/сохранение косметики/отказ записи/backup.
Состав проверяет каталоги1–4, одинаковые герои/RNG, все классы на поле,
настоящие возможности врагов, размещение и повтор checkpoint.
Смежные: hero_hub, hub_mercenaries, mage_deck_expedition, expedition_generator,
turn_forecast_ui, shieldbearer_ui, defender_death_routes, presentation_contact,
unit_visual_contract, visual_scene_contract, warrior_class, core.
Технические проверки не заменяют оценку шва idle и художественную приёмку.

Подготовка интерактивного прогноза (2026-11-01): `--check --only
battle_forecast_preparation_worker battle_forecast_preparation_ui battle_pointer_pick`.
Проверяются lease/join, полная move/attack parity и неизменность live/RNG,
callback/thread-start fallback, latest hover/панель/уход, клетка клика после движения
камеры, ограниченный буфер, reset/exit. Pointer runner сравнивает объединённый
поиск с прежними API и считает обходы, включая перекрытие рельефом.
Смежные: `attack_async_ui move_forecast_ui action_async_ui turn_forecast_ui
battle_execution_ui battle_execution_worker battle_camera_ui current_art_zoom`.
`tests/fixtures/forecast_preparation_wait.gd` возвращает владельца перед прямыми
мутациями legacy-тестов detached-симуляции; ввод во время lease покрыт отдельным UI runner.
Headless время обработчиков не означает 60 FPS на экране; автономный soak не
покрывает интерактивное наведение. [Результаты](performance/battle-interactive-forecast-20261101.md).

Свежесть магии/карт: `--check --only battle_forecast_freshness
battle_magic_freshness_ui battle_magic_mode_refresh mage_ui mage_deck_ui battle_forecast_preparation_worker
battle_forecast_preparation_ui action_forecast_async_ui`. Свидетель проверяется
на прямых изменениях без revision, identity/типах/RNG, неизвестных значениях и
границах отложенной публикации; click остаётся новой командой.
Длительный интерактивный контроль включается явно: `--render-check --only
battle_interactive_soak --screen 0`. Пять раундов, 32 бойца, DOT/огонь,
синтетическая мышь через Demo и HUD, готовые прогнозы магии/карт и быстрая смена
целей. Отчёт `user://battle-interactive-soak.json` сохраняет полную trace,
фокус и стоимость input; настройка/планировщик помечены отдельно, не удалены.
Это не аппаратная мышь и не свидетельство стабильного display FPS.

Длительный бой и стоимость показа (2026-10-31): `--render-check --only
battle_soak_performance battle_polygon_batch battle_presentation_owned battle_motion_pose --screen 0`.
Soak запускается только явно: 32 бойца, 24 опасные клетки (fire records с шипами), начальные DOT,
три полных цикла ходов с настоящими worker/ИИ/playback без skip и 60 с покоя.
JSON `battle-soak-performance.json` содержит startup/steady/combat, покадровый
trace, события/цели DOT, команды и минимум живых. Аппаратный ввод блокируется
и считается; начальные/финальные viewport и camera сохранены.
Данные display записывают фактические экран/Hz/позицию/размер окна, adapter и
max_fps; запросы идут только до/после замера. Индекс экрана не означает primary:
в текущей двухмониторной конфигурации контроль 60 Гц использует `--screen 1`.
Soak также записывает `window_focused`/`window_focus_available` в каждом кадре
и `window_focus_coverage` по существующим timing buckets. Для проверки активного
окна весь измеренный боевой участок должен иметь доступный фокус; headless и
потеря фокуса не считаются такой проверкой. Raw кадры при потере фокуса сохраняются.
Display metadata содержит `window_focused` только в GUI. См.
[системную трассу и ограничения замера](performance/battle-system-trace-20261031.md).
Выбор кандидатов test-planner имеет отдельный bucket и остаётся в общей трассе.
Он проверяет дешёвые пространственные/маршрутные условия; строгий допуск команды
исполняется обычным live-worker. Предварительные синхронные `validate()` в planner
удалены, поскольку сами создавали паузы. Повтор кандидата допустим только после
свежего завершённого REJECTED при доступной сессии на ходу игрока; fault/pending
прерывают сценарий. Перед итоговыми чтениями тест возвращает владение через join.
`--check --only battle_soak_planner` проверяет настоящий управляющий цикл теста
с подставными исходами worker, включая старые receipts и потерю владельца;
это не замена естественному soak с реальным admission. [Измерения](performance/battle-foreground-soak-20261031.md).
Прямой script поддерживает
`-- --units=32 --rounds=5 --idle-frames=3600` и `--uncapped`. Фикстура усиливает
HP/баланс до старта; боевые последствия меняют настоящие команды, актёра выбирает тест. Это нагрузочный
сценарий существующих эффектов, а не баланс или реализация нового AoE.
Polygon runner проверяет GPU pixels/draw calls, fallback и teardown; owned
runner — receipt/live изоляцию, порядок 120 кадров, skip/cancel и final,
числа и вложенный skip на пустом marker. Motion runner сравнивает авторские
трансформации после объединённого/прежнего sync и default/direct-setter fallback.
Дополнительно выбирать worker/capture/core и presentation/contact/push-slide/
environment/consequences/UI/visual gates по риску. [Метрики](performance/battle-soak-20261031.md).

Плавность действий с24 бойцами (2026-10-31): `--render-check --only
battle_action_performance visual_scene_contract battle_execution_ui battle_presentation
presentation_contact presentation_consequences presentation_environment --screen 0`.
Отдельно `--check --only battle_execution_worker presentation_capture core`.
Нагрузочный runner использует настоящий HeroHubBattleView, комнату24×16,
колоду/экипировку и24 живых бойца; проверяет движение/атаку через worker,
preview/live snapshots/events/steps и сохранение visual ID. JSON лежит в
изолированном `profile/Godot/app_userdata/intoDeDung/battle-action-performance.json`.
Время операций, кадров и dispatch диагностическое, без универсального FPS gate.
Runner отдельно сохраняет холодные `startup_frames` и 120 `steady_idle_frames`,
номера кадров и пороги 17.5/20/25/50 мс. Первый live action не отбрасывается.
Для запаса CPU/GPU тот же script в изолированном проекте принимает Godot user-arg
`-- --uncapped` (VSync off); обычный прогон сохраняет настройки VSync проекта.
Сравнивать baseline/current с одинаковым runner; исключать одновременные GPU-тесты.
Deferred before/after, отказ запуска и FAULTED покрыты worker-runner; snapshot
статов сравнивается с прежним clone-oracle без изменения live-кэша.
Render-регрессии смерти/реакций/камеры выбирать дополнительно при изменениях поз.
Технический A/B не заменяет ручную приёмку и проверку будущих артов/массовых AoE.

Прозрачный HUD и ввод за прежними границами Board (2026-10-31):
`python tools/demo/isolate.py --render-check --only battle_hud_input
battle_hud_authoring battle_camera_ui turn_forecast_ui mage_deck_ui hero_hub_ui --screen 0`
(одна команда). Новый runner использует реальные viewport-события для кликов,
наведения и камеры в освобождённых областях, проверяет границы кнопок и resize.
Остальные runners защищают authored overrides, прогноз, карты и камеру.
Снимки — `battle-hud-input-screenshots/` внутри отчёта launcher.
Full/core и ручная F5/DPI-приёмка этим набором не заменяются.

Исправление обрезки большой карты после обратной связи U (2026-10-31):
`--render-check --only battle_hud_input battle_camera_ui battle_hud_authoring
dungeon_room_comparison --screen 0`. В `battle_hud_input` отдельно проверяются
пиксели тайлов за прежними границами Board на реальной карте24×16 при104%,
повторный refresh/resize и ввод в тех же местах. Headless явно пропускает GPU;
один успешный click-test не доказывает, что клетка видна.

Шесть биомов, поле24×16 и настоящие отверстия (2026-10-28):
~~~powershell
python tools/demo/isolate.py --render-check --only biome_showcase_layout
dungeon_room_comparison hazards hazards_ui mage_deck_expedition
visual_scene_contract environment_visual_contract presentation_environment
collapse_phase battle_board_camera battle_camera_ui art_trial_battle --screen 0
~~~
(одна команда; переносы соединить пробелами). biome_showcase_layout проверяет
размер384, геометрию шести участков, snapshot copy/restore, движения через обе
границы8×8 с preview/live parity, обрушение дальней клетки, restart/profile/RNG
и прежний размер следующих/legacy боёв. Исторический dungeon_room_comparison
теперь проверяет шесть материалов/спрайтов, постоянную плотность вертикальных UV,
пустой VOID на alpha-кадре с соседними торцами, обзор/pan/picking всех участков,
reuse384 клеток и неизменность runtime. Он сохраняет overview, шесть деталей,
hole-transparent и время десяти refresh; это адресная метрика, не FPS/GPU-бенчмарк.
Прочие gates проверяют прежние ловушки, collapse playback, камеру и обычный арт.
Проверка launcher: python tools/demo/test_isolate.py.
[Исходники и кадры](art/biomes-showcase-20261028/README.md). Full/core и ручная
F5/движение/zoom/DPI-приёмка имеют отдельный статус.

Jersey 20 для чисел и Play Bold для букв (2026-10-27): `--render-check --only
presentation_contact presentation_consequences battle_presentation battle_camera_ui
--screen 0` (одна команда). При изменении генерации событий/подписей дополнительно
выбирать presentation_ranged, presentation_mage и presentation_reactions.
`presentation_contact` проверяет действительные шрифты glyph в смешанных строках
урона/крита/лечения/щита, латинском HP, кириллических статусах и многострочных
последствиях, а также все знаки числового подмножества; сохраняет `combat-font-pair.png`.
Цифры/числовые знаки требуют Jersey 20, остальные glyph — производный Play Bold
(`Combat Lettering`), включая среднюю точку, ×, длинное тире, двоеточие и слеш.
Прежние проверки покрывают
размещение, задержку контакта, lifetime/fade, ×3, zoom/resize, skip/cancel и RNG;
`presentation_consequences` также проверяет пиксели верхнего видимого лечения
в плотной цепочке chain-wall: подпись присутствует в верхней полосе 64 px,
а первые 3 строки пикселей свободны от её glyph — отступ от края сохранён.
Ручная F5/DPI-приёмка читаемости в движении остаётся отдельной.

Разворот всех живых атакующих к цели (2026-10-26): `--render-check --only
unit_visual_contract visual_scene_contract presentation_attack_styles presentation_contact
presentation_ranged presentation_reactions defender_idle defender_death_routes
rogue_death_routes --screen 0` (одна команда).
Проверяются обе стороны экрана/фракции, текущие и неизвестные классы, native/fallback,
вертикальная цель, authored flip/scale, замах/попадание/возврат, resize/zoom/pan,
реакции, ×3/skip/cancel/replay/FAULTED и неизменность runtime/пакета показа.
Снимки разворота — attack-style-screenshots/facing-*.png; ручная F5-приёмка отдельно.

Одиночный упор без урона оружия (2026-10-25): `--check --only push_chain
push_chain_reactions armor_integration fractional_armor_hit character_attributes_v1
spatial_guard_stats attack_forecast_worker battle_execution_worker`.
Проверяются стена/высокий уступ, дробная и нулевая база, независимость collision
от оружия при сохранении прямого удара, защита и прежняя сила конца цепочки.
Прогноз/live и workers проверяются адресно; full/core и ручная приёмка отдельно.

Отдельная Колода (2026-10-24): `--render-check --only hub_deck hub_development
hub_mercenaries hub_smith hub_sections hub_dashboard hub_scene_authoring hero_hub_ui
expedition_ui mage_deck_ui hero_hub mage_deck_models mage_deck_expedition --screen 0`.
Проверяются общий черновик двух UI, лимиты, запись/retry/reload, legacy,
запуск с выбранной базой и metadata/геометрия; снимки `hub-deck-screenshots/`.
Отдельно `python tools/demo/test_isolate.py`; full/core и ручная приёмка отдельно.

Развитие в Наёмниках (2026-10-24): `--render-check --only hub_development hub_mercenaries
hub_smith hub_sections hub_dashboard hub_scene_authoring hero_hub_ui expedition_ui mage_deck_ui
hero_hub hero_progression --screen 0`. Проверяются черновик/пороги/HP, повторное
подтверждение и устаревший снимок, запись/retry/reload, старое управление и оба
каталога, независимость элементов и три размера; снимки `hub-development-screenshots/`.
Отдельно `python tools/demo/test_isolate.py`; full/core и ручная приёмка отдельно.

Экипировка Кузнеца (2026-10-24): `--render-check --only hub_smith hub_mercenaries
hub_sections hub_dashboard hub_scene_authoring hero_hub_ui expedition_ui mage_deck_ui hero_hub --screen 0`.
Проверяются совместимость, замена без потери вещи/прочности, оба направления
записи/retry/reload, устаревший владелец, все 12 героев, пустой склад/состав,
черновик колоды и независимые controls. Снимки — `hub-smith-screenshots/`.
Отдельно `python tools/demo/test_isolate.py`; full/core и ручная приёмка отдельно.

Действия Наёмников (2026-10-24): `--render-check --only hub_mercenaries hub_sections
hub_dashboard hub_scene_authoring hero_hub_ui expedition_ui mage_deck_ui hero_hub --screen 0`.
Новый runner проверяет реальные клики найма/состава, полный/пустой отряд, лимиты
героев/склада/ID, сохранение/retry/reload, старые сигналы, черновик колоды и
metadata-редактирование. Снимки трёх размеров — `hub-mercenaries-screenshots/`.
Отдельно `python tools/demo/test_isolate.py` проверяет gate нового runner.
Full/core и ручная приёмка остаются отдельными проверками.

Цифры вскоре после контакта (2026-10-22): `--render-check --only presentation_contact
presentation_ranged presentation_attack_styles presentation_mage presentation_reactions
presentation_consequences presentation_environment defender_death_routes rogue_death_routes
battle_presentation --screen 0` (одна команда). Проверяются отсутствие цифры до
0,05 с после касания, появление в начале отдачи/смерти, однократность результата,
×3/skip/cancel/replay и прежний порядок after/HUD. Плейтест ощущения отдельно.

Перки экипировки/ножи (2026-10-18): `--check --only equipment_attacks hero_hub
hero_hub_playthrough counterattack action_event_validator forecast_definition_copy
forecast_restore_isolation attack_forecast_worker battle_execution_worker
current_schema_boundary core`. Метки передавать одной командой. Отдельно
`--render-check --only hero_hub_ui presentation_attack_styles presentation_contact rogue_animations --screen 0`.
Серия/цена/цель/сумма по слотам проверяются runtime-тестом, ручная F5/балансная
приёмка остаётся отдельной.

Скольжение при толчке (2026-10-18): `--render-check --only presentation_push_slide
presentation_contact presentation_consequences presentation_environment
presentation_attack_styles unit_visual_contract visual_scene_contract
defender_death_routes rogue_death_routes --screen 0` (одна команда).
Проверяются реальные receipts, четыре направления, native/fallback, наклон вокруг
стоп, торможение, resize/zoom, ×3/skip/cancel/replay и изоляция runtime/RNG.
Цепной сдвиг, упор и нижняя опора покрываются соседними presentation-метками;
маршруты смерти и visual-контракты защищают общую трансформацию тела.
PNG нового runner — `push-slide-screenshots/`; ощущение в ручном бою оценивает U.

Затухание импульса (2026-10-21): `--render-check --only presentation_push_slide
presentation_consequences presentation_environment presentation_contact --screen 0`.
Runner скольжения проверяет монотонный путь и падение скорости до нуля,
быстрый старт/мягкий конец, спад наклона и реальный путь на четверти/половине
сегмента. Прежние native/fallback/resize/zoom/прерывания и изоляция сохранены.

Глубина настенной ловушки: `--render-check --only hazards_ui environment_visual_contract
presentation_foundation --screen 0` (одна команда). `hazards_ui` сравнивает пиксели
стоящего нативного enemy-warrior до/после панели во всех четырёх направлениях,
проверяет видимость панели и активных шипов. Headless эту пиксельную часть пропускает.
`presentation_foundation` сохраняет порядок настоящей стены переднего плана;
при проверке слоя отдельно подтвердить, что старая ошибка ломает image assertion.

Поджог/яд (2026-10-17): `--check --only poison status_effects status_models
status_snapshots mage_deck_battle current_schema_boundary`. `poison` проверяет
обновление поджога до двух тиков, HP-gate яда/щит/лечебную реакцию, накопление,
HP-only тик/истечение/смерть, точные дроби, source/deck, FAULTED и оба worker.
Из-за Elemental4 дополнительно полный headless набор; UI/render:
`--render-check --only battle_hud_authoring battle_mage_presenter mage_deck_ui
presentation_status --screen 0`. Ручная F5/балансная приёмка отдельно.

Характеристики V1: `--check --only hero_progression fractional_armor_hit
status_contributions character_attributes_v1 hero_hub_ui expedition_postbattle
current_schema_boundary`. Многострочный список меток передавать одной командой.
Новые runners проверяют генерацию, точность дробей, авторские тики, snapshot и
preview/live; полный набор отдельно покрывает worker, очередь и frozen fixtures.
Сквозное прохождение техническим ботом не подтверждает игровой баланс.

До запуска выбрать проверки по затронутому поведению и ближайшим зависимостям.
Размер diff не определяет риск: одна строка codec/queue может требовать широкой
регрессии, а изменение подписи — только осмотра/diff. Полные прогоны не обязательны
для каждой правки; выбранный набор и непроверенные области указать в отчёте.

```powershell
python tools/demo/isolate.py --list-checks
python tools/demo/isolate.py --check --only battle_camera_ui
python tools/demo/isolate.py --render-check --only battle_camera_ui --screen 0
python -m unittest discover -s tools/demo -p "test_*.py"
```

`--only` принимает несколько меток через пробел и повторяется. Неизвестная метка,
отсутствие режима или сочетание с `--full` — ошибка до копирования. Import/startup
всегда выполняются; пропуск не считается PASS. `core` можно выбрать явно через
`--only core`. Итог подтверждает исполнение всех заказанных меток. `timing.json`
содержит время копирования, каждого выполненного runner, статус и общее время;
Независимые suites продолжаются после ошибки/timeout; итоговая сводка в stdout
и `timing.json.summary` перечисляет FAIL/TIMEOUT и невыполненные выбранные метки,
итоговый exit ненулевой при любом провале. Ошибка import/startup или повреждение
class cache блокирует зависимые проверки с явной причиной. Таймаут runner — 120 с,
core — 600 с. Это предел ожидания, не разрешение обрезать проверки до PASS.

Core подчиняется тем же ERROR/ObjectDB gates. Единственное подтверждённое
исключение — ровно одна строка `ERROR: BattleBoard.add_unit: клетка (2, 2) уже занята`
в negative core test; иная строка/повтор/другая suite не исключаются. Leaks,
shader ошибки и ненулевые failed counts не маскируются success marker.

Выбор `current_art_zoom`, `art_trial_battle` или `battle_view_reuse` автоматически
добавляет `visual_scene_contract`, `environment_visual_contract`, `unit_visual_contract`,
`defender_idle_clock`, `defender_idle`, `defender_buff`, `defender_death`, `defender_death_routes`,
`defender_cloth_palette`, `rogue_cloth_palette`, `archer_cloth_palette`, `rogue_animations`, `rogue_buff`, `rogue_death_routes`, `archer_idle`,
`presentation_consequences`, `presentation_environment`, `battle_camera_ui`, `battle_execution_ui`:
защита от пересоздания поля и сбоев поз, ловушек, камеры и worker/ИИ при смене пресета.
Прямой запуск только lifecycle:
`python tools/demo/isolate.py --render-check --only visual_scene_contract environment_visual_contract unit_visual_contract --screen 0`.
Лучница: `python tools/demo/isolate.py --render-check --only archer_idle --screen 0` —
12 кадров/2.6s, паузы/фаза/повторное использование, отражение/пикинг/fallback.
`current_art_zoom` проверяет её в текущем походном бою и сохраняет render-кадры;
PNG/resource/manifest: `python tools/art/build_archer_idle.py --check`.

Idle отдельно: `python tools/demo/isolate.py --render-check --only defender_idle_clock defender_idle --screen 0`.
Проверяются редкая петля/возврат/локальные часы без RNG, допуск, непрерывность idle
во время реального worker/движения ИИ и технических кадров, адресная пауза цели удара,
skip/cancel/finish, refresh/resize/retire, опора/якоря и state/RNG/counters настоящего похода.
`presentation_consequences` также проверяет паузу участников общей цепочки до конца Tween.
Жест усиления: `python tools/demo/isolate.py --render-check --only defender_buff shieldbearer_ui defender_idle --screen 0`.
`defender_buff` проверяет реальные успешные команды, 33 кадра/ритм, однократный
показ до after, возврат idle, speed/skip/cancel/resize и отказы чужих событий/классов.
`shieldbearer_ui` проверяет настоящий hover и click→worker→жест в HeroHub.
Смерть/отражение: `python tools/demo/isolate.py --render-check --only defender_death defender_death_routes defender_idle defender_buff --screen 0`.
`defender_death` проверяет ресурс и все 33 кадра, настоящий melee receipt/Tween,
resize и публикацию after. `defender_death_routes` проверяет ranged/mage и
одно-/многозвенные столкновения, before/тело, speed/skip/cancel/retire, fallback,
исключения падения/обвала и неизменность state/RNG/counters/пакета показа.
В той же проверке отдельный production enemy-warrior путь покрывает выбранную
death-2:17 кадров/2,55с, зеркальную опору, lifecycle и невалидный ресурс/fallback;
legacy-смерть союзного Защитника сохраняет своё покрытие.
Смежные пути смерти проверяются `presentation_contact`, `presentation_ranged`,
`presentation_mage`, `presentation_consequences`, `presentation_environment`;
общий lifecycle — `visual_scene_contract` и `unit_visual_contract`.
Счётчики/identity — hard gate, frame median/p95/max/>25ms — диагностика без
машинозависимого порога PASS. [Контракт и границы](BATTLE_VISUAL_SCENE_CONTRACT.md).

Одежда: `python tools/demo/isolate.py --render-check --only defender_cloth_palette rogue_cloth_palette archer_cloth_palette battle_hud_authoring --screen 0`.
Проверяет селектор/изоляцию материалов, все90 кадров и статичную позу,
отсутствие изменений вне маски/альфы, точный возврат исходных пикселей,
refresh/resize/reset, смену во время жеста/смерти и при отделённой сессии.
Маски сверяются с исходниками через `python tools/art/build_defender_cloth_masks.py --check`
(Pillow). PNG всех пар и семи гамм — техническое свидетельство, не F5-приёмка.
`rogue_cloth_palette` проверяет общий селектор и отдельные32 исторические маски
разбойника (idle/B1/D3, границы RGB/alpha, возврат исходной гаммы), изоляцию
материалов/классов/врага. Новый rogue_selected_v1 не получает старые маски:
сохраняются выбранный индекс, исходные цвета и Death3 fade при смене гаммы.
Маски: `python tools/art/build_rogue_cloth_masks.py --check` (Pillow).
`archer_cloth_palette` проверяет тот же HUD, изоляцию экземпляров/фракций,
12 кадров, still/fallback, сохранение фазы и state/RNG/counters. Render проверяет
все12×6 гамм с текущей brighter-коррекцией: RGB только внутри маски, alpha прежняя,
возврат0 побайтный. Маски: `python tools/art/build_archer_cloth_masks.py --check` (Pillow).

Разбойник: `python tools/demo/isolate.py --render-check --only rogue_animations rogue_buff rogue_death_routes --screen 0`.
Первый runner проверяет новую статичную позу, все17 кадров смерти, опору/отражение,
hold/fade, смену класса, reset/retire и повреждённые ресурсы. `rogue_buff` использует общий
`test_defender_buff.gd --rogue`: настоящая «Защита» фабричного разбойника,
общий cue без старой B1, границы matcher, публикации, resize/speed/skip/cancel
и неизменность core/RNG; fixture удерживает production execution_pending.
`rogue_death_routes` использует `test_defender_death_routes.gd --rogue`:
melee/ranged/mage, столкновения, after/тело, fall/VOID/обвал и cleanup.
Все три входят в автоматические visual gates для art/zoom/reuse и full/render.
`python tools/art/build_rogue_animation_assets.py --check` (Pillow) сверяет
историческую сборку и12 кадров прежнего idle. Текущие PNG/SHA и отдельный
render audit — [пакет интеграции](art/rogue-model-death3-20261023/README.md).
Новый idle не выбран. F5-приёмка отдельно.

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

### UI по обязанностям

Команда для строки таблицы: `python tools/demo/isolate.py --render-check --only <метки> --screen 0`.
Общий набор HUD — `battle_hud_authoring battle_execution_ui`; добавляйте его к
меткам затронутой обязанности. Он проверяет authored/legacy/H1, binding/refresh,
сигналы, worker/after-кадры и изоляцию snapshot/RNG. Программные `.new()`, overrides,
сохранность узлов/стилей и одиночные обработчики входят в authoring.

| Обязанность | Дополнительные метки | Особые границы |
|---|---|---|
| Список бойцов | `battle_panels control_ui entangle_ui` | Порядок/identity строк live/DTO, detached clicks, реальный осмотр врага |
| Тексты событий | `battle_event_text battle attack_async_ui status_ui mage_deck_ui` | Journal/forecast, предметы, статусы, карты; эталон прежнего producer |
| Подробный осмотр | `battle_inspection_text presentation_status battle control_ui entangle_ui` | Main/H1 hover, live-предметы, guard во время worker/показа |
| Authored binding | `battle_panels mage_deck_ui` | Main/H1/.new/legacy, повторное связывание, карты/страницы |
| DTO-кадр | `mage_deck_ui presentation_status` | Точные строки/порядок статусов, мана/карты без live-сессии |
| Legacy HUD | `demo battle d4_ui battle_panels` | Настоящий ввод, восемь слотов, guards, отказ на чужом ходе |
| Подробный прогноз/пути компонентов | `battle_forecast_text battle_event_text battle_inspection_text battle move_forecast_ui guard_forecast_ui item_forecast_ui raise_forecast_ui turn_forecast_ui armor_ui mage_ui mage_deck_ui core_reactions_ui entangle_ui d5_ui` | Golden280: строки/видимость/pending/отказы/fresh names/неверная мана, полный state/RNG |
| Динамические действия | `battle_action_descriptors four_slot_bar battle_panels shieldbearer_ui core_reactions_ui entangle_ui item_forecast_ui guard_forecast_ui` | Golden324: descriptors/fixed slots/compact filter, formatter override, свежесть и worker guard |
| Live-панель мага | `battle_mage_presenter mage_ui mage_deck_ui presentation_status` | Golden26: кнопки/страницы/callbacks, бесплатная замена/муллиган, pending guard |

Golden получен исходной реализацией; обычный тест не пересоздаёт его новым
formatter. При изменении границы сопоставить base/current и PNG, разобрать каждое
различие; seed/фаза анимации должны быть одинаковыми. При сохранении правил ядра,
команд, guards и мест вызовов full/core не назначаются только из-за UI-выноса.
Fixtures не подтверждают F5/Editor/DPI/GPU/FPS. Изменение launcher дополнительно
проверяется `python tools/demo/test_isolate.py` и `python tools/demo/test_interactive_cache.py`.
Для изменения интерактивного кэша дополнительно проверить реальный cold/warm запуск,
обновление импортированного ресурса при прежнем размере/mtime и чистый targeted check.
Cached import `SKIPPED` не является PASS проверки проекта.
Обычный cached-запуск исключает `docs/`: изменения отчётов не должны вызывать
импорт; игровые исходники по-прежнему сверяются по содержимому. Регрессии launcher
проверяют также удаление документов из старой копии и их наличие в чистом check.
`--fresh`/`--check`/`--render-check` сохраняют документацию для проверочных fixtures.

Для восстановления HP и экипировки: `python tools/demo/isolate.py --check --only restore_vitals armor_snapshot unit_snapshot_performance --screen 0`.
`restore_vitals` входит в обычный/full/render набор: equipped HP_MAX, точный
полный/раненый/нулевой HP, alive, ledger, canonical parity, две независимые ветки
и отсутствие событий на source. Порядок restore — [BATTLE_SNAPSHOT_CURRENT](BATTLE_SNAPSHOT_CURRENT.md#hp-и-экипировка-при-восстановлении).

Для границы старых форматов: `python tools/demo/isolate.py --check --only current_schema_boundary hero_hub expedition_transitions mage_deck_expedition --screen 0`.
`current_schema_boundary` входит в обычный/full набор: отказ старых/будущих
номеров и неверных типов, режимы компонентов, 512 сочетаний флагов/оплаты,
изоляция и приоритет повреждённых половин высоты перед неизвестной версией.
HeroHub проверяет неизменность файла и .bak/.tmp при отказах envelope/checksum.
Далее codecs затронутых компонентов, переходы/оба сквозных похода и full —
по риску общей сериализации. Render: hero_hub_ui, expedition_ui, mage_deck_ui,
shieldbearer_ui, bleeding_ui и status_ui: оба режима статусов должны сохранить
прогноз/журнал/описание после появления обязательных полей. Старые файлы
не мигрируются — SAVE_FORMAT_CURRENT.
Сравнение base/current после смены формы использует отдельный наблюдатель
только в копиях отчёта: добавляет явные значения прежних режимов и текущие
номера, затем сравнивает полные before/after/events/steps/frames/publications/
RNG/counters/admission. Код игры и его validators не заменяются; обычные
регрессии исполняются без наблюдателя. Методика и исходник — отчёт этапа.

Для разделения ActionQueue: `python tools/demo/isolate.py --check --only action_event_validator guard counterattack --screen 0`,
затем `--check --full` по риску общей очереди. Новый `action_event_validator` входит
в обычный/full набор и проверяет helper без экземпляра очереди. Прежние core,
bleeding/control/reaction/safe-retreat тесты обращаются к новому владельцу схем;
их проверки типов, арифметики и отказов сохранены. Core проверяет admission,
BUSY/reentrancy, malformed steps/events, limits/sequence и FAULTED-префикс.
В импортированных отдельных копиях base/current выполнить
`<Godot> --headless --path <project> --screen 0 --script tests/test_counterattack.gd -- --emit-parity`.
На base переносится только этот тест-наблюдатель, runtime остаётся исходным.
Сравнить все строки `ACTION QUEUE PARITY` по порядку, включая повторяющиеся labels:
before/after, полный preview, receipt, публикации, кадры, admission, RNG/counters;
матрица содержит нормальные ответы, отказ ответа, INTERRUPTED и FAULTED по лимитам.
Worker/clone fingerprints — команды ниже. UI render по риску: `presentation_reactions`,
`action_async_ui`, `attack_async_ui`, `move_forecast_ui`, `turn_forecast_ui`.
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

Точный экспериментальный board clone:
`python tools/demo/isolate.py --check --only board_clone_probe --screen 0`.
Runner opt-in, вне full/render, с import/startup и `--verify-only`.
Он прогоняет также матрицу допуска старого аудитора, но проверяет clone для
каждого OK, включая неполную occupancy/дубли cell/различный height.
После импорта парный режим:
`<Godot> --headless --path <изолированный-project> --screen 0 --script tools/demo/profile_board_clone.gd`.
Обратный порядок — `-- --reverse`. Методика, APPDATA, сырые samples/фазы и
критерии diagnostics — как выше; маркеры `BOARD CLONE PROBE RESULTS: ... 0 failed`
и `BOARD CLONE PROBE DONE`, exit0. Обе clone-стратегии здесь точные; старый
`profile_snapshot_strategies.gd` сохраняет fixture-only `direct_board`.
Это board-only CPU и локальные board events, не полный worker/queue/FPS.

Для общего runtime validator заказать оба `--only board_audit_probe board_clone_probe`:
они дополнительно проверяют admission/reason/IDs и canonical fingerprint по
`tools/demo/board_validator_baseline.json` (236 capture-результатов HEAD `84cb7b48`,
снятых до рефакторинга). Эталон не генерировать заново из проверяемого validator.
Clone runner требует полный состав эталонной матрицы; audit использует её подмножество.
Изменение общего production producer требует также core/full по таблице риска выше.

Эксперимент полного item-графа после capture:
`python tools/demo/isolate.py --check --only item_graph_clone_probe --screen 0`.
Opt-in вне default/full/render, с обязательными import/startup; success требует
`ITEM GRAPH CLONE RESULTS: ... 0 failed`, `ITEM GRAPH CLONE DONE`, exit0 и чистых
diagnostics. Полный capture сохранён; это не runtime-аудит всего графа без DTO.
После импорта в изолированной копии:
`<Godot> --headless --path <изолированный-project> --screen 0 --script tools/demo/profile_item_graph_clone.gd`.
`-- --reverse` обращает первый порядок стратегий. По 3 прогрева и 21 sample на
стратегию/fixture, чередование; `ITEM_GRAPH_SAMPLE` хранит capture/catalogue/build/
cleanup/total в мкс. Отдельные APPDATA и последовательные процессы, как выше.
Это tactical/artifacts/deck CPU fixtures, не рост 6/24/96 или FPS.
В verify-only также выполняется передача отделённых restore/clone пакетов в
реальный Thread: ownership всего известного графа, before/after/receipt/events/
steps/publications/RNG/counters/admission, FAULTED, one-shot, отказ запуска,
discard/join и изменение исходника после передачи. Потоковый harness не является
новым входом production forecast worker. `--emit-parity` сохраняет отпечатки
полных graph/command результатов для сравнения с отдельной копией исходного HEAD;
одного сравнения двух путей с общим builder недостаточно для независимого эталона.

Отключаемый clone штатного потребителя:
`python tools/demo/isolate.py --check --only forecast_clone_probe action_clone_worker action_clone_ui --screen 0`.
Все три метки opt-in, вне default/full/render. Последние две запускают обычные
worker/UI тесты с `--forecast-clone`; отдельно заказать исходные
`action_forecast_worker action_async_ui`. UI render —
`python tools/demo/isolate.py --render-check --only action_clone_ui --screen 0`.
Probe требует `FORECAST CLONE RESULTS: ... 0 failed`, `FORECAST CLONE DONE`,
exit0 и чистые diagnostics. Он проверяет реальные команды/Thread, перенос,
unsafe graph fallback/refusal, отказ ОС, discard/join, live isolation и FAULTED.
Отдельные границы: metadata с живым RefCounted и внешние `.tres` эффектов/призыва;
проверяются identity исходника/пакета, clone и fallback, отказ до Thread и cleanup.
Полная регрессия нужна при изменении общего ForecastSimulation по таблице выше.

Изоляция каталога default restore:
`python tools/demo/isolate.py --check --only forecast_definition_copy forecast_restore_isolation --screen 0`.
Обе метки входят в обычный/full набор; требуют своего `... RESULTS: ... 0 failed`,
exit0 и отсутствия warnings/errors. Первая проверяет metadata на всех Resource roots,
ключи/значения, циклы/лимиты и повтор ID. Вторая проходит реальный default prepare,
прямой instantiate и Action/Attack/Move/Turn worker с внешними `.tres`: после
изменения live пакет сохраняет захваченное поведение; unsafe metadata не запускает
поток. Полный command/publication/FAULTED parity и fallback остаются в clone probe.
Для изменения общего копировщика также запускать штатные worker/Turn, click_attack,
snapshot_value_copy/live_snapshot_capture, mage_deck_battle, full и затронутые UI render.
CPU до/после сравнивать в отдельных копиях base/current приведённым ниже profiler;
сохранять исходные samples и отдельно время prepare и admission/launch.

CPU в уже импортированной изолированной копии:
`<Godot> --headless --path <изолированный-project> --screen 0 --script tools/demo/profile_forecast_clone.gd`.
Повтор с `-- --reverse`; последовательные процессы и отдельные APPDATA.
Три прогрева, 21 чередующийся sample на каждую стратегию/fixture;
`FORECAST_CLONE_SAMPLE` сохраняет prepare/admission_launch/execute_join_cleanup/total
в мкс. Измеряются и полный путь, и оплачиваемая main подготовка, без UI frame/GPU.
`-- --verify-only --emit-parity` выдаёт command fingerprints. Сравнение с base:
обычный `tests/test_action_forecast_worker.gd -- --emit-parity` в отдельных
копиях base/current, затем current с `-- --forecast-clone --emit-parity`.
Изменённый тест на base переносит только наблюдение результатов, не runtime код.
При изменениях только harness достаточно его runner; board clone и штатные
`action_forecast_worker mage_deck_battle` проверяют соседние затронутые границы.
Изменение общего item builder требует также codec/checkpoint, live worker и
core/full по таблице риска. Diagnostics и известные baseline FAIL не скрывать.

Оба режима включают новые D2 runner (расчёт, snapshot, integration, recovery, UI).
Первая команда включает import/startup, attack_calculation/attack_d1, forecast, guard, summon_snapshot,
summon, healing, core и headless demo/battle. Вторая повторяет import/startup
и отдельные механические runner, затем запускает demo/battle с рендерингом и PNG;
core без `--full` или явного `--only core` в неё не входит. Повторять более широкие прогоны после успешных
проверок только при новых изменениях, сбоях или конкретном непроверенном риске.

| Область | Адресный runner в `tests/` |
|---|---|
| Обычная атака кликом | `test_click_attack.gd` (`--only click_attack`): подход, отказ без расхода, изоляция планирования, порядок move/attack, worker/sync и маршрутизация UI. Камера/отмена — `test_battle_camera_ui.gd`. |
| Общий бонус окружения | `test_surround_damage_calculation.gd`, `test_surround_damage.gd` (`--only surround_damage_calculation surround_damage`): 0–3 других союзника, обе команды, геометрия/контроль, скрытая атака, огонь/высота/пробивание/округление, неизменные periodic ticks, реакции, строгие события и preview/live/workers. Смежные: `core_reactions counterattack status_effects attack_forecast_worker battle_execution_worker battle_forecast_text battle_event_text`; после изменения общего расчёта — core/full. |
| Редактируемые сцены боя | `test_battle_hud_authoring.gd` (full/render): main/H1 до _ready, overrides и identity после binding/refresh/after-кадров, один обработчик, сохранность runtime/RNG, legacy/.new(), PNG; карта — [BATTLE_HUD_SCENES_V1](BATTLE_HUD_SCENES_V1.md). |
| Редактируемые сцены хаба | `test_hub_scene_authoring.gd` (full/render): узлы до _ready, сохранность настроек и экземпляров после refresh/ошибки, один обработчик на кнопку, профиль неизменен при редактировании/отмене; `test_hub_dashboard.gd`: ввод/навигация, черновик, данные профиля, сохранность файла/RNG и размеры 1024×720, 1280×850, 1920×1080. `test_hub_sections.gd`: независимые move/hide/delete/rename/reparent модулей/карточек/полей/линий, выбор/пагинация, изменённый/пустой состав и склад, неизменность профиля/сохранения, три размера. Адресно: `python tools/demo/isolate.py --render-check --only hub_sections hub_dashboard hub_scene_authoring hero_hub_ui expedition_ui mage_deck_ui --screen 0`. Карта сцен — [HUB_SCENES_V1](HUB_SCENES_V1.md). |
| Колода мага V1 | `test_mage_deck_models.gd`, `test_deck_ability_state.gd`, `test_mage_deck_expedition.gd`, `test_mage_deck_battle.gd`, `test_expedition_playthrough.gd -- --deck`, `test_mage_deck_ui.gd` (full/render): codecs/legacy/барьеры записи, рука/мана, все12 эффектов, sync/preview/workers, FAULTED prefix, реальный поход и UI до сохранённого итога; UI PNG через `-- --captures=<dir>` |
| Поддержка верховного мага R14 | `test_mage_r14.gd`, `test_battle_mage_bar.gd`, `test_mage_ui.gd` (full/render): лечение/командный призыв/поднятие/щит, полный preview/live и worker, отказы, pending/тело/зона помощников, schema9/legacy, H1 с артефактами, обе страницы 8+4 и межкадровые клики. PNG — mage-r14-screenshots/. |
| Щит R14 | `test_spell_shield.gd`, `test_push_chain.gd` (full/render): armor4 с/без щита и отказ старых форм, mage preview/live, обновление/замена, ноль/смешанный урон/overflow/несколько ударов, броня/горение/кровотечение/шипы, callback FAULTED prefix, летальный тик и 11 событий парного столкновения. |
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
| Полный цикл U14 | `test_expedition_generator`, `test_expedition_transitions`, `test_battle_artifact_snapshot`, `test_expedition_artifacts`, `test_expedition_playthrough`, `test_expedition_ui` (`.gd`, full/render): граф/seed, фазы/потери/merge/отказ старых форм, текущие snapshot/guards, триггеры/preview/workers, настоящий поход и ввод/PNG. Полная победа — допустимый профиль ветеранов уровня 10; ранний выход и поражение — новички. Баланс новичков runner не утверждает. UI использует terminal fixture; playthrough исполняет обычные действия/ИИ. |
| Хаб H1 | `test_hero_progression.gd`, `test_hero_hub.gd`, `test_hero_hub_ui.gd`, `test_hero_hub_playthrough.gd`: найм/XP/сброс, codecs/изоляция/отказ записи, бой/прогноз, полные бои, ввод/автосохранение/PNG |
| Итоги боя V1 | `test_expedition_postbattle.gd` (full/render): восстановление/потери/резерв, ремонт/цена/ledger, достижения/однократность, profile6/run4/report3, отказ старых форм и roundtrip checkpoint/RNG, отказ записи, финал/поражение/H1; ввод и PNG — `test_expedition_ui.gd`, `test_hero_hub_ui.gd`. Контракт — POST_BATTLE_V1. |
| Маг и откаты K18 | `test_ability_catalog.gd`, `test_mage_cooldowns.gd`, `test_mage_boundaries_guards.gd`, `test_mage_ui.gd` (full/render): реестр, schema7/часы/skip, цена/FAULTED/guards, полные snapshots/events/steps/RNG/counters, оба worker/TurnForecast, ввод/refresh/PNG. UI оставляет `_process` включённым, разделяет mouse down/up двумя кадрами и проверяет выбор заклинаний и стрелки обеих страниц. |
| Четыре слота, маг и зоны | `test_four_slot_bar.gd`, `test_battle_panels.gd` (full/render): четыре кнопки/нет страниц, legacy, макет 1280×850, шесть эффектов через preview/live worker, snapshots/events/steps/RNG/counters, K18-цены/иммунитеты/опциональный каталог, callback prefix, зоны готовности/источник/копия кадра и реальные клики/PNG |
| Завершающая сверка K10–K17 | `test_core_readiness_status.gd` (full/render): совместные границы команд/раунда, настоящие пространственные пути добивания, restore/preview/live и FAULTED; `test_push_chain_reactions.gd::_death_spikes_and_collapse`: смерть среднего помощника, реакции, кровотечение/шипы и следующий обвал. Карта покрытия — CORE_READINESS. |
| Эффекты K17 | `test_status_state_models.gd`, `test_elemental_snapshots.gd`, `test_status_effects.gd`, `test_status_effects_ui.gd` (full/render): codec/изоляция, источники/armor-gates/сроки, движение/цепи/добивание, guards/FAULTED, workers/preview/live и UI |
| Цепное отталкивание K16 | `test_push_chain.gd`, `test_push_chain_reactions.gd`, `test_push_chain_ui.gd` (full/render): затухание/смерти/геометрия, помощники/вещи/реакции, preflight/guards/FAULTED, полный parity/worker, ввод и PNG |
| Противник первым в K15 | `test_enemy_first.gd` (full/render): старт/расстановка/reset без refill, раунд/контроль, полный круг предупреждения, K13/live worker parity, terminal/FAULTED prefix; настоящий ввод — `test_collapse_ui.gd` |
| Обрушение K15 | `test_collapse_state.gd`, `test_collapse_phase.gd`, `test_collapse_ui.gd` (full/render): environment5 и отказ старых форм, фаза после обеих команд, RNG/задержка/пропасть/тела/помощники, preview/live/worker/FAULTED, BT, ввод/refresh/pending/PNG |
| Безопасный отход K14 | `test_safe_retreat.gd`, `test_safe_retreat_integration.gd`, `test_safe_retreat_ui.gd` (full/render): оплата/перехват/транзит/среда/отказы/FAULTED, helpers, preview/live/worker, настоящий ввод и инвалидация, PNG |
| Прогноз конца командного хода K13 | `test_turn_forecast.gd`, `test_turn_forecast_ui.gd` (full/render): настоящий переход до первого решения ИИ, изоляция/preview/live/worker, terminal/FAULTED, runtime-отказы, реальный hover/click/Enter, refresh без revision, очистка/exit и PNG |
| Восстановление равновесия | `test_balance_recovery.gd` (full/render): -1 на своём командном ходе, clamp, союзники/враги/помощники, мёртвые/выбор, реальный preview/live, без пробоя/RNG, preflight и повреждающие callbacks; `test_presentation_consequences.gd`: eventless refill, шкала/подпись и PNG |
| Компактный прогноз R15 | `test_compact_forecast.gd`: числа/запас равновесия, смена порога, пробой со сбросом, отказ/pending/префикс, цепь/упор/падение, новые участники/переполнение/изоляция; `test_attack_forecast_async_ui.gd`: живой hover, одинаковый запас в карточке/диагностике, stale/clear, закрытая диагностика, 75–250%, выбор/наведение/действующий без runtime; прочие forecast UI runners покрывают адаптеры |
| Исполнение общего боя вне render | `test_battle_execution_worker.gd`, `test_battle_execution_ui.gd` (full/render): владение session, sync parity всех действий/хода, callbacks fallback, pending/resize/публикация/reset/exit/FAULTED и PNG |
| Оптимизация снимков | `test_snapshot_walk_performance.gd`, `test_unit_snapshot_performance.gd` (full/render): parity raw graph/диагностики/лимитов, unit9/текущие компоненты, HP_MAX; полный и короткий DTO, 128 сочетаний компонентов, повреждённый runtime, свежесть/изоляция без мутаций; `test_mage_deck_ui.gd`: покадровый отказ/восстановление binding без revision и worker admission |
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
| Кровотечение D3 | `test_bleeding_snapshot.gd`, `test_bleeding.gd`, `test_bleeding_battle.gd` (full/render, шесть PNG): накопление срока, fixed tick, bleeding4 без смены версии, overflow/prefix, прогноз и ввод; production K2 — `test_core_combination_session.gd` |
| Забег D4 | `test_d4_run.gd`, `test_d4_integration.gd`, `test_d4_ui.gd` (full/render, восемь PNG) |
| Среда и трупы D5 | `test_d5_state.gd`, `test_d5_integration.gd`, `test_d5_ui.gd` (full/render; ввод, прогноз, поднятие, PNG) |
| Выдвижные ловушки/кислота | `test_hazards.gd`, `test_acid.gd`, `test_hazards_ui.gd` (`--only hazards acid hazards_ui`): срок команды/выход/повтор, push/wall/fall≥2 halfsteps, lethal/guard/corpse/collapse, прямой armor10 и срок, codec/preview/worker/live/production opening; detached показ/HP/пауза укола/resize/skip/cancel/speed/PNG. UI также проверяет авторские пресеты, 16 шипов, полную грань стены во всех четырёх направлениях и сохранность редактируемых силуэтов при анимации. Правила — [контракт](ENVIRONMENT_HAZARDS_V1.md). |
| Проход союзников | `test_ally_transit.gd` (full/render; два PNG в render) |
| Прогноз атаки | `test_attack_forecast.gd` |
| Контратака K12 | `test_counterattack.gd`, `test_counterattack_ui.gd` (full/render), codec в `test_combat_perks_state.gd`: доп. действие/legacy-заряд, tail после контроля/spatial/items, eligibility/смерть/FAULTED, sync/forecast worker/live worker parity, сохранения, ввод и PNG |
| Контроль K11 | `test_control_perks_codec.gd`, `test_control_package.gd`, `test_control_package_ui.gd` (full/render): единая perks7, stun/иммунитеты/истечение/реакции/BT, worker/live/restore, HP-gate/FAULTED; ввод и два PNG |
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

Пример адресного headless-запуска после импорта новых class_name:

```powershell
& $env:GODOT_BIN --path . --headless --editor --quit-after 5
& $env:GODOT_BIN --path . --headless --script tests/test_attack_forecast.gd
```

## Что считать приёмкой

`test_reaction_bonus.gd` входит в full/render: единый bonus, два ответа при bonus2
и отказ при bonus0, perks7 и точный roundtrip/оплата обоих режимов, строгие события,
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
проверяет маркеры результатов, `0 failed`, Parse/SCRIPT ERROR и ERROR/ObjectDB
для всех runner, включая core. Единственное точное исключение для core описано
выше в разделе «Изменение игрового кода». Результаты записывать с commit/составом исходников.
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

## Воин и выбранные модели — 2026-10-30

`python tools/demo/isolate.py --check --only warrior_class warrior_recovery warrior_visuals shieldbearer_profile`
проверяет права на активки, основной/дополнительный ресурс, CD1, дробные формулы,
preview/live/worker, recovery/caps/repair/save и отсутствие старых клипов.
`--render-check --only warrior_visuals` проверяет загрузку shader с renderer.
Целевой срез также требует проверки общих recovery, snapshot, hub/expedition и core.
Технический render не заменяет ручной F5, движение/зум/DPI и оценку баланса.
